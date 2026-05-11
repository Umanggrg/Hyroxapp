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
    // without a manual reload. "Has a photo" \= local bytes OR
    // synced cloud URL — keeps remote-only races from a fresh
    // device install in the gallery instead of hiding them until
    // the bytes get pulled.
    private var photoRaces: [Race] {
        races.filter { $0.photoData != nil || $0.photoURL != nil }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            if photoRaces.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        galleryHeader
                            .padding(.horizontal, Layout.screenMargin)
                            .padding(.top, 8)
                            .padding(.bottom, 16)

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
        }
        .navigationTitle("Photos")
        .hyroxDarkNavigationBar(inline: true)
    }

    // Two-line header above the grid. Mirrors the "X photos · earliest
    // → latest" framing Apple Photos uses on a date-grouped view —
    // grounds the visual feed with a quick count + spans cue. Reads
    // as memory metadata; doesn't compete with the photos themselves.
    private var galleryHeader: some View {
        let count = photoRaces.count
        let earliest = photoRaces.last?.startedAt
        let latest = photoRaces.first?.startedAt

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(count) Photo\(count == 1 ? "" : "s")")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()

            if let earliest, let latest {
                Text(spanText(from: earliest, to: latest))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Compact span label. Same date → no range, just the single
    // date. Different dates → "Mar 4 — Apr 22, 2026" (collapse the
    // year when both are the same calendar year, keep both years
    // when they differ — same convention iOS Photos uses).
    private func spanText(from start: Date, to end: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(start, inSameDayAs: end) {
            return start.formatted(date: .long, time: .omitted)
        }
        let startYear = cal.component(.year, from: start)
        let endYear = cal.component(.year, from: end)
        let earlyDate = min(start, end)
        let lateDate = max(start, end)
        let lateString = lateDate.formatted(date: .abbreviated, time: .omitted)
        if startYear == endYear {
            // Drop the year on the earlier date; keep it on the later
            // one (matches "Mar 4 – Apr 22, 2026").
            let earlyMonthDay = earlyDate.formatted(.dateTime.month(.abbreviated).day())
            return "\(earlyMonthDay) – \(lateString)"
        } else {
            let earlyString = earlyDate.formatted(date: .abbreviated, time: .omitted)
            return "\(earlyString) – \(lateString)"
        }
    }

    // Single tile. Square aspect, photo fills via .scaledToFill
    // + clipped, with a bottom gradient + date stamp. Race name
    // (if set) appears above the date in a smaller weight so the
    // date stays the dominant secondary cue.
    private func tile(for race: Race) -> some View {
        let image = race.photoData.flatMap(UIImage.init(data:))
        // Remote URL fallback — used only when local bytes
        // aren't available. Most tiles will have bytes (this
        // device is where the photo was picked); the AsyncImage
        // path mainly fires on a fresh device install where the
        // race row synced down before the bytes did.
        let remoteURL: URL? = {
            guard image == nil,
                  let s = race.photoURL else { return nil }
            return URL(string: s)
        }()

        return ZStack(alignment: .bottomLeading) {
            // GeometryReader gives us a perfect square at whatever
            // column-width LazyVGrid resolves to. Each tile keeps
            // its 1:1 aspect regardless of screen size.
            Color.surfaceElevated  // fallback while image loads

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Color.surfaceElevated
                    @unknown default:
                        Color.surfaceElevated
                    }
                }
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
    // black screen. Uses the same fingerprint watermark + glow
    // language as the History empty state so the brand voice
    // stays consistent.
    private var emptyState: some View {
        ZStack {
            HeroBackdrop(.calm)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accent.opacity(0.12))
                        .frame(width: 88, height: 88)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Color.accent)
                }

                Text("No race photos yet")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)

                Text("Add a photo to a race from its summary or detail view to start filling the gallery.")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}
#endif
