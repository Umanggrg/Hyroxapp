import Foundation

// A single heart-rate sample captured during a workout — used by
// both Free Run (Phase 27) and HYROX Race (Phase 28). Stored as a
// Codable struct so the array can be encoded to either
// `FreeRun.hrSeriesData` or `Race.hrSeriesData` (Data BLOBs on the
// @Models). Same persistence pattern other composite value types
// across the codebase use.
//
// Why we capture our own series instead of relying on HealthKit:
//   • The Watch streams HR to the iPhone via WCSession at ~1Hz during
//     a workout. Pre-capture, those samples drove only the live HR
//     chip and were discarded.
//   • Post-run zone-time computation used `HealthKitService.timeInZones`
//     to re-read the HR series from HK. HK's stored sample density is
//     unreliable — late writes, sparse passive readings, the 10s
//     `maxGap` cap in timeInZones — so a 34-min run could come back
//     with only ~14 min of zone time accounted for.
//   • Capturing every WCSession sample (and the HK 5s poll fallback)
//     into an in-memory buffer that we own gives us the true dense
//     series. Persisting it on finish makes the same series available
//     to post-race analytics — share card zones, per-split HR
//     aggregates, drift / recovery / efficiency math — without a
//     second HK round-trip.
//   • Critical enabler for §20 Path A (Garmin / external BLE HR).
//     With a BLE strap as the source, HK isn't being written to at
//     race-grade density; the in-app buffer is the only authoritative
//     dense series we have.
//
// Wire format: Codable struct with `sampledAt` + `bpm` field names.
// Renamed from `FreeRunHRSample` in Phase 28 to support both surfaces;
// existing Phase 27 Free Run blobs decode cleanly because Codable is
// structural (same field names + types) rather than nominal.
//
// 90 minutes × 1Hz ≈ 5400 samples × ~24 bytes encoded ≈ 130 KB worst
// case. Trivial as an external-storage BLOB on the SwiftData row.
struct HRSample: Codable, Equatable, Hashable, Sendable {
    let sampledAt: Date
    let bpm: Double
}
