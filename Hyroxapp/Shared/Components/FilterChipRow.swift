import SwiftUI

// Horizontal-scrolling chip row for filter selection, modeled on
// Strava's activity-feed filter pills. Used today by HistoryView's
// search/filter UI; designed generic so any other surface (custom
// workout templates, future feed) can drop it in.
//
// One selected chip at a time. Tapping the currently-selected chip
// is a no-op (don't accidentally deselect by re-tapping). Tapping
// a different chip swaps selection. There's deliberately no "none"
// state — exactly one filter is always active, defaulting to the
// caller's "all" option.
//
// Generic over the filter type so callers can pass any
// CaseIterable / Hashable enum and own the labels via a closure.
// Keeps the component free of HYROX-specific copy and lets the
// caller stay in control of localization later.
struct FilterChipRow<Filter: Hashable & Identifiable>: View {

    let filters: [Filter]
    @Binding var selection: Filter
    let label: (Filter) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    chip(for: filter)
                }
            }
            .padding(.horizontal, Layout.screenMargin)
        }
        // Don't let the chip row collapse to zero height during
        // layout passes — fixes a "row briefly invisible while
        // SwiftUI resolves intrinsic size" flicker on first appear.
        .frame(height: 36)
    }

    private func chip(for filter: Filter) -> some View {
        let isSelected = filter == selection
        return Button {
            // Idempotent reselection — guard against re-firing the
            // binding when the user re-taps the active chip,
            // which can cause unnecessary re-renders downstream.
            guard filter != selection else { return }
            selection = filter
        } label: {
            Text(label(filter))
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(isSelected ? Color.background : Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accent : Color.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.accent : Color.divider,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TagFilterRow

// Sibling component for nullable single-select string filters,
// used today for tag filtering on HistoryView. Tap an unselected
// chip to filter to that tag; tap a selected chip to clear back
// to nil ("show all"). Different from FilterChipRow's
// always-selected model because there isn't a sensible default
// "all tags" pseudo-tag — nil is the absence of filter.
//
// Auto-hides itself when there are no tags to show. Caller
// doesn't have to gate visibility manually.
struct TagFilterRow: View {

    let tags: [String]
    @Binding var selection: String?

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        chip(for: tag)
                    }
                }
                .padding(.horizontal, Layout.screenMargin)
            }
            .frame(height: 36)
        }
    }

    private func chip(for tag: String) -> some View {
        let isSelected = (tag == selection)
        return Button {
            // Tap-to-clear when re-tapping the active tag.
            // Clearing returns to the "no tag filter" state.
            if isSelected {
                selection = nil
            } else {
                selection = tag
            }
        } label: {
            Text(tag)
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .foregroundStyle(isSelected ? Color.background : Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accent : Color.surface)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? Color.accent : Color.divider,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
