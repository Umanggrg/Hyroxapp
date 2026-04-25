import SwiftUI
import SwiftData

// Apple-Memories-style photo grid of every race that has a photo
// attached. Pushed from the History toolbar when at least one race
// carries a photo. Each tile is a square crop of the photo with a
// subtle bottom gradient + date overlay so the date is readable
// without obscuring the image.
//
// Tap a tile to push that race's RaceDetailView — shares the same
// `Race.self` navigation destination already registered on
// HistoryView, so this view doesn't need to declare its own.
//
// Why a separate gallery vs. just filtering History to "With Photo"
// (which we already support): the feed is information-dense
// (numbers, badges, stats) — it reads as data. The gallery is
// photo-first; it reads as memory. Two valid mental models for
// the same content, two screens for the two modes.
//
// Guarded `#if !os(watchOS) && canImport(UIKit)` because UIImage
// + the photo-decoding path are UIKit / iOS only.
#if !os(watchOS) && canImport(UIKit)
struct RaceGalleryView: View {

    @Query(
        filter: #Predicate<Race> { $0.endedAt != nil },
        sort: [SortDescriptor(\Race.createdAt, order: .reverse)]
    ) private var races: [Race]

    // 3-column flexible grid — same column count Photos uses on
    // iPhone for square crops at iPhone-screen widths. 2pt gaps
    // give the grid a tight contact-sheet feel rather than a
    // gap-y "card row" feel.
    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 2),
        count: 3
    )

    // Filter once at view derivation. Computed property re-runs on
    // store changes so newly-photographed races show up live
    // without a manual reload.
    private var photoRaces: [Race] {
        races.filter { $0.photoData != nil }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            if photoRaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photoRaces) { race in
                            NavigationLink(value: race) {
                                tile(for: race)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Photos")
        .hyroxDarkNavigationBar(inline: true)
    }

    // Single tile. Square aspect, photo fills via .scaledToFill
    // + clipped, with a bottom gradient + date stamp. Race name
    // (if set) appears above the date in a smaller weight so the
    // date stays the dominant secondary cue.
    private func tile(for race: Race) -> some View {
        let image = race.photoData.flatMap(UIImage.init(data:))

        return ZStack(alignment: .bottomLeading) {
            // GeometryReader gives us a perfect square at whatever
            // column-width LazyVGrid resolves to. Each tile keeps
            // its 1:1 aspect regardless of screen size.
            Color.surfaceElevated  // fallback while image loads

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }

            // Bottom gradient — black fade from 0% at the top of
            // the overlay to 70% at the bottom. Keeps the date
            // legible on bright photos without darkening the
            // whole tile.
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .bottom)

            VStack(alignment: .leading, spacing: 1) {
                if !race.name.isEmpty {
                    Text(race.name)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(race.startedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    // Defensive empty state — the parent toolbar item that opens
    // this view is hidden when no photos exist, but if the user
    // somehow lands here with zero photos (e.g. after deleting
    // every photo), guide them back rather than show a bare
    // black screen.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("No race photos yet")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("Add a photo to a race from its summary or detail view.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
#endif
