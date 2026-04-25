import Foundation

// Tiny Identifiable wrapper around Int. SwiftUI's `.sheet(item:)`
// needs an Identifiable value, and a raw Int doesn't qualify
// (Int has no canonical id). This wrapper says "the value IS the
// id" — collisions are impossible inside a single view's state
// because we only store one at a time.
//
// Used today by:
//   • RaceSummaryView — splitting which split is being edited
//     in StationStatsSheet
//   • RaceDetailView — same
//
// Could also be done with `Identifiable` extensions on Int via
// a private wrapper, but having a named struct makes the intent
// at the call site obvious ("this Int identifies a row").
struct IdentifiedIndex: Identifiable, Hashable, Sendable {
    let value: Int
    var id: Int { value }

    init(_ value: Int) {
        self.value = value
    }
}
