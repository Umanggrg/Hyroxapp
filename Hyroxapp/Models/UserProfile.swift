import Foundation
import SwiftData

// The single user of this v0.1 / v1 build.
//
// Stored as a SwiftData `@Model` so profile edits persist across launches
// alongside `Race` rows. The convention in v1 is "there is exactly one
// `UserProfile` row" — the ProfileView bootstraps a default on first launch
// and never inserts another. When Supabase auth lands later, this same
// model gains an optional `remoteUserID: UUID?` tying it to the cloud
// account; migration is a single additive field.
//
// Avatar is stored as raw `Data` (JPEG, ~0.7 quality). For v1 this is
// bounded by however large the user's picker choice is — we compress on
// save. When cloud sync ships, avatars move to Supabase Storage and the
// field becomes a URL; the on-device copy stays as a cache.
@Model
final class UserProfile {

    // Stable identity, for pairing with a future remote account row.
    var id: UUID

    // Supabase user UUID, populated after the athlete signs in with
    // Apple. Optional + nil-default keeps SwiftData migration
    // additive-safe — existing rows from before auth shipped decode
    // cleanly. The `auth.users` table in Supabase is keyed by this
    // UUID; future cloud-sync code uses it to attribute a profile /
    // race / run to the right account.
    //
    // Stored as String (not UUID) because Supabase's user IDs are
    // returned as String from the auth response and there's no
    // reason to round-trip them through a UUID parse. SwiftData
    // handles String fields without ceremony.
    var remoteUserID: String?

    // Public URL of the avatar in Supabase Storage. Set after a
    // successful upload to the `avatars` bucket; nil for athletes
    // who haven't uploaded one. Mutually compatible with the
    // existing `avatarData` byte buffer:
    //   • avatarData (bytes) — local-only display path. Picked
    //     immediately on import; stays as a cache so the header
    //     view doesn't need to wait on the network for a freshly
    //     uploaded photo.
    //   • avatarURL (URL) — cloud authoritative copy. Synced via
    //     the profiles table, fetched via AsyncImage on devices
    //     that don't have the local bytes (e.g. signed in on a
    //     new phone).
    //
    // Display order: prefer avatarData when present (zero-latency
    // render), fall back to AsyncImage(URL: avatarURL) when not.
    // Pull-from-remote sets avatarURL but leaves avatarData nil;
    // the next render fetches the bytes.
    var avatarURL: String?

    var displayName: String
    var handle: String
    var location: String
    var bio: String

    // Wireframe §05.2 — home gym free-form text. Surfaces on
    // the profile page (next to division pill) and powers
    // per-race "where I trained" auto-fill on Edit Notes.
    // Lightweight migration: default empty string for old rows.
    var homeGym: String = ""

    // Compressed JPEG of the chosen avatar. `nil` means "show the default
    // SF Symbol fallback". Kept as Data rather than filesystem path so the
    // whole profile travels with the model (and later syncs) as one unit.
    var avatarData: Data?

    // Competitive HYROX division. Determines the wall ball rep count in
    // the race screen and (eventually) sled / sandbag weight defaults.
    //
    // Stored as Optional<Division> on purpose: SwiftData's lightweight
    // migration doesn't reliably populate a new non-optional field on
    // pre-existing rows (observed crash:
    //   "Could not cast value of type 'Swift.Optional<Any>' to 'Division'"
    // on `UserProfile.division.getter`). Optional-plus-default is the
    // robust pattern — existing rows load as `nil`, the `resolvedDivision`
    // computed property below gives every caller a non-optional value.
    //
    // Always read / write via `resolvedDivision`, never this property
    // directly, so the fallback default is consistently applied.
    //
    // Default value written as `Division.mensOpen` (fully qualified) —
    // not `.mensOpen` — because SwiftData's `@Model` macro expansion
    // can't infer the type from the optional declaration context.
    var division: Division? = Division.mensOpen

    // Non-optional accessor with a safe fallback. Views and view models
    // should use this — it insulates them from the stored optional and
    // ensures a consistent default (`.mensOpen`) when the field is nil
    // (freshly migrated rows from before the division field existed).
    var resolvedDivision: Division {
        get { division ?? .mensOpen }
        set { division = newValue }
    }

