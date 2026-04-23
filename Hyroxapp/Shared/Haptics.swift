import Foundation

#if canImport(UIKit)
import UIKit
#endif

// Central haptic feedback. All call sites use this wrapper rather than
// instantiating `UIImpactFeedbackGenerator` directly so:
//   - adding a "respect Reduce Motion" setting later is a one-file change
//   - non-UIKit platforms (macOS native) compile cleanly (no-op there)
//   - the semantic intent is named ("success", "advance") rather than
//     couplimg call sites to UIKit's style enum
enum Haptics {
    enum Impact {
        case light
        case medium
        case heavy
        case rigid
        case soft

        #if canImport(UIKit)
        fileprivate var uiStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light:  return .light
            case .medium: return .medium
            case .heavy:  return .heavy
            case .rigid:  return .rigid
            case .soft:   return .soft
            }
        }
        #endif
    }

    // A generic "action acknowledged" tap. Used on Next Station.
    static func impact(_ style: Impact = .medium) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    // A double-pulse success pattern. Used on race finish.
    static func success() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #endif
    }

    // A cautionary pulse. Used when abandoning a race.
    static func warning() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #endif
    }
}
