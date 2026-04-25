import SwiftUI

// Modal sheet for entering / editing per-station performance
// metadata: weight in kg, reps completed, and RPE 1-10. The
// killer HYROX-specific feature — every other "fitness app"
// treats a Sled Push as just a Sled Push, but a 4:32 push at
// 80kg and a 4:32 at 152kg are different universes.
//
// Pre-fills with division-canonical race-day values where they
// exist (Sled Push 152kg for Men's Open, etc.) so a one-tap-OK
// flow logs at-race-weight by default. Athletes who train at a
// different weight just adjust the stepper and save.
//
// Three independently-cleared fields. Tap "Clear" on a row to
// set that single field back to nil — useful when an athlete
// realizes they don't actually know their RPE, or wants to
// remove a previously-logged weight.
//
// Save callback flushes all three values together. Caller
// decides what to do with them — RaceSummaryView routes
// through the engine via VM, RaceDetailView mutates Race.splits
// directly via @Bindable.
//
// Run + erg stations have nil race weight; for those we hide
// the weight row entirely (they're bodyweight / fixed-resistance,
// no weight to track) and only show reps + RPE if reps make
// sense (basically just RPE for runs).
//
// Guarded `#if !os(watchOS) && canImport(UIKit)`.
#if !os(watchOS) && canImport(UIKit)
struct StationStatsSheet: View {

