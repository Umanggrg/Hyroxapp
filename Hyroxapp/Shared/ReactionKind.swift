import Foundation
import SwiftUI

// Four HYROX-themed reactions, locked at v1 per CLAUDE.md
// §17.4. Each has an emoji (the user-facing affordance) and
// a tint color (drives the "you reacted" highlight).
//
// `rawValue` matches the Postgres CHECK constraint on the
// reactions.kind column — change one without the other and
// inserts will fail server-side.
enum ReactionKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case fire
    case strong
    case fast
    case respect

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .fire: return "🔥"
        case .strong: return "💪"
        case .fast: return "⚡"
        case .respect: return "🫡"
        }
    }

    var label: String {
        switch self {
        case .fire: return "Fire"
        case .strong: return "Strong"
        case .fast: return "Fast"
        case .respect: return "Respect"
        }
    }

    // Subtle tint for the "you reacted" highlight on feed
    // cards. All four share the same coral accent so the
    // emojis carry the kind-distinction visually — color
    // doubles up only on the active state.
    var activeTint: Color {
        Color.accent
    }
}
