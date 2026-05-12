import SwiftUI

#if canImport(Auth)
import Auth
#endif

// Reusable follow / unfollow button.
//
// One place that owns the follow UX — what it looks like, what
// happens when you tap it, how it reconciles with the rest of
// the app when the same edge flips elsewhere. Used by:
//   • PublicProfileCard (size: .large) — the headline CTA on
//     a public profile sheet.
//   • FollowersListView rows (size: .compact) — inline follow-
//     back on each row in the followers / following list.
//
// Behavior contract:
//   1. On appear, fetches "am I following this userID?" via
//      FollowService.isFollowing. The button is in `.loading`
//      until that settles, then `.notFollowing` or `.following`.
//   2. On tap, optimistically flips to the opposite state +
//      enters `.pending` while the network call runs. On
//      success, stays at the new state and broadcasts via
//      NotificationCenter so other surfaces showing the same
//      userID can update without their own re-fetch. On
//      failure, reverts to the previous state silently (v1
//      polish — future: surface a toast).
//   3. Listens for `Notification.Name.followStateChanged` for
//      its userID. When a flip happens elsewhere (the user
//      tapped Follow on the sheet behind this list, or vice
//      versa), this button reconciles locally without a
//      network round-trip.
//
// Hides itself entirely when `userID` matches the local
// signed-in user (own profile case). The caller doesn't have
// to thread that check.
struct FollowButton: View {

    let userID: String
    var size: Size = .large

    // Optional caller-provided seed state. When the parent
    // already knows the relationship (e.g. it's been resolved
    // alongside other batch data), pass it in and the button
    // skips the `.loading` flash. Defaults to nil — button
    // does its own fetch in that case.
    var initialState: RelationshipState? = nil

    // Optional change observer. Fires after a successful flip
    // (not on the initial load resolve). Lets parents react —
    // e.g. ProfileView bumping its follower count when the
    // local user follows or unfollows someone displayed in a
    // list.
    var onChange: ((Bool) -> Void)? = nil

    @State private var state: ButtonState = .loading

    enum Size {
        case large    // 40pt height, capsule, gradient — public profile CTA
        case compact  // 28pt height, smaller text — list row inline action
    }

    // External relationship state (visible to callers). Maps
    // directly onto the internal ButtonState minus transient
    // .loading / .pending phases.
    enum RelationshipState {
        case following
        case notFollowing
    }

    private enum ButtonState: Equatable {
        case loading       // initial fetch in flight
        case notFollowing  // resolved: edge does not exist
        case following     // resolved: edge exists
        case pending       // optimistic flip in flight
    }

