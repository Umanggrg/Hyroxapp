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
                    FreeRunPhotoSection(run: run)
                    if hasHRData {
                        hrCard
                    }
                    if !run.splits.isEmpty {
                        splitsCard
                    }
                    // §11 / §19 — same data-sources card we
                    // surface on RaceSummaryView. Renders HR /
                    // Motion / Calories attribution from the
                    // registry (isCurrentSession: true — Free
                    // Run summary always renders right after
                    // finish so the registry state is fresh).
                    // Self-hides when no HR source was
                    // attributed (iPhone-only / no-HK runs).
                    SourceProvenanceCard(isCurrentSession: true)
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
        .onAppear {
            prepareShareImage()
            scheduleRehydrateRebake()
        }
        // Re-bake when ANY of the run's relevant data changes —
        // the post-finish HK rehydrate updates run.heartRateAvgBPM,
        // run.heartRateMaxBPM, run.activeCaloriesKcal, AND each
        // split's per-split HR averages. Keying the change
        // detector on a composite hash means the re-bake fires
        // for any of those, not just the run-level aggregate.
        .onChange(of: rehydrateChangeKey) { _, _ in
            prepareShareImage()
        }
    }

    // Composite signal that flips whenever any rehydratable
    // run field updates. Each Hashable component is the kind
    // of value the rehydrate writes to — when any combination
    // changes, SwiftUI fires .onChange and we re-bake the
    // share image with fresh data.
    //
    // Critically: includes the count of splits with HR data,
    // so the rehydrate's per-split HR patches trigger a re-bake
    // even though `run.heartRateAvgBPM` (the run-level aggregate)
    // would have also changed. Belt-and-suspenders for cases
    // where the run-level aggregate happens to land at the same
    // value as a prior bake (rare but possible).
    private var rehydrateChangeKey: Int {
        var hasher = Hasher()
        hasher.combine(run.heartRateAvgBPM)
        hasher.combine(run.heartRateMaxBPM)
        hasher.combine(run.activeCaloriesKcal)
        hasher.combine(run.splits.count)
        hasher.combine(run.splits.compactMap { $0.heartRateAvgBPM }.count)
        return hasher.finalize()
    }

    // Schedule an explicit re-bake ~9 seconds after appearing —
    // the FreeRunViewModel's post-finish rehydrate runs on an
    // 8-second delay (waiting for the Watch's finishWorkout to
    // flush samples to HK). The onChange path above SHOULD
    // catch it via observed property updates, but SwiftData's
    // change-tracking on nested Codable arrays (run.splits) is
    // sometimes lossy across the actor hops. The scheduled
    // re-bake guarantees the card reflects rehydrated data
    // even if the observation chain dropped a beat.
    private func scheduleRehydrateRebake() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(9))
            prepareShareImage()
        }
    }

    // Bake the share image. Queries HK for sample-level
    // time-in-zone bucketing FIRST, then renders the card with
    // those numbers — the bar chart now reflects actual time
    // spent in each zone regardless of how short the run was
    // or whether any split boundaries were captured.
    //
    // Why this needs the HK query: per-split HR aggregation
    // (the original implementation) only works when splits
    // exist. A 0.5-mile easy run with mile-based splits has
    // ZERO completed split boundaries, so the chart was always
    // empty. Querying HK directly for the run's window gives
    // us every HR sample in real time and lets us bucket each
    // sample's contribution by the gap to the next sample.
    //
    // Falls through to render with `[:]` zoneSeconds when HK
    // returns no data — the card stays renderable, the chart
    // shows flat zero bars (still readable, just signals "no
    // HR captured").
    private func prepareShareImage() {
        Task { @MainActor in
            let buckets: [HRZone: TimeInterval]
            // §27 — prefer the persisted in-app HR series when
            // present (post-Phase-27 runs). This is the dense
            // series captured live from the Watch WCSession
            // stream + HK 5s poll fallback, and it doesn't
            // depend on HK's stored sample density behaving.
            //
            // Pre-Phase-27 runs (and any post-Phase-27 run that
            // somehow ended with an empty series — e.g. iPhone-
            // only run with no Watch and HK auth denied) fall
            // through to the existing HK query. Empty result
            // there too renders the share card with flat zero
            // bars instead of failing.
            let inAppSeries = run.hrSeries
            if !inAppSeries.isEmpty {
                buckets = HRZone.timeInZones(
                    samples: inAppSeries,
                    maxBPM: maxHeartRate,
                    end: run.endedAt
                )
            } else if let endedAt = run.endedAt {
                buckets = await HealthKitService.shared.timeInZones(
                    from: run.startedAt,
                    to: endedAt,
                    maxBPM: maxHeartRate
                )
            } else {
                // Run is still in progress (the user is viewing
                // a stale summary while another run runs?). Use
                // an empty bucket — defensive only; the summary
                // is normally only rendered for finished runs.
                buckets = [:]
            }

            guard let image = FreeRunShareRenderer.render(
                run: run,
                maxHeartRate: maxHeartRate,
                zoneSeconds: buckets
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