    // Whether to fire voice cues ("Next: Sled Push") on station
    // transitions during a race. On by default — verbal announcement
    // is the primary value-add for athletes mid-workout who can't
    // glance at the screen. Off for users who train with music or
    // podcasts and don't want spoken interruptions.
    //
    // Bool with a default value is migration-safe out of the box for
    // SwiftData lightweight migration — existing rows pick up `true`
    // on next read.
    var audioCuesEnabled: Bool = true

    // Whether the race screen plays a 3-2-1-GO countdown before
    // the timer actually starts. On by default — gives the
    // athlete a moment to drop the phone, take a breath, and
    // start the race deliberately rather than the timer
    // ticking the instant they tap "Start Race." Off for users
    // who'd rather just begin instantly. Migration-safe via
    // SwiftData default-value lightweight migration.
    var countdownEnabled: Bool = true

    // Master toggle for local notifications (today: only the
    // streak-protection reminder; future: weekly digest, race
    // anniversaries, etc.). Off by default — opt-in respects the
    // user's "don't ping me unless I asked" baseline. Permission
    // is requested contextually when the user first flips this
    // on in Settings, not on launch.
    var notificationsEnabled: Bool = false

    // Roxzone tracking — captures the transition time between
    // segment-end and next-segment-start as a separate metric.
    // Off by default because it's an advanced HYROX-specific
    // feature: changes the in-race advance flow from one-tap to
    // two-tap (end segment → enter roxzone → start next).
    // Athletes who care about transition discipline turn it on;
    // athletes who don't, never know it exists.
    //
    // The metric the HYROX community calls "Roxzone time" — the
    // total time spent in transition, separate from work time.
    // No other fitness app surfaces this.
    var roxzoneEnabled: Bool = false

    // Maximum heart rate (bpm) used to classify HR zones on race
    // detail. Default 190 is a reasonable starting point for most
    // HYROX-age athletes; the "220 minus age" rule-of-thumb gives
    // a per-user value that the athlete can dial in via Settings.
    //
    // Stored as Int because a fractional max HR is meaningless
    // (HealthKit reports per-second integer bpm samples). Default
    // makes this migration-safe for existing rows.
    var maxHeartRate: Int = 190

    // First-launch onboarding completion flag. False on a fresh
    // install (and on rows from before the wizard shipped, via
    // SwiftData's default-value lightweight migration), true once
    // the athlete has walked through the wizard. Drives the
    // wizard sheet on app entry — `bootstrapIfNeeded` creates a
    // default profile on first run, the wizard then walks the user
    // through populating it before they touch the rest of the app.
    var hasCompletedOnboarding: Bool = false

    // Theme preference — drives `.preferredColorScheme(...)` at the
    // root of the app. Stored as Optional<String> for the same
    // SwiftData migration reason as `division` (lightweight
    // migration is unreliable for non-optional new fields on
    // pre-existing rows). The `resolvedThemePreference` property
    // gives every caller a non-optional `ThemePreference` value;
    // the default `.system` follows iOS's mode setting and is the
    // expected behavior for users upgrading from a pre-light-mode
    // build.
    var themePreferenceRaw: String? = ThemePreference.system.rawValue

    var resolvedThemePreference: ThemePreference {
        get {
            guard let raw = themePreferenceRaw,
                  let pref = ThemePreference(rawValue: raw)
            else { return .system }
            return pref
        }
        set { themePreferenceRaw = newValue.rawValue }
    }

    // The marketing version (CFBundleShortVersionString) the user
    // last saw the What's New sheet for. Drives the per-version
    // gating: ContentView shows the sheet on first launch after
    // the app's version bumps past whatever's stored here. After
    // dismiss, ContentView writes the current version back so the
    // sheet doesn't re-appear until the next bump.
    //
    // Optional + nil default keeps SwiftData migration safe for
    // existing rows. Existing users see the sheet exactly once on
    // their first launch after this field ships.
    var lastSeenWhatsNewVersion: String?

