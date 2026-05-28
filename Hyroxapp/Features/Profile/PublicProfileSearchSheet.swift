import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// First social-discovery surface — type a name OR handle, see
// matching athletes' public profiles. Drives off
// `PublicProfileService.search(query:)` which does a fuzzy
// `.ilike` across BOTH handle and display_name, so "Sarah"
// matches both @sarahb and the user whose display name is
// "Sarah Brown". On selection, delegates the visual +
// follow-action surface to `PublicProfileCard`.
//
// Four inline states:
//   • idle      — empty input, nothing fetched yet
//   • searching — request in flight (fires on debounced typing)
//   • results   — one or more matching profiles (rendered as a
//                 vertical stack of PublicProfileCards)
//   • notFound  — query returned zero matches
//
// Debounced live search: each keystroke schedules a 300ms
// delayed lookup, cancelled if the user keeps typing. This
// matches the Instagram / Twitter / Strava search affordance —
// no Go button needed.
struct PublicProfileSearchSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var rawInput: String = ""
    @State private var phase: Phase = .idle

    // Tracks the current async search task so a rapid retype
    // cancels the in-flight one before kicking off a new
    // lookup. Without this, two near-simultaneous queries could
    // land their results out of order.
    @State private var searchTask: Task<Void, Never>?

    // Not Equatable — the `.results` associated value
    // ([RemotePublicProfile]) isn't Equatable and synthesizing
    // would require either propagating that conformance or
    // doing a custom comparison. The view doesn't use `==`
    // on Phase anywhere, so we don't need it.
    private enum Phase {
        case idle
        case searching
        case results([RemotePublicProfile])
        case notFound
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        searchField
                        Divider()
                            .background(Color.divider)
                            .padding(.horizontal, Layout.screenMargin)

                        switch phase {
                        case .idle:
                            idleHint
                        case .searching:
                            searchingIndicator
                        case .results(let profiles):
                            // Render each match as its own card.
                            // The `.id(profile.id)` forces a fresh
                            // PublicProfileCard per athlete so the
                            // internal follow-state @State doesn't
                            // bleed from row to row.
                            VStack(spacing: 12) {
                                ForEach(profiles) { profile in
                                    PublicProfileCard(profile: profile)
                                        .id(profile.id)
                                }
                            }
                        case .notFound:
                            notFoundCard
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Find Athlete")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Debounced live search — every typed character
            // schedules a lookup ~300ms later, cancelled if the
            // user keeps typing. Matches the discovery feel of
            // every other social app.
            .onChange(of: rawInput) { _, newValue in
                scheduleSearch(for: newValue)
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .font(.body.weight(.semibold))

            TextField("Name or @handle", text: $rawInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { performSearch() }

            // Clear button when there's text — small affordance
            // so the user doesn't have to backspace through a
            // long query.
            if !rawInput.isEmpty {
                Button {
                    rawInput = ""
                    searchTask?.cancel()
                    phase = .idle
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textTertiary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .padding(.horizontal, Layout.screenMargin)
    }

    // Debounce the in-flight search by a short interval so the
    // backend doesn't get hammered on every keystroke. Cancel
    // any prior pending task before starting a new one.
    private func scheduleSearch(for query: String) {
        searchTask?.cancel()

        let trimmed = query
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        // Reset to idle on an empty / whitespace input rather
        // than firing a no-op request.
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }

        // Don't show "searching…" on every keystroke (it
        // flickers); only mark searching once the debounce
        // window has fired and the task actually launches.
        searchTask = Task { @MainActor in
            // 300ms debounce. If the task is cancelled before
            // this returns (because the user typed again), the
            // outer .cancel() handles it.
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            phase = .searching
            let results = await PublicProfileService.search(query: trimmed)
            guard !Task.isCancelled else { return }

            phase = results.isEmpty ? .notFound : .results(results)
        }
    }

    // Synchronous fire on submit — bypasses the debounce so
    // hitting Return immediately runs the search. Matches the
    // affordance every other search box on iOS has.
    private func performSearch() {
        let trimmed = rawInput
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard !trimmed.isEmpty else { return }

        searchTask?.cancel()
        phase = .searching

        searchTask = Task { @MainActor in
            let results = await PublicProfileService.search(query: trimmed)
            guard !Task.isCancelled else { return }
            phase = results.isEmpty ? .notFound : .results(results)
        }
    }

    // MARK: - States

    private var idleHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Find an athlete")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Type a name or @handle to find athletes on Trakrr.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.screenMargin + 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var searchingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.accent)
            Text("Looking up…")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var notFoundCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.warning)
            Text("No athlete found")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Double-check the handle and try again.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
