import SwiftUI

// Year-in-review story-aspect (1080×1920 at 3× scale) shareable
// card. Spotify Wrapped meets Strava Year In Sport, applied to
// HYROX. Where the per-race card is "this happened just now" and
// the per-month is "what just wrapped," this is the reflective
// year-end ("look at what I did").
//
// Anatomy, top to bottom:
//   • Caps wordmark "YEAR IN HYROX"
//   • Hero year (huge, rounded heavy)
//   • 2×2 stat grid: races, total hours, PBs set, streak peak
//   • Monthly bar sparkline (12 columns, height = race count)
//   • Best month + months-active dual callout
//   • Biggest improving station
//   • HYROXAPP wordmark + tagline
//
// Aesthetic: a deeper coral-saturated radial gradient than the
// monthly card so the year recap feels distinctly "premium / year-
// end." Bigger typography. More breathing room.
//
// Guarded `#if !os(watchOS)` because UIImage / ImageRenderer
// aren't available on watch.
#if !os(watchOS)
struct YearlyRecapShareCardView: View {

    let recap: YearlyRecap

    static let canvasSize = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                wordmarkHeader
                    .padding(.top, 30)

                Spacer(minLength: 8)

                heroYear

                Spacer(minLength: 18)

                statsGrid
                    .padding(.horizontal, 28)

                Spacer(minLength: 14)

                sparkline
                    .padding(.horizontal, 28)

                Spacer(minLength: 14)

                if let mover = recap.biggestMover {
                    biggestMoverCallout(mover)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 14)

                appFooter
                    .padding(.bottom, 28)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .background(Color(hex: 0x0A0A0B))
        // Force dark for the export — same rationale as the
        // RaceShareCardView. Year-in-review cards stay branded-
        // dark regardless of the user's in-app theme.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Background

    // Two-layer treatment: a coral-tinted radial gradient as the
    // base + a soft top-to-bottom luminance gradient that gives
    // the canvas a year-end-special feel without overwhelming the
    // data layer.
    private var backgroundLayer: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.accent.opacity(0.35),
                    Color(hex: 0x0A0A0B)
                ],
                center: .center,
                startRadius: 30,
                endRadius: Self.canvasSize.height * 0.7
            )
            LinearGradient(
                colors: [
                    Color.accent.opacity(0.10),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .center
            )
        }
        .background(Color(hex: 0x0A0A0B))
    }

    // MARK: - Header

    private var wordmarkHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .bold))
            Text("YEAR IN HYROX")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.6)
        }
        .foregroundStyle(Color.accent)
    }

    // MARK: - Hero

    private var heroYear: some View {
        VStack(spacing: 4) {
            Text(recap.displayName)
                .font(.system(size: 88, weight: .black, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .tracking(2)

            if let bestMonth = recap.bestMonth {
                Text("Best month: \(bestMonth.displayName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accent)
            }
        }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile(value: "\(recap.raceCount)", label: "RACES", isAccent: true)
                statTile(value: hoursTrainedString, label: "TRAINED")
            }
            HStack(spacing: 10) {
                statTile(
                    value: "\(recap.totalTimePBCount)",
                    label: "PBs SET",
                    isAccent: recap.totalTimePBCount > 0
                )
                statTile(value: "\(recap.streakPeak)", label: "STREAK PEAK")
            }
        }
    }

    private func statTile(value: String, label: String, isAccent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
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

    // MARK: - Monthly sparkline (12 columns)

    // 12 vertical bars showing race count per month. Heights
    // normalized to the max-month count so the busiest month
    // hits full height. Empty months render as thin dim lines
    // so the grid stays rectangular and reads as "12 months,
    // some empty."
    private var sparkline: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("RACES BY MONTH")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(recap.monthsActive) of 12 months active")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }

            GeometryReader { geo in
                let maxCount = recap.racesByMonth.values.max() ?? 1
                let barWidth: CGFloat = (geo.size.width - 11 * 4) / 12
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(1...12, id: \.self) { month in
                        let count = recap.racesByMonth[month] ?? 0
                        let height: CGFloat = count == 0
                            ? 4
                            : geo.size.height * CGFloat(count) / CGFloat(maxCount)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(count == 0 ? Color.surfaceElevated : Color.accent)
                            .frame(width: barWidth, height: max(height, 4))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .frame(height: 60)

            // Month labels — only render the first letter of each
            // so 12 labels fit comfortably in the same row width.
            HStack(spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    Text(monthInitial(month))
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface)
        )
    }

    private func monthInitial(_ month: Int) -> String {
        // Use locale's short month symbol's first character so
        // the labels feel right in any language. English: J F M A
        // M J J A S O N D.
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard symbols.indices.contains(month - 1) else { return "" }
        return String(symbols[month - 1].prefix(1))
    }

    // MARK: - Biggest mover

    private func biggestMoverCallout(_ mover: YearlyRecap.BiggestMover) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("BIGGEST MOVER")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.0)
            }
            .foregroundStyle(Color.success)

            Text(mover.station.displayName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Text("\(Int(mover.percentChange.rounded()))% faster")
                .font(.system(size: 14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Color.success)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.success.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.success.opacity(0.4), lineWidth: 1)
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

    // MARK: - Computed

    private var hoursTrainedString: String {
        let total = Int(recap.totalDuration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
#endif
