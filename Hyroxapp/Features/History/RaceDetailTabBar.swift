import SwiftUI

// §16 Layer 3 — five-tab segmented bar for the post-race detail
// view. Sits below the pinned hero, tabs scroll horizontally
// when the screen is too narrow to fit all five at once (which
// it usually is on a 6.1" iPhone).
//
// Each tab is a tappable button with caps-label typography
// matching the rest of the app's section headers. The selected
// tab gets an underline accent + brighter text; unselected tabs
// dim to textTertiary so the active tab reads at a glance.
//
// Tap fires a soft haptic so the bar feels reactive even on
// fast finger swipes between tabs.
struct RaceDetailTabBar: View {

    @Binding var selection: RaceDetailTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(RaceDetailTab.allCases) { tab in
                    button(for: tab)
                }
            }
            .padding(.horizontal, Layout.screenMargin)
        }
        .background(
            // Subtle bottom hairline divides the tab bar from
            // the scrolling tab content below. Matches the
            // navigation-style separator pattern.
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.divider)
                    .frame(height: 0.5)
            }
        )
    }

    private func button(for tab: RaceDetailTab) -> some View {
        let isSelected = (tab == selection)
        return Button {
            Haptics.impact(.light)
            withAnimation(reduceMotion ? .none : .smooth(duration: 0.25)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Text(tab.title.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                // Underline accent on selected tab. Coral so
                // the indicator picks up the brand language.
                Rectangle()
                    .fill(isSelected ? Color.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// Five-tab enum per §16 spec. CaseIterable so the tab bar can
// iterate; Hashable so the bound selection works with @State.
enum RaceDetailTab: String, CaseIterable, Identifiable, Hashable {
    case overview
    case runs
    case stations
    case hr
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .runs:     return "Runs"
        case .stations: return "Stations"
        case .hr:       return "HR"
        case .story:    return "Story"
        }
    }
}