    let split: Split
    let division: Division
    let onSave: (_ weightKg: Double?, _ reps: Int?, _ rpe: Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    // Working state — initialized from the split's current values
    // (or the division-canonical defaults when the split has none
    // yet, so first-time entry is one tap on Save).
    @State private var weightKg: Double
    @State private var weightEnabled: Bool
    @State private var reps: Int
    @State private var repsEnabled: Bool
    @State private var rpe: Int
    @State private var rpeEnabled: Bool

    init(
        split: Split,
        division: Division,
        onSave: @escaping (_ weightKg: Double?, _ reps: Int?, _ rpe: Int?) -> Void
    ) {
        self.split = split
        self.division = division
        self.onSave = onSave

        // Weight: existing value > division-canonical default > 0.
        // weightEnabled tracks whether the field is "set" — if the
        // split came in with nil and there's no race-day weight
        // for this station (runs / ergs), the row hides itself
        // entirely (see body).
        let canonicalWeight = division.raceWeight(for: split.station)
        let initialWeight = split.weightKg ?? canonicalWeight ?? 0
        _weightKg = State(initialValue: initialWeight)
        _weightEnabled = State(initialValue: split.weightKg != nil)

        // Reps: existing > division wallBallCount for wall balls,
        // otherwise 0 as a reasonable starting point.
        let canonicalReps = (split.station == .wallBalls) ? division.wallBallCount : 0
        _reps = State(initialValue: split.repsCompleted ?? canonicalReps)
        _repsEnabled = State(initialValue: split.repsCompleted != nil)

        _rpe = State(initialValue: split.rpe ?? 7)  // 7 = "hard" — common race-station RPE
        _rpeEnabled = State(initialValue: split.rpe != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                if division.raceWeight(for: split.station) != nil {
                    weightSection
                }
                repsSection
                rpeSection
            }
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("Station Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        commit()
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    // Caps-label header showing which station + duration the
    // athlete is editing. Reminds them what they're tagging stats
    // onto — the form below has no other station-identifying cue.
    private var headerSection: some View {
        Section {
            HStack {
                Text(split.station.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(RaceStats.format(split.duration))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accent)
            }
            .listRowBackground(Color.surface)
        }
    }

    private var weightSection: some View {
        Section {
            Toggle("Weight logged", isOn: $weightEnabled)
                .listRowBackground(Color.surface)

            if weightEnabled {
                Stepper(
                    value: $weightKg,
                    in: 0...300,
                    step: weightStepSize
                ) {
                    HStack {
                        Text("Weight")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(weightDisplay)
                            .monospacedDigit()
                            .foregroundStyle(Color.accent)
                            .fontWeight(.semibold)
                    }
                }
                .listRowBackground(Color.surface)

                // Race-day reference + mismatch warning. Helps the
                // athlete spot "I'm 22kg under race weight" without
                // mental math. Hidden when no canonical weight
                // exists (runs / ergs).
                if let canonical = division.raceWeight(for: split.station) {
                    HStack {
                        Text("Race weight (\(division.displayName))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(format(weight: canonical))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                abs(weightKg - canonical) < 0.5
                                    ? Color.success
                                    : Color.textTertiary
                            )
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("Weight")
        }
    }

    private var repsSection: some View {
        Section {
            Toggle("Reps logged", isOn: $repsEnabled)
                .listRowBackground(Color.surface)

            if repsEnabled {
                Stepper(value: $reps, in: 0...500, step: 1) {
                    HStack {
                        Text("Reps")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(reps)")
                            .monospacedDigit()
                            .foregroundStyle(Color.accent)
                            .fontWeight(.semibold)
                    }
                }
                .listRowBackground(Color.surface)

                // Show prescribed reps for stations where it varies
                // by division (wall balls). Runs and other distance-
                // based stations don't have a rep target.
                if split.station == .wallBalls {
                    HStack {
                        Text("Race reps (\(division.displayName))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(division.wallBallCount)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                reps == division.wallBallCount
                                    ? Color.success
                                    : Color.textTertiary
                            )
                    }
                    .listRowBackground(Color.surface)
                }
            }
        } header: {
            Text("Reps")
        }
    }

    private var rpeSection: some View {
        Section {
            Toggle("RPE logged", isOn: $rpeEnabled)
                .listRowBackground(Color.surface)

            if rpeEnabled {
                Stepper(value: $rpe, in: 1...10, step: 1) {
                    HStack {
                        Text("RPE")
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(rpe) / 10")
                            .monospacedDigit()
                            .foregroundStyle(Color.accent)
                            .fontWeight(.semibold)
                    }
                }
                .listRowBackground(Color.surface)

                Text(rpeDescriptor(rpe))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .listRowBackground(Color.surface)
            }
        } header: {
            Text("Effort")
        } footer: {
            Text("Rate of Perceived Exertion 1–10. Subjective scale — \"easy\" to \"all-out.\"")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Helpers

    // Step size for the weight stepper — we use 0.5 kg for stations
    // where small adjustments matter (wall balls 4 → 6 kg) and 2 kg
    // for sleds where gym increments are typically 5kg plates.
    // Compromise: 1 kg works well across both.
    private var weightStepSize: Double { 1 }

    // Display string for the weight value. Adds "per hand" suffix
    // for Farmers Carry so the unit matches reality.
    private var weightDisplay: String {
        let base = format(weight: weightKg)
        return Division.isPerHandStation(split.station) ? "\(base) per hand" : base
    }

    private func format(weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight)) kg"
        }
        return String(format: "%.1f kg", weight)
    }

    // Quick-glance descriptor for the RPE number. Helps athletes
    // who haven't internalized the 1-10 scale ground their answer
    // ("8 means I could've done one or two more reps").
    private func rpeDescriptor(_ value: Int) -> String {
        switch value {
        case 1...2:  return "Very easy — recovery pace"
        case 3...4:  return "Easy — could go all day"
        case 5...6:  return "Moderate — conversational"
        case 7:      return "Hard — could only chat in short bursts"
        case 8:      return "Very hard — could've done 1–2 more reps"
        case 9:      return "Extremely hard — barely finished"
        case 10:     return "Maximal — could not have done any more"
        default:     return ""
        }
    }

    // Translate the working state into the three optionals the
    // save callback expects. Disabled toggles → nil.
    private func commit() {
        onSave(
            weightEnabled ? weightKg : nil,
            repsEnabled ? reps : nil,
            rpeEnabled ? rpe : nil
        )
    }
}
#endif
