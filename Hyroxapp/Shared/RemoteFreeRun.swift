import Foundation

// Codable mirror of the Supabase `free_runs` table. Same DTO
// pattern profiles + races use — keep the network shape distinct
// from the SwiftData @Model class so they evolve independently.
//
// Splits stored as a JSONB column on the server, modeled as
// `[FreeRunSplit]` here. Same encoding strategy as race splits:
// supabase-swift's encoder applies its date strategy recursively,
// so nested Date fields inside FreeRunSplit round-trip cleanly.
//
// What's synced:
//   • All identity + lifecycle fields, distance, splits, HR
//     aggregates, calories, name, notes, privacy.
// What's deferred:
//   • photoData bytes → Supabase Storage holds the JPEG (the
//     `free-run-photos` bucket); only the public URL travels in
//     this row via `photo_url`. The bytes themselves stay
//     local-only as a render cache. The picker UI for FreeRun
//     ships in a follow-up; field is wired now so the schema
//     is ready.
struct RemoteFreeRun: Codable, Sendable {
    let id: String
    let userId: String
    let startedAt: Date
    let endedAt: Date?
    let pausedAt: Date?
    let distanceMetres: Double
    let locationType: String
    let splitUnit: String
    let splits: [FreeRunSplit]
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?
    let activeCaloriesKcal: Double?
    let name: String
    let notes: String
    let isPrivate: Bool
    let photoUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case pausedAt = "paused_at"
        case distanceMetres = "distance_metres"
        case locationType = "location_type"
        case splitUnit = "split_unit"
        case splits
        case heartRateAvgBPM = "heart_rate_avg_bpm"
        case heartRateMaxBPM = "heart_rate_max_bpm"
        case activeCaloriesKcal = "active_calories_kcal"
        case name
        case notes
        case isPrivate = "is_private"
        case photoUrl = "photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Insert/update payload — same shape minus server-managed fields
// (created_at, updated_at). The server fills these via defaults
// and the trigger.
struct RemoteFreeRunWrite: Codable, Sendable {
    let id: String
    let userId: String
    let startedAt: Date
    let endedAt: Date?
    let pausedAt: Date?
    let distanceMetres: Double
    let locationType: String
    let splitUnit: String
    let splits: [FreeRunSplit]
    let heartRateAvgBPM: Double?
    let heartRateMaxBPM: Double?
    let activeCaloriesKcal: Double?
    let name: String
    let notes: String
    let isPrivate: Bool
    let photoUrl: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case pausedAt = "paused_at"
        case distanceMetres = "distance_metres"
        case locationType = "location_type"
        case splitUnit = "split_unit"
        case splits
        case heartRateAvgBPM = "heart_rate_avg_bpm"
        case heartRateMaxBPM = "heart_rate_max_bpm"
        case activeCaloriesKcal = "active_calories_kcal"
        case name
        case notes
        case isPrivate = "is_private"
        case photoUrl = "photo_url"
    }
}
