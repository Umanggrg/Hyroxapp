import SwiftUI

// Central design tokens for HyroxApp.
//
// All colors, typography, layout constants, and motion primitives live here.
// Views should reference `Color.background`, `Font.raceTimer`, `Layout.cardPadding`,
// etc. — never hardcode hex values or magic numbers at the call site. This keeps
// the Strava-inspired dark theme consistent and makes future retuning (e.g.
// softening the accent red) a one-file change.

// MARK: - Colors

extension Color {
    // Surfaces
    static let background      = Color(hex: 0x0A0A0B)
    static let surface         = Color(hex: 0x141416)
    static let surfaceElevated = Color(hex: 0x1C1C1F)

    // Text
    static let textPrimary   = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary  = Color(hex: 0x636366)

    // Accent & semantic
    static let accent    = Color(hex: 0xFF3B30)
    static let accentDim = Color(hex: 0xFF3B30, opacity: 0.6)
    static let success   = Color(hex: 0x32D74B)
    static let warning   = Color(hex: 0xFF9F0A)

    // Hairlines & separators
    static let divider = Color(hex: 0x2C2C2E)

    // Init a Color from a 24-bit RGB hex literal (e.g. `0xFF3B30`).
    // Swift lets us add custom initializers to types via extensions — this is
    // how we avoid writing `Color(red: 1, green: 0.23, blue: 0.19)` everywhere.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
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

// Card hierarchy isn't just about background color — depth via
// shadow tells the eye what's interactive vs ambient. Three tiers:
//   • subtle: default cards, barely lifted
//   • elevated: hero / primary cards (race start CTA, recap banner)
//   • dramatic: floating overlays (countdown, finish moment)
//
// All shadows tinted slightly cool so they don't muddy the dark
// theme; tinted black at low opacity preserves the deep-black feel.
enum Depth {
    static func subtle() -> some View {
        Color.clear
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    // Stack via .background(...) on the card.
    struct ElevatedShadow: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
        }
    }

    struct DramaticShadow: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
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

// Consolidated nav-bar treatment used by HistoryView, RaceDetailView, and
// ProfileView. `navigationBarTitleDisplayMode`, `.toolbarBackground(_:for:)`,
// and `.toolbarColorScheme(_:for:)` with `.navigationBar` placement are
// iOS / iPadOS / visionOS / Mac-Catalyst only — macOS native uses a
// different title-bar model. The helper no-ops on macOS so the rest of the
// view tree compiles on every platform the project currently targets.
extension View {
    @ViewBuilder
    func hyroxDarkNavigationBar(inline: Bool = false) -> some View {
        #if !os(macOS)
        self
            .navigationBarTitleDisplayMode(inline ? .inline : .large)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }
}
