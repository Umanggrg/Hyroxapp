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
    // Giant always-visible race timer. Pair with `.monospacedDigit()`.
    static let raceTimer = Font.system(size: 72, weight: .bold, design: .rounded)

    // Hero stat on cards, e.g. a race's total time. Pair with `.monospacedDigit()`.
    static let heroStat = Font.system(size: 44, weight: .bold, design: .rounded)

    // Active station name on the race screen.
    static let stationTitle = Font.largeTitle.weight(.bold)

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
