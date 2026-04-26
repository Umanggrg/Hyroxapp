import SwiftUI

// User-facing theme preference. Drives the value passed to
// `.preferredColorScheme(...)` at the app root.
//
// Three options — same pattern as iOS Settings → Display & Brightness
// (which is the mental model users already have):
//   • .system — follow the OS-wide light/dark setting (default)
//   • .light  — force light mode regardless of OS
//   • .dark   — force dark mode regardless of OS
//
// Stored on `UserProfile` as an optional raw String for SwiftData
// migration safety (see `UserProfile.themePreferenceRaw`). All
// reads / writes from view code should go through
// `UserProfile.resolvedThemePreference`.
enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    // Display label for Settings UI.
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    // SF Symbol that matches the option in Settings — same icons
    // Apple uses on iOS Settings → Display & Brightness for
    // visual consistency with what users already recognize.
    var systemImage: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    // The value to pass to `.preferredColorScheme(...)`. SwiftUI
    // treats `nil` as "follow the environment" — i.e. follow iOS's
    // mode setting — which is exactly the .system semantics we
    // want. The other two cases force the corresponding scheme.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
