import SwiftUI

// Three-wheel duration picker (Hours / Minutes / Seconds) for
// setting a race target time. Used by:
//   • RaceStartView — pre-race goal for the next session
//   • RaceEventEditSheet — saved target for an upcoming HYROX event
//
// Two-way bound to a `TimeInterval?` so callers can clear the
// target by tapping the destructive "Clear target" button. Save
// returns the picked duration (or nil if the user dialed it down
// to zero, which is functionally "no target").
//
// Lives in its own file rather than nested in RaceStartView so
// every screen that needs a target picker can use it without
// re-inventing the wheel layout. Originally was nested-private
// in RaceStartView; moved here when RaceEventEditSheet needed it.
//
// Guarded `#if canImport(UIKit)` because Picker(.wheel) +
// NavigationStack toolbar is iOS / iPadOS specific styling.
#if canImport(UIKit)
struct TargetDurationPickerSheet: View {
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
