import Foundation
import AuthenticationServices
import CryptoKit
import Supabase
// `Auth` is a submodule of supabase-swift. The umbrella `Supabase`
// import re-exports the types but Swift's "implicit member access"
// rule still requires explicit imports of the *defining* module
// for property reads like `user.id`. Without this, the compiler
// errors with "Property 'id' is not available due to missing
// import of defining module 'Auth'."
import Auth

#if canImport(UIKit)

// Authentication state holder + Sign-in-with-Apple → Supabase bridge.
//
// Owns the entire auth lifecycle:
//   • Tracks the signed-in `User` (Supabase user object) as observable
//     state. Views that depend on auth state read this directly.
//   • Generates the cryptographic nonce required by Sign in with Apple
//     and forwards the resulting Apple identity token to Supabase via
//     `signInWithIdToken(provider: .apple, ...)`.
//   • Restores any previous session on app launch — Supabase persists
//     the session token in UserDefaults under the hood, so a returning
//     user is signed in automatically without a network round-trip.
//
// The Sign in with Apple flow has a specific cryptographic dance that's
// easy to get wrong. The contract:
//   1. Generate a random nonce string client-side.
//   2. SHA-256 hash it.
//   3. Pass the HASH as `request.nonce` on the Apple authorization
//      request.
//   4. Apple includes that hash as a claim in the identity token it
//      returns.
//   5. Send the token + the original RAW (un-hashed) nonce to Supabase.
//   6. Supabase verifies the token's signature against Apple's public
//      keys AND verifies the hash claim matches the raw nonce — proving
//      this auth flow actually came from THIS device, not a replay.
//
// `currentNonce` is held on the actor between the request and the
// authorization callback because the closures fire at different
// times and need to share the secret.
//
// `@Observable` macro (iOS 17+) gives SwiftUI views automatic
// re-rendering when `user` changes. No `@Published` boilerplate, no
// `ObservableObject` conformance.
@Observable
@MainActor
final class AuthService: NSObject {

    static let shared = AuthService()

    // The signed-in user, or nil when not authenticated. Views that
    // depend on auth state should read this — `HyroxappApp` checks
    // it to decide whether to render `ContentView` or `SignInView`.
    private(set) var user: User?

    // True while a sign-in flow is mid-flight. Drives a loading
    // indicator on the sign-in button so the user knows their tap
    // registered.
    private(set) var isAuthenticating = false

    // The nonce currently in flight — held between request creation
    // and credential receipt. Cleared after the token exchange so
    // a stale nonce can't be reused on a future sign-in attempt.
    private var currentNonce: String?

    private override init() {
        super.init()
    }

    // MARK: - Session restoration

