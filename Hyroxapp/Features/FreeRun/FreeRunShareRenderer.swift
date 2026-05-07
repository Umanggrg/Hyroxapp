import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

#if !os(watchOS) && canImport(UIKit)

// Bridges `FreeRunShareCardView` (a SwiftUI view) into a transparent
// PNG that the iOS share sheet can hand off. Same shape as the
// existing `RaceShareRenderer` but tuned for Free Run's story-only
// format and explicit alpha-channel preservation.
//
// Why transparent: the share card is a Strava-style overlay —
// athletes drop it onto an Instagram / Snap / TikTok story over
// their own photo or template. The exported PNG must preserve
// alpha so the athlete's background shows through. SwiftUI's
// ImageRenderer respects this when the rendered view's root has
// no opaque fill (ours uses `Color.clear`).
@MainActor
enum FreeRunShareRenderer {

    // Render the share card to a UIImage. ImageRenderer must run
    // on the main actor (it touches view layout). The resulting
    // image carries an alpha channel; transparency is preserved
    // through pngData() encoding because PNG natively supports
    // alpha.
    static func render(run: FreeRun, maxHeartRate: Int) -> UIImage? {
        let card = FreeRunShareCardView(
            run: run,
            maxHeartRate: maxHeartRate
        )
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: card)
        // 3× scale → 1080px wide from a 360pt canvas. The 360×640
        // canvas exports as 1080×1920, exactly Instagram story
        // aspect.
        renderer.scale = 3.0
        // Default proposedSize = nil (use the view's intrinsic
        // size). We don't override it because the card already
        // has a fixed-size frame.

        guard let cgImage = renderer.cgImage else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// `Transferable` wrapper that ShareLink takes directly. Carries
// the rendered PNG bytes plus a date-stamped filename so AirDrop
// / Files / Save-to-Photos lands with a descriptive name.
//
// Same Transferable pattern RaceShareImage uses for race shares —
// keeping the two parallel makes the share-sheet UX feel uniform
// across both card types.
struct FreeRunShareImage: Transferable {

    let image: UIImage
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            // pngData() preserves the alpha channel for transparent
            // PNGs — that's the contract Strava-style story
            // overlays rely on. Throws on the unlikely nil case
            // (CGImage-backed UIImages always succeed in practice).
            guard let data = item.image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { item in item.filename }
    }
}

extension FreeRunShareImage {

    // Suggested filename. Date-stamped so multiple exports of the
    // same run don't collide — example: "Trakrr-Run-2026-04-25.png".
    static func filename(for run: FreeRun) -> String {
        let date = run.endedAt ?? run.startedAt
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Trakrr-Run-\(f.string(from: date)).png"
    }
}

#endif
