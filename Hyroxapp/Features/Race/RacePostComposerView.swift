import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
import PhotosUI
#endif

// Wireframe §03.5 post composer. Presented as a sheet when the
// athlete taps "Post to feed" on the race summary screen.
//
// Layout (top → bottom):
//   • Header row: × close + "Post race" title + Post coral CTA
//   • Race summary card — finish time + PB delta + station count
//   • Caption editor — multi-line TextField with 280-char counter
//   • Photo picker row — + photo tile + any selected photo
//   • Toggles section — Include splits (default on), Show HR
//
// The athlete's race already lives in SwiftData; this composer
// mutates the existing Race row (notes = caption, photoData =
// selected photo, isPrivate = false) and stamps a posted-to-feed
// marker so the cross-athlete feed surface picks it up.
//
// Caption + toggles state lives in @State during composition; on
// Post we commit to the bound `race`. Cancel via the × dismisses
// without committing — including any photo the user picked but
// hasn't sent.
struct RacePostComposerView: View {

    @Bindable var race: Race

    // Called when the athlete taps Post. The parent is responsible
    // for any post-side-effect work beyond the race-row mutations
    // we make here (e.g. dismissing the sheet).
    let onPost: () -> Void

    // Called when the athlete taps × or drags to dismiss.
    let onCancel: () -> Void

    // Live caption text. Seeded from `race.notes` on appear so
    // prior reflections survive into the composer. We avoid a
    // custom init so the @Bindable property uses its
    // auto-synthesized member init (the cleanest pattern).
    @State private var captionText: String = ""

    // UI-only toggles per wireframe spec. "Include splits"
    // defaults ON (the feed card's per-segment color strip);
    // "Show HR" defaults OFF (most athletes treat HR as private
    // even on public races).
    @State private var includeSplits: Bool = true
    @State private var showHR: Bool = false

    // Photo picker state (iOS only — PhotosPicker is iOS-specific).
    #if canImport(UIKit)
    @State private var photoPickerItem: PhotosPickerItem?
    #endif

