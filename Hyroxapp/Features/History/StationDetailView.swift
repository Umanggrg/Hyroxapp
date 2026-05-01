import SwiftUI
import SwiftData
import Charts

// Roxfit-style per-station deep dive — pushed from a tap on any
// split row in `RaceDetailView`. Answers the questions a HYROX
// athlete asks about an individual station after the dust settles:
//
//   • how fast was THIS attempt?
//   • how does it compare to my all-time best on this station?
//   • where does this rank in my recent history?
//   • what was happening physiologically — HR avg / max, calories?
//
// Navigation contract: the nav value is a `Split` (Hashable). The
// view re-queries all finished races internally so the trend chart
// stays live to the rest of the app — no manual passing of the
// races list through the navigation graph.
//
// Run-station semantics: when the tapped split is a 1km run case
// (run1…run8), the trend collapses ALL run splits across history
// into a single series. From the athlete's POV they have one
// "1km Run" stat, not eight. Workout stations (Sled Push, Wall
// Balls, etc.) are 1:1 with their case.
//
// Guarded `#if !os(watchOS)` because Race + Charts aren't
// available on watchOS.
#if !os(watchOS)
struct StationDetailView: View {

    // The specific split the athlete tapped — drives the hero
    // duration, HR, calories. Its `station` field is the type used
    // for trend/PB queries.
    let split: Split

