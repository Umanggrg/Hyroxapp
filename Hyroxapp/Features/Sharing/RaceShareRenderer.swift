import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Bridges `RaceShareCardView` (a SwiftUI view) into something the
// iOS share sheet can hand off — a PNG image. Two pieces:
//
//   1. `RaceShareRenderer.render(...)` — uses SwiftUI's `ImageRenderer`
//      to bake the view into a `UIImage` at 3× scale (1080×1080 from
//      a 360pt canvas), suitable for Instagram post / story export.
//
//   2. `RaceShareImage` — a `Transferable`-conforming wrapper that
//      `ShareLink` can take directly. Carries both the image bytes
//      and a suggested filename so AirDrop / Files / etc. don't get
//      a generic name.
//
// Why a Transferable wrapper instead of just sharing the UIImage?
// `ShareLink(item: UIImage)` works but doesn't let us provide a
// preview thumbnail or a filename. Wrapping it in our own Transferable
// gives us both, and matches Apple's recommended pattern in
// `Transferable` documentation.
//
// Guarded `#if !os(watchOS)` because UIKit + ImageRenderer aren't
// available on watchOS.
#if !os(watchOS)

@MainActor
enum RaceShareRenderer {

    // Render the share card to a UIImage. ImageRenderer must run on
    // the main actor (it touches view layout). Returns nil only if
    // SwiftUI failed to produce a CGImage — extremely unlikely
    // unless the view itself crashed.
    static func render(
        race: Race,
        profile: UserProfile?,
        allRaces: [Race],
        format: ShareCardFormat = .square
    ) -> UIImage? {
        let card = RaceShareCardView(
            race: race,
            profile: profile,
            allRaces: allRaces,
            format: format
        )
        // Force the dark color scheme and the dark background even
        // when the rendering host's environment differs. This keeps
        // the shared card visually identical regardless of where the
        // share button was tapped from.
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        // 3× scale → 1080px wide from a 360pt canvas. For square
        // that's 1080×1080; for story (640pt tall) that's 1080×1920
        // — Instagram's exact story aspect.
        renderer.scale = 3.0

        guard let cgImage = renderer.cgImage else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// `Transferable` value that ShareLink uses. Holds the rendered PNG
// bytes plus a filename derived from the race date so exports land
// with descriptive names ("HYROX-Race-2026-04-25.png") rather than
// "Image.png".
struct RaceShareImage: Transferable {

    let image: UIImage
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        // PNG payload — universal, lossless, works as IG post upload
        // and survives "Save to Photos" without recompression.
        DataRepresentation(exportedContentType: .png) { item in
            // pngData() should never fail for a CGImage-backed
            // UIImage but the API is optional, so we throw on the
            // unlikely nil. ShareLink shows a generic failure if so.
            guard let data = item.image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { item in item.filename }
    }
}

extension RaceShareImage {

    // Suggested filename. Date-stamped + format-stamped so square
    // and story exports of the same race don't collide on disk.
    // Example: "HYROX-Race-2026-04-25-story.png".
    static func filename(for race: Race, format: ShareCardFormat = .square) -> String {
        let date = race.endedAt ?? race.startedAt
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "HYROX-Race-\(f.string(from: date))-\(format.filenameSuffix).png"
    }
}

#endif
