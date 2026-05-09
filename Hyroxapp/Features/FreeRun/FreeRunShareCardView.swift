import SwiftUI

#if !os(watchOS)

// Shareable Free Run card — story-format (9:16) export designed to
// drop into Instagram / Snap / TikTok stories on a transparent
// background.
//
// Why transparent: Strava-style overlays are universal currency for
// story sharing. The athlete's own background photo / story
// template shows through; the card only contributes the data
// itself + the brand mark. ImageRenderer preserves alpha when the
// view's root has no opaque fill, so we set the canvas background
// to .clear and let SwiftUI compose over transparency.
//
// Layout (top → bottom):
//   • HR Zones bar chart — Z1 through Z5 with neon-glow bars
//     scaled to time-in-zone, plus per-zone duration captions.
//   • Three stat tiles — Duration, Distance, Avg Pace — coral
//     glyph + caption + monospaced value, mirroring the
//     reference image.
//   • Trakrr logo + wordmark footer.
//
// Sized at 360×640pt → renders at 1080×1920 at 3× scale, exactly
// IG story dimensions.
struct FreeRunShareCardView: View {

    let run: FreeRun

    // Optional max HR — needed to classify HR samples into zones.
    // When nil we fall back to a 190 default (UserProfile's default
    // value); same behavior as the in-app HR zones view.
    let maxHeartRate: Int

    // Pre-computed time-in-zone bucketing. The summary view
    // queries HK directly via `HealthKitService.timeInZones(...)`
    // and passes the result here — that path works for any run
    // length, including runs too short to have crossed a split
    // boundary. Pass an empty dictionary for the "no HR data
    // yet" state and the chart renders flat zero bars (which
    // still hold the layout).
    let zoneSeconds: [HRZone: TimeInterval]

    // Canvas dimensions match RaceShareCardView's story format —
    // 360×640pt, exports as 1080×1920 at 3× via ImageRenderer.
    static let canvasSize = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            // Transparent canvas — Strava-style overlay. The
            // ImageRenderer preserves alpha because nothing
            // beneath fills opaquely. Athletes upload to a story
            // and their own photo / template shows through.
            Color.clear

            VStack(spacing: 0) {
                Spacer(minLength: 28)

                hrZonesChart

                Spacer(minLength: 24)

                statTiles

                Spacer(minLength: 16)

                logoFooter
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 24)
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - HR zones chart

    // Bar chart showing time spent in each of the 5 HR zones,
    // mirroring the reference design — neon-glowing rounded bars
    // with each zone labeled below + duration caption.
    //
    // Bar heights scale to the longest zone in this run. Max bar
    // is `maxBarHeight`; the others scale proportionally. A zone
    // with zero seconds gets a tiny stub (4pt) instead of disappearing
    // so the layout stays five-bars-wide regardless of the data.
    private var hrZonesChart: some View {
        // Use the pre-computed `zoneSeconds` (sample-level
        // bucketing from HK) when present; fall back to the
        // legacy split-derived bucketing for backward compat
        // with any caller that didn't pass it. The HK path
        // works for any run length; the split path needs at
        // least one captured split boundary.
        let durations: [HRZone: TimeInterval] = zoneSeconds.isEmpty
            ? zoneDurationsFromSplits(for: run)
            : zoneSeconds
        let maxDuration = durations.values.max() ?? 1

        return VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(HRZone.allCases, id: \.self) { zone in
                    zoneBar(
                        zone: zone,
                        seconds: durations[zone] ?? 0,
                        maxSeconds: maxDuration
                    )
                }
            }
            .frame(height: maxBarHeight + 8)

