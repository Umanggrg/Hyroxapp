import SwiftUI
import SwiftData

// First-launch onboarding wizard. Two-step flow matching the v1
// wireframe §01.3 + §01.5 (we skip §01.4 permissions — those fire
// contextually via OS prompts when the user first hits a feature
// that needs them, rather than as a wall of asks during onboarding):
//
//   1. Pick a handle + division     (wireframe 01.3)
//   2. Pick a starting point        (wireframe 01.5, three-card)
//
// Bound to a single `@Bindable` UserProfile so each step writes
// directly to the persisted row — no transient form state to
// reconcile, no risk of "I tapped Done but nothing saved."
//
// Dismissed by setting `profile.hasCompletedOnboarding = true`
// on the final step, which the parent sheet observes to close.
//
// Guarded `#if !os(watchOS)` because UserProfile is iOS-only.
#if !os(watchOS)
struct OnboardingView: View {

    @Bindable var profile: UserProfile

    @Environment(\.dismiss) private var dismiss

    // Needed to insert the optional `RaceEvent` row when the user
    // picks a starting point. Same model + write pattern as the
    // RaceEventEditSheet on Profile.
    @Environment(\.modelContext) private var modelContext

    // Active color scheme — drives shadow + glow scaling so the
    // wizard reads cleanly on both warm off-white (light) and
    // near-black (dark) backgrounds.
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: Step = .identity

    @State private var slideDirection: SlideDirection = .forward

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Handle availability check (live Supabase lookup)
    //
    // The wireframe specifies a live "✓ available" / "taken"
    // affordance on the handle field, with suggestion chips when
    // taken. State lives on the view because it's UI-only — the
    // canonical handle still flows through `profile.handle`.
    //
    // - .idle    — user hasn't typed anything actionable yet
    // - .checking — debounce window still open OR Supabase round-
    //               trip in flight
    // - .available — last check returned "no match" (handle is free)
    // - .taken     — last check returned a match
    // - .invalid   — handle fails basic validation (too short / bad chars)
    @State private var availability: HandleAvailability = .idle
    @State private var availabilityTask: Task<Void, Never>?

    enum HandleAvailability: Equatable {
        case idle
        case checking
        case available
        case taken
        case invalid(String)  // associated reason
    }

    enum SlideDirection {
        case forward
        case backward

        var insertEdge: Edge {
            switch self {
            case .forward:  return .trailing
            case .backward: return .leading
            }
        }

        var removeEdge: Edge {
            switch self {
            case .forward:  return .leading
            case .backward: return .trailing
            }
        }
    }

    // Two-step structure per wireframe (permissions handled at
    // usage time, not as a step). `rawValue` order drives the
    // progress bar and step transitions.
    enum Step: Int, CaseIterable, Identifiable {
        case identity   // handle + division (01.3)
        case starting   // pick a starting point (01.5)

        var id: Int { rawValue }

        // "Step N of 2" prefix shown above the headline. Wireframe
        // uses caps tracking and reads as the orientation cue:
        // "where am I in the flow."
        var stepLabel: String {
            "Step \(rawValue + 1) of \(Step.allCases.count)"
        }

        // Big headline below the step label. Wireframe-canonical
        // copy — short, declarative, period at the end (sentence,
        // not a label).
        var title: String {
            switch self {
            case .identity: return "Pick a handle."
            case .starting: return "Welcome, athlete."
            }
        }

