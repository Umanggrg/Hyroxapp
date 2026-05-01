# TestFlight Submission Checklist

A working checklist for the first TestFlight upload, ordered by when each step matters. Don't run through this sequentially the moment activation lands — instead, keep it open while uploading and tick items as you confirm them.

The codebase already covers most of these. Items marked **(verified)** have been audited and are correct as of the v1.0 build. Items marked **(action)** require you to do something post-activation.

---

## A. Activation prerequisites

- [ ] **(action)** Apple Developer Program activation email received
- [ ] **(action)** Sign in to [developer.apple.com](https://developer.apple.com), accept the latest **Program License Agreement**. App Store Connect refuses uploads until you accept.
- [ ] **(action)** Open Xcode → Settings → Accounts → confirm your Apple ID team now shows as **paid** (not personal/free).
- [ ] **(action)** Project's Signing & Capabilities tab — both Trakrr and TrakrrWatch targets show "Automatically manage signing" with the paid team selected.

## B. Build settings sanity

- [x] **(verified)** Bundle ID = `com.praanshuadiga.trakr` (Debug + Release)
- [x] **(verified)** `MARKETING_VERSION = 1.0`
- [x] **(verified)** `CURRENT_PROJECT_VERSION = 1` (build number — bump for each upload)
- [x] **(verified)** `IPHONEOS_DEPLOYMENT_TARGET = 26.2`
- [x] **(verified)** `INFOPLIST_FILE = Trakrr-Info.plist` (single source of truth)
- [x] **(verified)** `GENERATE_INFOPLIST_FILE = NO` (no double-processing)

## C. Info.plist completeness

- [x] **(verified)** `ITSAppUsesNonExemptEncryption = false` — skips the encryption export compliance prompt
- [x] **(verified)** `NSHealthShareUsageDescription` — required for HealthKit reads
- [x] **(verified)** `NSHealthUpdateUsageDescription` — required for HealthKit writes (race → workout)
- [x] **(verified)** `NSPhotoLibraryUsageDescription` — required for photo picker / race photo attach
- [x] **(verified)** `NSLocalNetworkUsageDescription` + `NSBonjourServices` — required for Multipeer Duo
- [x] **(verified)** `NSSupportsLiveActivities = YES`
- [x] **(verified)** `UISupportedInterfaceOrientations` set
- [x] **(verified)** `UILaunchScreen` defined (empty dict = system default)

## D. Privacy

- [x] **(verified)** `Trakrr/PrivacyInfo.xcprivacy` — privacy manifest declaring no tracking, no collected data, no required-reason API use. Required for all App Store submissions since Spring 2024.
- [x] **(verified)** `TrakrrWatch Watch App/PrivacyInfo.xcprivacy` — same shape for the Watch target
- [x] **(verified)** `docs/PRIVACY.md` — full privacy policy text drafted
- [ ] **(action)** Host the privacy policy at a public URL (GitHub Pages, Netlify, your own site). App Store Connect requires a Privacy Policy URL; TestFlight external testing may also require one. The drafted text in `docs/PRIVACY.md` is ready — just needs hosting.

## E. Entitlements

- [x] **(verified)** HealthKit entitlement (`com.apple.developer.healthkit`)
- [x] **(verified)** No App Groups, no Push Notifications, no iCloud, no Sign in with Apple — none needed for v1
- [x] **(verified)** No background modes — race tracking runs only while the app is foregrounded; this is intentional

## F. Assets

- [x] **(verified)** `AppIcon.appiconset` — 1024×1024 master with Light / Dark / Tinted variants. iOS 18 generates all required sizes.
- [x] **(verified)** Watch app icon present
- [x] **(verified)** Accent color set in Asset Catalog
- [x] **(verified)** Launch screen renders (configured via Info.plist `UILaunchScreen`)

## G. Schema + data integrity

- [x] **(verified)** `ModelContainer` registers all `@Model` types: `Race`, `UserProfile`, `WorkoutTemplate`, `RaceEvent`, `Challenge`
- [x] **(verified)** Every recent additive field uses default values (Optional or empty default) so existing rows decode cleanly. SwiftData migrations are fragile beyond additive changes — kept the schema growing forward.
- [x] **(verified)** `SchemaMigrationTests` covers the additive-field decode path

## H. Content review (App Review will check these)

- [x] **(verified)** No medical claims — readiness/recovery framed as "coaching guidance," not diagnostic
- [x] **(verified)** No third-party tracking SDKs, no analytics, no IDFA
- [x] **(verified)** No subscription / IAP — submitted as free with no paywalls
- [x] **(verified)** No user-generated content moderation requirements (notes/photos stay local; no social feed yet)
- [x] **(verified)** No login wall blocking core functionality on first launch (onboarding writes locally, no account required)

## I. Pre-upload steps

1. **(action)** Open Xcode → Product → Clean Build Folder (⇧⌘K)
2. **(action)** Set destination dropdown to "Any iOS Device (arm64)"
3. **(action)** Product → Archive — should take 2–5 minutes for both targets
4. **(action)** When Organizer opens, click "Distribute App" → "App Store Connect" → "Upload"
5. **(action)** Apple processes the build for ~5–15 minutes — watch email + App Store Connect → TestFlight tab

## J. App Store Connect setup

1. **(action)** appstoreconnect.apple.com → My Apps → "+" → New App
   - iOS platform
   - Name: "Trakrr" (or your preferred display name — can change later)
   - Bundle ID dropdown: select `com.praanshuadiga.trakr`
   - SKU: `hyroxapp-001` (anything memorable; never shown publicly)
   - Primary language: English (U.S.)
   - User access: Full Access
2. **(action)** Once the build appears under TestFlight tab, click into it
3. **(action)** Fill out the **Test Information** form:
   - Beta App Description (~250 chars): see suggested copy below
   - What to Test (each upload): see suggested copy below
   - Email + login (your contact for tester questions)
   - Privacy Policy URL (the one you hosted in step D)

## K. Suggested test invite copy

**Beta App Description:**
> Trakrr is a hybrid-fitness training companion. Race a HYROX-style 16-station format, custom workouts, or your own intervals. Track your races station-by-station with live heart rate, recovery insights, and per-station personal bests. Built for the gym, not the road — no GPS, indoor-first.

**What to Test (first build):**
> First TestFlight build. Things to try:
> 1. Run through a full HYROX simulation in Race Mode — does the timer stay accurate, do splits capture, does the summary feel useful?
> 2. Open History → tap a race → drill into any station for the per-station detail
> 3. Profile tab — readiness banner, charts, badges
> 4. Settings → Appearance — toggle Light / Dark / System
> 5. Anything that feels janky, weird, or broken — let me know via the TestFlight feedback button.

## L. Adding internal testers

1. **(action)** App Store Connect → Users and Access → "+" → add tester's Apple ID email + role (Developer or App Manager works)
2. **(action)** TestFlight tab → Internal Testing → "+" → create group "Friends"
3. **(action)** Add the tester to the group + add the build
4. **(action)** Tester gets an email; installs **TestFlight** from the App Store (free, official Apple app); accepts invite; build downloads over the air

Internal testing is instant — no review delay. Up to 100 testers. Internal testers must be added as users on your App Store Connect account first.

## M. Adding external testers (later)

Skip until needed. External testing requires:
- Beta App Review (~1 day for first build, faster for follow-up builds)
- Privacy Policy URL (mandatory)
- A "Why are you testing this" submission to Apple

For "me + a few friends," internal is what you want. External is for opening the beta wider.

## N. Ongoing — for every subsequent upload

1. Bump `CURRENT_PROJECT_VERSION` (build number) — Apple rejects uploads with the same build number as a prior one
2. (Optionally) bump `MARKETING_VERSION` for milestone releases
3. Archive + Distribute as before
4. Update "What to Test" with what changed in this build

---

## Honest caveats

- The first archive + upload is the slowest. Expect to spend ~30 min the first time fighting any signing or build-setting hiccups. Subsequent uploads take 5 min total.
- Apple's beta review for external testing is unpredictable — sometimes 4 hours, sometimes 2 days. Don't promise external testers a date.
- TestFlight builds expire after **90 days**. Plan to re-upload at least every couple of months even if no changes shipped.
- If a tester sees "could not download" — almost always a TestFlight app expiration or an Apple ID mismatch between the invite email and the TestFlight account. Have them confirm they're signed into TestFlight with the same Apple ID the invite went to.