    // Re-query finished races at view scope. Same pattern used on
    // RaceDetailView and ProfileView; keeps the trend live without
    // threading a races array through navigation.
    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .forward)]
    ) private var allFinishedRaces: [Race]

    // Need the user's Division to project this attempt to race-day
    // weight. Same singleton-via-Query pattern used elsewhere — the
    // bootstrap creates exactly one UserProfile, but we tolerate the
    // pre-bootstrap case by falling back to `.mensOpen` defaults.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    private var division: Division {
        profiles.first?.resolvedDivision ?? .mensOpen
    }

    // Athlete's configured max HR. Drives the per-station effort
    // category chip below the physiology tiles. Falls back to the
    // canonical 190 default when the user hasn't onboarded yet so
    // the chip still renders something defensible — same fallback
    // shipped on `UserProfile.maxHeartRate`.
    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Race-day projection — when the athlete logged a sub-race weight
    // for this attempt, linearly extrapolate what the same effort
    // would cost at the official HYROX weight. Returns nil when
    // there's no weight to project from (no log, run station, or
    // already at race weight).
    private var raceDayProjection: (projected: TimeInterval, raceWeight: Double)? {
        guard let projected = RaceStats.projectedRaceTime(
            forSplit: split,
            division: division
        ) else { return nil }
        guard let raceWeight = division.raceWeight(for: split.station) else { return nil }
        return (projected, raceWeight)
    }

    // Best ever on this station type (collapsing run cases together).
    private var personalBest: Split? {
        RaceStats.allTimeBest(for: split.station, among: allFinishedRaces)
    }

    // Time-series of every attempt at this station type, oldest
    // first. One dot per attempt (8 per race for runs, 1 per race
    // for workouts). Each tuple carries its source Split so the
    // chart can highlight the current attempt's dot exactly without
    // a per-dot lookup back to the parent race.
    private var trend: [(date: Date, duration: TimeInterval, split: Split)] {
        RaceStats.stationTrend(for: split.station, among: allFinishedRaces)
    }

    // True when this attempt is the fastest in the trend series.
    // Used for the "PB" pill above the hero number. `Split`
    // conforms to Equatable, so the identity check is exact —
    // station + start/end times + HR/cals all match.
    private var isPersonalBest: Bool {
        personalBest == split
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    heroCard.applyScrollAppearTransition()

                    if !trend.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ProfileSectionHeader(
                                title: "Trend",
                                icon: "chart.line.uptrend.xyaxis",
                                trailing: "\(trend.count) attempt\(trend.count == 1 ? "" : "s")"
                            )
                            trendCard
                        }
                        .applyScrollAppearTransition()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ProfileSectionHeader(
                            title: "Physiology",
                            icon: "waveform.path.ecg"
                        )
                        physiologyCard
                    }
                    .applyScrollAppearTransition()
                }
                .padding(Layout.screenMargin)
            }
        }
        .navigationTitle(split.station.displayName)
        .hyroxDarkNavigationBar(inline: true)
    }

    // MARK: - Hero (this attempt's duration + PB context)

    private var heroCard: some View {
        VStack(spacing: 8) {
            if isPersonalBest {
                HStack(spacing: 6) {
                    Image(systemName: "rosette")
                        .font(.caption.weight(.bold))
                    Text("Personal Best")
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                }
                .foregroundStyle(Color(hex: 0xFFD60A))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(hex: 0xFFD60A).opacity(0.15))
                )
            }

            Text(RaceStats.format(split.duration))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Text("This attempt")
                .capsLabelStyle()

            // Comparison line — only renders when there's a PB to
            // compare against (i.e. another attempt exists). For a
            // first-ever attempt this stays blank.
            if let pb = personalBest, !isPersonalBest {
                let delta = split.duration - pb.duration
                HStack(spacing: 6) {
                    Image(systemName: delta < 0 ? "arrow.down" : "arrow.up")
                        .font(.caption.weight(.bold))
                    Text(deltaText(absDelta: abs(delta), isFaster: delta < 0))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                    Text("vs your best (\(RaceStats.format(pb.duration)))")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
                .foregroundStyle(delta < 0 ? Color.success : Color.warning)
                .padding(.top, 4)
            }

            // Race-day projection — when the athlete trained at a
            // sub-race weight (e.g. 100kg sled push instead of the
            // 152kg Men's Open standard), extrapolate this attempt
            // linearly to what it would cost at race-day weight. The
            // intent is "you went 5:00 here, but on race day at the
            // real weight that's closer to ~6:30." A coaching honesty
            // signal — small training weights can disguise where
            // you'd actually struggle on race day.
            if let projection = raceDayProjection {
                HStack(spacing: 6) {
                    Image(systemName: "scalemass.fill")
                        .font(.caption.weight(.bold))
                    Text("Race-day projection")
                        .font(.caption.weight(.bold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                    Text("\(RaceStats.format(projection.projected)) at \(Int(projection.raceWeight)) kg")
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.accent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func deltaText(absDelta: TimeInterval, isFaster: Bool) -> String {
        "\(RaceStats.format(absDelta)) \(isFaster ? "faster" : "slower")"
    }

    // MARK: - Trend chart (all attempts at this station type)

    // SwiftCharts line + point chart of every attempt over time.
    // The current split's dot is highlighted in coral so the athlete
    // can see "where this attempt sits in my history at a glance."
    // Y-axis is duration in seconds — lower = faster, so the line
    // dropping over time visually reads as "getting fitter." Same
    // convention Strava uses for PR trend charts.
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Trend").capsLabelStyle()
                Spacer()
                Text("\(trend.count) attempt\(trend.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 4)

            Chart(Array(trend.enumerated()), id: \.offset) { index, point in
                // Connecting line — gives the chart its trend shape.
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Duration", point.duration)
                )
                .foregroundStyle(Color.accentDim)
                .interpolationMethod(.monotone)

                // Dots on every attempt. Current split's dot is
                // larger + coral, others are smaller + dim — same
                // pattern Strava uses to highlight "this activity"
                // in a PR history view. Identity check is exact —
                // we compare the trend tuple's source Split to the
                // viewed split via Equatable.
                let isCurrent = point.split == split
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Duration", point.duration)
                )
                .foregroundStyle(isCurrent ? Color.accent : Color.textSecondary)
                .symbolSize(isCurrent ? 120 : 40)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let seconds = value.as(TimeInterval.self) {
                            Text(RaceStats.format(seconds))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    AxisGridLine()
                        .foregroundStyle(Color.divider)
                }
            }
            .chartYScale(domain: yDomain)
            .frame(height: 180)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // Dynamic y-axis domain — ±10% padding around the data range so
    // the line doesn't kiss the edges. Falls back to a sane window
    // when there's only one point so the chart renders.
    private var yDomain: ClosedRange<TimeInterval> {
        let values = trend.map(\.duration)
        guard let minV = values.min(), let maxV = values.max() else {
            return 0...60
        }
        let span = max(maxV - minV, 1)
        let pad = span * 0.1
        return max(minV - pad, 0)...(maxV + pad)
    }

    // MARK: - Physiology (HR + calories for this segment)

    // Three-tile row: avg HR, max HR, calories. Each tile shows a
    // dash placeholder when the underlying HealthKit data isn't
    // available rather than hiding the row entirely — empty tiles
    // are a lighter cue ("we don't have that") than a missing
    // section ("there's nothing to say").
    private var physiologyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Physiology").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                physiologyTile(
                    value: split.heartRateAvgBPM.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "AVG HR"
                )
                physiologyTile(
                    value: split.heartRateMaxBPM.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "MAX HR"
                )
                physiologyTile(
                    value: split.activeCaloriesKcal.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "kcal",
                    label: "CALORIES"
                )
            }

            // Effort chip — full-width row below the three tiles.
            // Categorizes this station's avg HR / maxHR fraction into
            // Recovery / Moderate / High / Very High so the post-race
            // story carries a per-station intensity readout
            // alongside the raw HR. Whole-race effort lives on
            // RaceSummary; this answers the "which station hurt most"
            // question one level deeper.
            //
            // Hidden when there's no avg HR data — same silence
            // pattern as the other HR-derived UI elsewhere.
            if let category = RaceStats.effortCategory(
                forSplit: split,
                maxHR: maxHeartRate
            ) {
                effortChip(category: category)
            }

            // Boundary HR row — entry / end / 30s drop / 60s drop.
            // The HYROX-specific signal: how fatigued did you start
            // this station, where did your HR end up, and how fast
            // did it drop afterwards? Hidden entirely when none of
            // the four boundary samples exist. Each individual cell
            // shows "—" if its specific sample is missing while
            // others render — finer-grained silence than the whole-
            // section hide.
            if hasAnyBoundaryHR {
                boundaryHRRow
            }
        }
    }

    // True when at least one boundary HR sample is present —
    // gates the boundary row's visibility so we don't show four
    // dashes on legacy races that never captured this data.
    private var hasAnyBoundaryHR: Bool {
        split.heartRateEntryBPM != nil
            || split.heartRateEndBPM != nil
            || split.heartRateRecovery30sBPM != nil
            || split.heartRateRecovery60sBPM != nil
    }

    // Four small tiles: entry HR, end HR, 30s recovery drop, 60s
    // recovery drop. The drops are computed relative to the END
    // HR (not to peak), since that's the moment recovery clocks
    // start ticking. A bigger drop in the same time window =
    // better cardiovascular conditioning.
    private var boundaryHRRow: some View {
        let recovery30Drop: Int? = {
            guard let endHR = split.heartRateEndBPM,
                  let r30 = split.heartRateRecovery30sBPM else { return nil }
            return Int((endHR - r30).rounded())
        }()
        let recovery60Drop: Int? = {
            guard let endHR = split.heartRateEndBPM,
                  let r60 = split.heartRateRecovery60sBPM else { return nil }
            return Int((endHR - r60).rounded())
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Boundaries").capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)

            HStack(spacing: 8) {
                physiologyTile(
                    value: split.heartRateEntryBPM
                        .map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "ENTRY"
                )
                physiologyTile(
                    value: split.heartRateEndBPM
                        .map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "bpm",
                    label: "END"
                )
                physiologyTile(
                    value: recovery30Drop.map { drop in
                        // Display as a delta — e.g. "-12" — so
                        // the sign reads naturally. Negative drops
                        // (HR went UP after segment ended) are
                        // physiologically rare but possible during
                        // a heavy roxzone — we show the actual
                        // value rather than clamping to zero.
                        drop > 0 ? "-\(drop)" : "\(drop)"
                    } ?? "—",
                    unit: "30s",
                    label: "RECOVER"
                )
                physiologyTile(
                    value: recovery60Drop.map { drop in
                        drop > 0 ? "-\(drop)" : "\(drop)"
                    } ?? "—",
                    unit: "60s",
                    label: "RECOVER"
                )
            }
        }
    }

    // Per-station effort chip. Color tied to the category's HR
    // zone roughly (recovery = success, moderate = textPrimary,
    // high = warning, veryHigh = accent) so the chip carries
    // information at a glance — green for "easy day," coral for
    // "you absolutely sent it on this station."
    private func effortChip(category: RaceStats.EffortCategory) -> some View {
        let tint: Color = {
            switch category {
            case .recovery: return .success
            case .moderate: return .textPrimary
            case .high:     return .warning
            case .veryHigh: return .accent
            }
        }()

        return HStack(spacing: 8) {
            Image(systemName: category.symbol)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(tint)

            Text("\(category.displayName) effort")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            // Subtitle mirrors the whole-race "HR-time" framing so
            // athletes recognize this as part of the same effort
            // family rather than a brand-new metric. Keeps the
            // mental model coherent across surfaces.
            if let avg = split.heartRateAvgBPM {
                let percent = Int(((avg / Double(maxHeartRate)) * 100).rounded())
                Text("\(percent)% maxHR")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private func physiologyTile(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }
}
#endif
