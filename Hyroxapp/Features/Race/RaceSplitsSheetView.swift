import SwiftUI

// A peek at completed splits without leaving the in-progress race screen.
// Presented as a sheet that slides up from the bottom; the main race timer
// keeps running underneath (TimelineView doesn't pause when an iOS sheet
// covers it).
//
// Kept read-only on purpose — editing a split mid-race would be a mess
// (which segment's endedAt changes? do subsequent splits shift?). This is
// purely "what did I just do?" reference, like glancing at an Apple Watch
// during a run. The post-race summary is where deeper analysis lives.
//
// iOS-only (wrapped in canImport(UIKit)) because Form / listRowBackground
// styling we rely on is designed for iOS sheets. The splits-peek button in
// RaceView is also iOS-guarded, so this file isn't pulled into macOS builds.
#if canImport(UIKit)
struct RaceSplitsSheetView: View {

    // View-model reference rather than a copy of splits — we want this sheet
    // to stay live if a tap-and-hold advances the race while the sheet is up
    // (unlikely but harmless). The `@Bindable` attribute lets the view
    // observe `@Observable` properties without a Binding.
    @Bindable var viewModel: RaceViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if viewModel.splits.isEmpty {
                    emptyState
                } else {
                    splitsList
                }
            }
            .navigationTitle("Splits")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }

    // MARK: - Split list

    // Rendered as a plain VStack inside a ScrollView rather than a List so
    // the hairline dividers and monospaced right-aligned times read more
    // like Strava's segment leaderboard than iOS's stock list style.
    private var splitsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Caps-style section header, consistent with history cards.
                HStack {
                    Text("Completed")
                        .capsLabelStyle()
                    Spacer()
                    Text("\(viewModel.splits.count) of \(viewModel.totalSegments)")
                        .capsLabelStyle()
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                        splitRow(index: index, split: split)

                        if index < viewModel.splits.count - 1 {
                            Divider()
                                .background(Color.divider)
                                .padding(.leading, Layout.screenMargin)
                        }
                    }
                }
                .background(Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 24)
            }
        }
    }

    private func splitRow(index: Int, split: Split) -> some View {
        HStack(spacing: 12) {
            // 1-based position, Strava-style, muted so it doesn't compete
            // with the station name.
            Text("\(index + 1)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textTertiary)
                .frame(width: 24, alignment: .leading)

            Text(split.station.displayName)
                .font(.body)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(RaceStats.format(split.duration))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, Layout.cardPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("No splits yet")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("Finish your first station to see it here.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
#endif
