import Foundation

// A single heart-rate sample captured during a Free Run. Stored as
// a Codable struct so the array can be encoded to `FreeRun.hrSeriesData`
// (a Data BLOB on the @Model) — same persistence pattern other
// composite value types on Race / FreeRun use.
//
// Why we capture our own series instead of relying on HealthKit:
//   • The Watch streams HR to the iPhone via WCSession at ~1Hz during
//     a workout (FreeRunView wires `WatchCompanionService.shared.onHeartRate`
//     → `viewModel.ingestHeartRateBPM`). Pre-Phase-27 those samples
//     drove only the live HR chip and were discarded.
//   • Post-run zone-time computation used `HealthKitService.timeInZones`
//     to re-read the HR series from HK. HK's stored sample density is
//     unreliable — late writes, sparse passive readings, the 10s
//     `maxGap` cap in timeInZones — so a 34-min run could come back
//     with only ~14 min of zone time accounted for.
//   • Capturing every WCSession sample (and the HK 5s poll fallback)
//     into an in-memory buffer that we own gives us the true dense
//     series. Persisting it on finish makes the same series available
//     to History detail, future trend views, and any post-hoc
//     analytics without a second HK round-trip.
//
// 90 minutes × 1Hz ≈ 5400 samples × ~24 bytes encoded ≈ 130 KB worst
// case. Trivial as an external-storage BLOB on the SwiftData row.
struct FreeRunHRSample: Codable, Equatable, Hashable, Sendable {
    let sampledAt: Date
    let bpm: Double
}
