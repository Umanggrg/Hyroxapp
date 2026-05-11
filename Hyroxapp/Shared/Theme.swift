import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// Central design tokens for HyroxApp.
//
// All colors, typography, layout constants, and motion primitives live here.
// Views reference `Color.background`, `Font.raceTimer`, `Layout.cardPadding`,
// etc. — never hardcode hex values or magic numbers at the call site. This keeps
// the brand consistent across modes and makes future retuning a one-file change.
//
// As of v0.2 the color tokens are **adaptive** — every surface/text/divider
// resolves to a different value in light vs. dark mode via
// `UIColor(dynamicProvider:)`. The accent (coral) and HR-zone semantic
// colors stay constant across modes by design — they're brand signals,
// not chrome.
//
// Light palette is "Strava-warm" — off-white background, white surface
// cards on a warm bg, near-black warm text. The coral pops against
// either palette without retuning.

// MARK: - Colors

extension Color {
    // Surfaces
    static let background      = Color(lightHex: 0xFAF8F4, darkHex: 0x0A0A0B)
    static let surface         = Color(lightHex: 0xFFFFFF, darkHex: 0x141416)
    static let surfaceElevated = Color(lightHex: 0xF2EEE6, darkHex: 0x1C1C1F)

    // Text — light-mode values pulled darker per the v1 wireframe
    // audit. The previous tones (`#161513` / `#6B6964` / `#A8A6A0`)
    // read as slightly muted on the warm off-white background; the
    // updated stops (`#0E0E10` / `#4A4A4F` / `#8A8682`) match the
    // contrast ramp the design system locks in.
    static let textPrimary   = Color(lightHex: 0x0E0E10, darkHex: 0xF5F5F7)
    static let textSecondary = Color(lightHex: 0x4A4A4F, darkHex: 0x8E8E93)
    static let textTertiary  = Color(lightHex: 0x8A8682, darkHex: 0x636366)

    // Accent & semantic
    //
    // **v1 design-system shift:** the coral moved 8° hotter from the
    // iOS-system-red `#FF3B30` to `#FF4530`. Same hex is "destructive"
    // (stop / cancel / delete) for half our users — keeping it as the
    // brand accent meant the focusing tool kept reading as a warning.
    // The new hex burns the same emotional warmth but disambiguates
    // from system red. Audit budget: coral covers <12% of any surface.
    //
    // The system-red `#FF3B30` now lives as the `redline` state color
    // below — exactly where "danger" semantics belong (the Watch
    // takeover overlay for over-redline HR).
    //
    // success/warning + new state tokens shift slightly: the dark
    // variants are tuned for OLED black, the light variants are nudged
    // darker so they stay legible on warm off-white. Same hue, different
    // value step.
    static let accent    = Color(hex: 0xFF4530)
    static let accentDim = Color(hex: 0xFF4530, opacity: 0.6)
    static let success   = Color(lightHex: 0x1FA82A, darkHex: 0x32D74B)
    static let warning   = Color(lightHex: 0xC4720A, darkHex: 0xFF9F0A)

    // MARK: Race-state palette (v1 wireframe additions)
    //
    // Five colors keyed to the in-race coaching cue overlay states
    // (HOLD / SLOW / REDLINE / RECOVER / PUSH). These are TOOLS, not
    // brand decoration — they fire when the app needs to tell the
    // athlete to do something. Distinct from `accent`, which is for
    // brand moments, and from `success`/`warning`, which are general
    // semantic states.
    //
    //   • onPace   — green, matches HOLD overlay + pace-ahead chips.
    //                Colder than `success` so it doesn't pull
    //                emotional weight away from coral on celebratory
    //                surfaces (PBs, race finish).
    //   • slow     — amber, matches SLOW overlay + pace-behind chips.
    //   • redline  — true system-red, the over-threshold danger
    //                signal. THIS is iOS's `#FF3B30`. Use it sparingly;
    //                redline is supposed to feel scarce.
    //   • recover  — blue, matches RECOVER overlay. Cool tone so it
    //                reads as "rest" rather than "act."
    //   • push     — lime, matches PUSH overlay. Acidic enough to
    //                feel like a call to action against the calm
    //                in-race UI.
    static let onPace  = Color(hex: 0x2BC758)
    static let slow    = Color(hex: 0xFFB020)
    static let redline = Color(hex: 0xFF3B30)
    static let recover = Color(hex: 0x3A82F7)
    static let push    = Color(hex: 0xBFFF3E)

