import SwiftUI

// Pre-race screen: HYROX header, Solo/Duo toggle (Duo greyed out with
// "Coming soon" per CLAUDE.md §4.5 until Supabase Realtime sync lands in
// v2), the big Start Race button (runs the full 16-segment official
// race), and a secondary "Custom Workout" entry point that opens the
// builder sheet.
//
// Takes the owning `RaceViewModel` as a parameter rather than creating its
// own — the VM lives for the entire race flow (pre → in-progress → summary),
// and is owned by `RaceView`.
struct RaceStartView: View {
    let viewModel: RaceViewModel

    // Drives the Custom Workout Builder sheet. Stays false until the
    // user explicitly taps the secondary button below the primary
    // Start Race CTA.
    @State private var isBuilderPresented = false

    // Drives the target-time picker sheet.
    @State private var isTargetPickerPresented = false

    // Athlete's finish-time goal for the next race they start.
    // Defaults to 1:30:00 — the canonical HYROX target finish — so the
    // common case (elite/competitive athlete) is zero-config. Setting
    // to nil clears the goal (race runs without a target).
    // Persists for this screen's lifetime; resets on app restart.
    @State private var targetDuration: TimeInterval? = 90 * 60

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("HYROX")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Color.textPrimary)
                Text("Race Mode")
                    .capsLabelStyle()
            }

            Spacer()

            modeToggle

            targetRow

            VStack(spacing: 12) {
                // Primary: full 16-segment official HYROX race. Unchanged
                // zero-config path.
                Button {
                    Haptics.impact(.medium)
                    viewModel.startRace(targetDuration: targetDuration)
                } label: {
                    Text("Start Race")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.raceButtonHeight)
                        .background(Color.accent)
                        .foregroundStyle(Color.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                }

                // Secondary: opens the builder sheet. Styled as a muted
                // outline button so it reads as "advanced / alternative"
                // without competing with the primary CTA.
                Button {
                    isBuilderPresented = true
                } label: {
                    Text("Custom Workout")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: Layout.standardButtonHeight + 8)
                        .foregroundStyle(Color.textPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                                .stroke(Color.divider, lineWidth: 1)
                        )
                }
            }
            .padding(.bottom, 24)
        }
        #if canImport(UIKit)
        .sheet(isPresented: $isBuilderPresented) {
            CustomWorkoutBuilderView { sequence in
                Haptics.impact(.medium)
                viewModel.startRace(sequence: sequence, targetDuration: targetDuration)
            }
        }
        .sheet(isPresented: $isTargetPickerPresented) {
            TargetDurationPickerSheet(
                duration: $targetDuration,
                isPresented: $isTargetPickerPresented
            )
            .preferredColorScheme(.dark)
        }
        #endif
    }

    // Tappable row showing the current target. When set, reads
    // "TARGET · 1:30:00"; when cleared, reads "TARGET · Not set".
    // The whole row is one tap target to stay forgiving on sweaty
    // fingers pre-race.
    private var targetRow: some View {
        Button {
            isTargetPickerPresented = true
        } label: {
            HStack {
                Text("Target")
                    .capsLabelStyle()
                Spacer()
                Text(targetDuration.map(RaceStats.format) ?? "Not set")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Layout.cardPadding)
            .frame(height: Layout.standardButtonHeight + 8)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 12) {
            modeChip(.solo)
            modeChip(.duo)
        }
    }

    // Sheet with a countdown-style duration picker for setting a
    // finish-time goal. `DatePicker` with `.countDownTimer` is the
    // native duration picker — hour/minute wheels, standard iOS look,
    // no custom UI to maintain. Bound via `Binding<Date>` because
    // that's what DatePicker takes; we convert to/from TimeInterval
    // at the boundary.
    //
    // A "Clear target" button at the bottom unsets the goal entirely
    // for athletes who just want to show up and move without a timer
    // breathing down their neck.
    #if canImport(UIKit)
    private struct TargetDurationPickerSheet: View {
        @Binding var duration: TimeInterval?
        @Binding var isPresented: Bool

        // DatePicker binds to a Date. We interpret that Date's
        // `timeIntervalSinceReferenceDate` (offset from a fixed
        // anchor) as the countdown duration. On open, seed from
        // the current TimeInterval; on Save, read back.
        @State private var draftDate: Date = {
            // Default: 1:30:00 if no duration set, else existing.
            Date(timeIntervalSinceReferenceDate: 90 * 60)
        }()

        var body: some View {
            NavigationStack {
                ZStack {
                    Color.background.ignoresSafeArea()

                    VStack(spacing: 24) {
                        DatePicker(
                            "Target time",
                            selection: $draftDate,
                            displayedComponents: [.hourAndMinute]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
                        .frame(maxHeight: 220)
                        .padding(.top, 24)

                        Button(role: .destructive) {
                            duration = nil
                            isPresented = false
                        } label: {
                            Text("Clear target")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: Layout.standardButtonHeight)
                        }
                        .padding(.horizontal, Layout.screenMargin)

                        Spacer()
                    }
                }
                .navigationTitle("Target time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isPresented = false }
                            .foregroundStyle(Color.textPrimary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            // Extract hours + minutes from the draft
                            // and convert back to TimeInterval. GMT
                            // interpretation above ensures the raw
                            // components are what the wheel showed.
                            let comps = Calendar(identifier: .gregorian)
                                .dateComponents(in: TimeZone(secondsFromGMT: 0) ?? .current,
                                                from: draftDate)
                            let hours = comps.hour ?? 0
                            let minutes = comps.minute ?? 0
                            let total = TimeInterval(hours * 3600 + minutes * 60)
                            duration = total > 0 ? total : nil
                            isPresented = false
                        }
                        .foregroundStyle(Color.accent)
                    }
                }
            }
            .onAppear {
                // Seed the wheel with the current duration (or default
                // 1:30:00 if none set). GMT timezone so the hours we
                // pass in are what the picker shows — no offset drift.
                let seconds = duration ?? (90 * 60)
                var comps = DateComponents()
                comps.hour = Int(seconds) / 3600
                comps.minute = (Int(seconds) % 3600) / 60
                if let tz = TimeZone(secondsFromGMT: 0),
                   let seeded = Calendar(identifier: .gregorian).date(from: comps) {
                    _ = tz  // silence unused if all else goes sideways
                    draftDate = seeded
                }
            }
        }
    }
    #endif

    private func modeChip(_ mode: RaceMode) -> some View {
        // Solo is the only selectable mode in v0.1; Duo is laid out now so
        // the pattern exists in v2 when Supabase Realtime wires it up.
        let isSelected = (mode == .solo)
        let available = mode.isAvailable

        return VStack(spacing: 4) {
            Text(mode.displayName)
                .font(.system(size: 18, weight: .semibold))
            if !available {
                Text("Coming soon")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(isSelected ? Color.surfaceElevated : Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .strokeBorder(isSelected ? Color.accent : Color.divider, lineWidth: 1)
        )
        .foregroundStyle(available ? Color.textPrimary : Color.textTertiary)
        .opacity(available ? 1.0 : 0.55)
    }
}
