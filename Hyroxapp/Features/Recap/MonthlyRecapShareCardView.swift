import SwiftUI

// Spotify-Wrapped-style shareable card for a single month of HYROX
// training. Story aspect (9:16, 1080×1920 at 3× scale) by default
// — the format athletes most often share to Instagram / Snapchat
// stories. A square variant could ship later but story is the
// canonical fit for "look back" content.
//
// Anatomy, top to bottom:
//   • Caps wordmark
//   • Hero: month name (huge, rounded mono) + year (small, caps)
//   • 2×2 grid of stat tiles: races, total time, PBs, streak peak
//   • Biggest mover callout (when applicable)
//   • Hero number: fastest race or fastest run for the month
//   • TRAKRR wordmark footer
//
// Designed to feel different from the per-race share card —
// celebratory + reflective rather than data-dense + competitive.
// Bigger typography, more whitespace, gold-yellow PB highlights
// where the per-race card uses coral throughout.
//
// Guarded `#if !os(watchOS)` because UIImage / ImageRenderer aren't
// available on watch.
#if !os(watchOS)
struct MonthlyRecapShareCardView: View {

    let recap: MonthlyRecap

    // Story aspect canvas — 360pt × 640pt at 3× scale = 1080×1920.
    // Same scale convention as RaceShareCardView so output ends
    // up Instagram-quality.
    static let canvasSize = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            // Background: deep coral-tinted radial gradient,
            // slightly more saturated than the per-race card so
            // the recap feels like a different aesthetic — less
            // "data report," more "year in review."
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
                    .padding(.top, 32)

                Spacer(minLength: 16)

                heroBlock

                Spacer(minLength: 24)

                statsGrid
                    .padding(.horizontal, 28)

                Spacer(minLength: 16)

                if let mover = recap.biggestMover {
                    biggestMoverCallout(mover)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 16)

                appFooter
                    .padding(.bottom, 32)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .background(Color(hex: 0x0A0A0B))
        // Force dark for the export — share cards are Instagram /
        // Stories-bound and stay branded-dark regardless of the
        // user's in-app theme.
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Header

    private var wordmarkHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.system(size: 11, weight: .bold))
            Text("MONTH IN HYROX")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
        }
        .foregroundStyle(Color.accent)
    }

    // MARK: - Hero (month name + year)

    private var heroBlock: some View {
        VStack(spacing: 4) {
            Text(recap.monthName.uppercased())
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 16)

            Text(recap.yearLabel)
                .font(.system(size: 14, weight: .bold))
                .tracking(2.0)
                .foregroundStyle(Color.accent)
        }
    }

    // MARK: - 2×2 stat grid

    private var statsGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statTile(
                    value: "\(recap.raceCount)",
                    label: "RACES",
                    isAccent: true
                )
                statTile(
                    value: hoursTrainedString,
                    label: "TRAINED"
                )
            }
            HStack(spacing: 10) {
                statTile(
                    value: "\(recap.totalTimePBCount)",
                    label: "PBs SET",
                    isAccent: recap.totalTimePBCount > 0
                )
                statTile(
                    value: "\(recap.streakPeak)",
                    label: "STREAK PEAK"
                )
            }
        }
    }

    private func statTile(value: String, label: String, isAccent: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isAccent ? Color.accent : Color.textPrimary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.surface)
        )
    }

    // MARK: - Biggest mover callout

    private func biggestMoverCallout(_ mover: MonthlyRecap.BiggestMover) -> some View {
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
        .padding(.vertical, 16)
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
            Text("TRAKRR")
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

    // Total trained → "12h 24m" or "47m" depending on magnitude.
    // Stat tiles are tight so we always render the most compact
    // form that keeps both numbers visible.
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