    // When on, the run segments (run1..run8) wait for an explicit
    // "Start Run" tap before their segment timer begins —
    // mirrors the way Strava lets you stage a run before pressing
    // Go. Lets the athlete pre-position at the start line, take
    // a breath, then deliberately start running.
    //
    // Off by default — most athletes are happy with the
    // continuous-tap-advance flow. Turning it on opt-in via
    // Settings → Race ritual.
    //
    // The in-race UI for this slice ships in a follow-up; this
    // field is added now so the setting persists and the
    // forthcoming UI has something to bind to.
    var manualRunStartEnabled: Bool = false

    // ─── In-race display preferences ──────────────────────────
    //
    // Per-feature toggles for the live race screen. Defaults all
    // ON because dogfooding showed these are the things that
    // actually make the race screen useful. Athletes who find
    // them distracting (or just want a minimalist screen) can
    // turn them off in Settings → In-race displays.
    //
    // All Bool-with-default for SwiftData lightweight migration
    // safety — pre-existing rows pick up `true` cleanly.

    // HR coaching pill (HOLD / SLOW / PUSH / WORK) on the live
    // HR chip mid-race. Mirrors to the Watch via the snapshot.
    // Off → the chip just shows BPM + zone color, no command.
    var coachingCuesEnabled: Bool = true

    // Full-screen coaching banner overlay (wireframe §03.3) that
    // takes over the top of the race screen for 2.5s when the
    // athlete enters a new HR state (HOLD / SLOW / REDLINE /
    // RECOVER / PUSH). Distinct from `coachingCuesEnabled` above:
    // that one controls the always-on inline chip text; this
    // one controls the decisive interrupt-style overlay. The
    // overlay also fires distinct haptic patterns per state.
    // Off → no banner, no haptic. The inline chip continues to
    // reflect state via its color/text.
    var coachingOverlaysEnabled: Bool = true

    // Pace ahead/behind chip in the in-race header. Compares
    // actual elapsed vs naïve split of target finish time.
    // Off → no pace chip at all. Athletes who race by feel
    // rather than by clock benefit from turning this off.
    var paceChipEnabled: Bool = true

    // Predicted finish projection on the in-race screen
    // ("projected H:MM:SS" line). Linear extrapolation of
    // current pace forward. Off → only the elapsed timer
    // shows. Reduces pressure for athletes who don't want
    // a verdict mid-race.
    var predictedFinishEnabled: Bool = true

    // Live Activity (lock screen + Dynamic Island race timer).
    // Off → race runs entirely in-app, nothing on the lock
    // screen. Saves a small amount of battery and reduces
    // notification surface area for users who don't want
    // race state visible when the phone is locked.
    var liveActivityEnabled: Bool = true

    // ─── Privacy ──────────────────────────────────────────────
    //
    // When on, every new race starts with `isPrivate = true`.
    // The athlete can still flip the per-race toggle on the
    // summary screen if they want this race public after all.
    // Forward-compat for v2 social feed: private races stay
    // out of any future public surface automatically.
    var defaultRacePrivate: Bool = false

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String,
        location: String = "",
        bio: String = "",
        avatarData: Data? = nil,
        division: Division? = Division.mensOpen,
        audioCuesEnabled: Bool = true,
        countdownEnabled: Bool = true,
        notificationsEnabled: Bool = false,
        roxzoneEnabled: Bool = false,
        maxHeartRate: Int = 190,
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.location = location
        self.bio = bio
        self.avatarData = avatarData
        self.division = division
        self.audioCuesEnabled = audioCuesEnabled
        self.countdownEnabled = countdownEnabled
        self.notificationsEnabled = notificationsEnabled
        self.roxzoneEnabled = roxzoneEnabled
        self.maxHeartRate = maxHeartRate
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // Convenience for first-launch bootstrapping — values match the
    // placeholders we used in v0.1's hardcoded ProfileHeaderView so the
    // transition is visually seamless for the existing user.
    static func makeDefault() -> UserProfile {
        UserProfile(
            displayName: "Athlete",
            handle: "@athlete",
            location: "",
            bio: "HYROX athlete in training.",
            division: .mensOpen
        )
    }
}
