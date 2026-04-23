import Foundation

// A single completed segment of a race.
//
// Every split carries its own start and end timestamps. Duration is computed
// from those — never accumulated tick-by-tick from a timer — so it's accurate
// regardless of UI refresh rate, backgrounding, or device sleep.
struct Split: Codable, Equatable, Hashable, Identifiable, Sendable {
    let station: Station
    let startedAt: Date
    let endedAt: Date

    // `Station.rawValue` is stable and unique within a race, so it doubles as
    // the Identifiable id — no extra UUID needed.
    var id: Int { station.rawValue }

    var duration: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}
