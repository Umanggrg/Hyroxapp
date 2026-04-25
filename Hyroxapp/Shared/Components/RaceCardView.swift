import SwiftUI

// The canonical race card. Strava-inspired anatomy described in CLAUDE.md §5:
// header (title + relative time) → hero stat (total time) → supporting stats
// (3-up grid) → optional badges (e.g. PB). Lives in Shared/Components/ so it
// can appear anywhere we need to render a race row:
//   - History feed (primary consumer today)
//   - Profile "Recent races" section
//   - Future v1 social feed — a flag for social actions (like/comment/share)
//     will slot in at the bottom without changing the rest of the card.
//
// The PB badge is derived from `allRaces`, not a property on the race model
// itself, because "was this a PB at the time it was set?" depends on every
// earlier race. Passing the slice at render time keeps the model clean and
// lets callers decide what pool of races to evaluate against (all races,
// this month, just this user's, etc. when social lands).
struct RaceCardView: View {

    let race: Race
    let allRaces: [Race]

    private var isPB: Bool {
        RaceStats.wasPBWhenSet(race, among: allRaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo (when present) sits flush at the top of the card
            // with no padding so it reads as a true hero image —
            // exactly the way Strava's activity cards anchor on the
            // route map. Without a photo, this branch is skipped and
            // the card renders compact, identical to before.
            #if canImport(UIKit)
            if let data = race.photoData, let image = UIImage(data: data) {
                photoHero(image: image)
            }
            #endif

            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                supportingStats
                if isPB {
                    pbBadge
                }
            }
            .padding(Layout.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        // Clip the entire card so the photo's top corners follow the
        // card's rounded shape; without this the image overflows the
        // background's rounded rectangle on the top edge.
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }

    // MARK: - Photo hero (top banner when race has a photo)

    #if canImport(UIKit)
    private func photoHero(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            // Subtle gradient fade at the bottom so a continuation
            // into the card body doesn't read as a hard edge — this
            // gradient is what makes the image feel like part of the
            // card rather than a stamped-on rectangle.
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.surface.opacity(0),
                        Color.surface.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
    }
    #endif

    // MARK: - Sections

    private var header: some View {
        HStack {
            // Show user-set title when present; fall back to the
            // generic "HYROX Race" label otherwise. Two-line stack
            // when a custom name exists so the kind indicator
            // ("HYROX RACE" caps) stays visible — same pattern
            // Strava uses for activities with a custom title.
            VStack(alignment: .leading, spacing: 2) {
                if !race.name.isEmpty {
                    Text("HYROX RACE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(Color.textTertiary)
                    Text(race.name)
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                } else {
                    Text("HYROX Race")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                }
            }
            Spacer()
            Text(race.startedAt.formatted(.relative(presentation: .named)))
                .font(.metadata)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(RaceStats.totalTime(race))
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text("TOTAL TIME")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var supportingStats: some View {
        HStack(spacing: 0) {
            statTile(value: RaceStats.bestRun(race), label: "Best Run")
            statDivider
            statTile(value: RaceStats.avgRun(race), label: "Avg Run")
            statDivider
            statTile(value: RaceStats.wallBalls(race), label: "Wall Balls")
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 32)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var pbBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption)
            Text("New PB")
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.success)
    }
}
