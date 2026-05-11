import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Auth)
import Auth
#endif

// Standalone card rendering one athlete's public profile —
// avatar, name, handle, division, location, bio, follow CTA.
// Two callers:
//   • `PublicProfileSearchSheet` shows it as the result of a
//     handle search.
//   • `PublicProfileSheet` shows it after looking up a userID
//     (e.g. tap on a duo race partner name).
//
// Owns its own follow state — fetches "am I following this
// athlete?" on appear, supports optimistic follow/unfollow
// with revert-on-failure. Hides the Follow button when the
// profile is the local signed-in user.
//
// Reuse pattern intentional: the card is the "thing" that's
// shared; the surrounding context (sheet header, search bar,
// loading state) differs per caller. Extracting the visual
// + interaction surface keeps both call sites lean.
struct PublicProfileCard: View {

    let profile: RemotePublicProfile

    @State private var followState: FollowState = .loading

    // Public race aggregates loaded lazily on appear. Optional —
    // nil means "still loading," explicit `.none` (mapped to
    // the noRaces local state) means "this athlete has no
    // finished public races yet."
    @State private var statsState: StatsState = .loading

    // Recent finished public races for this athlete. Drives
    // the bottom "Recent Races" section. Empty array = either
    // loading (initial) or genuinely no races; the stats state
    // disambiguates so the UI doesn't render an empty section
    // while loading.
    @State private var recentRaces: [RemotePublicRace] = []

    private enum FollowState {
        case loading
        case notFollowing
        case following
        case pending
    }

    private enum StatsState {
        case loading
        case loaded(RemotePublicRaceStats)
        case noRaces
    }

    var body: some View {
        VStack(spacing: 14) {
            avatar

            VStack(spacing: 4) {
                Text(profile.displayName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("@\(profile.handle)")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            metadataLine

            if !profile.bio.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Layout.screenMargin)
            }

            if !isOwnProfile {
                followButton
                    .padding(.top, 8)
            }

            statsRow
                .padding(.top, 12)

            recentRacesSection
                .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Layout.screenMargin)
        .onAppear {
            refreshFollowState()
            refreshStats()
            refreshRecentRaces()
        }
    }

    // MARK: - Recent races

