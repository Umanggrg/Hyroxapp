import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// List of athletes who follow `userID` (Kind.followers) or whom
// `userID` follows (Kind.following). Single view handles both
// — navigation title + service call branch on the `kind`,
// everything else is identical.
//
// Flow:
//   1. Load — fetch user IDs via FollowService, then bulk-resolve
//      the profiles via PublicProfileService.lookup(userIDs:).
//   2. Render rows — avatar + display name + handle + division.
//   3. Tap a row → present `PublicProfileSheet` over the stack.
//      From inside that sheet the user can follow/unfollow,
//      then dismiss and the list stays as-is. Refresh on next
//      Profile re-appear via the counts fetch.
//
// Pushed from `ProfileView` via `.navigationDestination(item:)`.
// `userID` is the local user today, but the parameter shape is
// ready for tap-from-public-profile (e.g. "view Sarah's
// followers") without rework.
struct FollowersListView: View {

    enum Kind: String, Identifiable, Hashable {
        case followers
        case following

        // `Identifiable` so `navigationDestination(item:)` can
        // dispatch on the enum directly without wrapping it.
        // The rawValue suffices since the enum has only two
        // cases and each is unique.
        var id: String { rawValue }

        var title: String {
            switch self {
            case .followers: return "Followers"
            case .following: return "Following"
            }
        }

        var emptyMessage: String {
            switch self {
            case .followers:
                return "No followers yet. Share your handle so other athletes can find you."
            case .following:
                return "Not following anyone yet. Tap the search icon on Profile to find athletes by handle."
            }
        }
    }

    let userID: String
    let kind: Kind

    @State private var profiles: [RemotePublicProfile] = []
    @State private var isLoading = true
    @State private var selectedProfile: RemotePublicProfile?

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if isLoading {
                        loadingIndicator
                    } else if profiles.isEmpty {
                        emptyState
                    } else {
                        ForEach(profiles) { profile in
                            row(for: profile)
                                .onTapGesture {
                                    selectedProfile = profile
                                }
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.top, 16)
            }
        }
        .navigationTitle(kind.title)
        .hyroxNavigationBar(inline: true)
        .task { await load() }
        .sheet(item: $selectedProfile) { profile in
            // Reuse the by-userID sheet rather than pushing into
            // the same nav stack — keeps a tappable Follow CTA
            // and dismissable surface, and the user can hop
            // between profiles without growing the back stack.
            PublicProfileSheet(userID: profile.id)
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        let userIDs: [String]
        switch kind {
        case .followers:
            userIDs = await FollowService.followers(of: userID)
        case .following:
            userIDs = await FollowService.following(of: userID)
        }

        // Bulk profile fetch — one round-trip for N user IDs
        // rather than N round-trips. PostgREST handles up to
        // a few hundred in a single `.in()` clause; long-tail
        // capping (e.g. 200+) would need pagination, deferred
        // until follow counts get there.
        if userIDs.isEmpty {
            profiles = []
        } else {
            let fetched = await PublicProfileService.lookup(userIDs: userIDs)
            // Sort by display name for a stable, scannable
            // list. Future v2: relevance sort (mutual follows
            // first, recent activity, etc.).
            profiles = fetched.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        isLoading = false
    }

    // MARK: - Row

    private func row(for profile: RemotePublicProfile) -> some View {
        HStack(spacing: 12) {
            avatar(for: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("@\(profile.handle)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        .contentShape(Rectangle())
    }

    private func avatar(for profile: RemotePublicProfile) -> some View {
        Group {
            #if canImport(UIKit)
            if let urlString = profile.avatarUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        defaultAvatarSymbol
                    @unknown default:
                        defaultAvatarSymbol
                    }
                }
            } else {
                defaultAvatarSymbol
            }
            #else
            defaultAvatarSymbol
            #endif
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    // MARK: - States

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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: kind == .followers
                  ? "person.2.slash"
                  : "person.crop.circle.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text(kind.emptyMessage)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Layout.screenMargin)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
