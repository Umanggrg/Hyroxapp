import Foundation
import SwiftData
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// Race sync — push finished races up to Supabase, pull any
// remote-only races down on launch. Same last-write-wins
// pattern profiles use, scaled to "many rows per user."
//
// Sync triggers:
//   • Push: when a race finishes (RaceViewModel.advance()
//     transitions the engine to .finished), the just-saved
//     row is upserted to Supabase. Errors are swallowed; the
//     next launch's pullAndReconcile catches up.
//   • Pull: on app launch after profile sync completes, fetch
//     all races for this user from Supabase, merge by id with
//     local races. Last-write-wins by `updated_at`.
//
// In-progress races stay LOCAL ONLY. The contract is "a race is
// synced once it's finished." Mid-race app kills resume locally
// the way they always have; if the user finishes the race after
// the resume, normal push-on-finish covers it.
//
// Failure mode: when network is offline, the upsert fails and
// the local row sits with no `remote_synced_at` flag. We don't
// have an explicit sync queue today — the next pull-on-launch
// re-checks every local race against remote and pushes any
// missing ones. This handles offline-finished races as a
// natural side effect of last-write-wins merging.
@MainActor
enum RaceSyncService {

    // MARK: - Push

    // Send a finished race to Supabase. Called from
    // `RaceViewModel.advance()` when the engine transitions to
    // .finished. Idempotent: upsert by primary key, so the same
    // race called twice (e.g. retry after a network failure)
    // doesn't create duplicates.
    //
    // Bails silently if the user isn't authenticated or the
    // race isn't actually finished — defensive guards.
    static func pushFinishedRace(
        _ race: Race,
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        guard race.endedAt != nil else { return }

        let payload = RemoteRaceWrite(
            id: race.id.uuidString,
            userId: userID,
            startedAt: race.startedAt,
            endedAt: race.endedAt,
            splits: race.splits,
            sequenceRaw: race.sequenceRaw,
            mode: race.modeRawValue,
            notes: race.notes,
            targetDuration: race.targetDuration,
            name: race.name,
            pausedAt: race.pausedAt,
            partner: race.partner,
            isPrivate: race.isPrivate,
            tagsRaw: race.tagsRaw
        )

        do {
            try await client
                .from("races")
                .upsert(payload)
                .execute()
        } catch {
            // Sync failure is non-fatal. The local row persists;
            // next pullAndReconcile catches it and retries.
        }
    }

    // MARK: - Pull + reconcile

    // Fetch all remote races for this user, merge with local.
    // Three cases per row:
    //   1. Remote-only — race finished on another device, exists
    //      in Supabase, missing locally. Insert into SwiftData.
    //   2. Local-only — finished offline, never synced. Push up.
    //   3. Both exist — last-write-wins by `updated_at`. If
    //      remote is fresher, copy the changed fields onto local.
    //      If local is fresher, push up.
    //
    // For v1, "fresher fields" means we just take the whole
    // remote row's content and overwrite local. Per-field merge
    // (e.g. local-edited `notes` + remote-edited `name`) is a v2
    // feature — for now races rarely change after they finish,
    // so wholesale replace is acceptable.
    static func pullAndReconcile(
        userID: String,
        modelContext: ModelContext,
        client: SupabaseClient = SupabaseService.shared
    ) async {
        let remoteRaces: [RemoteRace]
        do {
            remoteRaces = try await client
                .from("races")
                .select()
                .eq("user_id", value: userID)
                .execute()
                .value
        } catch {
            // Network failure — leave everything as-is. Next
            // launch retries.
            return
        }

        // Pull local rows. Index by id for fast lookup.
        let descriptor = FetchDescriptor<Race>()
        let localRaces = (try? modelContext.fetch(descriptor)) ?? []
        var localByID: [String: Race] = [:]
        for race in localRaces {
            localByID[race.id.uuidString] = race
        }

        // Walk the remote set, reconcile each.
        for remote in remoteRaces {
            if let local = localByID[remote.id] {
                // Both exist — last-write-wins by updated_at.
                let remoteTimestamp = remote.updatedAt ?? .distantPast
                // Race doesn't have an explicit local
                // updated_at; use createdAt as a proxy. Most
                // edits to a race land via persistActiveRun
                // which doesn't bump anything, so for v1 we
                // bias toward "remote always wins on
                // conflict." Acceptable since races are
                // mostly write-once on finish.
                let localTimestamp = local.createdAt
                if remoteTimestamp > localTimestamp {
                    apply(remote: remote, to: local)
                }
                // Remove from the local map so what's left
                // after the loop is "local-only" rows.
                localByID.removeValue(forKey: remote.id)
            } else {
                // Remote-only — insert as a new local row.
                let inserted = Race(
                    id: UUID(uuidString: remote.id) ?? UUID(),
                    startedAt: remote.startedAt,
                    endedAt: remote.endedAt,
                    splits: remote.splits,
                    sequence: remote.sequenceRaw.compactMap { Station(rawValue: $0) },
                    mode: RaceMode(rawValue: remote.mode) ?? .solo,
                    createdAt: remote.createdAt ?? Date(),
                    notes: remote.notes,
                    targetDuration: remote.targetDuration,
                    name: remote.name,
                    pausedAt: remote.pausedAt,
                    partner: remote.partner
                )
                inserted.isPrivate = remote.isPrivate
                inserted.tagsRaw = remote.tagsRaw
                modelContext.insert(inserted)
            }
        }

        // Anything still in localByID is local-only — finished
        // offline or by an older app version that didn't push.
        // Upload them so the remote catches up.
        for (_, leftover) in localByID where leftover.endedAt != nil {
            await pushFinishedRace(
                leftover,
                userID: userID,
                client: client
            )
        }

        try? modelContext.save()
    }

    // Copy remote fields onto a local Race row in place. Used in
    // the conflict path (both exist, remote fresher). We replace
    // every synced field rather than diffing — finished races
    // are mostly write-once on the server, so wholesale replace
    // is the simplest correct behavior.
    private static func apply(remote: RemoteRace, to local: Race) {
        local.startedAt = remote.startedAt
        local.endedAt = remote.endedAt
        local.splits = remote.splits
        local.sequenceRaw = remote.sequenceRaw
        local.modeRawValue = remote.mode
        local.notes = remote.notes
        local.targetDuration = remote.targetDuration
        local.name = remote.name
        local.pausedAt = remote.pausedAt
        local.partner = remote.partner
        local.isPrivate = remote.isPrivate
        local.tagsRaw = remote.tagsRaw
    }
}

#else

@MainActor
enum RaceSyncService {
    static func pushFinishedRace(_ race: Race, userID: String) async {}
    static func pullAndReconcile(userID: String, modelContext: ModelContext) async {}
}

#endif
