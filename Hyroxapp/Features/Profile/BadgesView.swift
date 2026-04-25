import SwiftUI

// Guarded `#if !os(watchOS)` because the underlying BadgeAwarder
// depends on RaceStats helpers that don't compile on watchOS
// (same gating pattern used elsewhere — RaceStats, BadgeAwarder).
// Profile is iOS-only anyway, so this is purely belt-and-braces.
#if !os(watchOS)

// Achievements panel on Profile — Strava-style milestone tiles.
// Renders all six `Badge` cases as a 3-up grid; earned badges
// light up in their tint color, unearned badges render dimmed
// with a lock icon overlay so the athlete sees what's still
// out there to chase.
//
// Tap a tile to surface a sheet describing the badge requirement
// — same affordance pattern Strava uses for its trophy wall.
//
// Hidden when zero badges have been earned (handled by the parent
// via `BadgesView.hasAnyEarned`); a brand-new install with no
// races yet would otherwise show a wall of grey lock tiles, which
// reads more like "you have nothing" than "here's what's coming."
struct BadgesView: View {

    let races: [Race]
    let templates: [WorkoutTemplate]

    // Earned set is computed once at render time. Cheap — six
    // criteria, each a single pass over the races array.
    private var earned: Set<Badge> {
        BadgeAwarder.evaluate(races: races, templates: templates)
    }

    @State private var selectedBadge: Badge?

    // Helper for the parent: don't show the section at all until
    // at least one badge has been earned.
    static func hasAnyEarned(races: [Race], templates: [WorkoutTemplate]) -> Bool {
        !BadgeAwarder.evaluate(races: races, templates: templates).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // 3-column flexible grid — same column treatment as the
            // HYROX Performance pillar tiles so the two sections feel
            // visually consistent stacked together.
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 0),
                    count: 3
                ),
                spacing: 16
            ) {
                ForEach(Badge.allCases) { badge in
                    Button {
                        selectedBadge = badge
                    } label: {
                        tile(for: badge, isEarned: earned.contains(badge))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Layout.cardPadding)
        }
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        // `.sheet(item:)` binds to the optional Badge — tap a tile,
        // sheet opens with that badge's detail. Closes by setting
        // selectedBadge back to nil.
        .sheet(item: $selectedBadge) { badge in
            BadgeDetailSheet(
                badge: badge,
                isEarned: earned.contains(badge)
            )
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    // Single tile: SF Symbol on top inside a tinted circle, name
    // below in caps-label style. Earned tiles use the badge's
    // tint color; unearned tiles render in textTertiary with a
    // lock symbol superimposed on the circle.
    private func tile(for badge: Badge, isEarned: Bool) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isEarned ? badge.color.opacity(0.18) : Color.surfaceElevated)
                    .frame(width: 56, height: 56)

                Image(systemName: badge.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isEarned ? badge.color : Color.textTertiary)

                // Lock overlay for unearned badges. Sits in the
                // bottom-trailing corner so it reads as a state
                // marker, not as the primary icon.
                if !isEarned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(4)
                        .background(
                            Circle().fill(Color.background)
                        )
                        .offset(x: 20, y: 20)
                }
            }

            Text(badge.displayName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isEarned ? Color.textPrimary : Color.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// Sheet shown when an athlete taps a badge tile. Displays the
// badge symbol large, the display name, the requirement text,
// and an "earned" / "locked" status pill so the athlete knows
// at a glance whether they've got it.
private struct BadgeDetailSheet: View {

    let badge: Badge
    let isEarned: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 8)

                // Hero icon — same circular treatment as the tile,
                // just larger and elevated visually for the detail.
                ZStack {
                    Circle()
                        .fill(isEarned ? badge.color.opacity(0.20) : Color.surfaceElevated)
                        .frame(width: 96, height: 96)

                    Image(systemName: badge.symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(isEarned ? badge.color : Color.textTertiary)
                }

                Text(badge.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                // Status pill — green "Earned" when it's in the set,
                // grey "Locked" otherwise. Mirrors Strava's "achieved"
                // ribbon on its trophy detail screens.
                statusPill

                Text(badge.requirement)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.surfaceElevated)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 16)
            }
            .padding(.top, 24)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Image(systemName: isEarned ? "checkmark.seal.fill" : "lock.fill")
                .font(.caption.weight(.bold))
            Text(isEarned ? "Earned" : "Locked")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .foregroundStyle(isEarned ? Color.success : Color.textTertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isEarned ? Color.success.opacity(0.15) : Color.surfaceElevated)
        )
    }
}

#endif

