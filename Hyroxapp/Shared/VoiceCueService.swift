import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

// Spoken voice cues fired on station transitions during an active race.
//
// Wraps `AVSpeechSynthesizer` so views and view models can call
// `VoiceCueService.shared.announceNextStation(...)` without thinking
// about audio session config or speech queue management. Idempotent
// `stop()` cancels any pending utterance — used on race finish /
// abandon / view-disappear so a stale "next: sled push" doesn't
// fire after the user already left the race screen.
//
// AVAudioSession is configured with `.playback` + `.mixWithOthers`
// so the cue plays over the user's existing audio (Spotify, Apple
// Music, podcast) rather than ducking or stopping it. Athletes train
// with music; voice cues should layer on top, not interrupt.
//
// iOS-only via `canImport(AVFoundation)`. The class no-ops on
// platforms without speech support so caller code doesn't need
// platform guards at every call site.
final class VoiceCueService {

    static let shared = VoiceCueService()

    #if canImport(AVFoundation)
    // The synthesizer is a long-lived object — reuse one instance
    // for the whole app lifetime. AVSpeechSynthesizer queues
    // utterances internally so back-to-back calls (e.g. rapid
    // station advances) don't drop announcements.
    private let synthesizer = AVSpeechSynthesizer()
    #endif

    // Did we configure the AVAudioSession yet? Doing it lazily on
    // first announcement avoids touching the audio system at app
    // launch when the user might not even be racing.
    private var configuredAudioSession = false

    private init() {}

    // MARK: - Public API

    // Announce the next station coming up. Speaks "Next: Sled Push"
    // (or whatever the station's display name is). Skips silently if
    // speech is unsupported on this platform.
    func announceNextStation(_ station: Station) {
        speak("Next: \(station.displayName)")
    }

    // Spoken when the athlete completes the final station.
    // Distinct from advance announcements so the brain registers
    // "race is over" without ambiguity.
    func announceFinish() {
        speak("Race complete")
    }

    // Cancel any pending utterance immediately. Used when the user
    // leaves the race screen mid-announcement, abandons a race, or
    // toggles the cue setting off mid-race — we don't want a
    // stale announcement firing seconds later.
    func stop() {
        #if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
        #endif
    }

    // MARK: - Internal

    private func speak(_ text: String) {
        #if canImport(AVFoundation)
        configureAudioSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: text)
        // Default rate sounds robotic-fast on AVSpeechSynthesizer;
        // 0.5 (half default) is closer to natural conversational
        // pace and reads well at arm's length.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        // Pitch slightly above default so the voice cuts through
        // music / ambient gym noise without sounding shrill.
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        #endif
    }

    // Configure AVAudioSession to mix with other audio. Without
    // this, speaking would either fail (if no session is active)
    // or duck/stop the user's music. We want our cue to layer on
    // top of whatever else is playing — same pattern Strava and
    // other workout apps use for their voice prompts.
    private func configureAudioSessionIfNeeded() {
        guard !configuredAudioSession else { return }
        #if canImport(AVFoundation) && !os(macOS)
        let session = AVAudioSession.sharedInstance()
        // `.playback` + `.duckOthers` would temporarily lower the
        // user's music while we speak; `.mixWithOthers` is gentler
        // and lets the cue layer in at full volume without changing
        // the music's volume. Strava-style.
        try? session.setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.mixWithOthers, .duckOthers]
        )
        try? session.setActive(true, options: [])
        configuredAudioSession = true
        #endif
    }
}
