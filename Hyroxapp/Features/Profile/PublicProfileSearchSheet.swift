import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// First social-discovery surface — type a handle, see another
// athlete's public profile. Drives straight off
// `PublicProfileService.lookup(handle:)`; on result, delegates
// the visual + follow-action surface to `PublicProfileCard`.
//
// Four inline states:
//   • idle      — empty input, nothing fetched yet
//   • searching — request in flight after Go
//   • result    — PublicProfileCard renders the athlete
//   • notFound  — handle didn't match any athlete
struct PublicProfileSearchSheet: View {

    @Environment(\.dismiss) private var dismiss

    @State private var rawInput: String = ""
    @State private var phase: Phase = .idle

    // Tracks the current async search task so a rapid retype
    // cancels the in-flight one before kicking off a new
    // lookup. Without this, two near-simultaneous Go taps
    // could land their results out of order.
    @State private var searchTask: Task<Void, Never>?

    // Not Equatable — the `.result` associated value
    // (RemotePublicProfile) isn't Equatable and synthesizing
    // would require either propagating that conformance or
    // doing a custom comparison. The view doesn't use `==`
    // on Phase anywhere, so we don't need it.
    private enum Phase {
        case idle
        case searching
        case result(RemotePublicProfile)
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
                        case .result(let profile):
                            PublicProfileCard(profile: profile)
                                // Force a fresh card per result so
                                // the follow-state @State inside
                                // resets when a different athlete
                                // is shown.
                                .id(profile.id)
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
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "at")
                .foregroundStyle(Color.textTertiary)
                .font(.body.weight(.semibold))

            TextField("handle", text: $rawInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { performSearch() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .padding(.horizontal, Layout.screenMargin)
    }

    // Trim, drop a leading @, lowercase, kick off lookup. The
    // service applies the same normalization defensively, but
    // doing it here too means our `notFound` UX feels
    // immediate for empty / whitespace-only input.
    private func performSearch() {
        let normalized = rawInput
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()

        guard !normalized.isEmpty else { return }

        searchTask?.cancel()
        phase = .searching

        searchTask = Task { @MainActor in
            let result = await PublicProfileService.lookup(handle: normalized)
            // Swallow the result if the task was cancelled —
            // a newer search is already in flight and will
            // populate `phase` itself.
            guard !Task.isCancelled else { return }
            if let result {
                phase = .result(result)
            } else {
                phase = .notFound
            }
        }
    }

    // MARK: - States

    private var idleHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Search by handle")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("Enter another athlete's @handle to view their public profile.")
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
