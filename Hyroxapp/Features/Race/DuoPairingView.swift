import SwiftUI

#if canImport(MultipeerConnectivity)

// The pairing flow for co-located Duo. Lives behind the "Duo" toggle
// on RaceStartView; presented as a sheet. Three logical screens, all
// rendered as a single switch on `coordinator.state`:
//
//   1. .idle               → role picker (Host or Join)
//   2. .hosting(advertising) → "Waiting for partner — your name is X"
//   2. .joining(browsing)    → list of nearby hosts to tap
//   3. .ready(partner)       → "Connected to Sarah · ready to start"
//
// Same brand language as RaceStartView and Onboarding — coral
// accents, fingerprint motif, hero glyph in a tinted halo. Built as
// a sheet so it can be dismissed independently of the pairing state
// (cancelling cleanly tears down the session via
// `coordinator.cancel()` in onDisappear).
//
// On `.ready`, the user taps "Start Race" which dismisses the sheet
// AND signals the parent (RaceStartView) to enter the in-race flow
// in Duo mode. That signal flows back via the `onReady` callback
// passed in.
struct DuoPairingView: View {

    @Bindable var coordinator: DuoCoordinator

    // Called when both partners are paired and the local user
    // taps "Start Race." Parent dismisses the sheet and starts
    // the race in duo mode.
    var onReady: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ZStack {
                HeroBackdrop(.calm)

                VStack(spacing: 24) {
                    Spacer(minLength: 12)

                    switch coordinator.state {
                    case .idle:
                        rolePicker
                    case .hosting(let transport):
                        hostingPanel(transport: transport)
                    case .joining(let transport):
                        joiningPanel(transport: transport)
                    case .ready(let partnerName, let partnerDivision):
                        readyPanel(partnerName: partnerName, partnerDivision: partnerDivision)
                    }

                    Spacer()
                }
                .padding(.horizontal, Layout.screenMargin)
            }
            .navigationTitle("Duo Race")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        coordinator.cancel()
                        dismiss()
                    }
                }
            }
            // Mirror DuoSession's @Observable state into the coordinator
            // every time it changes. Apple's @Observable doesn't fire
            // a "didChange" hook automatically across nested observables
            // — this onChange is the bridge that keeps coordinator.state
            // in sync with session.state.
            .onChange(of: coordinator.session.state) { _, _ in
                coordinator.observeSessionState()
            }
            // The hello exchange happens once per connection. Watch
            // for the moment the transport reports .connected and
            // fire our identity payload then. The receiving side
            // handles hello inside DuoSession.didReceive.
            .onChange(of: coordinator.session.state) { oldValue, newValue in
                if case .connected = newValue, !connectedAlready(oldValue) {
                    coordinator.sendHello()
                }
            }
            .onDisappear {
                // If the user dismisses the sheet via swipe or the X
                // without explicitly tapping Start, treat as cancel —
                // tear down the session so we don't leak peers or
                // accidentally accept invitations after the user
                // moved on.
                if case .ready = coordinator.state {
                    // They tapped Start; the parent will own the
                    // coordinator now, so don't tear down here.
                    return
                }
                coordinator.cancel()
            }
        }
    }

    // True if the previous transport state was already .connected,
    // so we don't re-send hello on intermediate state shuffles
    // (e.g. .connected → .connected re-emit on no-op).
    private func connectedAlready(_ s: DuoSession.State) -> Bool {
        if case .connected = s { return true }
        return false
    }

    // MARK: - Role picker

    private var rolePicker: some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "person.2.fill", caption: "Pair with a partner nearby")

            VStack(spacing: 12) {
                actionButton(
                    title: "Host the Race",
                    subtitle: "Be the leader — your phone runs the timer",
                    systemImage: "antenna.radiowaves.left.and.right",
                    isPrimary: true
                ) {
                    coordinator.startHosting()
                }

                actionButton(
                    title: "Join a Partner",
                    subtitle: "Find a host nearby and pair to their race",
                    systemImage: "magnifyingglass",
                    isPrimary: false
                ) {
                    coordinator.startJoining()
                }
            }
        }
    }

    // MARK: - Hosting panel

    private func hostingPanel(transport: DuoSession.State) -> some View {
        VStack(spacing: 18) {
            heroIcon(
                symbol: "antenna.radiowaves.left.and.right",
                caption: "Waiting for partner…"
            )

            VStack(spacing: 6) {
                Text("Visible as")
                    .capsLabelStyle()

                Text(coordinator.localDisplayName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
            }

            Text("Ask your partner to tap **Join a Partner** on their phone — your name will appear in their list.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if case .connecting(let peerName) = transport {
                connectingChip(peerName: peerName)
            }
        }
    }

    // MARK: - Joining panel

    private func joiningPanel(transport: DuoSession.State) -> some View {
        VStack(spacing: 16) {
            heroIcon(symbol: "magnifyingglass", caption: "Looking for hosts…")

            if coordinator.session.nearbyPeers.isEmpty {
                Text("Make sure your partner has tapped **Host the Race**, and that both phones have Bluetooth + Wi-Fi enabled.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(coordinator.session.nearbyPeers) { peer in
                        peerRow(peer: peer)
                    }
                }
            }

            if case .connecting(let peerName) = transport {
                connectingChip(peerName: peerName)
            }
        }
    }

    private func peerRow(peer: PeerHandle) -> some View {
        Button {
            coordinator.invite(peer)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone.gen3")
                    .font(.title3)
                    .foregroundStyle(Color.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Tap to send invite")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ready panel

    private func readyPanel(partnerName: String, partnerDivision: Division) -> some View {
        VStack(spacing: 18) {
            heroIcon(symbol: "checkmark.seal.fill", caption: "Paired")

            VStack(spacing: 4) {
                Text("Connected to")
                    .capsLabelStyle()
                Text(partnerName)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(partnerDivision.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text("Either of you can tap **Next Station** during the race. Times save to both your histories.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button {
                onReady()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 18, weight: .heavy))
                    Text("Start Duo Race")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(
                    LinearGradient(
                        colors: [Color.accent, Color.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.4 : 0.22),
                    radius: 18,
                    y: 0
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shared components

    private func heroIcon(symbol: String, caption: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            .shadow(
                color: Color.accent.opacity(colorScheme == .dark ? 0.3 : 0.16),
                radius: 24,
                y: 0
            )

            Text(caption)
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.heavy))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isPrimary ? Color.onAccent.opacity(0.8) : Color.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .opacity(0.7)
            }
            .foregroundStyle(isPrimary ? Color.onAccent : Color.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(
                        isPrimary
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color.accent, Color.accent.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(Color.surface)
                    )
            )
            .shadow(
                color: isPrimary
                    ? Color.accent.opacity(colorScheme == .dark ? 0.30 : 0.16)
                    : Color.clear,
                radius: 16,
                y: 0
            )
        }
        .buttonStyle(.plain)
    }

    private func connectingChip(peerName: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.accent)
            Text("Connecting to \(peerName)…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.surface)
        )
    }
}

#endif
