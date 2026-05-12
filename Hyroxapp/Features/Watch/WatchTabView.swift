import SwiftUI
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// Tab 5 — Devices (formerly "Watch"). Top-level surface for
// the athlete to see what's connected and what each device
// contributes to their race. Originally Watch-only when the
// v1 design system shipped; expanded to multi-device in §19
// when AirPods Pro 3 ingestion landed.
//
// Current scope:
//   • Apple Watch section — pairing + app-installed +
//     reachable status, pairing footer when not paired
//   • AirPods section — connected state, model name, motion
//     + HR sensor availability (§19.1), pairing footer when
//     not connected
//   • Shared In-race toggles — voice cues, coaching cues,
//     pace chip, predicted finish, Live Activity. Bind
//     directly to UserProfile so flipping here writes
//     through to the same source-of-truth Settings reads.
//
// Tab bar label stays "Watch" because the SF Symbol icon
// is `applewatch` and the existing routing key is `.watch`.
// Inside, the navigation title is "Devices" — honestly
// reflects the multi-device scope without a tab restructure.
//
// Deferred to v2 (separate file or substantial expansion):
//   • Real-time HR streaming health gauge
//   • Live-activity preview tile
//   • Per-feature "what this does" inline explainers
//   • A "Re-install on Watch" CTA wired to WKExtension
struct WatchTabView: View {

    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    // Refresh tick — incremented by the .onAppear / scenePhase
    // listener so the pairing status block re-renders if the
    // user toggled pairing in the iOS Watch app, swapped
    // watches, or installed the companion since the last
    // visit. WCSession doesn't surface a SwiftUI-observable
    // wrapper; this manual tick is the lightweight pattern.
    @State private var refreshTick: Int = 0

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.md) {
                        hero
                        watchSection
                        airPodsSection
                        if let profile = profiles.first {
                            inRaceSection(profile: profile)
                        }
                        Spacer(minLength: Spacing.lg)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Devices")
            .hyroxNavigationBar(inline: false)
            .onAppear {
                refreshTick += 1
                // §19 — refresh the AirPods / Watch connection
                // registry too. Audio-route changes auto-fire
                // while the app is backgrounded, but WCSession
                // pairing changes don't, so a manual refresh on
                // appear keeps the status rows honest.
                SensorSourceRegistry.shared.refresh()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshTick += 1
                    SensorSourceRegistry.shared.refresh()
                }
            }
        }
    }

    // MARK: - Hero

    // Brand moment at the top — coral-tinted Watch + AirPods
    // glyphs sharing a single halo to signal the multi-device
    // story. Reads as "these are the sensors that make Trakrr
    // work for you." Caps subtitle picks the right copy based
    // on what's actually connected so the hero isn't lying to
    // an iPhone-only athlete.
    private var hero: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 112, height: 112)
                Circle()
                    .stroke(Color.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 112, height: 112)
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            isPaired ? Color.accent : Color.accent.opacity(0.35)
                        )
                    Image(systemName: "airpodspro")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(
                            isAirPodsConnected ? Color.accent : Color.accent.opacity(0.35)
                        )
                }
            }
            .padding(.top, Spacing.sm)

            Text(heroSubtitle)
                .capsLabelStyle()
        }
        .frame(maxWidth: .infinity)
    }

    // Subtitle picks the right brand line based on what's
    // actually connected. Avoids a generic "Connected devices"
    // that reads as marketing copy.
    private var heroSubtitle: String {
        switch (isPaired, isAirPodsConnected) {
        case (true, true):   return "Wrist + ears connected"
        case (true, false):  return "Wrist-first racing"
        case (false, true):  return "AirPods connected"
        case (false, false): return "Connect a sensor to begin"
        }
    }

    // MARK: - Watch section

    // Section wrapping the Apple Watch pairing / reachability /
    // installed status. Composes the caps section label, the
    // existing status block, and the existing pairing footer
    // (when not paired) into one logical unit.
    private var watchSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Apple Watch").capsLabelStyle()
                .padding(.horizontal, 4)
            watchStatusBlock
            if !isPaired {
                watchPairingFooter
            }
        }
    }

    private var watchStatusBlock: some View {
        VStack(spacing: Spacing.sm) {
            statusRow(
                label: "Paired",
                value: isPaired ? "Yes" : "Not paired",
                tint: isPaired ? Color.onPace : Color.warning,
                symbol: isPaired ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            Divider().background(Color.divider)
            statusRow(
                label: "App installed",
                value: isWatchAppInstalled ? "Yes" : "No",
                tint: isWatchAppInstalled ? Color.onPace : Color.textTertiary,
                symbol: isWatchAppInstalled ? "checkmark.circle.fill" : "circle"
            )
            Divider().background(Color.divider)
            statusRow(
                label: "Reachable now",
                value: isReachable ? "Yes" : "No",
                tint: isReachable ? Color.onPace : Color.textTertiary,
                symbol: isReachable ? "dot.radiowaves.left.and.right" : "dot.radiowaves.left.and.right"
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - AirPods section (§19)

    // Parallel device card for AirPods Pro 1+ / 4 / Max / Pro 3.
    // Reads from SensorSourceRegistry (which auto-subscribes
    // to audio-route changes) so connecting / disconnecting
    // AirPods updates this section in real time. Status rows
    // cover: connected, model name, motion sensor capability
    // (false on AirPods 2/3 non-Pro), heart rate capability
    // (true only on AirPods Pro 3 today).
    private var airPodsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("AirPods").capsLabelStyle()
                .padding(.horizontal, 4)
            airPodsStatusBlock
            if !isAirPodsConnected {
                airPodsPairingFooter
            }
        }
    }

    private var airPodsStatusBlock: some View {
        let registry = SensorSourceRegistry.shared
        let connected = isAirPodsConnected
        let modelName = registry.airPodsModelName

        return VStack(spacing: Spacing.sm) {
            statusRow(
                label: "Connected",
                value: connected ? "Yes" : "Not connected",
                tint: connected ? Color.onPace : Color.textTertiary,
                symbol: connected ? "checkmark.circle.fill" : "circle"
            )
            Divider().background(Color.divider)
            statusRow(
                label: "Model",
                value: modelName ?? "—",
                tint: connected ? Color.textPrimary : Color.textTertiary,
                symbol: "airpodspro"
            )
            Divider().background(Color.divider)
            statusRow(
                label: "Motion sensors",
                value: registry.hasAirPodsMotion ? "Available" : "Not on this model",
                tint: registry.hasAirPodsMotion ? Color.onPace : Color.textTertiary,
                symbol: registry.hasAirPodsMotion ? "figure.run" : "circle"
            )
            Divider().background(Color.divider)
            statusRow(
                label: "Heart rate",
                value: registry.hasAirPodsHR ? "Available" : "Pro 3 only",
                tint: registry.hasAirPodsHR ? Color.onPace : Color.textTertiary,
                symbol: registry.hasAirPodsHR ? "heart.fill" : "heart"
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func statusRow(
        label: String,
        value: String,
        tint: Color,
        symbol: String
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(label)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
        }
    }

    // MARK: - In-race toggles

    // Subset of `UserProfile` toggles that specifically govern the
    // in-race Watch (and phone) experience. Each binds directly to
    // the profile model so a flip here writes through to SwiftData
    // immediately and is visible in Settings without a sync.
    private func inRaceSection(profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("In-race")
                .capsLabelStyle()
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                toggleRow(
                    title: "Voice cues",
                    subtitle: "Spoken \"Next: Sled Push\" between stations.",
                    isOn: Binding(
                        get: { profile.audioCuesEnabled },
                        set: { profile.audioCuesEnabled = $0 }
                    )
                )
                Divider().background(Color.divider).padding(.leading, Layout.cardPadding)
                toggleRow(
                    title: "Coaching cues",
                    subtitle: "HOLD / SLOW / PUSH on the HR chip and Watch.",
                    isOn: Binding(
                        get: { profile.coachingCuesEnabled },
                        set: { profile.coachingCuesEnabled = $0 }
                    )
                )
                Divider().background(Color.divider).padding(.leading, Layout.cardPadding)
                toggleRow(
                    title: "Pace chip",
                    subtitle: "Ahead / on pace / behind delta in the header.",
                    isOn: Binding(
                        get: { profile.paceChipEnabled },
                        set: { profile.paceChipEnabled = $0 }
                    )
                )
                Divider().background(Color.divider).padding(.leading, Layout.cardPadding)
                toggleRow(
                    title: "Predicted finish",
                    subtitle: "Live projection beneath the race timer.",
                    isOn: Binding(
                        get: { profile.predictedFinishEnabled },
                        set: { profile.predictedFinishEnabled = $0 }
                    )
                )
                Divider().background(Color.divider).padding(.leading, Layout.cardPadding)
                toggleRow(
                    title: "Live Activity",
                    subtitle: "Lock-screen + Dynamic Island race timer.",
                    isOn: Binding(
                        get: { profile.liveActivityEnabled },
                        set: { profile.liveActivityEnabled = $0 }
                    )
                )
            }
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.accent)
        }
        .padding(Layout.cardPadding)
    }

    // MARK: - Pairing footers

    // Renders only when the Apple Watch isn't paired. Tells the
    // athlete the next concrete step rather than leaving the
    // empty-state ambiguous.
    private var watchPairingFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Pair your Apple Watch")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Open the iOS Watch app and pair an Apple Watch. Once paired, install Trakrr on the watch and the in-race controls will become available from the wrist.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Renders when no AirPods are currently in the audio route.
    // Two-paragraph copy explains how to connect and what
    // pairing unlocks — sets expectations about which model
    // gets which features (motion is Pro 1+, HR is Pro 3).
    private var airPodsPairingFooter: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Connect your AirPods")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Pop your AirPods in your ears or select them from Control Center → AirPlay. Once connected, Trakrr surfaces the right features for your model — cadence from AirPods Pro 1+ and continuous heart rate from AirPods Pro 3.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - State helpers

    // Reads WCSession.default lazily so the view stays platform-
    // safe. `refreshTick` is referenced inside each helper to
    // force re-evaluation when the tick changes (SwiftUI tracks
    // it via the @State read). The default-value branches keep
    // the file compiling on macOS / unit-test targets without
    // WatchConnectivity.
    private var isPaired: Bool {
        _ = refreshTick
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isPaired
        #else
        return false
        #endif
    }

    private var isWatchAppInstalled: Bool {
        _ = refreshTick
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isWatchAppInstalled
        #else
        return false
        #endif
    }

    private var isReachable: Bool {
        _ = refreshTick
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
        #else
        return false
        #endif
    }

    // §19 — true when any AirPods are currently the active
    // audio output, regardless of model. The status block
    // renders specific capability detail (motion / HR) per
    // SensorSourceRegistry so the athlete knows what their
    // particular AirPods can do for Trakrr. `_ = refreshTick`
    // ties this property to the same re-evaluation trigger
    // the Watch status helpers use — guarantees a fresh
    // reading after a scene-phase return.
    private var isAirPodsConnected: Bool {
        _ = refreshTick
        let registry = SensorSourceRegistry.shared
        return registry.hasAirPodsMotion || registry.hasAirPodsHR
    }
}
