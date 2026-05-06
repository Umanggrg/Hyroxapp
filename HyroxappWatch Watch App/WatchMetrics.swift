import SwiftUI
#if os(watchOS)
import WatchKit
#endif

// One source of truth for watchOS UI scaling.
//
// We support a wide hardware spread once the deployment target dropped
// to watchOS 10.0 — Series 4 (40mm = 162pt wide) all the way up to
// Ultra 2 (49mm = 205pt wide). That's a ~26% range; sizes that read
// well on a 41mm baseline (176pt) overflow on 40mm and look anaemic on
// the Ultra. Rather than sprinkle `if device == .ultra` checks across
// every screen, every hero size on the wrist routes through this
// helper.
//
// The scale factor is computed once at first access from
// `WKInterfaceDevice.screenBounds` — the screen doesn't resize during
// the app's lifetime, so caching is safe and avoids per-render work.
//
// Baseline 176pt is the Series 7-9 41mm width — the most common modern
// Watch and the size most of the existing call sites were originally
// hand-tuned for. Clamping to 0.88…1.18 keeps the smallest tier from
// becoming unreadably tiny and the largest tier from looking
// cartoonishly oversized; the timer hero shifts from ~39pt on a 40mm
// watch to ~52pt on a 49mm Ultra, both of which read cleanly.
//
// Existing surfaces with `.minimumScaleFactor` keep that escape valve
// in place — this helper handles the *target* size, the modifier
// handles overflow when a string is unusually long.
enum WatchMetrics {

    /// Reference width — Series 7–9 41mm. Sizes are hand-tuned against
    /// this and scaled up/down for other hardware.
    private static let baselineWidth: CGFloat = 176

    /// Lower clamp prevents the smallest watches (40mm, 162pt) from
    /// rendering text that's too thin to read mid-sprint. 0.88 still
    /// leaves headroom — the underlying `minimumScaleFactor` on long
    /// strings can shrink further.
    private static let minScale: CGFloat = 0.88

    /// Upper clamp prevents Ultra (205pt) from getting fonts that
    /// look like a children's book — the watch is bigger but the
    /// athlete's glance budget is the same.
    private static let maxScale: CGFloat = 1.18

    /// Computed once on first access. The screen size doesn't change
    /// during app lifetime, so a `let` here is the right shape.
    static let scale: CGFloat = {
        #if os(watchOS)
        let width = WKInterfaceDevice.current().screenBounds.size.width
        let raw = width / baselineWidth
        return min(max(raw, minScale), maxScale)
        #else
        // Previews / non-watchOS compile contexts get the baseline.
        return 1.0
        #endif
    }()

    /// Returns a SwiftUI font scaled against the baseline. Replaces
    /// `.system(size: 44, weight: .heavy, design: .rounded)` with
    /// `WatchMetrics.font(size: 44, weight: .heavy, design: .rounded)`
    /// — same semantic intent, but the actual point size flexes with
    /// hardware.
    static func font(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size * scale, weight: weight, design: design)
    }

    /// Scaled point dimension — for button heights, padding, glyph
    /// box sizes. Use this any time a hand-tuned 36 / 38 / 44 needs
    /// to track the hero text size on bigger or smaller watches.
    static func dim(_ pt: CGFloat) -> CGFloat {
        pt * scale
    }
}
