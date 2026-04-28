import SwiftUI

// Editable tags row used on RaceSummaryView (post-race) and
// RaceDetailView (retroactive). Renders the existing tags as
// removable chips + a "+ Add" pill that surfaces a small input
// field. Caps at 5 tags (the model also enforces this on write).
//
// Lowercase canonical form is enforced by the model's `tags`
// setter, so the UI just shows whatever was stored. Display
// name capitalization is the storage form ("zone2" displays as
// "zone2"; the athlete picks their own taxonomy and we don't
// title-case it for them — preserving their voice).
//
// Suggested-tags ribbon: when the user opens the input, we
// surface tags they've used on past races so the second-time
// experience is one tap, not retyping. Pulled from the parent's
// `suggestedTags` parameter — caller is responsible for
// scanning their race history; the component itself stays dumb
// about data fetching.
//
// Guarded `#if !os(watchOS)` because Race is iOS-only.
#if !os(watchOS)
struct TagsSection: View {

    @Bindable var race: Race

    // Tags the athlete has used on past races. Surfaced as a
    // suggestion ribbon when the input field is open. Empty
    // array is fine — input still works, just no suggestions.
    let suggestedTags: [String]

    @State private var isEditing = false
    @State private var draftTag = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxTags = 5
    private static let maxTagLength = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags").capsLabelStyle()
                Spacer()
                if race.tags.count >= Self.maxTags {
                    Text("Max \(Self.maxTags)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                tagsFlow
                if isEditing {
                    inputRow
                    if !filteredSuggestions.isEmpty {
                        suggestionsRibbon
                    }
                }
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    // MARK: - Tags flow

    // Wrapping flex layout that fits as many chips per row as the
    // width allows, then wraps to the next line. SwiftUI's native
    // FlowLayout requires iOS 16+ and is well-supported on our
    // iOS 17+ target.
    private var tagsFlow: some View {
        FlowLayout(spacing: 8) {
            ForEach(race.tags, id: \.self) { tag in
                tagChip(tag)
            }
            if race.tags.count < Self.maxTags {
                addButton
            }
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Button {
                Haptics.impact(.light)
                race.tags = race.tags.filter { $0 != tag }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.accent.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Color.accent.opacity(0.30), lineWidth: 1)
        )
    }

    private var addButton: some View {
        Button {
            Haptics.impact(.light)
            withAnimation(reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.85)) {
                isEditing = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .heavy))
                Text("Add")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .strokeBorder(Color.accent.opacity(0.40), style: StrokeStyle(lineWidth: 1, dash: [3]))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("Tag name", text: $draftTag)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { commitDraft() }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.surfaceElevated)
                )

            Button {
                commitDraft()
            } label: {
                Text("Add")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(canCommit ? Color.onAccent : Color.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canCommit ? Color.accent : Color.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // Suggestions filtered to ones not already on this race + a
    // simple prefix-match against what's typed so far. Empty draft
    // shows the full suggestion list (capped at 6 to avoid wall-of-
    // chips). Typed draft narrows it.
    private var filteredSuggestions: [String] {
        let existing = Set(race.tags)
        let trimmed = draftTag.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = suggestedTags.filter { !existing.contains($0) }
        if trimmed.isEmpty {
            return Array(pool.prefix(6))
        }
        return Array(
            pool.filter { $0.hasPrefix(trimmed) }.prefix(6)
        )
    }

    private var suggestionsRibbon: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECENT")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textTertiary)

            FlowLayout(spacing: 6) {
                ForEach(filteredSuggestions, id: \.self) { suggestion in
                    Button {
                        Haptics.impact(.light)
                        var tags = race.tags
                        tags.append(suggestion)
                        race.tags = tags
                        draftTag = ""
                    } label: {
                        Text(suggestion)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.surfaceElevated)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private var canCommit: Bool {
        let trimmed = draftTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= Self.maxTagLength else { return false }
        guard !race.tags.contains(trimmed) else { return false }
        return race.tags.count < Self.maxTags
    }

    private func commitDraft() {
        guard canCommit else { return }
        let trimmed = draftTag.trimmingCharacters(in: .whitespaces).lowercased()
        Haptics.impact(.medium)
        var tags = race.tags
        tags.append(trimmed)
        race.tags = tags
        draftTag = ""
    }
}

// MARK: - FlowLayout

// Native iOS 16+ flex-wrap layout. Wraps tag chips onto multiple
// lines when they don't fit horizontally. Pure layout — no state,
// no animation; SwiftUI handles the rest via .animation modifiers
// at the call site.
//
// Could've used a third-party WrappingHStack, but this stays
// dependency-free and the implementation is ~30 lines.
//
// NB: we qualify `SwiftUI.Layout` because the project's `Theme.swift`
// declares its own `enum Layout` (cardPadding / cardCornerRadius
// constants) which would otherwise shadow the protocol.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: LayoutSubviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalHeight += lineHeight + spacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
#endif
