import SwiftUI

// §19.2 — post-race source provenance.
//
// Quiet card rendered at the bottom of RaceSummary (and
// future-eligible historical races once Race.hrSourcePrimary
// persists) telling the athlete what sensors made the race
// possible. Trust through transparency: when the HR / motion /
// calorie data lives on the screen, the athlete should know
// whether it came from the Watch on their wrist, the AirPods
// Pro 3 in their ears, or both fused.
//
// v1 reads `SensorSourceRegistry.shared.lastHRSource` directly —
// accurate for the just-finished race because the registry is
// fresh. Historical races (RaceDetail of an old row) won't
// have this data; the card is opt-in via `isCurrentSession`
// and skips rendering when false.
//
// When the Race model gains `hrSourcePrimary: String?` (a
// queued v2 schema change), this card can be reused on
// RaceDetail too — same layout, sourced from the persisted
// field instead of the runtime registry.
struct SourceProvenanceCard: View {

    /// True when reading live state from the registry (post-
    /// finish RaceSummary). False when rendering for a
    /// historical race that has its source persisted on the
    /// `Race.hrSourcePrimary` field. Drives where the HR
    /// label comes from — live registry vs persisted field.
    let isCurrentSession: Bool

    /// Optional Race row — when provided AND non-nil
    /// `hrSourcePrimary`, the card renders the persisted
    /// value instead of the live registry. Lets RaceDetail
    /// show provenance for historical races where the
    /// registry has long since moved on.
    var race: Race? = nil

    /// Override for previews — when nil, reads from the
    /// shared registry singleton.
    var hrSourceOverride: SensorSourceRegistry.HRSource? = nil
    var profileOverride: SensorSourceRegistry.DeviceProfile? = nil

    private var hrSource: SensorSourceRegistry.HRSource {
        // Resolution order:
        //   1. Explicit override (previews / forced display)
        //   2. Persisted Race.hrSourcePrimary (historical
        //      races) — decode the stored string back through
        //      the classifier
        //   3. Live registry (live RaceSummary post-finish)
        if let override = hrSourceOverride {
            return override
        }
        if let persisted = race?.hrSourcePrimary, !persisted.isEmpty {
            return SensorSourceRegistry.HRSource.classify(sourceName: persisted)
        }
        return SensorSourceRegistry.shared.lastHRSource
    }

    private var profile: SensorSourceRegistry.DeviceProfile {
        profileOverride ?? SensorSourceRegistry.shared.profile
    }

    var body: some View {
        // Render when either:
        //   • Live session AND registry has a real source
        //   • Historical race with a persisted hrSourcePrimary
        let hasLiveSource = isCurrentSession && hrSource != .unknown
        let hasPersistedSource = (race?.hrSourcePrimary?.isEmpty == false)
        if hasLiveSource || hasPersistedSource {
            card
        }
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.heavy))
                Text("DATA SOURCES")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 6) {
                row(
                    label: "Heart rate",
                    symbol: hrSource.symbolName,
                    detail: hrSource.shortLabel
                )

                // Motion attribution — AirPods if motion-capable
                // pods are in the route, otherwise Watch when
                // paired, otherwise iPhone fallback.
                row(
                    label: "Motion",
                    symbol: motionSourceSymbol,
                    detail: motionSourceLabel
                )

                // Calories — Apple computes from HR + motion +
                // health profile. Source is whichever device fed
                // the inputs (Watch / AirPods / iPhone).
                row(
                    label: "Calories",
                    symbol: caloriesSourceSymbol,
                    detail: caloriesSourceLabel
                )
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.divider, lineWidth: 0.5)
        )
    }

    private func row(label: String, symbol: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 18, alignment: .center)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Derived motion + calorie attribution

    // Motion source rules — AirPods Pro 1+ on head are the best
    // running-motion source (cadence + vertical oscillation).
    // Otherwise the Watch wrist IMU. Otherwise iPhone pedometer
    // if carried.
    private var motionSourceSymbol: String {
        if SensorSourceRegistry.shared.hasAirPodsMotion { return "airpodspro" }
        if SensorSourceRegistry.shared.hasWatch { return "applewatch" }
        return "iphone"
    }

    private var motionSourceLabel: String {
        if SensorSourceRegistry.shared.hasAirPodsMotion {
            return SensorSourceRegistry.shared.airPodsModelName ?? "AirPods"
        }
        if SensorSourceRegistry.shared.hasWatch { return "Apple Watch" }
        return "iPhone (carried)"
    }

    // Calories — Apple computes whichever device is providing
    // HR + motion. When both are present, the Watch's HK
    // calorie series typically wins (denser samples).
    private var caloriesSourceSymbol: String {
        if SensorSourceRegistry.shared.hasWatch { return "applewatch" }
        if SensorSourceRegistry.shared.hasAirPodsHR { return "airpodspro" }
        return "iphone"
    }

    private var caloriesSourceLabel: String {
        if SensorSourceRegistry.shared.hasWatch { return "Apple Watch" }
        if SensorSourceRegistry.shared.hasAirPodsHR {
            return SensorSourceRegistry.shared.airPodsModelName ?? "AirPods"
        }
        return "iPhone derived"
    }
}

#Preview("Full — Watch + AirPods") {
    SourceProvenanceCard(
        isCurrentSession: true,
        hrSourceOverride: .fused,
        profileOverride: .full
    )
    .padding()
    .background(Color.background)
}

#Preview("AirPods only") {
    SourceProvenanceCard(
        isCurrentSession: true,
        hrSourceOverride: .airPods(model: "AirPods Pro 3"),
        profileOverride: .airpodsOnly
    )
    .padding()
    .background(Color.background)
}

#Preview("Watch only") {
    SourceProvenanceCard(
        isCurrentSession: true,
        hrSourceOverride: .watch,
        profileOverride: .watchOnly
    )
    .padding()
    .background(Color.background)
}