    // Last N (3) finished public races for this athlete. Each
    // row is a compact line — race title, finish time, relative
    // date. Hidden entirely when there are no public races —
    // the stats row already shows "No public races yet" in
    // that case, so a second empty section would be noise.
    @ViewBuilder
    private var recentRacesSection: some View {
        if !recentRaces.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Races")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    ForEach(recentRaces) { race in
                        recentRaceRow(race)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func recentRaceRow(_ race: RemotePublicRace) -> some View {
        HStack(spacing: 12) {
            // Mode icon — small visual differentiator between
            // HYROX races and custom workouts. Avoids needing
            // a separate label line.
            Image(systemName: race.isHyroxRace ? "flag.checkered" : "figure.strengthtraining.functional")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(Color.accent.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle(for: race))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(relativeDateLabel(from: race.endedAt))
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            Text(RaceStats.format(race.totalDuration))
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func displayTitle(for race: RemotePublicRace) -> String {
        let trimmed = race.name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return race.isHyroxRace ? "HYROX Race" : "Custom Workout"
    }

    // MARK: - Stats row

    // Three-tile row: Races · PB · Last raced. Matches
    // ProfileHero's own stat tile language so users see the
    // same shape on their own profile and on someone else's.
    // Hidden while loading; shows a "No races yet" pill when
    // the athlete has nothing public.
    @ViewBuilder
    private var statsRow: some View {
        switch statsState {
        case .loading:
            // Compact placeholder — keeps the layout from
            // collapsing on first-paint. Disappears once the
            // fetch settles.
            HStack(spacing: 16) {
                statTilePlaceholder
                statTilePlaceholder
                statTilePlaceholder
            }
            .frame(maxWidth: .infinity)

        case .noRaces:
            Text("No public races yet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.surface)
                )

        case .loaded(let stats):
            HStack(spacing: 16) {
                statTile(
                    value: "\(stats.raceCount)",
                    label: stats.raceCount == 1 ? "race" : "races"
                )
                if let pb = stats.pbSeconds {
                    statTile(
                        value: RaceStats.format(pb),
                        label: "pb"
                    )
                }
                if let lastRaceAt = stats.lastRaceAt {
                    statTile(
                        value: relativeDateLabel(from: lastRaceAt),
                        label: "last race"
                    )
                }
            }
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var statTilePlaceholder: some View {
        VStack(spacing: 2) {
            Text("—")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
            Text(" ")
                .font(.caption2)
        }
    }

    // Format a date as "3d ago" / "12h ago" / "5m ago" — the
    // condensed Strava-style relative timestamp. Falls back to
    // "today" for anything under a minute.
    private func relativeDateLabel(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Avatar

    private var avatar: some View {
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
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.accent.opacity(0.4), lineWidth: 1.5)
        )
    }

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataLine: some View {
        let division = Division(rawValue: profile.division)?.displayName ?? profile.division
        let trimmedLocation = profile.location.trimmingCharacters(in: .whitespaces)

        HStack(spacing: 8) {
            Text(division)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.surface)
                )

            if !trimmedLocation.isEmpty {
                Label(trimmedLocation, systemImage: "mappin.and.ellipse")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - Follow

    private var isOwnProfile: Bool {
        #if canImport(Auth)
        return AuthService.shared.user?.id.uuidString == profile.id
        #else
        return false
        #endif
    }

    private var followButton: some View {
        Button {
            toggleFollow()
        } label: {
            HStack(spacing: 6) {
                switch followState {
                case .loading, .pending:
                    ProgressView()
                        .controlSize(.small)
                        .tint(followButtonForeground)
                case .following:
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                    Text("Following")
                        .font(.callout.weight(.heavy))
                case .notFollowing:
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Follow")
                        .font(.callout.weight(.heavy))
                }
            }
            .foregroundStyle(followButtonForeground)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(followButtonBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        followState == .following
                            ? Color.divider
                            : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(followState == .pending || followState == .loading)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.85),
            value: followState
        )
    }

    private var followButtonForeground: Color {
        switch followState {
        case .following:
            return Color.textPrimary
        case .loading, .notFollowing, .pending:
            return Color.onAccent
        }
    }

    private var followButtonBackground: some ShapeStyle {
        switch followState {
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

    private func refreshFollowState() {
        followState = .loading
        Task { @MainActor in
            let following = await FollowService.isFollowing(userID: profile.id)
            followState = following ? .following : .notFollowing
        }
    }

    private func refreshStats() {
        statsState = .loading
        Task { @MainActor in
            if let stats = await PublicProfileService.stats(for: profile.id) {
                statsState = .loaded(stats)
            } else {
                statsState = .noRaces
            }
        }
    }

    // Pull the athlete's last 3 finished public races. Drives
    // the "Recent Races" section. Result is sorted-newest-
    // first by the service's `order by ended_at desc` clause.
    // Errors / no-results both yield an empty array — the
    // section auto-hides when that's the case.
    private func refreshRecentRaces() {
        Task { @MainActor in
            recentRaces = await PublicRaceFeedService.recent(
                forUserID: profile.id,
                limit: 3
            )
        }
    }

    private func toggleFollow() {
        let previous = followState
        let target: FollowState = (previous == .following) ? .notFollowing : .following
        followState = .pending

        Task { @MainActor in
            do {
                if previous == .following {
                    try await FollowService.unfollow(userID: profile.id)
                } else {
                    try await FollowService.follow(userID: profile.id)
                }
                followState = target
            } catch {
                // Silent revert. Future polish: toast/banner.
                followState = previous
            }
        }
    }
}