            HStack(alignment: .top, spacing: 18) {
                ForEach(HRZone.allCases, id: \.self) { zone in
                    zoneCaption(
                        zone: zone,
                        seconds: durations[zone] ?? 0
                    )
                }
            }
        }
    }

    private let maxBarHeight: CGFloat = 220

    private func zoneBar(zone: HRZone, seconds: TimeInterval, maxSeconds: TimeInterval) -> some View {
        // Scale relative to the tallest bar; tiny stub for zero
        // values so the chart's silhouette stays five-bars wide
        // even on a run with no time in (e.g.) Z5.
        let normalized = max(seconds / maxSeconds, 0.02)
        let height = max(maxBarHeight * normalized, 8)
        let color = zone.color

        return RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.55),
                        color.opacity(0.20)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Outer neon halo — multiple layered shadows give
            // the soft-glow effect the reference image shows.
            // Three distinct radii so the glow falls off gradually.
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: 1.2)
            )
            .shadow(color: color.opacity(0.55), radius: 12, y: 0)
            .shadow(color: color.opacity(0.35), radius: 22, y: 0)
            .frame(width: 36, height: height)
    }

    private func zoneCaption(zone: HRZone, seconds: TimeInterval) -> some View {
        VStack(spacing: 4) {
            Text("Z\(zone.rawValue)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(zone.color)
            Text(formatZoneDuration(seconds))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
        }
        .frame(width: 36)
    }

    // Format a zone duration as "MM:SS". Free runs are typically
    // <60min so we don't need an hour component; if a zone goes
    // long the M field overflows naturally.
    private func formatZoneDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Stat tiles

    // Three side-by-side stat tiles — Duration / Distance / Avg Pace.
    // Each has a coral icon at top, caps-tracked label, then a
    // monospaced value with optional unit suffix. Same pattern as
    // the reference image.
    private var statTiles: some View {
        HStack(alignment: .top, spacing: 0) {
            statTile(
                icon: "clock",
                label: "DURATION",
                value: durationString,
                unit: nil
            )
            statTile(
                icon: "mappin.and.ellipse",
                label: "DISTANCE",
                value: distanceValue,
                unit: run.splitUnit.shortLabel
            )
            statTile(
                icon: "stopwatch",
                label: "AVG PACE",
                value: avgPaceString,
                unit: "/\(run.splitUnit.shortLabel)"
            )
        }
    }

    private func statTile(
        icon: String,
        label: String,
        value: String,
        unit: String?
    ) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.accent)

            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(Color.accent)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    // Trakrr brand wordmark. The icon mark is the "T" silhouette
    // from the app icon — we render it inline as a coral-tinted
    // chevron pair, then the wordmark in heavy rounded type.
    // Approximates the TRAKRR logo signature without needing a
    // separate logo asset baked into the bundle.
    private var logoFooter: some View {
        HStack(spacing: 8) {
            // Brand glyph — coral chevron stack reads as the "T"
            // mark in the reference image.
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(Color.accent)
                .rotationEffect(.degrees(-90))

            Text("TRAKRR")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Derived values

    private var durationString: String {
        guard let total = run.totalDuration else { return "—" }
        return RaceStats.format(total)
    }

    private var distanceValue: String {
        let units = run.distanceMetres / run.splitUnit.metresPerUnit
        return String(format: "%.2f", units)
    }

    private var avgPaceString: String {
        guard let total = run.totalDuration,
              run.distanceMetres > 0 else { return "—" }
        let perUnit = total / (run.distanceMetres / run.splitUnit.metresPerUnit)
        let mins = Int(perUnit) / 60
        let secs = Int(perUnit) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // Tally HR samples per split into zones. Free runs don't carry
    // a continuous HR series (only per-split avg), so we approximate
    // each split's contribution by classifying its avg HR into a
    // zone and crediting the entire split duration to that zone.
    //
    // This is a coarser estimate than RaceStats.timeInZone (which
    // operates on per-sample HR series), but it produces a
    // reasonable bar chart from the data Free Run actually
    // captures. When per-sample HR series lands for free runs
    // (future enhancement), this method swaps to the same
    // sample-based aggregation races use.
    // Legacy split-derived bucketing — kept as a fallback when
    // the HK sample-level path returns empty (e.g. iPhone-only
    // run with no Watch on wrist). Only useful for runs that
    // crossed at least one split boundary; short runs with no
    // splits return an empty dictionary here too.
    private func zoneDurationsFromSplits(for run: FreeRun) -> [HRZone: TimeInterval] {
        var bucket: [HRZone: TimeInterval] = [:]
        for split in run.splits {
            guard let avg = split.heartRateAvgBPM else { continue }
            let zone = HRZone.zone(for: avg, maxBPM: maxHeartRate)
            bucket[zone, default: 0] += split.duration
        }
        return bucket
    }
}

#endif