    var body: some View {
        if isOwnProfile {
            EmptyView()
        } else {
            button
                .onAppear(perform: setupOnAppear)
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: .followStateChanged
                    )
                ) { note in
                    receiveBroadcast(note)
                }
        }
    }

    // MARK: - Button surface

    private var button: some View {
        Button(action: toggleFollow) {
            HStack(spacing: size == .large ? 6 : 4) {
                switch state {
                case .loading, .pending:
                    ProgressView()
                        .controlSize(.small)
                        .tint(foregroundColor)
                case .following:
                    Image(systemName: "checkmark")
                        .font(iconFont)
                    Text("Following")
                        .font(labelFont)
                case .notFollowing:
                    Image(systemName: "plus")
                        .font(iconFont)
                    Text("Follow")
                        .font(labelFont)
                }
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundShape)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        state == .following ? Color.divider : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(state == .pending || state == .loading)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.85),
            value: state
        )
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Visual params (size-driven)

    private var iconFont: Font {
        size == .large ? .caption.weight(.bold) : .caption2.weight(.bold)
    }

    private var labelFont: Font {
        size == .large ? .callout.weight(.heavy) : .caption.weight(.heavy)
    }

    private var horizontalPadding: CGFloat {
        size == .large ? 20 : 12
    }

    private var verticalPadding: CGFloat {
        size == .large ? 10 : 6
    }

    private var foregroundColor: Color {
        switch state {
        case .following:
            return Color.textPrimary
        case .loading, .notFollowing, .pending:
            return Color.onAccent
        }
    }

    private var backgroundShape: some ShapeStyle {
        switch state {
        case .following:
            return AnyShapeStyle(Color.surface)
        case .loading, .notFollowing, .pending:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accent, Color.accent.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .loading:
            return "Loading follow status"
        case .pending:
            return "Updating"
        case .following:
            return "Following. Tap to unfollow."
        case .notFollowing:
            return "Follow"
        }
    }

    // MARK: - Logic

    private var isOwnProfile: Bool {
        #if canImport(Auth)
        return AuthService.shared.user?.id.uuidString == userID
        #else
        return false
        #endif
    }

    // First-appear seeding. Two paths:
    //   1. Caller provided `initialState` — skip the network
    //      round-trip, use what we were handed. Common for
    //      list rows where the parent batched the lookup.
    //   2. No seed — fetch fresh via FollowService. The
    //      button shows a ProgressView in the meantime.
    private func setupOnAppear() {
        if let seed = initialState {
            state = (seed == .following) ? .following : .notFollowing
        } else {
            refreshFollowState()
        }
    }

    private func refreshFollowState() {
        state = .loading
        Task { @MainActor in
            let following = await FollowService.isFollowing(userID: userID)
            state = following ? .following : .notFollowing
        }
    }

    private func toggleFollow() {
        let previous = state
        let optimistic: ButtonState = (previous == .following) ? .notFollowing : .following
        state = .pending

        Task { @MainActor in
            do {
                if previous == .following {
                    try await FollowService.unfollow(userID: userID)
                } else {
                    try await FollowService.follow(userID: userID)
                }
                state = optimistic
                let nowFollowing = (optimistic == .following)
                onChange?(nowFollowing)
                broadcast(isFollowing: nowFollowing)
            } catch {
                // Silent revert. Future: surface as a toast.
                state = previous
            }
        }
    }

    // MARK: - Broadcast

    // Post a global notification so every other FollowButton
    // (and any other listener — e.g. ProfileView's follower
    // counts) for this same userID can update without a
    // re-fetch. Carries the new boolean state as the object;
    // we use the notification's `userInfo` to also include the
    // userID so listeners can filter cheaply.
    private func broadcast(isFollowing: Bool) {
        NotificationCenter.default.post(
            name: .followStateChanged,
            object: nil,
            userInfo: [
                FollowBroadcastKey.userID: userID,
                FollowBroadcastKey.isFollowing: isFollowing
            ]
        )
    }

    // Receive broadcasts from other FollowButtons. If the
    // notification is about *our* userID and the state differs
    // from what we currently show, reconcile locally — no
    // network round-trip. The originating button's `state` is
    // already correct (it just flipped it), so its onReceive
    // is a no-op for itself; the same userInfo just helps
    // other buttons sync.
    private func receiveBroadcast(_ note: Notification) {
        guard
            let info = note.userInfo,
            let id = info[FollowBroadcastKey.userID] as? String,
            id == userID,
            let following = info[FollowBroadcastKey.isFollowing] as? Bool
        else { return }

        let target: ButtonState = following ? .following : .notFollowing
        if state != target {
            state = target
        }
    }
}

// MARK: - Broadcast keys + name

// String keys for the `userInfo` dictionary on the follow-state
// notification. Centralized here so listeners can subscribe
// without redefining the literals.
enum FollowBroadcastKey {
    static let userID = "trakrr.follow.userID"
    static let isFollowing = "trakrr.follow.isFollowing"
}

extension Notification.Name {
    // Posted by FollowButton after a successful follow / unfollow
    // mutation. Listeners that care about a specific userID (or
    // about any change — e.g. ProfileView's "refresh my follower
    // counts" handler) can subscribe and reconcile in-place.
    static let followStateChanged = Notification.Name("trakrr.followStateChanged")
}

#Preview("Large states") {
    VStack(spacing: 24) {
        FollowButton(
            userID: "preview-not-following",
            size: .large,
            initialState: .notFollowing
        )
        FollowButton(
            userID: "preview-following",
            size: .large,
            initialState: .following
        )
        Divider()
        FollowButton(
            userID: "preview-compact-not",
            size: .compact,
            initialState: .notFollowing
        )
        FollowButton(
            userID: "preview-compact-yes",
            size: .compact,
            initialState: .following
        )
    }
    .padding()
    .background(Color.background)
}
