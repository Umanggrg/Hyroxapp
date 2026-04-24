import Foundation

// Formatting + per-race stat helpers, shared across Race, History, and
// Profile. Consolidated here so every surface uses the same numbers and the
// same MM:SS / H:MM:SS rendering — future retuning (millisecond display,
// pace per km, etc.) is a single-file change.
//
// A subset of this file is also shared with the watchOS target (via
// target membership), because the watch's placeholder race screen needs
// `RaceStats.format()` to render its timer. But the watch target does NOT
// include `Race.swift` — Race is a SwiftData `@Model` with persistence
// semantics the watch doesn't need. To keep one file for both platforms,
// everything that touches `Race` is guarded `#if !os(watchOS)`; only
// `format()` is unconditionally compiled and therefore visible on watch.
enum RaceStats {

    // MARK: - Per-race stats (phone only)

    #if !os(watchOS)

    static func totalTime(_ race: Race) -> String {
        format(race.totalDuration ?? 0)
    }

    // Fastest single 1km run in this race.
    static func bestRun(_ race: Race) -> String {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard let best = runs.map(\.duration).min() else { return "—" }
        return format(best)
    }

    // Average of the 8 run splits.
    static func avgRun(_ race: Race) -> String {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard !runs.isEmpty else { return "—" }
        let avg = runs.map(\.duration).reduce(0, +) / Double(runs.count)
        return format(avg)
    }

    // Time spent on the Wall Balls station — the final grind in a HYROX
    // race, often the most indicative single split for overall fitness.
    static func wallBalls(_ race: Race) -> String {
        guard let split = race.splits.first(where: { $0.station == .wallBalls }) else { return "—" }
        return format(split.duration)
    }

    // MARK: - Cross-race aggregates (for Profile) — phone only

    // Fastest total race time across the provided races (nil if none).
    static func personalBest(_ races: [Race]) -> TimeInterval? {
        races.compactMap(\.totalDuration).min()
    }

    // Average total race time across the provided races.
    static func averageTotal(_ races: [Race]) -> TimeInterval? {
        let times = races.compactMap(\.totalDuration)
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    // Sum of completed splits across all provided races.
    static func totalStationsCompleted(_ races: [Race]) -> Int {
        races.reduce(0) { $0 + $1.splits.count }
    }

    // Was this race a personal best (fastest total time) at the moment it
    // was completed? Matches the Strava "New PR" model — only races that
    // actually broke a record get the badge, not every current-best race.
    // The first completed race counts as a PB by default.
    static func wasPBWhenSet(_ race: Race, among all: [Race]) -> Bool {
        guard let thisTotal = race.totalDuration else { return false }
        let earlierBest = all
            .filter { $0.createdAt < race.createdAt && $0.isFinished }
            .compactMap(\.totalDuration)
            .min()
        guard let earlierBest else {
            return true
        }
        return thisTotal < earlierBest
    }

    #endif  // !os(watchOS)

    // MARK: - Formatting (shared with watchOS)

    // Render a TimeInterval as MM:SS, or H:MM:SS when it crosses an hour.
    // Rounds down to whole seconds — sub-second precision is distracting on
    // the big timer and only matters in the split table where raw splits
    // are already shown alongside. Pure arithmetic — no platform-specific
    // dependencies — so it compiles unchanged on iOS and watchOS.
    static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
