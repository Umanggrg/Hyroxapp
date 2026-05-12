import Foundation

// Platform-specific haptic imports. iOS uses UIImpactFeedbackGenerator
// from UIKit; watchOS has its own tightly-curated set of haptic types
// in WKInterfaceDevice (WatchKit). macOS has no haptic API at all, so
// everything below becomes a silent no-op there.
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

// Central haptic feedback. All call sites use this wrapper rather than
// instantiating `UIImpactFeedbackGenerator` / `WKInterfaceDevice` directly
// so:
//   - adding a "respect Reduce Motion" setting later is a one-file change
//   - the same Race code path fires the right haptic on both iPhone
//     (continuous impact styles) and Apple Watch (discrete WKHapticType
//     presets) without the caller caring which device it's on
//   - the semantic intent ("success", "advance") is named rather than
//     coupled to any platform's style enum
enum Haptics {
    enum Impact {
        case light
        case medium
        case heavy
        case rigid
        case soft

        #if os(iOS)
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

        #if os(watchOS)
        // watchOS exposes a small enumerated set of system haptics, not a
        // continuous impact scale. Map each of our semantic Impact cases
        // to the closest WKHapticType so callers can keep writing
        // `.medium` / `.light` etc. without watch-specific branches at
        // every call site. `.click` is the generic "action acknowledged"
        // tap — that's what most of our intermediate taps want.
        fileprivate var watchHaptic: WKHapticType {
            switch self {
            case .light, .soft:       return .click
            case .medium, .rigid:     return .click
            case .heavy:              return .notification
            }
        }
        #endif
    }

    // A generic "action acknowledged" tap. Used on Next Station.
    static func impact(_ style: Impact = .medium) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style.uiStyle)
        generator.prepare()
        generator.impactOccurred()
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(style.watchHaptic)
        #endif
    }

    // A double-pulse success pattern. Used on race finish.
    static func success() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
        #elseif os(watchOS)
        WKInterfaceDevice.current().play(.success)
        #endif
    }

    // A cautionary pulse. Used when abandoning a race.
    static func warning() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
        #elseif os(watchOS)
        // watchOS doesn't expose a `.warning` case; `.failure` is the
        // closest "something was undone" pattern. `.notification` would
        // also work but is louder / more attention-grabbing.
        WKInterfaceDevice.current().play(.failure)
        #endif
    }

    // Wireframe 03.3 — per-coaching-cue haptic pattern. Each banner
    // state has a distinct rhythm so the wrist (or pocket) can tell
    // the cue apart before the eye reaches the screen:
    //
    //   • HOLD     → single gentle tap         (you're in the zone)
    //   • SLOW     → two quick taps            (ease back)
    //   • REDLINE  → three urgent heavy taps   (critical, act now)
    //   • RECOVER  → single soft tap           (let the descent happen)
    //   • PUSH     → strong single tap         (go go go)
    //   • workout/none → no haptic
    //
    // The 3-tap REDLINE pattern uses asyncAfter to space out the
    // impacts. Same approach the watchOS RaceView already takes
    // for the same cue on the wrist.
    static func coachingCue(_ cue: RaceStats.CoachingCue) {
        switch cue {
        case .hold:
            impact(.light)
        case .slow:
            impact(.medium)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                impact(.medium)
            }
        case .redline:
            impact(.heavy)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                impact(.heavy)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                impact(.heavy)
            }
        case .recover:
            impact(.soft)
        case .push:
            impact(.heavy)
        case .workout, .none:
            // No haptic on these states — they're absence-of-cue.
            break
        }
    }
}
