import SwiftUI
import SwiftData

#if canImport(UIKit)

// Post-finish summary for a Free Run.
//
// Hero: total distance + total time + average pace.
// Below that: HR aggregates (when present), splits list, and a
// Done button that pops back to wherever the start was triggered.
//
// Photo + notes editing surface lands in a future polish pass —
// for now this is read-only display, and athletes can edit the
// run from History detail.
struct FreeRunSummaryView: View {

    @Bindable var run: FreeRun

    // When pushed from FreeRunView's finish flow, the parent
    // owns the fullScreenCover and needs to dismiss the entire
    // run UI; `onClose` fires that. When pushed from History
    // (no parent fullScreenCover involved), `onClose` defaults
    // to nil and the Done button uses `\.dismiss` to pop the
    // navigation stack instead. Either context produces "Done →
    // back to where I came from" without callers having to plumb
    // explicit nav state.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    // Drives the Profile-style max HR — needed by the share-card
    // renderer to classify per-split HR samples into zones.
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    private var maxHeartRate: Int {
        profiles.first?.maxHeartRate ?? 190
    }

    // Pre-baked share image — built lazily on appear so ShareLink
    // gets an instant-ready Transferable instead of waiting for
    // ImageRenderer mid-tap. Re-baked when the run's HR data
    // changes (rehydrate post-finish).
    @State private var shareImage: FreeRunShareImage?

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    heroCard
                    if hasHRData {
                        hrCard
                    }
                    if !run.splits.isEmpty {
                        splitsCard
                    }
                    metaRow
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Free Run")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Share button — leading edge of the trailing
            // toolbar group. Only renders once the share image
            // has finished baking (otherwise ShareLink would
            // briefly show with no payload).
            if let shareImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(
                            "Trakrr Run",
                            image: Image(uiImage: shareImage.image)
                        )
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Color.accent)
                    }
                    .accessibilityLabel("Share run")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    if let onClose {
                        onClose()
                    } else {
                        // History-push flow — pop the nav stack.
                        // Same one-tap "back to where I came
                        // from" behavior the live-finish flow
                        // gets through onClose's fullScreenCover
                        // dismiss.
                        dismiss()
                    }
                }
                .foregroundStyle(Color.accent)
            }
        }
        .onAppear(perform: prepareShareImage)
        // Re-bake when the HR rehydrate fills in per-split
        // averages — the chart bars get more detail once
        // the post-finish HK rehydrate completes.
        .onChange(of: run.heartRateAvgBPM) { _, _ in
            prepareShareImage()
        }
    }

    // Bake the share image off the main actor's hot path. ImageRenderer
    // requires MainActor but the work is fast (~50ms for a 360×640
    // canvas at 3×) so we run it directly on appear and on rehydrate.
    private func prepareShareImage() {
        Task { @MainActor in
            guard let image = FreeRunShareRenderer.render(
                run: run,
                maxHeartRate: maxHeartRate
            ) else { return }
            shareImage = FreeRunShareImage(
                image: image,
                filename: FreeRunShareImage.filename(for: run)
            )
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 6) {
            Text("DISTANCE")
                .font(.caption.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.2f", distanceUnits))
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text(run.splitUnit.shortLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Divider()
                .background(Color.divider)
                .padding(.vertical, 8)

            HStack(spacing: 0) {
                statTile(
                    label: "TIME",
                    value: RaceStats.format(totalDuration)
                )
                statTile(
                    label: "AVG PACE",
                    value: avgPace.map { formatPace($0) + " /\(run.splitUnit.shortLabel)" } ?? "—"
                )
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - HR card

    private var hrCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Heart rate").capsLabelStyle()
                Spacer()
            }
            HStack(spacing: 12) {
                if let avg = run.heartRateAvgBPM {
                    statBox(label: "AVG", value: "\(Int(avg.rounded()))", unit: "bpm", tint: Color.accent)
                }
                if let max = run.heartRateMaxBPM {
                    statBox(label: "MAX", value: "\(Int(max.rounded()))", unit: "bpm", tint: Color.warning)
                }
                if let kcal = run.activeCaloriesKcal {
                    statBox(label: "CALORIES", value: "\(Int(kcal.rounded()))", unit: "kcal", tint: Color.success)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func statBox(label: String, value: String, unit: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.heavy))
                .tracking(0.5)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - Splits card

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Splits").capsLabelStyle()
                Spacer()
                Text("\(run.splits.count) \(run.splits.count == 1 ? run.splitUnit.singularSplitNoun : run.splitUnit.displayName.lowercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(run.splits.enumerated()), id: \.offset) { index, split in
                    splitRow(index: index, split: split)
                    if index < run.splits.count - 1 {
                        Divider().background(Color.divider)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    private func splitRow(index: Int, split: FreeRunSplit) -> some View {
        let pace = split.paceSecondsPerUnit(metresPerUnit: run.splitUnit.metresPerUnit)
        return HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.heavy))
                .frame(width: 28, alignment: .leading)
                .foregroundStyle(Color.accent)

            Text(RaceStats.format(split.duration))
                .font(.subheadline.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let pace {
                Text("\(formatPace(pace)) /\(run.splitUnit.shortLabel)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }

            if let avg = split.heartRateAvgBPM {
                HStack(spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.caption2.weight(.bold))
                    Text("\(Int(avg.rounded()))")
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                }
                .foregroundStyle(Color.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Meta row

    private var metaRow: some View {
        HStack(spacing: 6) {
            Image(systemName: run.locationType.iconName)
            Text(run.locationType.displayName)
            Spacer()
            Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.textTertiary)
        .padding(.horizontal, 4)
    }

    // MARK: - Derived

    private var distanceUnits: Double {
        run.distanceMetres / run.splitUnit.metresPerUnit
    }

    private var totalDuration: TimeInterval {
        run.totalDuration ?? 0
    }

    private var avgPace: TimeInterval? {
        guard run.distanceMetres > 0, totalDuration > 0 else { return nil }
        return totalDuration / (run.distanceMetres / run.splitUnit.metresPerUnit)
    }

    private var hasHRData: Bool {
        run.heartRateAvgBPM != nil
            || run.heartRateMaxBPM != nil
            || run.activeCaloriesKcal != nil
    }

    private func formatPace(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#endif
