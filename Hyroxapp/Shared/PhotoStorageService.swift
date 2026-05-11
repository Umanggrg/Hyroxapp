import Foundation
#if canImport(Supabase)
import Supabase
import Storage
#endif

#if canImport(Supabase)

// Photo upload helper for Supabase Storage. v1 ships the avatar
// upload path; race / free-run photos are the next step and
// follow the same pattern (different bucket, different folder
// scheme).
//
// Bucket layout for `avatars`:
//   avatars/{userID}/profile.jpg
//
// One avatar per user, deterministic path. Reupload overwrites
// the same object via `upsert: true`. The public URL therefore
// stays stable in shape — but we append a `?t={epochMs}` cache
// buster so AsyncImage (and downstream caches like URLCache /
// SDWebImage / Kingfisher when we ship them) see the new URL
// string on each upload and refetch instead of serving the
// stale, cached image.
//
// Storage RLS (set in Supabase SQL editor) gates writes to the
// folder named after the authenticated user's auth.uid(), so an
// athlete can never overwrite another user's avatar.
@MainActor
enum PhotoStorageService {

    // MARK: - Errors

    enum PhotoStorageError: Error {
        case bytesEncodingFailed
        case publicURLUnavailable
    }

    // MARK: - Avatars

    // Upload a JPEG-compressed avatar to the `avatars` bucket.
    // Returns the public URL (with a cache-busting query param)
    // for the caller to stamp onto `UserProfile.avatarURL`.
    //
    // Caller is responsible for compressing first — `EditProfileView`
    // already does this via `compressedAvatarJPEG(maxDimension:)`.
    // We don't recompress here because the bytes might come from
    // an avatar already cached on disk, and double-compression
    // accumulates artifacts.
    static func uploadAvatar(
        data: Data,
        userID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws -> String {
        let path = "\(userID)/profile.jpg"

        // `upsert: true` so the second-and-onward upload replaces
        // the existing object at the same path. Without this the
        // SDK throws on a re-upload because the object already
        // exists.
        let options = FileOptions(
            contentType: "image/jpeg",
            upsert: true
        )

        try await client.storage
            .from("avatars")
            .upload(
                path,
                data: data,
                options: options
            )

        // Resolve the public URL from the SDK rather than
        // hardcoding a string — keeps us robust to future
        // base-URL changes (custom domain, region migration).
        let publicURL = try client.storage
            .from("avatars")
            .getPublicURL(path: path)

        // Cache-bust on every upload. A consumer (this device,
        // a paired device, the future web view) sees a fresh
        // URL string and refetches; the underlying object is
        // the same.
        let busted = appendCacheBuster(to: publicURL)
        return busted.absoluteString
    }

    // MARK: - Race photos

    // Upload a JPEG-compressed race photo to the `race-photos`
    // bucket at `{userID}/{raceID}.jpg`. Same upsert + cache-bust
    // pattern as `uploadAvatar`. The folder-per-user structure
    // pairs with the storage RLS policy that gates writes to
    // `(storage.foldername(name))[1] = auth.uid()::text`.
    //
    // Compression is the caller's responsibility — RacePhotoSection
    // already runs a 1280pt-longest-edge JPEG re-encode at 0.7
    // quality before this point.
    static func uploadRacePhoto(
        data: Data,
        userID: String,
        raceID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws -> String {
        let path = "\(userID)/\(raceID).jpg"

        let options = FileOptions(
            contentType: "image/jpeg",
            upsert: true
        )

        try await client.storage
            .from("race-photos")
            .upload(
                path,
                data: data,
                options: options
            )

        let publicURL = try client.storage
            .from("race-photos")
            .getPublicURL(path: path)

        return appendCacheBuster(to: publicURL).absoluteString
    }

    // MARK: - Free Run photos

    // Mirrors `uploadRacePhoto` for the `free-run-photos` bucket.
    // Wired now so `FreeRunSyncService` can round-trip URLs even
    // before the FreeRun photo picker UI ships — when the picker
    // arrives it just calls this helper, no further plumbing.
    static func uploadFreeRunPhoto(
        data: Data,
        userID: String,
        runID: String,
        client: SupabaseClient = SupabaseService.shared
    ) async throws -> String {
        let path = "\(userID)/\(runID).jpg"

        let options = FileOptions(
            contentType: "image/jpeg",
            upsert: true
        )

        try await client.storage
            .from("free-run-photos")
            .upload(
                path,
                data: data,
                options: options
            )

        let publicURL = try client.storage
            .from("free-run-photos")
            .getPublicURL(path: path)

        return appendCacheBuster(to: publicURL).absoluteString
    }

    // MARK: - Helpers

    // Append `?t={epochMs}` (or extend an existing query string)
    // to bust HTTP / AsyncImage caches when the file at a stable
    // path is overwritten.
    private static func appendCacheBuster(to url: URL) -> URL {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return url
        }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "t", value: stamp))
        components.queryItems = items
        return components.url ?? url
    }
}

#else

// Non-Supabase build (preview / macOS / unit-test targets that
// don't link the SDK). Stub so call sites compile without a
// pile of #if guards.
@MainActor
enum PhotoStorageService {
    enum PhotoStorageError: Error {
        case bytesEncodingFailed
        case publicURLUnavailable
    }

    static func uploadAvatar(
        data: Data,
        userID: String
    ) async throws -> String {
        throw PhotoStorageError.publicURLUnavailable
    }

    static func uploadRacePhoto(
        data: Data,
        userID: String,
        raceID: String
    ) async throws -> String {
        throw PhotoStorageError.publicURLUnavailable
    }

    static func uploadFreeRunPhoto(
        data: Data,
        userID: String,
        runID: String
    ) async throws -> String {
        throw PhotoStorageError.publicURLUnavailable
    }
}

#endif