    // FIXED off-white for labels that sit ON the coral accent
    // (primary CTAs, hold-to-finish, gradient buttons). Brand
    // contract: white-on-coral is the canonical button look in
    // both modes. Without this fixed token, light-mode users see
    // near-black warm text on coral which reads as muted /
    // unfinished even though it has enough contrast. Use this
    // anywhere the background is `Color.accent` or a coral
    // gradient — NOT `Color.textPrimary`.
    static let onAccent = Color(hex: 0xFFFFFF)

    // Hairlines & separators — light-mode value pulled in line with
    // the v1 audit (`#E4DFD4` ≈ `#E5E1D8`, but matches the design
    // system's documented hairline exactly).
    static let divider = Color(lightHex: 0xE4DFD4, darkHex: 0x2C2C2E)

    // MARK: Brand decoration tokens
    //
    // Used by HeroBackdrop and other surfaces that paint coral
    // glows + fingerprint watermarks. Both need to adapt: a glow
    // that reads as "subtle stadium light" on near-black would
    // read as a coral wash on white if you didn't dial it back.
    // Same for the fingerprint — white-on-dark inverts to
    // dark-on-light.
    //
    // Exposing these as design tokens (instead of hard-coding the
    // adaptive logic inside HeroBackdrop) lets every brand
    // surface stay in lockstep when we tune the values.
    static let fingerprintInk = Color(lightHex: 0x161513, darkHex: 0xF5F5F7)

    // MARK: Hex initializers

    // Init a Color from a 24-bit RGB hex literal (e.g. `0xFF3B30`).
    // This is the FIXED-COLOR variant — same in light + dark mode.
    // Use for the coral accent, share-card backgrounds, anywhere
    // the value should not adapt.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }

    // Init an ADAPTIVE Color that resolves to one hex in light mode
    // and another in dark mode. Backed by `UIColor(dynamicProvider:)`
    // on iOS / iPadOS / Mac Catalyst / tvOS / visionOS — the
    // platforms that ship the dynamic provider API.
    //
    // watchOS is excluded: Apple deliberately omits both
    // `UIColor(dynamicProvider:)` and `UITraitCollection.userInterfaceStyle`
    // there (watchOS is dark-first and skips the whole adaptive-color
    // framework). On watchOS we fall back to the dark hex — which
    // matches the watch app's actual aesthetic. Same for macOS-
    // native, which isn't a real target for this project but appears
    // in some shared-type compile contexts.
    init(lightHex: UInt32, darkHex: UInt32, opacity: Double = 1.0) {
        #if canImport(UIKit) && !os(watchOS)
        let dyn = UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(rgbHex: isDark ? darkHex : lightHex, alpha: CGFloat(opacity))
        }
        self = Color(uiColor: dyn)
        #else
        // watchOS / macOS fallback — fixed dark variant.
        self.init(hex: darkHex, opacity: opacity)
        #endif
    }
}

