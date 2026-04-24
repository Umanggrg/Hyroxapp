import Foundation

// An action initiated on the Apple Watch, sent to the paired iPhone
// through `WCSession.sendMessage(_:replyHandler:errorHandler:)`.
//
// Symmetric counterpart to `RaceStateSnapshot` (phone → watch state
// pushes): this carries user intent in the other direction. Today only
// `.advance` is defined — the primary Watch use case is tapping "Next
// Station" mid-workout without pulling out the phone. Future extensions
// are trivially additive (`.start`, `.cancel`, `.finishSession`, etc.)
// so long as both sides decode defensively.
//
// Design notes:
//   - `sendMessage` requires both apps to be reachable; that's fine
//     here because action messages only matter when both are alive
//     (mid-race). If reachability drops, the Watch's local tap should
//     fail visibly — we don't want silent queueing where the phone
//     advances 20 seconds later because the message finally arrived.
//   - Dictionary encoding is trivial (one String key) but we keep the
//     pattern consistent with RaceStateSnapshot so both sides are
//     decoded the same way.
//
// Shared between iOS and watchOS targets via target membership.
enum WatchAction: Sendable, Equatable {
    case advance

    // MARK: - Dictionary encoding

    private enum Key {
        static let action = "action"
    }

    // Raw string values sent over the wire. Keep these stable — changing
    // them later without a version-handshake story would break older
    // Watch builds talking to newer iPhone builds.
    private var rawValue: String {
        switch self {
        case .advance: return "advance"
        }
    }

    func toDictionary() -> [String: Any] {
        [Key.action: rawValue]
    }

    init?(dictionary: [String: Any]) {
        guard let raw = dictionary[Key.action] as? String else { return nil }
        switch raw {
        case "advance": self = .advance
        default: return nil
        }
    }
}
