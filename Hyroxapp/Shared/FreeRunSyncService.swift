import Foundation
import SwiftData
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// Free Run sync — push finished runs up to Supabase, pull any
// remote-only runs down on launch. Same last-write-wins pattern
// races use, applied to the FreeRun model.
//
// Sync triggers:
//   • Push: when a run finishes AND the post-finish HK rehydrate
//     has populated HR averages. Calling pushFinishedRun before
//     rehydrate would push a row with nil HR fields, which would
//     get re-pushed after rehydrate anyway — by waiting for the
//     rehydrate task to complete we push once with full data.
//   • Pull: on app launch after profile + race sync, fetch all
//     free runs for this user from Supabase, merge by id with
//     local rows.
//
// In-progress runs stay LOCAL ONLY. Same contract as races: a
// run is synced once it's finished. Mid-run app kills resume
// locally; the eventual finish triggers the push.
@MainActor
enum FreeRunSyncService {

    // MARK: - Push

    // Send a finished run to Supabase. Idempotent upsert by
    // primary key. Bails silently on errors (next launch's
    // pullAndReconcile catches up) and on in-progress runs
    // (defensive guard against accidental mid-run pushes).
    static func pushFinishedRun(
        _ run: FreeRun,
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        guard run.endedAt != nil else { return }

        let payload = RemoteFreeRunWrite(
            id: run.id.uuidString,
            userId: userID,
            startedAt: run.startedAt,
            endedAt: run.endedAt,
            pausedAt: run.pausedAt,
            distanceMetres: run.distanceMetres,
            locationType: run.locationType.rawValue,
            splitUnit: run.splitUnit.rawValue,
            splits: run.splits,
            heartRateAvgBPM: run.heartRateAvgBPM,
            heartRateMaxBPM: run.heartRateMaxBPM,
            activeCaloriesKcal: run.activeCaloriesKcal,
            name: run.name,
            notes: run.notes,
            isPrivate: run.isPrivate,
            // Photo URL pre-wired for the FreeRun photo picker
            // shipping in a follow-up. Stays nil for now since
            // there's no UI yet — the schema is round-trip
            // ready so adding the picker is purely a UI change.
            photoUrl: run.photoURL
        )

        do {
            try await client
                .from("free_runs")
                .upsert(payload)
                .execute()
        } catch {
            // Non-fatal — local row persists, next launch retries.
        }
    }

    // MARK: - Pull + reconcile

    // Same three-case merge race sync uses:
    //   1. Remote-only — insert as a new local row
    //   2. Local-only — push up
    //   3. Both exist — last-write-wins by `updated_at`, taking
    //      remote when newer
    static func pullAndReconcile(
        userID: String,
        modelContext: ModelContext,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        let remoteRuns: [RemoteFreeRun]
        do {
            remoteRuns = try await client
                .from("free_runs")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
        } catch {
            return
        }

        let descriptor = FetchDescriptor<FreeRun>()
        let localRuns = (try? modelContext.fetch(descriptor)) ?? []
        var localByID: [String: FreeRun] = [:]
        for run in localRuns {
            localByID[run.id.uuidString] = run
        }

        for remote in remoteRuns {
            if let local = localByID[remote.id] {
                // Both exist — last-write-wins. FreeRun has a
                // `createdAt` we use as the local proxy for
                // updatedAt (FreeRun doesn't track edits with
                // their own timestamp, same pattern as Race).
                let remoteTimestamp = remote.updatedAt ?? .distantPast
                let localTimestamp = local.createdAt
                if remoteTimestamp > localTimestamp {
                    apply(remote: remote, to: local)
                }
                localByID.removeValue(forKey: remote.id)
            } else {
                // Remote-only — insert.
                let inserted = FreeRun(
                    id: UUID(uuidString: remote.id) ?? UUID(),
                    startedAt: remote.startedAt,
                    endedAt: remote.endedAt,
                    pausedAt: remote.pausedAt,
                    distanceMetres: remote.distanceMetres,
                    locationType: FreeRunLocationType(rawValue: remote.locationType) ?? .indoor,
                    splitUnit: FreeRunSplitUnit(rawValue: remote.splitUnit) ?? .mile,
                    splits: remote.splits,
                    heartRateAvgBPM: remote.heartRateAvgBPM,
                    heartRateMaxBPM: remote.heartRateMaxBPM,
                    activeCaloriesKcal: remote.activeCaloriesKcal,
                    name: remote.name,
                    notes: remote.notes,
                    photoData: nil,
                    isPrivate: remote.isPrivate,
                    createdAt: remote.createdAt ?? Date()
                )
                inserted.photoURL = remote.photoUrl
                modelContext.insert(inserted)
            }
        }

        // Local-only finished runs get pushed up.
        for (_, leftover) in localByID where leftover.endedAt != nil {
            await pushFinishedRun(
                leftover,
                userID: userID,
                client: client
            )
        }

        try? modelContext.save()
    }

    // Wholesale-replace synced fields. Same approach as race
    // sync's `apply` — for v1, on conflict we trust remote
    // entirely.
    private static func apply(remote: RemoteFreeRun, to local: FreeRun) {
        local.startedAt = remote.startedAt
        local.endedAt = remote.endedAt
        local.pausedAt = remote.pausedAt
        local.distanceMetres = remote.distanceMetres
        local.locationTypeRaw = remote.locationType
        local.splitUnitRaw = remote.splitUnit
        local.splits = remote.splits
        local.heartRateAvgBPM = remote.heartRateAvgBPM
        local.heartRateMaxBPM = remote.heartRateMaxBPM
        local.activeCaloriesKcal = remote.activeCaloriesKcal
        local.name = remote.name
        local.notes = remote.notes
        local.isPrivate = remote.isPrivate
        local.photoURL = remote.photoUrl
    }
}

#else

@MainActor
enum FreeRunSyncService {
    static func pushFinishedRun(_ run: FreeRun, userID: String) async {}
    static func pullAndReconcile(userID: String, modelContext: ModelContext) async {}
}

#endif
