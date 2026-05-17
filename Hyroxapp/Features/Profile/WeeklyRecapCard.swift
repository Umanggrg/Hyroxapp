import SwiftUI

// §38 Whoop pattern 3 + 5 — weekly recap card.
//
// Surfaces a Monday-morning ritual surface in the Trakrr Profile.
// Whoop's strongest retention surface is their Monday weekly
// assessment; this is the HYROX-cadence equivalent. Sits inside
// the Next Up section so it's the first thing the athlete sees
// when they open Profile.
//
// Three signals layered:
//
//   1. SESSION COUNT (this week vs last). Drives the headline
//      tone — "Strong week" (≥3 sessions), "Steady" (2),
//      "Quiet" (1), "Rest week" (0).
//
//   2. ENGINE SCORE DELTA. Engine Score is already a 5-race
//      rolling rollup, so directly comparing "this week's avg
//      Engine Score" to "last week's avg" works without
//      additional smoothing. Drives the green/amber tint of
//      the trajectory line.
//
//   3. TRAINING LOAD (Whoop strain equivalent). Sum of
//      RaceStats.effortScore across this week's finished
//      races. Effort score is intensity-weighted minutes —
//      sums cleanly across races. Target zone is 14–18 for
//      competition-prep, 8–14 for base, calibrated against
//      typical HYROX athlete training volume.
//
// Forward-looking line references next race event countdown
// when one is pinned, otherwise omits. Keeps the card honest:
// if the athlete has no race on the calendar, we don't fake
// a "12 days until race" line.
//
// Self-hides when athlete has zero finished races (no signal
// to recap). For a single-finished-race athlete, renders with
// "First week tracked. Let's build a pattern." copy so the
// surface still teaches what's coming.
struct WeeklyRecapCard: View {

    let races: [Race]
    let maxHR: Int
    let nextRaceEvent: RaceEvent?

    private let now: Date

    init(
        races: [Race],
        maxHR: Int,
        nextRaceEvent: RaceEvent? = nil,
        now: Date = Date()
    ) {
        self.races = races
        self.maxHR = maxHR
        self.nextRaceEvent = nextRaceEvent
        self.now = now
    }

    static func hasEnoughData(in races: [Race]) -> Bool {
        races.contains { $0.isFinished }
    }

    var body: some View {
        if WeeklyRecapCard.hasEnoughData(in: races) {
            card
        }
    }

    // MARK: - Card

