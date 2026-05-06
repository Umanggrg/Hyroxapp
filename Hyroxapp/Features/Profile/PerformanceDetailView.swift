import SwiftUI

// Pushed detail view for the Profile Performance section. Houses
// the deep Performance cards that don't earn permanent above-the-
// fold real estate on Profile but are still useful one tap away:
//
//   • HYROX Performance (3-pillar grid)
//   • Race Ready check
//   • HR Baseline (athlete-specific Z3 band)
//   • Station Fingerprint (per-station tendency map)
//   • Performance Overload (volume + intensity trend sentence)
//   • Engine Impact (per-station weakness analysis)
//
// Profile shows the headline metrics inline (HYROX Score + Engine
// Score); these surfaces sit one nav tap away. Same depth-behind-
// nav approach the Race Start screen uses for Custom Workout.
//
// Each child card is gated on its own data-sufficiency check —
// when the user has no qualifying data for a given card, that
// section silently omits, same as Profile did before. The view
// can render with as few as one populated card.
struct PerformanceDetailView: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    @Environment(\.dismiss) private var dismiss

    private var hasPerf: Bool { HyroxPerformanceScoreView.hasAnyData(in: races) }
    private var hasReady: Bool { RaceReadyView.shouldShow(in: races) }
    private var hasOverload: Bool { PerformanceOverloadView.hasMeaningfulTrends(in: races) }
    private var hasEngine: Bool { EngineImpactView.shouldShow(in: races) }
    private var hasHRBaseline: Bool { PersonalHRBaselineView.hasEnoughData(in: races) }
    private var hasStationFingerprint: Bool { StationFingerprintView.hasEnoughData(in: races) }
    private var hasFatigueResistance: Bool { FatigueResistanceView.hasEnoughData(in: races) }
    private var hasFatigueFingerprint: Bool { FatigueFingerprintView.hasEnoughData(in: races) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if hasPerf {
                    section(title: "HYROX Performance") {
                        HyroxPerformanceScoreView(races: races)
                    }
                }
                if hasReady {
                    section(title: "Race Ready") {
                        RaceReadyView(races: races, division: division)
                    }
                }
                if hasHRBaseline {
                    section(title: "Race HR Target") {
                        PersonalHRBaselineView(races: races)
                    }
                }
                if hasStationFingerprint {
                    section(title: "Station Fingerprint") {
                        StationFingerprintView(races: races, maxHR: maxHR)
                    }
                }
                // Fatigue Resistance Score — §17.5 per-station
                // 0-100 score wrapping the existing
                // EngineImpactView's slowdown data into a tier'd
                // metric. Sits next to Engine Impact since they
                // surface the same data through different
                // lenses (FRS = score-and-tier, Engine Impact =
                // raw slowdown %).
                if hasFatigueResistance {
                    section(title: "Fatigue Resistance") {
                        FatigueResistanceView(races: races)
                    }
                }
                // Fatigue Fingerprint — §18 Pillar 1. Where do
                // I characteristically fall apart? Sits next to
                // Fatigue Resistance because they're related
                // signals: FRS = "which station hurts the next
                // run?", Fingerprint = "where in the race does
                // the cliff happen?". Together they answer the
                // full back-half story.
                if hasFatigueFingerprint {
                    section(title: "Fatigue Fingerprint") {
                        FatigueFingerprintView(races: races)
                    }
                }
                if hasOverload {
                    section(title: "Progressive Overload") {
                        PerformanceOverloadView(races: races)
                    }
                }
                if hasEngine {
                    section(title: "Engine Impact") {
                        EngineImpactView(races: races)
                    }
                }
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.vertical, 16)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Performance")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // Caps-label header + content. Mirrors the section-renderer
    // pattern Profile uses inline so the cards look identical
    // when pushed here vs in their old above-the-fold spot.
    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .capsLabelStyle()
                Spacer()
            }
            .padding(.horizontal, 4)

            content()
        }
    }
}
