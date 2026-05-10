import Foundation
import Supabase

// Singleton Supabase client used across the app. One client instance
// shared by every feature so they all see the same auth session,
// connection pool, and reachability state.
//
// Initialized lazily on first access. Reads URL + anon key from the
// `Secrets` enum (gitignored). The Supabase SDK persists session
// tokens to UserDefaults under the hood, so a returning user is
// auto-signed-in across launches without us writing any keychain
// plumbing — `auth.session` resolves immediately on app launch
// when a previous session exists.
//
// Why a global singleton: every view-model + service that talks to
// the backend needs the same client, and dependency-injecting it
// through every initializer would balloon the call chain for a
// concrete dependency that has zero test surface today. When auth
// flows expand and we want to mock the client in tests, swap this
// for a protocol + injected concrete.
enum SupabaseService {
    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: Secrets.supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }()
}
