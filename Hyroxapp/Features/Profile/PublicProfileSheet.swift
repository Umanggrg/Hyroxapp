import SwiftUI

// Sheet that fetches a public profile by user UUID and renders
// it via `PublicProfileCard`. The tap-from-race-card surface —
// when a duo race shows "Duo · with Sarah", tapping Sarah's
// name presents this sheet pre-loaded with her UUID. The sheet
// fetches her public profile and shows the same card the
// search flow shows.
//
// Three states:
//   • loading  — fetch in flight
//   • result   — PublicProfileCard renders
//   • notFound — UUID returned no row (deleted account, RLS
//                drift, network failure). Same not-found
//                language as the handle-search path.
struct PublicProfileSheet: View {

    let userID: String

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading

    private enum Phase {
        case loading
        case result(RemotePublicProfile)
        case notFound
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        switch phase {
                        case .loading:
                            loadingIndicator
                        case .result(let profile):
                            PublicProfileCard(profile: profile)
                                .id(profile.id)
                        case .notFound:
                            notFoundCard
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Athlete")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await load()
            }
        }
    }

    private func load() async {
        if let profile = await PublicProfileService.lookup(userID: userID) {
            phase = .result(profile)
        } else {
            phase = .notFound
        }
    }

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.accent)
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    private var notFoundCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.warning)
            Text("Athlete not found")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("This account may have been deleted, or you don't have access to view it right now.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.screenMargin)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