    // Called on app launch from `HyroxappApp.init`. Asks Supabase for
    // the persisted session — if one exists, populates `user` so the
    // app skips the sign-in screen entirely. Returns silently when
    // no session is cached (first launch / signed out).
    //
    // Wrapped in a Task because `auth.session` is async; the caller
    // doesn't need to wait. The signed-in state lands within ~50ms
    // of launch on a warm cache.
    func restoreSession() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await SupabaseService.shared.auth.session
                self.user = session.user
            } catch {
                // No session cached, or session refresh failed.
                // Either way, leave `user` nil — the app will
                // render the sign-in screen.
                self.user = nil
            }
        }
    }

    // MARK: - Sign in with Apple

    // Prepares the Apple authorization request. Called from
    // `SignInWithAppleButton`'s `.onRequest` closure. Generates a
    // fresh nonce, stores the raw value for the verify step, sets
    // the SHA-256 hash on the request.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)
    }

    // Handles the Apple authorization result. Called from
    // `SignInWithAppleButton`'s `.onCompletion` closure. Extracts
    // the identity token, sends it + the raw nonce to Supabase,
    // updates `user` on success.
    //
    // Failures land silently in `isAuthenticating = false` —
    // Apple's authorization framework already shows error UI for
    // user-cancelled flows, and we don't want to layer our own
    // error sheet on top of that. A future enhancement could
    // surface "couldn't reach Supabase" specifically since that's
    // a different failure mode than user cancellation.
    func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = appleIDCredential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8),
                let nonce = currentNonce
            else {
                isAuthenticating = false
                return
            }

            isAuthenticating = true
            Task { @MainActor in
                do {
                    let session = try await SupabaseService.shared.auth.signInWithIdToken(
                        credentials: .init(
                            provider: .apple,
                            idToken: identityToken,
                            nonce: nonce
                        )
                    )
                    self.user = session.user
                    self.currentNonce = nil
                } catch {
                    // Token exchange failed — likely a network
                    // error or a Supabase config issue. Reset the
                    // nonce so the next attempt generates a fresh
                    // one.
                    self.currentNonce = nil
                }
                self.isAuthenticating = false
            }

        case .failure:
            // User cancelled or Apple flow errored. No-op; the
            // sign-in button stays available for another attempt.
            isAuthenticating = false
        }
    }

    // MARK: - Sign out

    // Clear the Supabase session AND the local auth state. The
    // app's auth gate flips back to the sign-in screen.
    func signOut() {
        Task { @MainActor in
            try? await SupabaseService.shared.auth.signOut()
            self.user = nil
        }
    }

    // MARK: - Account deletion (§15A/B)

    // Self-service account deletion via the Supabase
    // `delete_user_account` RPC. The RPC cascades through
    // follows / duo_races / races / race-photos / avatars /
    // profile / auth.users — see docs/supabase/delete_user_account.sql
    // for the full SQL definition.
    //
    // App Store Guideline 5.1.1(v) requires apps with account
    // creation to support in-app deletion. This is the direct
    // one-tap path; the previous mailto: flow on
    // SettingsView.requestAccountDeletion remains as a v0
    // fallback for any case where the RPC errors.
    //
    // After the RPC succeeds, we sign out locally so the auth
    // gate flips back to the sign-in screen. The session token
    // is invalidated server-side by the auth.users delete, so
    // future requests with the old token would fail anyway —
    // calling signOut() is belt-and-suspenders for clean state.
    //
    // Throws on RPC failure (network, RLS rejection, missing
    // function, etc.) so the caller can surface an error. Does
    // NOT swallow errors — partial-success on the server is
    // worse than a clear failure the user can retry.
    @discardableResult
    func deleteAccount() async throws -> Bool {
        // Belt-and-suspenders: refuse when not signed in. The
        // server-side RPC would reject too (auth.uid() IS NULL
        // → exception) but failing fast here gives a clearer
        // error message.
        guard user != nil else {
            throw NSError(
                domain: "AuthService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Sign in before deleting your account."]
            )
        }

        // Invoke the RPC. supabase-swift's .rpc(name) returns
        // a query builder; .execute() runs it and surfaces any
        // server-side error as a thrown PostgrestError.
        try await SupabaseService.shared
            .rpc("delete_user_account")
            .execute()

        // RPC succeeded — the user is server-side-deleted.
        // Tear down local auth state on the main actor. signOut()
        // already hops to MainActor internally; await ensures we
        // don't return before local state is cleared.
        await MainActor.run {
            self.user = nil
        }
        // Best-effort server-side sign out — the session token
        // is already dead (auth.users row is gone) but calling
        // signOut() cleanly clears any cached Supabase state on
        // the client. Errors swallowed because the account is
        // gone either way.
        try? await SupabaseService.shared.auth.signOut()

        return true
    }

    // MARK: - Nonce helpers

    // Apple's recommended random nonce: 32 chars from a fixed
    // alphabet, generated via SecRandomCopyBytes. Deterministic
    // length + URL-safe charset is what Apple's docs specify.
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var byte: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
                if status != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
                }
                return byte
            }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    // SHA-256 hex string. Apple's request.nonce expects the hash
    // as hex; the verify step on Supabase expects the same raw
    // nonce that was hashed here.
    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

#endif
