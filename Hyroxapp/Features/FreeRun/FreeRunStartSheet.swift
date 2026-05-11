import SwiftUI

#if canImport(UIKit)

// Pre-run configuration sheet for Free Run.
//
// Picks two things and ONLY two things — anything more would clutter
// the start surface for what's meant to be a "tap, tap, go" experience:
//
//   1. Location type — indoor (pedometer-only) or outdoor (GPS + ped).
//   2. Split unit — miles or km.
//
// Both choices are committed at start time and frozen for the run's
// lifetime. The athlete who runs outdoors today + indoor on a treadmill
// tomorrow just picks the right card each time.
//
// Hands the picked combination back via a single `onStart` callback so
// the parent (CustomWorkoutBuilderView) controls dismissal and the
// downstream FreeRunView push.
//
// Visual structure: two large cards for indoor/outdoor (with SF Symbol
// hero + subtitle hinting at the privacy / battery cost), then a
// segmented control for the unit, then a coral primary CTA. Same
// language as RaceStartView's primary surface.
struct FreeRunStartSheet: View {

    let onStart: (FreeRunLocationType, FreeRunSplitUnit) -> Void

    @Environment(\.dismiss) private var dismiss

    // Default to outdoor since the most common dogfood case is "the
    // athlete tapped Free Run because they're heading out for a run."
    // Indoor is a more deliberate pick (treadmill day).
    @State private var selectedLocation: FreeRunLocationType = .outdoor

    // Default to miles for the US-based cohort. Locale-aware default
    // is a Phase-4 polish — for v1 we honor the explicit user pick
    // on every start.
    @State private var selectedUnit: FreeRunSplitUnit = .mile

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        introCopy

                        locationSection

                        unitSection

                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                }

                // Pinned start CTA. Bottom of the sheet so the
                // thumb lands on it without travelling — the sheet
                // is short enough that we don't strictly need a
                // pinned button, but mirroring the race-start
                // pattern keeps muscle memory consistent.
                VStack {
                    Spacer()
                    startButton
                        .padding(.horizontal, Layout.screenMargin)
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle("Free Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }

    // MARK: - Sections

    // Intro copy at the top of the sheet — sets the expectation
    // that this is a different mode from a HYROX race. Two lines,
    // no preamble; athletes mid-warmup don't have patience for
    // marketing.
    private var introCopy: some View {
        VStack(spacing: 4) {
            Text("Just run. We'll track distance, pace, and HR.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
            Text("No HYROX scoring. No map. Just the run.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    // Two big tappable cards — indoor / outdoor — laid side-by-side.
    // Each card is large enough to read at-a-glance with sweaty
    // hands; the chosen card pops in coral, unchosen dims.
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Where")

            HStack(spacing: 12) {
                ForEach(FreeRunLocationType.allCases) { type in
                    locationCard(for: type)
                }
            }
        }
    }

    private func locationCard(for type: FreeRunLocationType) -> some View {
        let isSelected = (type == selectedLocation)
        return Button {
            Haptics.impact(.light)
            withAnimation(.smooth(duration: 0.2)) {
                selectedLocation = type
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.iconName)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.onAccent : Color.accent)
                    .frame(maxWidth: .infinity)

                Text(type.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.onAccent : Color.textPrimary)

                Text(type.subtitle)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.onAccent.opacity(0.85) : Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(isSelected ? Color.accent : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(
                        isSelected ? Color.clear : Color.divider,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.pressableCard)
    }

    // Compact segmented control for mile / km. Smaller surface
    // than the location cards because the choice is lighter — most
    // users will pick a unit once and rarely switch.
    private var unitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Splits")

            Picker("Splits", selection: $selectedUnit) {
                ForEach(FreeRunSplitUnit.allCases) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // Primary CTA — same coral gradient + chevron pattern as
    // the race start button. Tapping fires onStart with the
    // selected combo; the parent dismisses + pushes the live
    // run view.
    private var startButton: some View {
        Button {
            Haptics.impact(.heavy)
            onStart(selectedLocation, selectedUnit)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .heavy))
                Text("Start Free Run")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            // 60pt full-bleed CTA → sheet tier (22pt) per the v1
            // two-tier radius hierarchy.
            .background(
                RoundedRectangle(cornerRadius: Layout.sheetCornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.accent, Color.accent.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .shadow(color: Color.accent.opacity(0.4), radius: 18, y: 0)
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
            .padding(.leading, 4)
    }
}

#endif
