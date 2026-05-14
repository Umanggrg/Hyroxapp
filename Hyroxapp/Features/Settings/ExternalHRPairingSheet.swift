import SwiftUI
import SwiftData

// §20 Path A — pairing sheet for an external Bluetooth HR monitor.
//
// Renders ExternalHRService.shared's discovery state. Athlete enables
// "Broadcast Heart Rate" on their Garmin watch (or pairs a Polar
// strap, Wahoo TICKR, etc.), the sheet scans, and they tap the device
// to pair. Selected device's identifier + name persists to
// UserProfile so future race / free-run starts auto-reconnect.
//
// Surfaces:
//   • Bluetooth permission state — guides the user through enabling
//     BT if it's off / unauthorized.
//   • Scan list — discovered devices with signal strength.
//   • Currently-paired card — shown when a paired record already
//     exists; gives the athlete an Unpair button and a "Test
//     connection" CTA that displays the live BPM as confidence.
//   • Trade-off disclosure — most Garmin watches won't record their
//     own workout while broadcasting HR, so the athlete needs to
//     choose. Background BLE on iOS is fragile. iPhone battery
//     drain is meaningful. All called out plainly so it's not a
//     surprise mid-race.
//
// Concurrency: @MainActor by default (the codebase's default
// isolation per §8.1). Reads from ExternalHRService.shared via
// the @Observable bindings — no manual onChange wiring needed.
struct ExternalHRPairingSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    @State private var service = ExternalHRService.shared
    @State private var showConnectingError = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Pair HR Monitor")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
                .onAppear {
                    // Refresh the paired-record cache from the
                    // current UserProfile in case Settings was
                    // edited elsewhere in the app between
                    // openings.
                    if let profile {
                        let uuid = profile.pairedHRDeviceUUID
                            .flatMap { UUID(uuidString: $0) }
                        service.loadPaired(
                            uuid: uuid,
                            name: profile.pairedHRDeviceName
                        )
                    }
                    service.startScan()
                }
                .onDisappear {
                    service.stopScan()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch service.state {
        case .poweredOff:
            statusCard(
                glyph: "antenna.radiowaves.left.and.right.slash",
                title: "Bluetooth Off",
                message: "Turn Bluetooth on in Control Center, then come back to this screen.",
                tint: Color.warning
            )
        case .unauthorized:
            statusCard(
                glyph: "lock.shield",
                title: "Bluetooth Permission Needed",
                message: "Grant Trakrr Bluetooth access in Settings → Trakrr → Bluetooth to pair an external HR monitor.",
                tint: Color.warning
            )
        default:
            mainContent
        }
    }

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if hasPairedDevice {
                    pairedDeviceCard
                }

                instructionsCard

                scanResultsSection

                tradeoffsDisclosure
            }
            .padding(20)
        }
    }

    // MARK: - Currently-paired device card

    private var hasPairedDevice: Bool {
        (profile?.pairedHRDeviceUUID).flatMap { $0.isEmpty ? nil : $0 } != nil
    }

    private var pairedDeviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Color.accent)
                Text("PAIRED DEVICE")
                    .capsLabelStyle()
            }

            Text(profile?.pairedHRDeviceName ?? "Unknown device")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            connectionStatusRow

            HStack(spacing: 10) {
                Button("Unpair") {
                    unpair()
                }
                .buttonStyle(.bordered)
                .tint(Color.warning)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
        )
    }

    @ViewBuilder
    private var connectionStatusRow: some View {
        HStack(spacing: 8) {
            switch service.state {
            case .connected(let name):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to \(name)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let last = service.lastSample {
                        Text("\(Int(last.bpm.rounded())) bpm")
                            .font(.caption.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Color.accent)
                    } else {
                        Text("Waiting for first sample…")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            case .connecting(let name):
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to \(name)…")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            case .scanning, .idle:
                Image(systemName: "moon.zzz")
                    .foregroundStyle(Color.textTertiary)
                Text("Not connected — enable HR broadcast on the device")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            case .poweredOff, .unauthorized:
                EmptyView()
            }
            Spacer()
        }
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW TO PAIR")
                .capsLabelStyle()
            instructionRow(number: 1, text: "On your Garmin / Polar / Wahoo device, enable Heart Rate broadcast in its sensor menu.")
            instructionRow(number: 2, text: "Wait for the device name to appear below.")
            instructionRow(number: 3, text: "Tap it to pair. Trakrr will auto-reconnect on future workouts.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
        )
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.heavy))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accent.opacity(0.15)))
                .foregroundStyle(Color.accent)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Scan results

    private var scanResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AVAILABLE DEVICES")
                    .capsLabelStyle()
                Spacer()
                if case .scanning = service.state {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 4)

            if service.discoveredDevices.isEmpty {
                emptyScanState
            } else {
                VStack(spacing: 8) {
                    ForEach(service.discoveredDevices) { device in
                        deviceRow(device: device)
                    }
                }
            }
        }
    }

    private var emptyScanState: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(Color.textTertiary)
            Text("Scanning for devices…")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Text("Make sure HR broadcast is enabled on your watch.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
        )
    }

    private func deviceRow(device: ExternalHRService.DiscoveredDevice) -> some View {
        Button {
            pair(device: device)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Signal: \(rssiLabel(for: device.rssi))")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.pressableCard)
    }

    // RSSI is dBm, typically -40 (very close) to -100 (very far).
    // Translate into a coarse label for non-engineers.
    private func rssiLabel(for rssi: Int) -> String {
        switch rssi {
        case (-60)...0:    return "Excellent"
        case (-75)...(-61): return "Good"
        case (-90)...(-76): return "Fair"
        default:           return "Weak"
        }
    }

    // MARK: - Trade-offs disclosure

    private var tradeoffsDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WORTH KNOWING")
                .capsLabelStyle()
            tradeoffRow(text: "Most Garmin watches can't record their own workout while broadcasting HR. Pick: Trakrr (with HR) OR Garmin (without Trakrr coaching).")
            tradeoffRow(text: "Background Bluetooth on iOS can flake. If the phone is pocketed and the screen sleeps, HR may drop until it wakes.")
            tradeoffRow(text: "Continuous Bluetooth drains ~10-15% of iPhone battery over a 90-min race.")
            tradeoffRow(text: "Apple Watch users additionally get the wrist race screen and auto rep counting — features Garmin / external strap setups don't provide.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
        )
    }

    private func tradeoffRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Generic status card

    private func statusCard(
        glyph: String,
        title: String,
        message: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: glyph)
                .font(.largeTitle)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surface)
        )
        .padding(20)
    }

    // MARK: - Actions

    private func pair(device: ExternalHRService.DiscoveredDevice) {
        service.pair(device: device)
        // Persist the pairing record to UserProfile so future
        // launches auto-reconnect. The service will emit
        // `.connected` after the GATT handshake completes; we
        // write the record optimistically here so the persisted
        // state matches the user's tap, and an `.idle` from a
        // failed handshake doesn't wipe a previously-good record.
        if let profile {
            profile.pairedHRDeviceUUID = device.id.uuidString
            profile.pairedHRDeviceName = device.displayName
            try? modelContext.save()
        }
    }

    private func unpair() {
        service.unpair()
        if let profile {
            profile.pairedHRDeviceUUID = nil
            profile.pairedHRDeviceName = nil
            try? modelContext.save()
        }
    }
}
