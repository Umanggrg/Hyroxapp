import SwiftUI
import SwiftData

// Wireframe §05.2 All Stats page. Pushed from a profile-level
// "See all stats" entry. Three sections:
//
//   • FINISH TIMES — 3-cell grid: BEST / AVG / RACES
//   • STATION PBs — per-workout-station best time list
//   • MILESTONES — chip wrap of earned + upcoming badges
//
// The profile already has individual cards for each of these
// concerns, but the wireframe spec is a consolidated deep-dive
// surface. This screen pulls all three into one push so the
// athlete can see their archive at a glance.
struct AllStatsView: View {

    let races: [Race]

    private var finishedRaces: [Race] {
        races.filter { $0.isFinished }
    }

    // Best total time across all finished races. nil when the
    // athlete has zero finished races (empty state handled
    // outside this view).
    private var bestFinish: TimeInterval? {
        finishedRaces.compactMap(\.totalDuration).min()
    }

    private var avgFinish: TimeInterval? {
        let totals = finishedRaces.compactMap(\.totalDuration)
        guard !totals.isEmpty else { return nil }
        return totals.reduce(0, +) / Double(totals.count)
    }

    // Per-station best — one row per workout station type. nil
    // entry when the athlete has never logged a split for that
    // station (still rendered so the layout doesn't shuffle as
    // the athlete fills in their archive).
    private var stationPBs: [(station: Station, best: TimeInterval?)] {
        let workoutStations: [Station] = [
            .skiErg, .sledPush, .sledPull, .burpeeBroadJumps,
            .rowing, .farmersCarry, .sandbagLunges, .wallBalls
        ]
        return workoutStations.map { station in
            let splits = finishedRaces
                .flatMap(\.splits)
                .filter { $0.station == station }
                .map(\.duration)
            return (station, splits.min())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                finishTimesSection
                stationPBsSection
                milestonesSection
                Spacer(minLength: 12)
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.vertical, Layout.screenMargin)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("All stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Finish times

    private var finishTimesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FINISH TIMES").capsLabelStyle()

            HStack(spacing: 12) {
                finishStatCell(
                    caption: "BEST",
                    value: bestFinish.map(RaceStats.format) ?? "—",
                    tint: Color.accent
                )
                finishStatCell(
                    caption: "AVG",
                    value: avgFinish.map(RaceStats.format) ?? "—",
                    tint: Color.textPrimary
                )
                finishStatCell(
                    caption: "RACES",
                    value: "\(finishedRaces.count)",
                    tint: Color.textPrimary
                )
            }
            .padding(Layout.cardPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    private func finishStatCell(caption: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Station PBs

    private var stationPBsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STATION PBs").capsLabelStyle()

            VStack(spacing: 4) {
                ForEach(stationPBs, id: \.station) { pair in
                    stationPBRow(station: pair.station, best: pair.best)
                }
            }
        }
    }

    private func stationPBRow(station: Station, best: TimeInterval?) -> some View {
        HStack {
            Text(station.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(best.map(RaceStats.format) ?? "—")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(best == nil ? Color.textTertiary : Color.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surface)
        )
    }

    // MARK: - Milestones

    // Lightweight chip wrap for earned milestones. For v1 we
    // surface a small static set; future iterations can pull
    // from the BadgeAwarder layer the existing BadgesView uses.
    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MILESTONES").capsLabelStyle()

            FlowLayout(spacing: 5) {
                ForEach(earnedMilestones, id: \.label) { milestone in
                    milestoneChip(milestone)
                }
            }
        }
    }

    private func milestoneChip(_ milestone: Milestone) -> some View {
        let tint = milestone.isEarned ? Color.accent : Color.textSecondary
        let border = milestone.isEarned ? Color.accent : Color.divider

        return Text(milestone.label)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(milestone.isEarned ? Color.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
    }

    // Derive milestone state from the athlete's actual race
    // archive. Three illustrative ones for v1; more can layer
    // in from BadgeAwarder once we wire that integration.
    private var earnedMilestones: [Milestone] {
        let bestSeconds = bestFinish ?? .infinity
        let raceCount = finishedRaces.count
        let allWallBallsBest = finishedRaces
            .flatMap(\.splits)
            .filter { $0.station == .wallBalls }
            .map(\.duration)
            .min()

        return [
            Milestone(
                label: bestSeconds < 4800 ? "⚡ Sub-1:20" : "⚡ Sub-1:20 (chase it)",
                isEarned: bestSeconds < 4800
            ),
            Milestone(
                label: raceCount >= 10 ? "🔥 10 race milestone" : "🔥 10 races (\(raceCount)/10)",
                isEarned: raceCount >= 10
            ),
            Milestone(
                label: allWallBallsBest != nil ? "🏆 Wall Balls logged" : "Wall Balls (not yet)",
                isEarned: allWallBallsBest != nil
            ),
        ]
    }

    private struct Milestone {
        let label: String
        let isEarned: Bool
    }
}

// FlowLayout lives in `Shared/Components/TagsSection.swift` —
// declared as `SwiftUI.Layout` there to dodge the name collision
// with `Theme.swift`'s `enum Layout`. We reuse it here so we
// don't carry two copies of the same wrap-layout code.
