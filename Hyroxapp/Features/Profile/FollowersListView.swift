import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Auth)
import Auth
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

    // Sets used to seed each row's FollowButton initial state
    // and to drive the "Follows you" mutual indicator. Both are
    // populated once when the list loads, then kept fresh by
    // the `.followStateChanged` broadcast (so tapping Follow on
    // one row doesn't make a sibling row stale).
    //   • myFollowing — user IDs the LOCAL user follows. A row
    //     in this set means the inline Follow button starts in
    //     the `.following` state.
    //   • myFollowers — user IDs that follow the LOCAL user.
    //     Drives the "Follows you" badge.
    @State private var myFollowing: Set<String> = []
    @State private var myFollowers: Set<String> = []

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
        // Listen for follow-state flips from any FollowButton
        // (in our own rows, in the sheet that opens over this
        // list, or anywhere else in the app). Keeps the
        // myFollowing set fresh so a tap on Follow inside the
        // sheet immediately reflects on the list behind it
        // when the sheet dismisses.
        .onReceive(
            NotificationCenter.default.publisher(
                for: .followStateChanged
            )
        ) { note in
            guard
                let info = note.userInfo,
                let targetID = info[FollowBroadcastKey.userID] as? String,
                let isFollowing = info[FollowBroadcastKey.isFollowing] as? Bool
            else { return }
            applyFollowBroadcast(userID: targetID, isFollowing: isFollowing)
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

        // Resolve the two sets used to seed each row's
        // FollowButton + drive the "Follows you" indicator.
        // Both queries are about the LOCAL user, so they run
        // in parallel via async-let and don't block the row
        // render — by the time SwiftUI lays out the rows,
        // these sets are usually populated.
        await refreshRelationshipSets()

        isLoading = false
    }

    // Pull the local user's complete follow graph (who I
    // follow + who follows me) and convert to Sets for O(1)
    // lookup per row. Called once on load() and again when
    // a `.followStateChanged` broadcast tells us the graph
    // changed under us.
    private func refreshRelationshipSets() async {
        guard let me = localUserID else { return }
        async let following = FollowService.following(of: me)
        async let followers = FollowService.followers(of: me)
        let (fIDs, gIDs) = await (followers, following)
        myFollowers = Set(fIDs)
        myFollowing = Set(gIDs)
    }

    private var localUserID: String? {
        #if canImport(Auth)
        return AuthService.shared.user?.id.uuidString
        #else
        return nil
        #endif
    }

    // Apply an in-place delta to `myFollowing` when a
    // FollowButton broadcasts a change. Saves a network
    // round-trip — the broadcast carries the new state.
    private func applyFollowBroadcast(userID: String, isFollowing: Bool) {
        if isFollowing {
            myFollowing.insert(userID)
        } else {
            myFollowing.remove(userID)
        }
    }

    // MARK: - Row

    private func row(for profile: RemotePublicProfile) -> some View {
        // Split the row into two tap zones:
        //   • Left/center "info area" (avatar + name + handle +
        //     mutual indicator) — tap to open the profile sheet.
        //   • Trailing FollowButton — tap to follow/unfollow
        //     inline without leaving the list. The button's own
        //     ButtonStyle.plain swallows the tap so the parent
        //     onTapGesture doesn't double-fire.
        HStack(spacing: 12) {
            Button {
                selectedProfile = profile
            } label: {
                HStack(spacing: 12) {
                    avatar(for: profile)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text("@\(profile.handle)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)

                            if showsMutualBadge(for: profile) {
                                mutualBadge
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            FollowButton(
                userID: profile.id,
                size: .compact,
                initialState: myFollowing.contains(profile.id)
                    ? .following
                    : .notFollowing
            )
        }
        .padding(Layout.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // "Follows you" pill — Twitter/Instagram convention. Tells
    // the local user that THIS profile follows them back. Only
    // meaningful when the list is rooted at the local user
    // (viewing my own followers/following). For a future
    // public-profile-followers entry point we'd want a more
    // nuanced relationship label and we'd suppress this one.
    private var mutualBadge: some View {
        Text("Follows you")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.surfaceElevated)
            )
    }

    private func showsMutualBadge(for profile: RemotePublicProfile) -> Bool {
        // Only meaningful when viewing the local user's own
        // lists. If we're viewing someone else's followers /
        // following, the "Follows you" label would be
        // ambiguous (follows whom — the list owner, or me?)
        // so we suppress it.
        guard let me = localUserID, me == userID else { return false }

        switch kind {
        case .followers:
            // Every row here follows me by definition — the
            // badge would be tautological. Skip.
            return false
        case .following:
            // Show when this person I follow also follows me
            // back. Mutual relationship.
            return myFollowers.contains(profile.id)
        }
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
