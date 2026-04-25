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

    // Sheet with a duration picker for setting a finish-time goal.
    //
    // Implementation note: SwiftUI's `DatePicker(.hourAndMinute)` is a
    // TIME-OF-DAY picker (6:45 PM), not a duration picker. Apple
    // doesn't ship a native countdown-style DatePicker for SwiftUI on
    // iPhone, so we build a real duration picker with three wheel
    // Pickers (hours, minutes, seconds) bound to Int state. Save
    // converts the three components to a TimeInterval.
    //
    // A "Clear target" button at the bottom unsets the goal entirely
    // for athletes who just want to show up and move without a timer
    // breathing down their neck.
    #if canImport(UIKit)
    private struct TargetDurationPickerSheet: View {
        @Binding var duration: TimeInterval?
        @Binding var isPresented: Bool

        // Three separate components so each wheel spins independently.
        // Upper bound on hours (10) is generous — a 10h HYROX would
        // be a miracle. Bumping later is a 1-line change if needed.
        @State private var hours: Int = 1
        @State private var minutes: Int = 30
        @State private var seconds: Int = 0

        private let hoursRange = 0..<10
        private let minutesRange = 0..<60
        private let secondsRange = 0..<60

        var body: some View {
            NavigationStack {
                ZStack {
                    Color.background.ignoresSafeArea()

                    VStack(spacing: 20) {
                        // Three wheel pickers side by side. Labels below
                        // each column identify the unit so the athlete
                        // reads duration, not clock time, at a glance.
                        HStack(spacing: 0) {
                            wheelColumn(
                                title: "Hours",
                                selection: $hours,
                                range: hoursRange
                            )
                            wheelColumn(
                                title: "Minutes",
                                selection: $minutes,
                                range: minutesRange
                            )
                            wheelColumn(
                                title: "Seconds",
                                selection: $seconds,
                                range: secondsRange
                            )
                        }
                        .frame(maxHeight: 200)
                        .padding(.top, 16)

                        // Live preview of what the picker currently
                        // represents — reinforces "this is a duration"
                        // framing with the MM:SS / H:MM:SS format the
                        // rest of the app uses.
                        Text(RaceStats.format(currentTotal))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.textPrimary)

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
                            let total = currentTotal
                            // A duration of 0 is effectively "no target"
                            // — no athlete sets a 0:00:00 goal.
                            duration = total > 0 ? total : nil
                            isPresented = false
                        }
                        .foregroundStyle(Color.accent)
                    }
                }
            }
            .onAppear(perform: seedFromBinding)
        }

        // Computed total used both for the live preview text and on
        // Save. Single source of truth so the preview and the persisted
        // value can't ever drift.
        private var currentTotal: TimeInterval {
            TimeInterval(hours * 3600 + minutes * 60 + seconds)
        }

        // On first appear, split the incoming duration back out into
        // three Ints for the wheels. Defaults to 1:30:00 when the
        // caller hasn't set a target yet — matches the canonical HYROX
        // finish benchmark.
        private func seedFromBinding() {
            let total = Int(duration ?? (90 * 60))
            hours = total / 3600
            minutes = (total % 3600) / 60
            seconds = total % 60
        }

        // Single column renderer — keeps the three wheels visually
        // consistent without repeating a stack of modifiers.
        private func wheelColumn(
            title: String,
            selection: Binding<Int>,
            range: Range<Int>
        ) -> some View {
            VStack(spacing: 4) {
                Picker(title, selection: selection) {
                    ForEach(range, id: \.self) { value in
                        Text(String(format: "%02d", value))
                            .foregroundStyle(Color.textPrimary)
                            .tag(value)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Text(title.lowercased())
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
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
