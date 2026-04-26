import SwiftUI

// Athlete-identity shareable card — the third member of the share-
// card family alongside RaceShareCardView (per-race) and
// MonthlyRecapShareCardView (per-month). Where those two are
// "this thing happened," this card answers "this is who I am as
// a HYROX athlete." Story aspect (1080×1920 at 3× scale) by default
// because it's primarily for IG / Snapchat / TikTok stories — the
// "post this on your profile" piece of social ammunition.
//
// Anatomy, top to bottom:
//   • Caps wordmark "HYROX ATHLETE"
//   • Hero: avatar circle + display name + @handle + division pill
//   • 4-tile stat grid: races, PB time, PBs set count, streak peak
//   • HYROX Performance pillar strip (Strength / Endurance / Engine)
//   • Top earned badge callout (when athlete has any badges)
//   • HYROXAPP wordmark footer
//
// Hidden gracefully on cold start (no races, no badges) — every
// section that depends on data is conditional. Worst case the card
// renders avatar + name + zeros, which is still a valid "joining
// the platform" share.
//
// Guarded `#if !os(watchOS)` because it leans on UIImage / iOS
// theme tokens.
#if !os(watchOS)
struct ProfileShareCardView: View {

    let profile: UserProfile
    let races: [Race]
    let templates: [WorkoutTemplate]

    static let canvasSize = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            // Same coral-tinted radial as the monthly recap — keeps
            // the share-card family visually consistent. Slightly
            // more centered so the avatar reads as the hot spot of
            // the composition.
            RadialGradient(
                colors: [
                    Color.accent.opacity(0.30),
                    Color(hex: 0x0A0A0B)
                ],
                center: .center,
                startRadius: 30,
                endRadius: Self.canvasSize.height * 0.7
            )
            .background(Color(hex: 0x0A0A0B))

            VStack(spacing: 0) {
                wordmarkHeader
                    .padding(.top, 28)

                Spacer(minLength: 12)

                identityBlock

                Spacer(minLength: 20)

                statsGrid
                    .padding(.horizontal, 28)

                Spacer(minLength: 16)

                if HyroxPerformanceScoreView.hasAnyData(in: races) {
                    pillarStrip
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 16)

                if let badge = topEarnedBadge {
                    badgeCallout(badge)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 16)

                appFooter
                    .padding(.bottom, 28)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .background(Color(hex: 0x0A0A0B))
        // Force dark for the export — same rationale as the
        // RaceShareCardView: Instagram/Stories cards always render
        // as branded dark, regardless of the user's app theme.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header (caps wordmark)

    private var wordmarkHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 11, weight: .bold))
            Text("HYROX ATHLETE")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Color.accent)
    }

    // MARK: - Identity block (avatar + name + handle + division)

    private var identityBlock: some View {
        VStack(spacing: 10) {
            avatar
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.accent.opacity(0.6), lineWidth: 2)
                )

            Text(profile.displayName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                if !profile.handle.isEmpty {
                    Text("@\(profile.handle)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                Text("·")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                Text(profile.resolvedDivision.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.accent.opacity(0.18))
                    )
            }
        }
    }

    // Avatar: profile photo if present, otherwise a coral-tinted
    // circle with the athlete's initial — same fallback we use on
    // RaceShareCardView so the visual language is consistent.
    @ViewBuilder
    private var avatar: some View {
        if let data = profile.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(Color.accent.opacity(0.25))
                Text(initial)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accent)
            }
        }
    }

    private var initial: String {
        String(profile.displayName.prefix(1)).uppercased()
    }

    // MARK: - 4-tile stat grid (races / PB / PBs set / streak peak)

    private var statsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile(value: "\(finishedRaceCount)", label: "RACES")
                statTile(value: pbString, label: "PB", isAccent: true)
            }
            HStack(spacing: 10) {
                statTile(value: "\(totalPBsSet)", label: "PBs SET")
                statTile(value: "\(longestStreak)", label: "BEST STREAK")
            }
        }
    }

    private func statTile(value: String, label: String, isAccent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isAccent ? Color.accent : Color.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface)
        )
    }

    // MARK: - Pillar strip (Strength / Endurance / Engine)

    // Tight inline strip — name + value per pillar, rendered as
    // three columns. More compact than the full HyroxPerformanceScoreView
    // tile grid because the share card has limited vertical real
    // estate. Hidden when no pillar has data (cold start).
    private var pillarStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(HyroxPillar.allCases.enumerated()), id: \.offset) { index, pillar in
                let best = RaceStats.pillarTheoreticalBest(pillar, among: races)
                VStack(spacing: 4) {
                    Text(pillar.displayName.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(pillar.color)
                    Text(best.map(RaceStats.format) ?? "—")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity)

                if index < HyroxPillar.allCases.count - 1 {
                    Rectangle()
                        .fill(Color.divider)
                        .frame(width: 1, height: 28)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface)
        )
    }

    // MARK: - Top badge callout

    private func badgeCallout(_ badge: Badge) -> some View {
        HStack(spacing: 12) {
            Image(systemName: badge.symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(badge.color)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(badge.color.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("LATEST BADGE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(badge.color)
                Text(badge.displayName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(badge.color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(badge.color.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var appFooter: some View {
        VStack(spacing: 6) {
            Text("HYROXAPP")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2.0)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .stroke(Color.accent.opacity(0.5), lineWidth: 1)
                )

            Text("Race · Track · Compete")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Computed values

    private var finishedRaceCount: Int {
        races.filter(\.isFinished).count
    }

    // PB total race time. Format using shared formatter; "—" when
    // no finished races yet so the cold-start card still renders.
    private var pbString: String {
        guard let pb = RaceStats.personalBest(races) else { return "—" }
        return RaceStats.format(pb)
    }

    // Total count of races that set a NEW total-time PB at the
    // moment they were saved. Same predicate the per-card trophy
    // uses, so this number aligns with what the athlete sees on
    // their feed.
    private var totalPBsSet: Int {
        races.filter { RaceStats.wasPBWhenSet($0, among: races) }.count
    }

    private var longestStreak: Int {
        RaceStreaks.longestStreak(in: races)
    }

    // Pick the most prestigious earned badge as the callout. We
    // sort by the natural Badge.allCases order which goes from
    // "first race" (entry-level) → "perfect day" (elite tier),
    // and pick the LAST earned one. That gives us the highest-
    // tier badge the athlete has earned, which is the most worth
    // bragging about.
    private var topEarnedBadge: Badge? {
        let earned = BadgeAwarder.evaluate(races: races, templates: templates)
        return Badge.allCases.last { earned.contains($0) }
    }
}
#endif
