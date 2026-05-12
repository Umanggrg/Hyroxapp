import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// v2 redesign hero header for Profile. The hero treats the
// top of Profile as a moment, not a header — coral spotlight
// backdrop, large avatar with accent ring, name in display
// weight, single stand-out PB number underneath. (The earlier
// flat ProfileHeaderView was pruned once ProfileView fully
// migrated to this view.)
//
// Anatomy:
//   • Subtle radial coral glow (via HeroBackdrop's logic
//     applied locally, since this needs its own bounded shape)
//   • 112pt avatar circle with coral ring + soft drop shadow
//   • Display-weight name (28pt heavy rounded)
//   • Handle + division pill row
//   • Below: 4 stat tiles in a row — Races / PB / Avg / Streak.
//     PB is rendered in the bigger 32pt accent treatment to
//     anchor as the headline number; the other three are
//     supporting in 22pt textPrimary. Real hierarchy, not
//     four equal tiles.
//
// Renders inside its own padded container so it can sit at the
// top of a ScrollView with edge-to-edge backdrop while the
// inner content stays comfortably padded.
//
// Guarded `#if canImport(UIKit)` for UIImage avatar support.
#if canImport(UIKit)
struct ProfileHero: View {

    let profile: UserProfile
    let raceCount: Int
    let pbDisplay: String
    let avgDisplay: String
    let streakDays: Int

    // Followers + Following counts. Optional — nil means "still
    // loading from FollowService" and the line is hidden. Once
    // either resolves to a real Int, the line slides in. Cached
    // in @State at the caller (ProfileView) so leaving + returning
    // to the tab shows the last-known values immediately.
    var followerCount: Int? = nil
    var followingCount: Int? = nil

    // Optional tap callbacks. When non-nil, the corresponding
    // count becomes a tappable button (typically pushing a
    // FollowersListView). When nil, the count renders as plain
    // text — same visual, no affordance. Lets callers decide
    // whether to expose navigation; previews + share-card
    // contexts don't.
    var onTapFollowers: (() -> Void)? = nil
    var onTapFollowing: (() -> Void)? = nil

    // Active mode — drives shadow intensity on the avatar so the
    // drop shadow stays subtle on warm off-white but reads with
    // depth on near-black.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Top half coral wash — bleeds full width via
            // ignoresSafeArea on the parent ScrollView. Subtle so
            // name + avatar still pop.
            backdropLayer

