import SwiftUI
import SwiftData
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// Tab 5 — Watch. New top-level surface introduced in the v1
// design-system shift. Pre-v1 the Watch tab didn't exist; watch-
// related controls were buried inside Settings and pairing /
// reachability state was invisible to the athlete unless they
// opened Apple's first-party Watch app.
//
// v1 scope (this file):
//   • Pairing + reachability status block at the top
//   • Section of toggles that affect the in-race Watch
//     experience — voice cues, coaching cues, pace chip,
//     predicted finish projection, Live Activity. Bound to
//     `UserProfile` directly so flipping a switch here updates
//     the same source-of-truth the existing Settings screen
//     writes to.
//   • Footer pairing instructions when the watch isn't paired
//
// Deferred to v2 (separate file or substantial expansion):
//   • Real-time HR streaming health gauge
//   • Live-activity preview tile
//   • Per-feature "what this does" inline explainers
//   • A "Re-install on Watch" CTA wired to WKExtension
//
// `@Bindable` on the profile is what makes the toggles
// write-through to SwiftData on flip. Identical pattern to
// SettingsView; the same toggles live in both places by
// design — Settings holds the canonical list, the Watch tab
// surfaces the subset that's specifically watch-shaped so
// athletes don't have to dig through Settings mid-pairing.
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
                        statusBlock
                        if let profile = profiles.first {
                            inRaceSection(profile: profile)
                        }
                        if !isPaired {
                            pairingFooter
                        }
                        Spacer(minLength: Spacing.lg)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, Spacing.md)
                }
            }
            .navigationTitle("Watch")
            .hyroxNavigationBar(inline: false)
            .onAppear { refreshTick += 1 }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { refreshTick += 1 }
            }
        }
    }

    // MARK: - Hero

    // Brand moment at the top of the screen — coral-tinted
    // applewatch glyph in a soft halo. Single visual anchor
    // before the data-dense status block. Sized to read at
    // glance distance without dominating the screen.
    private var hero: some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.accent.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                Image(systemName: "applewatch")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(Color.accent)
            }
            .padding(.top, Spacing.sm)

            Text("Wrist-first racing")
                .capsLabelStyle()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status block

    private var statusBlock: some View {
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

    // MARK: - Pairing footer

    // Only renders when the Apple Watch isn't paired. Tells the
    // athlete the next concrete step rather than leaving the
    // empty-state ambiguous.
    private var pairingFooter: some View {
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
}
