import Foundation
import SwiftData
#if canImport(Supabase)
import Supabase
import PostgREST
#endif

#if canImport(Supabase)

// Profile sync — push local UserProfile changes to Supabase, pull
// remote changes back. The first real "data follows the athlete
// across devices" feature; subsequent table syncs (races, free
// runs) repeat the same patterns this file establishes.
//
// Sync strategy: last-write-wins by `updated_at`. When a local +
// remote profile both exist, whichever has the more recent
// `updated_at` is treated as authoritative. For v1 this is
// sufficient — profile edits are rare and conflicts are unlikely
// (one user, two devices, would have to edit on both within
// seconds). When v2 adds offline conflict resolution, we'll
// revisit.
//
// What gets synced (see RemoteProfile.swift for rationale):
//   • Identity fields: displayName, handle, location, bio,
//     division, maxHeartRate, avatarUrl
// What stays device-local:
//   • Every preference toggle (audio cues, theme, in-race
//     displays). These are per-device, not per-account.
//
// The service is `@MainActor` because every call site is a
// SwiftUI view's lifecycle method or a SwiftData mutation; the
// occasional network hop happens off-actor inside the
// PostgREST builder, so this isolation doesn't hurt.
@MainActor
enum ProfileSyncService {

    // Called from ContentView's bootstrap once per launch when an
    // authenticated user is available. Two flows:
    //
    //   1. First-ever sign-in (no remote row exists yet):
    //      INSERT a new row using the local UserProfile values.
    //   2. Returning sign-in (remote row exists):
    //      Fetch it; if the remote `updated_at` is newer than
    //      local, copy fields onto the local profile. If local
    //      is newer (we edited offline), push local up.
    //
    // Errors are swallowed — sync failure shouldn't block the
    // user from using the app. Profile sync is "best effort"
    // for v1; the next launch retries. Worth surfacing as a
    // banner in the future when sync regularly fails.
    static func syncOnSignIn(
        userID: String,
        localProfile: UserProfile,
        modelContext: ModelContext
    ) async {
        let client = SupabaseService.shared

        // Try to fetch the existing row. PostgREST returns a
        // 406 / "PGRST116" when no row matches — we treat that
        // as "no remote row exists, push local."
        do {
            let response: RemoteProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value

            // Remote exists — decide direction by `updated_at`.
            try await reconcile(
                local: localProfile,
                remote: response,
                userID: userID,
                client: client,
                modelContext: modelContext
            )
        } catch {
            // No row OR network failure. We can't distinguish
            // cleanly without parsing the error code, so the
            // safest move is to TRY to push local. If the
            // server already has a row, the upsert will
            // handle it; if it errors out cleanly, the next
            // launch retries.
            //
            // Phase 60: we previously discarded any push error
            // with a bare `try?`. That bit us — three production
            // accounts ended up without `profiles` rows because
            // the upsert failed silently (likely a transient
            // RLS / schema mismatch in an earlier deploy) and
            // the next launch's syncOnSignIn fell into the
            // SAME catch (still no remote row, push again, push
            // fails the same way, no signal). Surface the error
            // now so we don't repeat that — a banner is still
            // future work but at minimum a console + DEBUG
            // assertion makes the failure visible during dev
            // and reachable from device logs in TestFlight.
            do {
                try await pushLocalProfile(
                    localProfile,
                    userID: userID,
                    client: client
                )
            } catch {
                print("[ProfileSyncService] pushLocalProfile failed for \(userID): \(error)")
                #if DEBUG
                assertionFailure("ProfileSyncService push failed: \(error)")
                #endif
            }
        }
    }

    // Push the local profile's identity fields up. Used both for
    // first-sign-in inserts AND for "user just edited their
    // profile in EditProfileView" write-throughs. Upsert (insert
    // OR update on conflict by primary key) handles both cases
    // without us having to branch.
    static func pushLocalProfile(
        _ profile: UserProfile,
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws {
        let payload = RemoteProfileWrite(
            id: userID,
            displayName: profile.displayName,
            handle: profile.handle,
            location: profile.location,
            bio: profile.bio,
            division: profile.resolvedDivision.rawValue,
            maxHeartRate: profile.maxHeartRate,
            // Avatar URL points at the public object in the
            // `avatars` Supabase Storage bucket, set by
            // `PhotoStorageService.uploadAvatar` after a
            // successful upload. Local-only `avatarData` bytes
            // stay on-device as a zero-latency cache; the URL
            // is what travels across devices.
            avatarUrl: profile.avatarURL
        )

        try await client
            .from("profiles")
            .upsert(payload)
            .execute()
    }

    // Decide who wins, push or pull accordingly. Last-write-wins
    // by `updated_at`. Remote `updated_at` is server-managed via
    // the trigger; local `updatedAt` is set by ContentView /
    // EditProfileView when the user edits.
    private static func reconcile(
        local: UserProfile,
        remote: RemoteProfile,
        userID: String,
        client: SupabaseClient,
        modelContext: ModelContext
    ) async throws {
        let localTimestamp = local.updatedAt
        let remoteTimestamp = remote.updatedAt ?? .distantPast

        if remoteTimestamp > localTimestamp {
            // Remote is fresher — pull onto local. Only the
            // synced (identity) fields get overwritten; local
            // device preferences are untouched.
            apply(remote: remote, to: local)
            try? modelContext.save()
        } else {
            // Local is fresher (or tied) — push up.
            try await pushLocalProfile(
                local,
                userID: userID,
                client: client
            )
        }
    }

    // Copy remote field values onto a local UserProfile. Fields
    // listed here are the ones the remote table tracks; everything
    // else on UserProfile (settings toggles, theme, etc.) stays
    // local-only.
    private static func apply(remote: RemoteProfile, to local: UserProfile) {
        local.displayName = remote.displayName
        local.handle = remote.handle
        local.location = remote.location
        local.bio = remote.bio
        if let division = Division(rawValue: remote.division) {
            local.resolvedDivision = division
        }
        local.maxHeartRate = remote.maxHeartRate
        // Pull avatar URL from remote. We deliberately do NOT
        // download the JPEG bytes here — `ProfileHero` (and
        // any other avatar surface) falls back to
        // `AsyncImage(url:)` when `avatarData` is nil, which
        // streams the bytes lazily on render. Saves us a
        // synchronous network hit during sync, and the bytes
        // are cached by URLSession after the first paint.
        local.avatarURL = remote.avatarUrl

        // Bump local `updatedAt` so future reconciles see this
        // pull-from-remote as the new local baseline. Without
        // this, a slow follow-up edit could "win" against the
        // remote value we just pulled.
        local.updatedAt = remote.updatedAt ?? Date()
    }
}

#else

// Non-Supabase build (won't happen on iOS but keeps macOS / test
// targets compiling cleanly). Stub all methods as no-ops.
@MainActor
enum ProfileSyncService {
    static func syncOnSignIn(
        userID: String,
        localProfile: UserProfile,
        modelContext: ModelContext
    ) async {}

    static func pushLocalProfile(
        _ profile: UserProfile,
        userID: String
    ) async throws {}
}

#endif