        var subtitle: String {
            switch self {
            case .identity:
                return "This is how other athletes find you."
            case .starting:
                return "Pick a starting point. You can change later."
            }
        }
    }

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar
                    .padding(.top, 24)
                    .padding(.horizontal, Layout.screenMargin)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heroBlock
                        Group {
                            switch step {
                            case .identity: identityStep
                            case .starting: startingStep
                            }
                        }
                    }
                    .padding(Layout.screenMargin)
                    .id(step)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: slideDirection.insertEdge)
                                    .combined(with: .opacity),
                                removal: .move(edge: slideDirection.removeEdge)
                                    .combined(with: .opacity)
                            )
                    )
                }

                Spacer(minLength: 0)

                actionRow
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.bottom, 16)
            }
        }
        .onAppear {
            // Pre-warm the availability state if the user already
            // had a handle stored (e.g. they reopened onboarding
            // via Settings → Reset). Without this they'd see no
            // status indicator on the field until they typed.
            triggerAvailabilityCheck(profile.handle, debounce: false)
        }
        .onChange(of: profile.handle) { _, newValue in
            triggerAvailabilityCheck(newValue)
        }
    }

    // MARK: - Hero block (step label + title + subtitle)
    //
    // Wireframe §01.3/01.5 spec: caps step label, big headline,
    // sub-line. No icon-in-circle hero — that's a Trakrr-only
    // flourish from the previous design; the wireframe is
    // typography-first and reads more like Strava onboarding.

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.stepLabel)
                .font(.caption2.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.textSecondary)

            Text(step.title)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .padding(.top, 4)

            Text(step.subtitle)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Step 1 of 2: identity (handle + division)

    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            handleField

            // Suggestions row — only rendered when the current
            // handle is taken AND we've generated at least one
            // suggestion. Hidden in the available / idle / invalid
            // states so the layout doesn't shift when typing.
            if case .taken = availability {
                handleSuggestionChips
            }

            divisionField
        }
    }

    // Coral-border handle box with `@` prefix and inline status
    // affordance. Wireframe §01.3 spec — the border stays coral
    // while the user is editing (focused), regardless of avail
    // state; the status badge on the right of the row tells the
    // user whether it's available, taken, or being checked.
    private var handleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HANDLE")
                .capsLabelStyle()

            HStack(alignment: .center, spacing: 4) {
                Text("@")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textSecondary)

                TextField("", text: $profile.handle, prompt: Text("yourhandle")
                    .foregroundColor(Color.textTertiary))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Spacer()

                availabilityBadge
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(Color.accent, lineWidth: 1.5)
            )
        }
    }

    // Right-aligned status chip inside the handle row. Five
    // states, all wireframe-prescribed copy where applicable:
    //
    //   • idle      → empty (no chip rendered)
    //   • checking  → small spinner, kept silent — no copy clutter
    //   • available → green "✓ available"
    //   • taken     → coral "taken"
    //   • invalid   → coral with the reason ("too short", "letters only")
    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
        case .available:
            Text("✓ available")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.success)
        case .taken:
            Text("taken")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accent)
        case .invalid(let reason):
            Text(reason)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accent)
        }
    }

    // Suggestion chip ribbon shown when the handle is taken.
    // Generated client-side from the typed handle — appends
    // common HYROX-flavored variants the wireframe shows
    // (@x_runs, @x_hyrox) plus first-letter / number-suffix
    // forms. Tap a chip to copy the suggestion into the field.
    private var handleSuggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try one of these")
                .capsLabelStyle()

            FlowingChipRow(
                items: handleSuggestions(from: profile.handle),
                onTap: { suggestion in
                    profile.handle = suggestion
                    Haptics.impact(.light)
                }
            )
        }
    }

    // Generate suggestion variants. Mirrors the wireframe's set
    // (@sarah_runs / @sarahc / @sarah_hyrox / @s_chen) generalized
    // for any input string.
    private func handleSuggestions(from raw: String) -> [String] {
        let base = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard base.count >= 2 else { return [] }

        let firstLetter = String(base.prefix(1))
        let tail = String(base.dropFirst())

        let candidates = [
            "\(base)_runs",
            "\(base)_hyrox",
            "\(firstLetter)_\(tail)",
            "\(base)\(Int.random(in: 10...99))"
        ]
        return Array(Set(candidates))
            .filter { $0 != base }
            .prefix(4)
            .map { $0 }
    }

    // Division selector — surface card with the current selection
    // and a chevron, taps to open a Menu of all Division cases.
    // Matches the wireframe's "Men's Open ⌄" layout.
    private var divisionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DIVISION")
                .capsLabelStyle()

            Menu {
                ForEach(Division.allCases, id: \.self) { division in
                    Button {
                        profile.resolvedDivision = division
                    } label: {
                        if profile.resolvedDivision == division {
                            Label(division.displayName, systemImage: "checkmark")
                        } else {
                            Text(division.displayName)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(profile.resolvedDivision.displayName)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .fill(Color.surface)
                )
            }
            .buttonStyle(.plain)

            Text("Drives wall ball reps and HR zone math. Change later in Settings.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Step 2 of 2: pick a starting point (3 cards)
    //
    // Wireframe §01.5 — three tap-to-commit cards. Each card
    // writes a different RaceEvent shape (or none) and exits
    // onboarding. The Skip button at the bottom of `actionRow`
    // takes the same path as "Just exploring."

    private var startingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            startingCard(
                kind: .raceTomorrow,
                title: "Race tomorrow →",
                detail: "Anchor your week to an upcoming HYROX event.",
                accent: true
            )
            startingCard(
                kind: .trainForOne,
                title: "Train for one →",
                detail: "Build toward a race months out."
            )
            startingCard(
                kind: .exploring,
                title: "Just exploring →",
                detail: "Drop me straight into the app."
            )
        }
    }

    private enum StartingPoint {
        case raceTomorrow
        case trainForOne
        case exploring

        // Default race date for each starting point. raceTomorrow
        // picks tomorrow; trainForOne picks 8 weeks out (the typical
        // "register today, race in two months" cadence for HYROX
        // events); exploring writes no event.
        var defaultDate: Date? {
            let cal = Calendar.current
            switch self {
            case .raceTomorrow:
                return cal.date(byAdding: .day, value: 1, to: Date())
            case .trainForOne:
                return cal.date(byAdding: .weekOfYear, value: 8, to: Date())
            case .exploring:
                return nil
            }
        }
    }

    // One card in the 3-row stack. `accent: true` adds the coral
    // border the wireframe puts on the top card (visual primary).
    // Tap commits the choice and exits onboarding.
    private func startingCard(
        kind: StartingPoint,
        title: String,
        detail: String,
        accent: Bool = false
    ) -> some View {
        Button {
            commitStartingChoice(kind)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent ? Color.accent : Color.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(accent ? Color.accent.opacity(0.10) : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(accent ? Color.accent : Color.divider,
                            lineWidth: accent ? 1.5 : 1)
            )
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("\(title). \(detail)")
    }

    private func commitStartingChoice(_ choice: StartingPoint) {
        if let date = choice.defaultDate {
            let event = RaceEvent(
                name: "HYROX Race",  // user can rename in Profile
                date: Calendar.current.startOfDay(for: date),
                division: profile.resolvedDivision,
                targetDuration: nil,
                location: ""
            )
            modelContext.insert(event)
        }
        profile.hasCompletedOnboarding = true
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { stepCase in
                let isFilled = stepCase.rawValue <= step.rawValue
                let isCurrent = stepCase == step

                RoundedRectangle(cornerRadius: 2)
                    .fill(isFilled ? Color.accent : Color.surfaceElevated)
                    .frame(height: 4)
                    .shadow(
                        color: isCurrent ? Color.accent.opacity(0.6) : Color.clear,
                        radius: isCurrent ? 6 : 0,
                        x: 0,
                        y: 0
                    )
            }
        }
        .animation(Motion.snappySpring, value: step)
    }

    // MARK: - Action row

    // Step .identity: Continue button only (Back hidden since
    //   it's the first step). Continue is disabled while the
    //   handle is taken / invalid / checking, enabled once
    //   .available or .idle (empty handle is allowed — user
    //   picks one later).
    // Step .starting: Skip button only (cards self-commit via
    //   tap; Skip = same path as "Just exploring").
    private var actionRow: some View {
        HStack(spacing: 12) {
            if step == .identity {
                Button {
                    goNext()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(Color.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .fill(Color.accent.opacity(canContinue ? 1.0 : 0.4))
                        )
                }
                .buttonStyle(.pressableCard)
                .disabled(!canContinue)
            } else {
                Button {
                    commitStartingChoice(.exploring)
                } label: {
                    Text("Skip")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .stroke(Color.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.pressableCard)
            }
        }
        .animation(stepAnimation, value: step)
    }

    // Continue-enable predicate. Permissive on idle (user hasn't
    // committed to a handle yet) since handle is technically
    // optional — the canonical empty value just means "no public
    // profile yet, can set later in Settings." Hard-blocks on
    // taken / invalid because those are bug-prone states to
    // commit.
    private var canContinue: Bool {
        switch availability {
        case .available, .idle:
            return true
        case .taken, .invalid, .checking:
            return false
        }
    }

    private func goNext() {
        if let next = Step(rawValue: step.rawValue + 1) {
            slideDirection = .forward
            withAnimation(stepAnimation) {
                step = next
            }
        }
    }

    private var stepAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.45, dampingFraction: 0.85)
    }

    // MARK: - Handle availability check (debounced Supabase lookup)
    //
    // Called on every keystroke + on initial view appear. Cancels
    // any in-flight task so the user's latest typing wins. A
    // 400ms debounce window keeps Supabase round-trips at-most
    // ~2/sec even under rapid typing, but the very first call
    // (debounce: false) skips the wait so the initial state
    // resolves immediately.

    private func triggerAvailabilityCheck(_ raw: String, debounce: Bool = true) {
        availabilityTask?.cancel()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Empty handle → idle (no badge, Continue still allowed
        // because handle is optional).
        guard !trimmed.isEmpty else {
            availability = .idle
            return
        }

        // Client-side validation gates before we even hit the
        // network. Short / bad-char handles get an inline reason.
        if let reason = validateHandleClientSide(trimmed) {
            availability = .invalid(reason)
            return
        }

        availability = .checking
        availabilityTask = Task { @MainActor in
            if debounce {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
            }
            #if canImport(Supabase)
            let match = await PublicProfileService.lookup(handle: trimmed)
            if Task.isCancelled { return }
            // If the matched profile is the SAME user (e.g. they
            // already set this handle remotely on a prior install),
            // treat as available. Otherwise it's taken.
            // `RemotePublicProfile.id` IS the Supabase user UUID
            // — it's the primary key of the underlying profiles
            // table, exposed through the public view.
            if let match {
                if let remoteID = profile.remoteUserID,
                   match.id == remoteID {
                    availability = .available
                } else {
                    availability = .taken
                }
            } else {
                availability = .available
            }
            #else
            // No Supabase build — fall back to local-only
            // validation (just length / chars). The handle
            // technically can't be "taken" without a remote
            // store, so we trust it.
            availability = .available
            #endif
        }
    }

    private func validateHandleClientSide(_ trimmed: String) -> String? {
        if trimmed.count < 3 {
            return "too short"
        }
        if trimmed.count > 20 {
            return "too long"
        }
        // Allow letters, numbers, underscore — nothing else.
        // Mirrors Twitter / Instagram handle rules; broad enough
        // for HYROX athletes who tend to use existing handles.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "letters, numbers, _"
        }
        return nil
    }
}

// MARK: - Flowing chip row

// Lightweight wrap-aware horizontal layout for suggestion chips.
// SwiftUI's HStack doesn't wrap; this fakes wrapping with a
// vertical stack of horizontal rows. Width-agnostic since we
// don't know the available width at build time — each row fits
// as many chips as fit naturally and overflows to the next.
// Used by the handle-taken suggestion ribbon (wireframe §01.3-err).
struct FlowingChipRow: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        // Simple horizontal scroll fallback rather than true wrap —
        // SwiftUI's true wrap requires GeometryReader gymnastics
        // and our suggestion list is short (max 4). A horizontal
        // ScrollView is plenty for the 4-chip case and degrades
        // gracefully for any future growth.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Button {
                        onTap(item)
                    } label: {
                        Text("@\(item)")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.surface)
                            )
                            .overlay(
                                Capsule().stroke(Color.divider, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
#endif