#if canImport(UIKit) && !os(watchOS)
private extension UIColor {
    // Helper init that mirrors `Color(hex:)` so the dynamic provider
    // can stay readable. Pulled out as a private extension so it
    // doesn't pollute the public UIColor surface. Only compiled on
    // platforms where the dynamic provider above actually uses it
    // (i.e. not watchOS, where `Color(lightHex:darkHex:)` falls back
    // to the static dark hex).
    convenience init(rgbHex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((rgbHex >> 16) & 0xFF) / 255
        let g = CGFloat((rgbHex >>  8) & 0xFF) / 255
        let b = CGFloat( rgbHex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
#endif

// MARK: - Mode-aware glow opacity
//
// The coral spotlight on HeroBackdrop is one of the few brand
// elements that MUST be retuned per mode. On near-black it reads as
// stadium light at 8% opacity. The same 8% on warm off-white reads
// as a heavy coral wash that competes with the content. The fix is
// to scale glow opacity down in light mode by ~40%.
//
// Exposed as a free function (rather than a Color extension) because
// the consumer is HeroBackdrop, which builds a RadialGradient and
// needs the opacity as a Double, not a Color.
@MainActor
func adaptiveGlowOpacity(base: Double, scheme: ColorScheme) -> Double {
    switch scheme {
    case .light: return base * 0.5
    case .dark:  return base
    @unknown default: return base
    }
}

// Same idea for the fingerprint watermark — base opacity stays the
// same value in either mode (the ink color flips, not the alpha),
// but we expose this helper for surfaces that want to tweak.
@MainActor
func adaptiveFingerprintOpacity(base: Double, scheme: ColorScheme) -> Double {
    switch scheme {
    case .light: return base * 0.7  // dark ink on light bg reads more strongly
    case .dark:  return base
    @unknown default: return base
    }
}

// MARK: - Typography

extension Font {
    // Hero display — for screens that need to feel like a moment.
    // Used by the race-summary "FINISHED" treatment, monthly recap
    // hero, year-in-review hero. 88pt rounded heavy. Pair with
    // monospacedDigit() when displaying numerics.
    static let displayHero = Font.system(size: 88, weight: .heavy, design: .rounded)

    // Giant always-visible race timer. Bumped from 72pt → 96pt for
    // the v2 redesign — at arm's length, mid-sprint, in bright
    // light, every extra pt of size matters. Pair with
    // `.monospacedDigit()`.
    static let raceTimer = Font.system(size: 96, weight: .heavy, design: .rounded)

    // Hero stat on cards, e.g. a race's total time. Pair with `.monospacedDigit()`.
    static let heroStat = Font.system(size: 44, weight: .bold, design: .rounded)

    // Active station name on the race screen.
    static let stationTitle = Font.system(size: 36, weight: .heavy, design: .rounded)

    // Section headers (outside cards).
    static let sectionHeader = Font.title2.weight(.semibold)

    // Card title, e.g. "HYROX Race" above the hero stat.
    static let cardTitle = Font.headline

    // Small metadata: dates, locations, split labels.
    static let metadata = Font.footnote

    // Strava-style ALL-CAPS section label inside cards ("SPLITS", "STATS").
    // Use the `.capsLabelStyle()` view modifier below to also get tracking
    // and uppercasing applied — `Font` alone can't express those.
    static let capsLabel = Font.caption2.weight(.bold)
}

// MARK: - Layout

// `enum` with no cases is Swift's idiomatic way to declare a namespace that
// can't be instantiated. Keeps these constants grouped without polluting the
// global scope.
enum Layout {
    // Default outer horizontal padding for screens. 24pt is the Apple
    // Fitness / Strava convention — keep.
    static let screenMargin: CGFloat = 24

    // Padding inside cards. Bumped 16 → 20 per the v1 audit — the
    // tighter padding read as "settings page" rather than "athlete
    // profile" on dense surfaces. Every card automatically picks
    // this up via `Layout.cardPadding`.
    static let cardPadding: CGFloat = 20

    // Standard corner radius for cards. Bumped 12 → 16 per the
    // v1 audit — 12pt is mid-2010s iOS; 16pt locks us to the
    // current Apple platform aesthetic.
    static let cardCornerRadius: CGFloat = 16

    // Sheet / pill / full-bleed surface radius. Used for modal
    // sheets and any pressable element taller than ~56pt (the
    // duo pair-code pill, the primary CTA gradient buttons,
    // bottom sheets). Distinct from cards so the system reads
    // as a two-tier radius hierarchy.
    static let sheetCornerRadius: CGFloat = 22

    // Minimum tap-target height for in-race buttons (sweaty, shaky
    // hands). Wireframe audit raised the floor to 64pt; we already
    // ship at 80pt which exceeds that. Leaving at 80 — 64pt is the
    // hard minimum, 80pt is the preferred for the cathedral.
    static let raceButtonHeight: CGFloat = 80

    // Hard floor for in-race controls when 80pt would crowd a
    // multi-button layout (e.g. pause + cancel side-by-side).
    // Anything in-race must be ≥ this value.
    static let raceButtonMinHeight: CGFloat = 64

    // Minimum tap-target height outside of a race. Apple HIG.
    static let standardButtonHeight: CGFloat = 44
}

// MARK: - Spacing
//
// Stack rhythm scale locked to 8 / 12 / 20 / 32 per the v1 audit.
// Anything off-scale (6, 10, 14, 24, 28) is a bug — pick the closest
// canonical value. Exposed as a `Spacing` namespace so views can
// write `Spacing.md` instead of magic numbers and so retuning the
// whole rhythm is a one-file change.
//
// Today the codebase has lots of `padding(16)` / `spacing: 14` /
// etc. — we're not retro-fitting every call site in this turn (too
// invasive), but new code uses these tokens.
enum Spacing {
    /// 8pt — tight stack rhythm, used between paired labels and
    /// caption/value pairs inside a single cell.
    static let xs: CGFloat = 8

    /// 12pt — comfortable rhythm between elements within a card.
    static let sm: CGFloat = 12

    /// 20pt — between sections within a screen. Matches the new
    /// `cardPadding`, so a section break visually equals one card
    /// width of breathing room.
    static let md: CGFloat = 20

    /// 32pt — between major screen regions (hero → stats →
    /// trends). Largest stop on the scale.
    static let lg: CGFloat = 32
}

// MARK: - Motion

enum Motion {
    // Default spring for state transitions — subtle, not bouncy.
    // Respects Reduce Motion automatically when applied via `.animation`.
    //
    // **v1 motion role 1 of 3:** state-change. ~90% of motion in
    // the app. Card mounts, sheet presents, tab swaps. If you're
    // animating routine UI, this is the spring.
    static let standardSpring: Animation = .spring(response: 0.4, dampingFraction: 0.8)

    // Snappier spring for primary CTAs and tab transitions — faster
    // response time so taps feel instant. Slightly less damped so
    // there's a tiny visual settle that confirms the action.
    static let snappySpring: Animation = .spring(response: 0.28, dampingFraction: 0.75)

    // Loose spring for hero animations — number count-ups, race
    // finish moment, badge unlocks. More follow-through, more
    // emotional. Reach for this when the moment deserves it.
    static let heroSpring: Animation = .spring(response: 0.55, dampingFraction: 0.7)

    // **v1 motion role 2 of 3:** alert takeover. Used by the
    // five Watch coaching overlays (HOLD / SLOW / REDLINE /
    // RECOVER / PUSH) and any decisive full-screen moment that
    // demands attention. Hard, no bounce, paired with haptic.
    // 200ms is short enough to feel immediate, long enough to
    // register on the eye. The scale-from-0.9 entrance prevents
    // the snap from being jarring without softening it.
    static let alertTakeover: Animation = .easeOut(duration: 0.2)

    // **v1 motion role 3 of 3:** ambient. Background life —
    // live HR dot pulsing, active streak flame breathing,
    // race-day countdown glow. Pair with
    // `.repeatForever(autoreverses: true)`. Wireframe locks
    // this at 1.4s; we shortened from 2.4s so the ambient
    // feels more like a pulse and less like a slow tide.
    // Disabled under Reduce Motion via the per-call-site
    // `@Environment(\.accessibilityReduceMotion)` check; the
    // animation token doesn't gate itself.
    static let ambient: Animation = .easeInOut(duration: 1.4)
}

// MARK: - Depth (layered shadows for surface hierarchy)
//
// Card hierarchy isn't just about background color — depth via
// shadow tells the eye what's interactive vs ambient. Three tiers:
//   • subtle: default cards, barely lifted
//   • elevated: hero / primary cards (race start CTA, recap banner)
//   • dramatic: floating overlays (countdown, finish moment)
//
// Shadows here are tuned to read in BOTH modes. We use
// `Color.black.opacity(...)` on dark and a similar tint on light
// (because pure black shadow under a white card on a warm off-white
// background reads as expected — it's the universal shadow color).
// Light-mode shadow opacities are dialed down because the contrast
// against the bg is much higher.
enum Depth {
    static func subtle() -> some View {
        Color.clear
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    // Stack via .background(...) on the card.
    struct ElevatedShadow: ViewModifier {
        @Environment(\.colorScheme) private var scheme
        func body(content: Content) -> some View {
            content
                .shadow(
                    color: Color.black.opacity(scheme == .dark ? 0.5 : 0.12),
                    radius: scheme == .dark ? 12 : 14,
                    x: 0,
                    y: 6
                )
        }
    }

    struct DramaticShadow: ViewModifier {
        @Environment(\.colorScheme) private var scheme
        func body(content: Content) -> some View {
            content
                .shadow(
                    color: Color.black.opacity(scheme == .dark ? 0.6 : 0.18),
                    radius: scheme == .dark ? 24 : 18,
                    x: 0,
                    y: 12
                )
                .shadow(color: Color.accent.opacity(0.15), radius: 32, x: 0, y: 0)
        }
    }
}

extension View {
    // Apply elevated card shadow — for hero / primary cards.
    func elevatedDepth() -> some View {
        modifier(Depth.ElevatedShadow())
    }

    // Apply dramatic shadow + coral glow — for race-defining
    // moments (countdown overlay, finish hero, share buttons).
    func dramaticDepth() -> some View {
        modifier(Depth.DramaticShadow())
    }
}

// MARK: - Caps Label Modifier

// Applies the ALL-CAPS Strava-style section label treatment in one modifier.
// A `ViewModifier` is SwiftUI's way to package a reusable chain of modifiers
// so we can write `.capsLabelStyle()` at the call site instead of repeating
// four modifiers every time.
struct CapsLabelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.capsLabel)
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
    }
}

extension View {
    func capsLabelStyle() -> some View {
        modifier(CapsLabelStyle())
    }
}

// MARK: - Navigation Bar Styling
//
// Consolidated nav-bar treatment used by HistoryView, RaceDetailView, and
// ProfileView. As of v0.2 the bar adapts to the active color scheme — the
// background is `Color.background` (which is now an adaptive token) and the
// text/tint follows the system, so we no longer force `.toolbarColorScheme(.dark)`.
//
// `.toolbarBackground(_:for:)` is iOS / iPadOS / visionOS / Mac-Catalyst
// only — macOS native uses a different title-bar model. The helper no-ops
// on macOS so the rest of the view tree compiles on every platform the
// project currently targets.
extension View {
    @ViewBuilder
    func hyroxNavigationBar(inline: Bool = false) -> some View {
        #if !os(macOS)
        self
            .navigationBarTitleDisplayMode(inline ? .inline : .large)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    // Backwards-compatible alias. Old call sites wrote
    // `.hyroxDarkNavigationBar()` — keep them working while we
    // migrate. The "Dark" prefix is no longer accurate post light-
    // mode but renaming every call site can happen in a follow-up
    // pass.
    @ViewBuilder
    func hyroxDarkNavigationBar(inline: Bool = false) -> some View {
        self.hyroxNavigationBar(inline: inline)
    }
}

// MARK: - Pressable card button style

// Subtle press-feedback for tappable card surfaces (RaceCardView,
// recent-race rows, recap banners). Replaces .buttonStyle(.plain)
// on NavigationLinks that wrap a card-shaped element so the user
// gets tactile confirmation their tap registered.
//
// Scale-down on press: 0.98 — small enough to feel like the card
// "depresses" rather than shrinks, but visible enough to register
// at typical iPhone viewing distance. Reduce-Motion users get no
// scale change (the spring is bypassed) but still get the press
// state through SwiftUI's default tinting.
//
// Spring response 0.3 / damping 0.7 — same brand-canonical motion
// shape called out in CLAUDE.md §5. Lands with weight, doesn't
// bounce.
//
// Usage: `.buttonStyle(.pressableCard)` in place of `.plain` on
// any NavigationLink wrapping a card.
struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .animation(
                reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressableCardButtonStyle {
    static var pressableCard: PressableCardButtonStyle {
        PressableCardButtonStyle()
    }
}

// MARK: - Scroll-appearance transition

// Subtle fade + scale-up applied to children of a scrolling view.
// SwiftUI's .scrollTransition runs the closure with a `phase` value
// describing the child's position relative to the viewport — at the
// edges it's reduced (.topLeading / .bottomTrailing), in the middle
// it's .identity. We map .identity to full opacity + 1.0 scale and
// edges to dimmed + slightly smaller, so children fade in as they
// scroll into view.
//
// Used on long scrolling stacks like ProfileView's grouped sections
// and HistoryView's race feed to give them an Apple-grade entrance
// rhythm. The effect is strongest on first appearance (each child
// fades in sequentially as the layout settles) and during
// pull-to-refresh-style scrolls (children at the edges dim slightly).
//
// Reduce-Motion users get the full identity rendering at every
// phase via SwiftUI's built-in motion-respecting behavior on
// .scrollTransition (system handles it automatically).
extension View {
    @ViewBuilder
    func applyScrollAppearTransition() -> some View {
        self.scrollTransition(axis: .vertical) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .scaleEffect(phase.isIdentity ? 1 : 0.96)
                .blur(radius: phase.isIdentity ? 0 : 1.5)
        }
    }
}