    private var card: some View {
        let recap = recapData

        return VStack(alignment: .leading, spacing: 14) {
            header(recap: recap)
            trainingLoadRow(recap: recap)
            narrative(recap: recap)
            statTiles(recap: recap)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func header(recap: RecapData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.caption.weight(.heavy))
                Text("WEEK OF \(weekOfLabel)")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.textSecondary)

            Text(recap.headline)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func trainingLoadRow(recap: RecapData) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TRAINING LOAD")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
                Text(loadValueString(recap.trainingLoad))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("TARGET ZONE")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textTertiary)
                Text(targetZoneLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(zoneStatusLabel(recap.trainingLoad))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(zoneStatusColor(recap.trainingLoad))
            }
        }
    }

    @ViewBuilder
    private func narrative(recap: RecapData) -> some View {
        if let narrative = recap.narrative {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.accent)
                    .padding(.top, 2)
                Text(narrative)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.surfaceElevated)
            )
        }
    }

    private func statTiles(recap: RecapData) -> some View {
        HStack(spacing: 8) {
            statTile(label: "SESSIONS", value: "\(recap.sessionsThisWeek)", tint: Color.textPrimary)
            statTile(
                label: "ENGINE Δ",
                value: engineDeltaLabel(recap.engineScoreDelta),
                tint: engineDeltaColor(recap.engineScoreDelta)
            )
            statTile(label: "STREAK", value: "\(streakDays)d", tint: Color.accent)
        }
    }

    private func statTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surfaceElevated)
        )
    }

    // MARK: - Recap calculation

    private struct RecapData {
        let sessionsThisWeek: Int
        let sessionsLastWeek: Int
        let trainingLoad: Double
        let engineScoreDelta: Double?
        let headline: String
        let narrative: String?
    }

    private var recapData: RecapData {
        let calendar = Calendar.current
        let thisWeekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let lastWeekStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let finished = races.filter { $0.isFinished }
        let thisWeek = finished.filter {
            let when = $0.endedAt ?? $0.startedAt
            return when >= thisWeekStart && when <= now
        }
        let lastWeek = finished.filter {
            let when = $0.endedAt ?? $0.startedAt
            return when >= lastWeekStart && when < thisWeekStart
        }

        let trainingLoad: Double = thisWeek
            .compactMap { RaceStats.effortScore(for: $0, maxHR: maxHR) }
            .reduce(0, +)
        let thisAvgEngine = RaceStats.engineScore(across: thisWeek, maxHR: maxHR)?.overall
        let lastAvgEngine = RaceStats.engineScore(across: lastWeek, maxHR: maxHR)?.overall
        let engineDelta: Double? = {
            if let t = thisAvgEngine, let l = lastAvgEngine { return t - l }
            return nil
        }()

        let headline = headlineForSessions(thisWeek.count)
        let narrative = composeNarrative(
            sessions: thisWeek.count,
            engineDelta: engineDelta,
            daysUntilRace: nextRaceEvent?.daysUntil
        )

        return RecapData(
            sessionsThisWeek: thisWeek.count,
            sessionsLastWeek: lastWeek.count,
            trainingLoad: trainingLoad,
            engineScoreDelta: engineDelta,
            headline: headline,
            narrative: narrative
        )
    }

    private func headlineForSessions(_ count: Int) -> String {
        switch count {
        case 0:  return "Rest week."
        case 1:  return "Quiet week."
        case 2:  return "Steady week."
        case 3:  return "Strong week."
        default: return "Big week."
        }
    }

    private func composeNarrative(
        sessions: Int,
        engineDelta: Double?,
        daysUntilRace: Int?
    ) -> String? {
        var parts: [String] = []

        if sessions == 0 {
            parts.append("No sessions logged. Easy reset week — back at it tomorrow.")
        } else {
            parts.append("\(sessions) session\(sessions == 1 ? "" : "s") this week.")
            if let delta = engineDelta {
                let rounded = Int(delta.rounded())
                if rounded >= 3 {
                    parts.append("Engine Score climbed +\(rounded).")
                } else if rounded <= -3 {
                    parts.append("Engine Score dropped \(rounded).")
                }
            }
        }

        if let days = daysUntilRace, days > 0, days <= 60 {
            parts.append("Race in \(days) day\(days == 1 ? "" : "s").")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - Formatters

    private var weekOfLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        return formatter.string(from: weekStart).uppercased()
    }

    private func loadValueString(_ load: Double) -> String {
        String(format: "%.1f", load / 60)  // convert seconds → minutes for display, then per-10
    }

    // Target zone matches the comp-prep heuristic in the mock —
    // 14–18 effort-minutes/week is a strong race-prep block.
    // Lower bound is base-building territory; above is overreach.
    private let targetZoneLow: Double = 14
    private let targetZoneHigh: Double = 18

    private var targetZoneLabel: String {
        "\(Int(targetZoneLow)) — \(Int(targetZoneHigh))"
    }

    private func zoneStatusLabel(_ load: Double) -> String {
        let loadValue = load / 60
        if loadValue >= targetZoneLow && loadValue <= targetZoneHigh {
            return "ON TRACK"
        } else if loadValue < targetZoneLow {
            return "BUILDING"
        } else {
            return "PUSH"
        }
    }

    private func zoneStatusColor(_ load: Double) -> Color {
        let loadValue = load / 60
        if loadValue >= targetZoneLow && loadValue <= targetZoneHigh {
            return Color.success
        } else if loadValue < targetZoneLow {
            return Color.textSecondary
        } else {
            return Color.warning
        }
    }

    private func engineDeltaLabel(_ delta: Double?) -> String {
        guard let delta else { return "—" }
        let rounded = Int(delta.rounded())
        if rounded > 0 { return "+\(rounded)" }
        return "\(rounded)"
    }

    private func engineDeltaColor(_ delta: Double?) -> Color {
        guard let delta else { return Color.textTertiary }
        if delta > 0 { return Color.success }
        if delta < 0 { return Color.warning }
        return Color.textPrimary
    }

    // Days-since-most-recent-finished-race used as a proxy for
    // "training streak length" — the same heuristic Profile's
    // existing streak banner pattern uses. Full RaceStreaks
    // helper would be a cleaner source but pulling it inline
    // for v1 to avoid coupling.
    private var streakDays: Int {
        let finished = races.filter { $0.isFinished }
        guard let mostRecent = finished
            .compactMap({ $0.endedAt ?? $0.startedAt })
            .max() else { return 0 }
        return Calendar.current.dateComponents([.day], from: mostRecent, to: now).day ?? 0
    }
}
