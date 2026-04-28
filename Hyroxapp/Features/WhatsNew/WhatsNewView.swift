import SwiftUI

// First-launch-after-upgrade sheet. Surfaces the headline additions
// in the latest version so they're discoverable instead of buried.
//
// Triggered from `ContentView` when `UserProfile.lastSeenWhatsNewVersion`
// doesn't match the current `CFBundleShortVersionString`. After
// dismiss, ContentView writes the current version back so the sheet
// doesn't re-appear until the next version bump.
//
// Layout: `HeroBackdrop` + caps wordmark header + a vertical scroll
// of feature cards. Each card has an icon in a coral halo, a title,
// and a one-line description. Same brand language as Onboarding's
// hero icon treatment so the user immediately recognizes "this is
// Trakr speaking to me."
//
// Content is a static list — features ship as code changes, so the
// list ships as code too. When v0.3 lands, edit `Self.features` and
// bump the marketing version; the next launch shows the new list.
struct WhatsNewView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // The version this sheet describes. Surfaced in the header so
    // users can tell which bump they're seeing notes for. Defaults
    // to the runtime app version; tests / previews can override.
    let version: String

    init(version: String = WhatsNewView.currentMarketingVersion) {
        self.version = version
    }

    var body: some View {
        ZStack {
            HeroBackdrop(.standard)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        header

                        VStack(spacing: 14) {
                            ForEach(Self.features(forVersion: version)) { feature in
                                featureCard(feature)
                            }
                        }
                        .padding(.horizontal, Layout.screenMargin)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 32)
                }

                // Pinned dismiss CTA at the bottom. Coral primary
                // because we want the user to actually tap through
                // and start using the new stuff.
                Button {
                    Haptics.impact(.medium)
                    dismiss()
                } label: {
                    Text("Let's Go")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
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
                            color: Color.accent.opacity(colorScheme == .dark ? 0.35 : 0.20),
                            radius: 18,
                            y: 0
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text("TRAKR")
                .font(.caption.weight(.heavy))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Text("What's New")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("Version \(version)")
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Feature card

    private func featureCard(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon in a coral halo — same treatment used by
            // Onboarding's step heroes, scaled smaller for the
            // card row.
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.14))
                    .frame(width: 52, height: 52)
                Image(systemName: feature.symbol)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.accent)
            }
            .shadow(
                color: Color.accent.opacity(colorScheme == .dark ? 0.25 : 0.14),
                radius: 14,
                y: 0
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text(feature.detail)
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Feature data

    struct Feature: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    // The headline additions for this version. Ordered top-to-
    // bottom by impact / "what would I most want a returning user
    // to know about." Edit + bump version on every release; the
    // list rotates per release.
    static func features(forVersion version: String) -> [Feature] {
        // Version-keyed feature lists. Each version's headline
        // additions are returned for that version exactly so a
        // user upgrading multiple versions sees only the most
        // recent set (what's actually new for them) — versus
        // a stacking changelog which gets unreadable.
        //
        // When a new version ships, add a new branch above and
        // leave the old ones for any user catching up via a
        // delayed install.
        switch version {
        case let v where v.hasPrefix("1.1"):
            return featuresV1_1()
        default:
            // Earlier versions and any out-of-band test runs
            // fall back to the v1.0 set — the original public
            // launch list.
            return featuresV1_0()
        }
    }

    // v1.0 — original public launch. Duo, appearance, roxzone,
    // weight projection, watch polish. Kept around so users
    // who skip 1.0 → 1.1 (highly unlikely but possible) still
    // see something coherent.
    private static func featuresV1_0() -> [Feature] {
        [
            Feature(
                id: "duo",
                symbol: "person.2.fill",
                title: "Duo Races",
                detail: "Pair with a training partner over Bluetooth and Wi-Fi. Tap Duo on the Race screen, host or join, and either of you can advance the race. Saves to both Histories."
            ),
            Feature(
                id: "appearance",
                symbol: "circle.lefthalf.filled",
                title: "Light, Dark, or System",
                detail: "Pick your appearance in Settings → Appearance. Coral stays brand-true in either mode; off-white surfaces and warm grays for the new daytime look."
            ),
            Feature(
                id: "roxzone",
                symbol: "arrow.right.circle.fill",
                title: "Roxzone Tracking",
                detail: "Two-tap advance: end a station, time the transition, then start the next. The HYROX-specific 'roxzone' metric. Toggle on in Settings → Race ritual."
            ),
            Feature(
                id: "weight-projection",
                symbol: "scalemass.fill",
                title: "Race-Day Weight Projection",
                detail: "Train at sub-race weight? Tap any station's detail to see what the same effort would cost at official HYROX weight. Coaching honesty, baked in."
            ),
            Feature(
                id: "watch-polish",
                symbol: "applewatch",
                title: "Watch Race Screen",
                detail: "Wrist-tuned brand identity: the 16-bar fingerprint as live progress, hero timer with coral underglow, hold-to-finish on the final station to prevent mistaps."
            ),
        ]
    }

    // v1.1 — effort everywhere. Per-station effort categories,
    // hardest-station insight, race privacy toggle, streak-
    // at-risk surfacing. The intensity-story arc that ties
    // every post-race surface together.
    private static func featuresV1_1() -> [Feature] {
        [
            Feature(
                id: "effort-everywhere",
                symbol: "bolt.fill",
                title: "Effort, Everywhere",
                detail: "Every race card now shows its effort category at a glance. Inside, each split row gets a colored dot — recovery, moderate, high, very high — so you can see which stations cooked you without leaving the summary."
            ),
            Feature(
                id: "hardest-station",
                symbol: "flame.fill",
                title: "Hardest Station Callout",
                detail: "Post-race insights now name the single workout station that demanded the biggest physiological cost. Pulls from HR-time integration; only fires when one station genuinely stood out from the pack."
            ),
            Feature(
                id: "privacy",
                symbol: "lock.fill",
                title: "Per-Race Privacy",
                detail: "New toggle on every race — public or private. Local History always shows everything; private races stay out of any future feed or leaderboard. Forward-compatible with the social work coming in v2."
            ),
            Feature(
                id: "streak-at-risk",
                symbol: "exclamationmark.triangle.fill",
                title: "Streak-at-Risk Banner",
                detail: "On the day your streak is in danger of breaking, Profile now surfaces a warning banner — and the evening reminder gets sharper copy. Defend the streak, or don't; either way you'll know."
            ),
            Feature(
                id: "duo-pb",
                symbol: "person.2.fill",
                title: "Mode-Aware PBs",
                detail: "Duo and solo PBs are now tracked separately. Cracking your fastest duo race fires a distinct insight from cracking your fastest solo — because they're not really the same race."
            ),
        ]
    }

    // Convenience accessor — reads CFBundleShortVersionString from
    // the main bundle. Same value used by Settings → About so the
    // What's New sheet's header matches what the user sees there.
    static var currentMarketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
}

#Preview {
    WhatsNewView(version: "1.0")
}
