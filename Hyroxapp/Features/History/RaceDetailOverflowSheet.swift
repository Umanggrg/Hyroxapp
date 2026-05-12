import SwiftUI

// Wireframe §04.2 overflow actions sheet. Presented from
// RaceDetailView's ··· toolbar button as a bottom sheet with
// six discrete actions:
//
//   1. Post to feed       — coral chevron, kicks off the post composer
//   2. Share image        — opens the share-card export flow
//   3. Compare to another — pushes RaceComparisonView seeded with this race
//   4. Edit notes         — opens the existing reflection sheet
//   5. Export Apple Health— manual HK write fallback for older races
//   6. Delete race        — coral destructive, confirm-gated
//
// All callbacks come from the parent so this view stays
// view-only and the navigation / persistence side effects live
// alongside the rest of the detail flow.
struct RaceDetailOverflowSheet: View {

    // Callbacks per row. Each is fired on tap; the parent
    // typically dismisses the sheet right after (the menu is
    // single-action — pick one and the sheet closes).
    let onPostToFeed: () -> Void
    let onShareImage: () -> Void
    let onCompare: () -> Void
    let onEditNotes: () -> Void
    let onExportAppleHealth: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(title: "Post to feed",
                accent: true,
                trailing: .chevron(coral: true),
                action: onPostToFeed)

            divider

            row(title: "Share image",
                accent: false,
                trailing: .chevron(coral: false),
                action: onShareImage)

            divider

            row(title: "Compare to another race",
                accent: false,
                trailing: .chevron(coral: false),
                action: onCompare)

            divider

            row(title: "Edit notes",
                accent: false,
                trailing: .chevron(coral: false),
                action: onEditNotes)

            divider

            row(title: "Export · Apple Health",
                accent: false,
                trailing: .chevron(coral: false),
                action: onExportAppleHealth)

            divider

            row(title: "Delete race",
                accent: false,
                trailing: .none,
                destructive: true,
                action: onDelete)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(Color.background.ignoresSafeArea())
    }

    // MARK: - Row builder

    // Single action row. Title + optional trailing affordance
    // (chevron or empty). Destructive rows render in coral with
    // heavier weight.
    private func row(
        title: String,
        accent: Bool,
        trailing: TrailingAffordance,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            HStack {
                Text(title)
                    .font(.system(
                        size: 14,
                        weight: destructive ? .heavy : .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(rowColor(accent: accent, destructive: destructive))

                Spacer()

                switch trailing {
                case .chevron(let coral):
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(coral ? Color.accent : Color.textTertiary)
                case .none:
                    EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowColor(accent: Bool, destructive: Bool) -> Color {
        if destructive { return Color.accent }
        return Color.textPrimary
    }

    // Lightweight visual separator between rows. Inset so the
    // row tap-target stretches edge-to-edge but the visual line
    // doesn't.
    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    enum TrailingAffordance {
        case chevron(coral: Bool)
        case none
    }
}