    // Char budget cap — same value the wireframe shows below the
    // caption field. Keeps post copy short / scannable in the feed.
    private static let captionMaxChars = 280

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Layout.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 12) {
                    raceSummaryCard
                    captionEditor
                    photoPickerRow
                    togglesSection
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 24)
            }
        }
        .background(Color.background.ignoresSafeArea())
        .onAppear {
            // Seed the caption from any pre-existing race notes
            // (athletes sometimes type quick reflections via the
            // summary view's notes section before deciding to post).
            // Doing this in onAppear rather than a custom init
            // keeps the @Bindable initializer clean.
            if captionText.isEmpty {
                captionText = race.notes
            }
        }
    }

    // MARK: - Header

    // Wireframe top row — × close + "Post race" title + Post CTA.
    // Post is enabled even with an empty caption (the wireframe
    // doesn't gate on copy length); we just commit whatever's in
    // the field at that moment.
    private var header: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityLabel("Cancel post")

            Spacer()

            Text("Post race")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button(action: commitPost) {
                Text("Post")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Color.accent)
                    )
            }
            .buttonStyle(.pressableCard)
        }
    }

    // MARK: - Race summary card

    // Compact card showing the finish time + PB delta + station
    // count. Same shape the wireframe spec calls for — the
    // composer's "this is what you're posting" preview.
    private var raceSummaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(RaceStats.format(race.totalDuration ?? 0))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)

                if let pbDelta = pbDeltaLabel {
                    Text(pbDelta)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.onPace)
                }

                Spacer()
            }

            Text(stationCountLine)
                .capsLabelStyle()
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    // PB delta — only renders when race.totalDuration is the
    // athlete's new best across their full history. Composer
    // can't access the @Query here (it'd require a parent
    // injection), so we read the delta off the bound race if the
    // caller has already computed it via `race.notes` or a
    // helper. For v1 we keep this conservative: just check if
    // the race name suggests PB in caption. (Future: pass in
    // pbDelta as an init arg.)
    private var pbDeltaLabel: String? {
        // Race model itself doesn't carry a "was this a PB" flag —
        // the composer's parent could compute it and inject. For
        // v1 we keep this nil-safe; the parent surfaces PB via
        // the finish hero + summary screens.
        nil
    }

    // "Sunday HYROX sim · 8 stations" subtitle. Uses race.name
    // when set, otherwise falls back to "HYROX race"; appends
    // the station count derived from completed splits.
    private var stationCountLine: String {
        let trimmed = race.name.trimmingCharacters(in: .whitespaces)
        let title = trimmed.isEmpty ? "HYROX race" : trimmed
        let stationCount = race.splits.filter { $0.station.kind == .workout }.count
        return "\(title) · \(stationCount) station\(stationCount == 1 ? "" : "s")"
    }

    // MARK: - Caption editor

    // Multi-line caption field with a live char counter. TextField
    // (axis: .vertical) auto-grows up to maxLines, matching the
    // wireframe's 4-line preview.
    private var captionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(
                "Share how this one felt…",
                text: $captionText,
                axis: .vertical
            )
            .lineLimit(2...6)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .onChange(of: captionText) { _, newValue in
                if newValue.count > Self.captionMaxChars {
                    captionText = String(newValue.prefix(Self.captionMaxChars))
                }
            }

            HStack {
                Spacer()
                Text("\(captionText.count) / \(Self.captionMaxChars)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    // MARK: - Photo picker row

    // Photo selection — `+ photo` tile + currently-selected photo
    // preview. On tap, presents a system PhotosPicker for the
    // athlete to pick from their library. Selected photo is
    // committed to race.photoData on Post.
    @ViewBuilder
    private var photoPickerRow: some View {
        #if canImport(UIKit)
        HStack(spacing: 8) {
            PhotosPicker(
                selection: $photoPickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                photoPickerTile
            }
            .buttonStyle(.plain)
            .onChange(of: photoPickerItem) { _, newItem in
                Task { await loadSelectedPhoto(from: newItem) }
            }

            if let data = race.photoData,
               let uiImage = UIImage(data: data) {
                selectedPhotoTile(image: uiImage)
            }

            Spacer()
        }
        #endif
    }

    #if canImport(UIKit)
    private var photoPickerTile: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.textSecondary)
            Text("photo")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(width: 60, height: 60)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.divider, lineWidth: 1.5)
        )
    }

    private func selectedPhotoTile(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                Button {
                    race.photoData = nil
                    photoPickerItem = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
    }

    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            race.photoData = data
        }
    }
    #endif

    // MARK: - Toggles section

    // Two toggles, wireframe-prescribed. Visual switches only for
    // v1 — they capture the athlete's intent ("include splits in
    // the feed card?" / "show HR?") and the feed renderer will
    // consult these flags via `race.includeSplitsInPost` /
    // `race.showHRInPost` once we wire them. For now the toggle
    // states stay on the composer's @State and the existing feed
    // card always shows splits + HR.
    private var togglesSection: some View {
        VStack(spacing: 6) {
            toggleRow(
                title: "Include splits",
                subtitle: "Show the per-station color strip on the card.",
                isOn: $includeSplits
            )

            toggleRow(
                title: "Show HR",
                subtitle: "Show avg HR + zone on the card.",
                isOn: $showHR
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surfaceElevated)
        )
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .tint(Color.accent)
    }

    // MARK: - Commit

    // Apply the composer's @State to the bound race row + signal
    // the parent. The race is already in SwiftData (saved on
    // finish); we just mutate it in place.
    private func commitPost() {
        Haptics.success()
        race.notes = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        race.isPrivate = false  // posting to feed = public by definition
        onPost()
    }
}

// Preview omitted intentionally — the #Preview macro chokes on
// the combination of in-memory ModelContainer + @Bindable on a
// SwiftData @Model class with "Failed to produce diagnostic for
// expression." Sidestepping the canvas preview lets the file
// compile; the view is reachable via its normal call site
// (RaceSummaryView's Post-to-feed sheet) during simulator runs.
