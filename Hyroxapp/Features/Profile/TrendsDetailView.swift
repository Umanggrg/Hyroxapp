import SwiftUI

// Pushed detail view for the Profile Trends section. Houses the
// secondary trend charts that don't earn permanent above-the-
// fold real estate on Profile but are still useful one tap away:
//
//   • Time Trend          — am I getting faster?
//   • Effort Trend        — am I training harder?
//   • HR Drift Trend      — is my engine holding HR within races?
//   • Run Fade Trend      — is my run pacing holding within races?
//   • Recovery Trend      — am I recovering faster between stations?
//   • Intensity Mix       — what's the load distribution?
//
// Profile shows the headline trend inline (Engine Score Trend —
// the composite rollup); these surfaces sit one nav tap away.
//
// Each chart is gated on its own data-sufficiency check — the
// view can render with as few as one populated chart. Empty
// state (no charts populate) is intentionally allowed because
// the parent gates whether to even surface the nav link.
struct TrendsDetailView: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    private var hasEffortTrend: Bool { EffortTrendView.hasEnoughData(in: races, maxHR: maxHR) }
    private var hasEffortDistribution: Bool { EffortDistributionView.hasEnoughData(in: races, maxHR: maxHR) }
    private var hasDriftTrend: Bool { HRDriftTrendView.hasEnoughData(in: races) }
    private var hasRecoveryTrend: Bool { RecoveryTrendView.hasEnoughData(in: races) }
    private var hasRunDegradationTrend: Bool { RunDegradationTrendView.hasEnoughData(in: races) }
    private var hasHyroxScoreTrend: Bool { HyroxScoreTrendView.hasEnoughData(in: races) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // HYROX Score Trend — sits at the top of the
                // detail view because it's the headline-of-
                // headlines metric. Composite of best-time
                // performance + engine state + pillar balance +
                // race consistency. Each dot is the score the
                // athlete would have seen finishing that race.
                if hasHyroxScoreTrend {
                    section(title: "HYROX Score Trend") {
                        HyroxScoreTrendView(
                            races: races,
                            division: division,
                            maxHR: maxHR
                        )
                    }
                }

                // Time Trend — always renders when any race
                // exists; PerformanceTrendsView's own guard
                // handles the "not enough yet" case.
                section(title: "Time Trend") {
                    PerformanceTrendsView(races: races)
                }

                if hasEffortTrend {
                    section(title: "Effort Trend") {
                        EffortTrendView(races: races, maxHR: maxHR)
                    }
                }

                if hasDriftTrend {
                    section(title: "HR Drift Trend") {
                        HRDriftTrendView(races: races)
                    }
                }

                if hasRunDegradationTrend {
                    section(title: "Run Fade Trend") {
                        RunDegradationTrendView(races: races)
                    }
                }

                if hasRecoveryTrend {
                    section(title: "Recovery Trend") {
                        RecoveryTrendView(races: races)
                    }
                }

                if hasEffortDistribution {
                    section(title: "Intensity Mix") {
                        EffortDistributionView(races: races, maxHR: maxHR)
                    }
                }
            }
            .padding(.horizontal, Layout.screenMargin)
            .padding(.vertical, 16)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("Trends")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

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
