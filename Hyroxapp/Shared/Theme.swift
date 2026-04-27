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

    // Text
    static let textPrimary   = Color(lightHex: 0x161513, darkHex: 0xF5F5F7)
    static let textSecondary = Color(lightHex: 0x6B6964, darkHex: 0x8E8E93)
    static let textTertiary  = Color(lightHex: 0xA8A6A0, darkHex: 0x636366)

    // Accent & semantic
    //
    // Coral accent stays constant across modes — it's the brand signal.
    // The success/warning greens and ambers shift slightly: the dark
    // variants are tuned for OLED black, the light variants are nudged
    // darker so they stay legible on warm off-white. Same hue, different
    // value step.
    static let accent    = Color(hex: 0xFF3B30)
    static let accentDim = Color(hex: 0xFF3B30, opacity: 0.6)
    static let success   = Color(lightHex: 0x1FA82A, darkHex: 0x32D74B)
    static let warning   = Color(lightHex: 0xC4720A, darkHex: 0xFF9F0A)

    // FIXED off-white for labels that sit ON the coral accent
    // (primary CTAs, hold-to-finish, gradient buttons). Brand
    // contract: white-on-coral is the canonical button look in
    // both modes. Without this fixed token, light-mode users see
    // near-black warm text on coral which reads as muted /
    // unfinished even though it has enough contrast. Use this
    // anywhere the background is `Color.accent` or a coral
    // gradient — NOT `Color.textPrimary`.
    static let onAccent = Color(hex: 0xFFFFFF)

    // Hairlines & separators
    static let divider = Color(lightHex: 0xE5E1D8, darkHex: 0x2C2C2E)

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
    // Default outer horizontal padding for screens.
    static let screenMargin: CGFloat = 24

    // Padding inside cards.
    static let cardPadding: CGFloat = 16

    // Standard corner radius for cards.
    static let cardCornerRadius: CGFloat = 12

    // Minimum tap-target height for in-race buttons (sweaty, shaky hands).
    static let raceButtonHeight: CGFloat = 80

    // Minimum tap-target height outside of a race.
    static let standardButtonHeight: CGFloat = 44
}

// MARK: - Motion

enum Motion {
    // Default spring for state transitions — subtle, not bouncy.
    // Respects Reduce Motion automatically when applied via `.animation`.
    static let standardSpring: Animation = .spring(response: 0.4, dampingFraction: 0.8)

    // Snappier spring for primary CTAs and tab transitions — faster
    // response time so taps feel instant. Slightly less damped so
    // there's a tiny visual settle that confirms the action.
    static let snappySpring: Animation = .spring(response: 0.28, dampingFraction: 0.75)

    // Loose spring for hero animations — number count-ups, race
    // finish moment, badge unlocks. More follow-through, more
    // emotional. Reach for this when the moment deserves it.
    static let heroSpring: Animation = .spring(response: 0.55, dampingFraction: 0.7)

    // Soft ease for ambient changes — breathing glows, idle
    // pulse on the race-day countdown, low-frequency loops. Pair
    // with `.repeatForever(autoreverses: true)`.
    static let ambient: Animation = .easeInOut(duration: 2.4)
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
