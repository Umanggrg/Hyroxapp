# Hyroxapp Privacy Policy

**Last updated:** April 25, 2026
**Effective date:** April 25, 2026

This is a plain-English privacy policy. The short version: **Hyroxapp stores your training data on your device. It does not collect, transmit, sell, or share your data with anyone.** The longer version follows.

If anything in this document is unclear, email **umang.gurung35@gmail.com** and we'll fix it.

---

## 1. Who runs this app

Hyroxapp is built and maintained by Umang Gurung (the "developer," "we," or "us"). It is a personal project, not a company, and does not operate any servers, accounts, or back-end services at this time.

## 2. What data Hyroxapp uses

Hyroxapp is a fitness companion for HYROX athletes. To do its job, it works with the following kinds of information — all of which stay on your device unless you explicitly export or share them:

- **Race data you create.** Splits, total times, station-level reps and weights, race-day notes, race photos, custom workout templates, target finish times, race-event countdowns. Saved locally via SwiftData.
- **Profile data you enter.** Display name, handle, location, bio, division (Men's Open / Women's Open / etc.), max heart rate, avatar photo. All saved locally.
- **HealthKit data you allow.** When you grant access, Hyroxapp reads your heart rate (during a race and as per-station summary statistics) and your active-energy-burned (calorie estimate per station). Apple HealthKit governs that access; you can revoke it at any time in **Settings → Privacy & Security → Health → Hyroxapp**.
- **Photos you attach.** When you add a photo to a race, Hyroxapp uses the iOS PhotosPicker to receive that single photo. The photo is stored alongside the race in local storage. We do not access any other photos in your library.
- **App preferences.** Toggles for voice cues, countdowns, notifications, Roxzone (transition) tracking, etc.

We do **not** collect or store: your real name (unless you type it as your display name), email address, phone number, location coordinates, IP address, device identifiers, advertising IDs, or browsing activity inside other apps.

## 3. What we do *not* do

- We do not run analytics. There is no Firebase, Mixpanel, Amplitude, App Store Connect Analytics opt-in, or equivalent SDK in the app.
- We do not run crash reporting other than what Apple's standard `MetricKit` exposes anonymously to the App Store dashboard, and only if you have opted in to share crash data with developers in iOS settings.
- We do not show advertising and do not integrate with any ad networks.
- We do not sell, rent, or otherwise transfer any of your data to third parties.
- We do not track you across other apps or websites.

## 4. HealthKit specifics

Apple's HealthKit framework requires a special privacy disclosure. Per Apple's developer policy:

- Hyroxapp uses HealthKit **only** to support the features in §2 (read your heart rate and active-energy-burned values, and write completed races back to Health as workouts so they appear alongside your other Apple Fitness data).
- Hyroxapp does **not** use HealthKit data for advertising, marketing, or other use-based data mining.
- Hyroxapp does **not** disclose HealthKit data to any third party.
- HealthKit data never leaves your device.

You can revoke HealthKit permissions at any time in **iOS Settings → Privacy & Security → Health → Hyroxapp**. The app continues to work without HealthKit; heart rate / calorie fields simply remain blank for new races.

## 5. Live Activities and notifications

If you enable Live Activities, the active race timer can render on your Lock Screen and in the Dynamic Island via Apple's standard ActivityKit. The data shown there (race timer, current station) is delivered locally on your device — no remote server is involved.

If you enable notifications, Hyroxapp uses Apple's local notification system to remind you about training streaks and upcoming race events. These notifications are scheduled on-device. We do **not** send push notifications from any server.

## 6. Sharing and exporting

Some screens (the post-race summary, monthly/yearly recaps, profile) offer a "Share" button that renders a portable PNG image of your data. When you tap that button, you control where the image goes — it is handed off to iOS's standard share sheet. Hyroxapp does not transmit a copy elsewhere.

## 7. Where your data lives

Right now, on your iPhone (and your paired Apple Watch, when you opt in to the Watch companion). Specifically:

- SwiftData store inside the app's sandbox container.
- Apple Health (only the workouts you let Hyroxapp write back).
- Standard iOS application backups via iCloud / Finder, which are encrypted by Apple and managed under Apple's own privacy terms.

If you delete the app, the local database goes with it. Any workouts already written to Apple Health remain in Apple Health under your control.

## 8. Future cloud sync

A future version of Hyroxapp will offer optional cloud sync (planned via Supabase) so the same account can be used across multiple devices and to support social features. **That capability is not active in the current version.** When it ships, this document will be updated to spell out exactly what gets synced, where it is stored, the legal basis, and how you can delete it. You will be asked to opt in before any data leaves your device.

## 9. Children

Hyroxapp is not directed to children under 13 (or the equivalent minimum age in your jurisdiction). If you are a parent or guardian and believe a child has used the app, you can simply uninstall it; no remote data exists to be deleted.

## 10. Your rights

Because Hyroxapp does not transmit your data anywhere, the practical mechanism for exercising rights like access, deletion, or portability is the iOS device itself:

- **Access / portability.** The Settings screen exposes data export options for your race history.
- **Deletion.** You can delete individual races from the History screen, or delete the entire app from your home screen to wipe the local database.
- **Withdrawal of HealthKit consent.** See §4.

If a future cloud-sync version is released, additional access/deletion mechanisms will be added at that time.

## 11. Security

Hyroxapp relies on the security guarantees of iOS — sandboxed file storage, Data Protection class encryption when the device is locked, secure enclave for biometrics. We do not attempt to bypass or weaken these protections.

No system is perfectly secure, and we make no guarantee of absolute security. If you become aware of a security issue affecting Hyroxapp, please email **umang.gurung35@gmail.com**.

## 12. Changes to this policy

If material changes are made — for example, when cloud sync ships — this document will be updated and the "Last updated" date at the top will change. Continued use of the app after the change indicates acceptance of the updated policy.

## 13. Contact

Questions, requests, or concerns about this privacy policy:

**Umang Gurung**
Email: umang.gurung35@gmail.com