            VStack(spacing: 14) {
                avatar
                    .padding(.top, 24)

                nameAndHandle

                identityPills

                bioAndLocation

                followStatsLine

                statsRow
                    .padding(.top, 6)
                    .padding(.horizontal, 4)
            }
            .padding(.bottom, 20)
        }
    }

    // Top-anchored radial glow that fades into the page. Looks
    // like a stadium spotlight on the avatar without coloring
    // the whole header coral.
    //
    // Mode-aware: `.screen` blend mode lifts dark backgrounds
    // (correct on OLED black) but reads as a heavy wash on warm
    // off-white. Light mode falls back to `.normal` compose with
    // the opacity dialed down so it reads as a soft tint, not a
    // stamp.
    private var backdropLayer: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        Color.accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.25),
                    startRadius: 0,
                    endRadius: max(geo.size.width, 320) * 0.7
                )
                .blendMode(colorScheme == .dark ? .screen : .normal)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private var avatar: some View {
        // Display order:
        //   1. Local bytes (`avatarData`) — zero-latency, ALWAYS
        //      preferred when present.
        //   2. Remote URL (`avatarURL`) — synced from Supabase.
        //      Used when this device has the URL but not the
        //      bytes (signed in on a new phone after avatar was
        //      uploaded from another device). Pre-v1 this case
        //      fell through to the initial-letter placeholder
        //      which was a real fresh-device bug.
        //   3. Initial-letter coral disc — final fallback when
        //      neither bytes nor URL exist.
        Group {
            if let data = profile.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let urlString = profile.avatarURL,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        initialPlaceholder
                    @unknown default:
                        initialPlaceholder
                    }
                }
            } else {
                initialPlaceholder
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.accent.opacity(0.55), lineWidth: 2.5)
        )
        // Drop shadow tuned per mode — full strength on dark
        // (the avatar reads as elevated above the background),
        // dialed back on light bg where harsh black shadow
        // against warm off-white reads as muddy.
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.5 : 0.16),
            radius: 16,
            x: 0,
            y: 8
        )
        // Coral halo around the avatar — same mode-aware scaling
        // pattern as the rest of the brand spotlights.
        .shadow(
            color: Color.accent.opacity(colorScheme == .dark ? 0.25 : 0.14),
            radius: 24,
            x: 0,
            y: 0
        )
    }

    // The pre-bytes / pre-URL fallback — coral disc with the
    // first character of the display name. Extracted so all
    // three branches of the avatar resolver can share it.
    private var initialPlaceholder: some View {
        ZStack {
            Circle().fill(Color.accent.opacity(0.18))
            Text(initial)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.accent)
        }
    }

    private var initial: String {
        String(profile.displayName.prefix(1)).uppercased()
    }

    private var nameAndHandle: some View {
        VStack(spacing: 4) {
            Text(profile.displayName)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)

            if !profile.handle.isEmpty {
                Text("@\(profile.handle)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // §05.2 identity-pill row — Division pill (always rendered)
    // + optional Home Gym pill. When the athlete hasn't set a
    // home gym, only the Division pill shows so the row reads
    // clean. When both are set, they sit side-by-side as the
    // identity strip between the handle and the social-graph
    // line.
    private var identityPills: some View {
        HStack(spacing: 6) {
            divisionPill
            if !profile.homeGym.isEmpty {
                gymPill
            }
        }
        .padding(.horizontal, 16)
    }

    // Division pill — small caps wordmark with coral border. Same
    // treatment used by the share-card athlete footer so the
    // identity reads consistently across surfaces.
    private var divisionPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.caption2.weight(.bold))
            Text(profile.resolvedDivision.displayName)
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.accent.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.accent.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // Home gym pill — neutral surface treatment (not coral) so
    // it reads as supporting identity rather than competing with
    // the division pill. Hidden entirely when the athlete hasn't
    // set a home gym yet. Truncates with a tail ellipsis at
    // longer gym names so the row stays single-line on a 375pt
    // device.
    private var gymPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "building.2.fill")
                .font(.caption2.weight(.bold))
            Text(profile.homeGym)
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.surface)
                .overlay(
                    Capsule()
                        .stroke(Color.divider, lineWidth: 1)
                )
        )
    }

    // Bio + location strip — quiet metadata between the identity
    // pills and the social-graph line. Hidden entirely when both
    // fields are empty so a fresh-onboarded athlete doesn't see
    // an empty gap. Location renders as a small caps + pin icon
    // line; bio as a soft body paragraph beneath. Both center-
    // aligned to match the rest of the hero column.
    @ViewBuilder
    private var bioAndLocation: some View {
        let trimmedLocation = profile.location.trimmingCharacters(in: .whitespaces)
        let trimmedBio = profile.bio.trimmingCharacters(in: .whitespaces)

        if !trimmedLocation.isEmpty || !trimmedBio.isEmpty {
            VStack(spacing: 6) {
                if !trimmedLocation.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.caption2.weight(.bold))
                        Text(trimmedLocation)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                if !trimmedBio.isEmpty {
                    Text(trimmedBio)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                }
            }
            .padding(.top, 2)
        }
    }

    // Followers / Following inline line — Strava convention:
    // small text below the identity that anchors the social
    // graph without competing with performance stats. Hidden
    // until at least one count resolves so we don't flash "0
    // followers · 0 following" during the network round-trip on
    // every Profile entry. Single-digit pluralization handled
    // inline; localized plurals are a future polish pass.
    @ViewBuilder
    private var followStatsLine: some View {
        if followerCount != nil || followingCount != nil {
            HStack(spacing: 6) {
                if let followers = followerCount {
                    followCountButton(
                        value: followers,
                        label: followers == 1 ? "follower" : "followers",
                        action: onTapFollowers
                    )
                }

                if followerCount != nil && followingCount != nil {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }

                if let following = followingCount {
                    followCountButton(
                        value: following,
                        label: "following",
                        action: onTapFollowing
                    )
                }
            }
            .padding(.top, 2)
        }
    }

    // Renders one "12 followers" segment. When the action
    // closure is non-nil, wraps in a Button so the segment
    // becomes tappable; otherwise renders the inline text
    // pair. Same visual shape either way — Strava-style
    // inline count + noun.
    @ViewBuilder
    private func followCountButton(
        value: Int,
        label: String,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(spacing: 4) {
            Text("\(value)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                // Hit area extends slightly past the visible
                // text so the small caption-sized target is
                // less finicky to tap on a sweaty hand.
                .contentShape(Rectangle())
        } else {
            content
        }
    }

    // Wireframe §05.1 asymmetric 4-tile stat row — coral PB tile
    // leftmost as the visual anchor (1.4fr in the wireframe),
    // RACES / AVG / STREAK as the three equal secondaries
    // (1fr each). Equal widths in the SwiftUI realization since
    // fractional-flex isn't first-class, but the hero tile's
    // larger numeric, coral tint, and sub-line do the visual
    // hierarchy work the wireframe asymmetry implies.
    //
    // Tile order matches the wireframe: PB · RACES · AVG · STREAK.
    private var statsRow: some View {
        HStack(spacing: 4) {
            heroPBTile
            secondaryStatTile(value: "\(raceCount)", label: "RACES")
            secondaryStatTile(value: avgDisplay, label: "AVG")
            secondaryStatTile(
                value: "\(streakDays)\(streakDays > 0 ? " 🔥" : "")",
                label: "STREAK"
            )
        }
        .padding(.horizontal, Layout.screenMargin)
    }

    // Hero PB tile — coral wash, big rounded number, caps "PB"
    // label + a small contextual sub-line. Reads as the headline
    // stat on the row.
    private var heroPBTile: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pbDisplay)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("PB")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.accent)

            // Sub-line — wireframe shows "Ski Erg · best" or
            // "Nov 9 · −42s". For v1 we render a quiet "best
            // finish" anchor when the athlete has races, falling
            // back to a dash placeholder when not.
            Text(raceCount > 0 ? "best finish" : "no races yet")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .stroke(Color.accent.opacity(0.35), lineWidth: 1)
        )
    }

    // Plain stat tile — rounded number + caps label, neutral
    // surface fill. Three of these sit to the right of the hero
    // tile in the stat row.
    private func secondaryStatTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 28)
    }

    private func statTile(value: String, label: String, isHero: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(
                    isHero
                        ? .system(size: 28, weight: .heavy, design: .rounded)
                        : .system(size: 18, weight: .bold, design: .rounded)
                )
                .monospacedDigit()
                .foregroundStyle(isHero ? Color.accent : Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
