import SwiftUI
import SwiftData

// Custom Workout Builder — sheet presented from RaceStartView that lets
// an athlete compose their own sequence of HYROX stations for today's
// training, instead of running the full 16-segment official race.
//
// Why this exists: an athlete might want "three 1km runs and a sled
// push circuit" on a conditioning day, or "wall balls × 3" when their
// squat is the weak link. Rather than forcing the full simulation, we
// let the user build exactly the sequence they'll do. The engine is
// already sequence-parameterized (see RaceEngine.init(sequence:)) so
// the plumbing this wires up is mostly UI.
//
// State model: the sheet owns a local draft sequence (`@State var
// sequence`). Save turns the draft into a persisted `WorkoutTemplate`
// the user can re-load later; Load opens the picker of existing
// templates and replaces the current draft with the chosen sequence.
// No "Save As" semantic today — saving always creates a new template,
// and editing an existing one is delete + re-save.
#if canImport(UIKit)
struct CustomWorkoutBuilderView: View {

    // Fires when the athlete taps Start, carrying the built sequence
    // back up to RaceView → RaceViewModel.startRace(sequence:). The
    // sheet dismisses itself before calling the callback, so the
    // race UI takes over cleanly.
    let onStart: ([Station]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // All saved templates, newest first. Drives the Load button's
    // enabled state (disabled when empty) and populates the picker
    // sheet when opened.
    @Query(sort: [SortDescriptor(\WorkoutTemplate.createdAt, order: .reverse)])
    private var templates: [WorkoutTemplate]

    // Starts empty. The "Add Station" CTA is the primary affordance
    // for building the workout.
    @State private var sequence: [Station] = []

    // Drives the station-picker sheet. Presented as a nested sheet
    // instead of a NavigationLink so the builder stays a single
    // compact screen — reordering-heavy UI is easier to use without
    // navigation push/pop.
    @State private var isPickerPresented = false

    // Drives the saved-template picker sheet. Opened from the Load
    // toolbar item; selecting a template copies its sequence into
    // the local draft state and dismisses.
    @State private var isTemplatePickerPresented = false

    // Drives the Save-name alert. When true, shows a text-field alert
    // prompting for the template name.
    @State private var isSaveAlertPresented = false
    @State private var saveDraftName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    if sequence.isEmpty {
                        emptyState
                    } else {
                        sequenceList
                    }

                    addButton
                        .padding(.horizontal, Layout.screenMargin)
                        .padding(.top, 12)

                    startButton
                        .padding(.horizontal, Layout.screenMargin)
                        .padding(.vertical, 16)
                }
            }
            .navigationTitle("Custom Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
                // Save + Load live on the trailing edge. Load first
                // (left of Save in LTR) because loading an existing
                // template is the faster path; Save is the lower-
                // frequency action.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            isTemplatePickerPresented = true
                        } label: {
                            Image(systemName: "tray.and.arrow.up")
                        }
                        .disabled(templates.isEmpty)
                        .accessibilityLabel("Load template")

                        Button {
                            saveDraftName = ""
                            isSaveAlertPresented = true
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .disabled(sequence.isEmpty)
                        .accessibilityLabel("Save as template")
                    }
                    .foregroundStyle(Color.textPrimary)
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                StationPickerSheet { picked in
                    sequence.append(picked)
                    isPickerPresented = false
                }
                .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $isTemplatePickerPresented) {
                WorkoutTemplatePickerSheet { picked in
                    // Load replaces the current draft wholesale.
                    // We don't auto-start — the athlete might want
                    // to tweak the loaded sequence first.
                    sequence = picked.sequence
                    isTemplatePickerPresented = false
                }
                .preferredColorScheme(.dark)
            }
            .alert("Save template", isPresented: $isSaveAlertPresented) {
                TextField("Name", text: $saveDraftName)
                    .textInputAutocapitalization(.words)
                Button("Save", action: saveTemplate)
                    .disabled(saveDraftName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Give this workout a name so you can run it again later.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Persistence

    // Create and insert a new WorkoutTemplate from the current draft
    // sequence. No-op if the sequence is empty (shouldn't happen
    // because the Save button is disabled in that state, but defensive).
    private func saveTemplate() {
        let trimmed = saveDraftName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !sequence.isEmpty else { return }

        let template = WorkoutTemplate(name: trimmed, sequence: sequence)
        modelContext.insert(template)
        try? modelContext.save()

        // Clear the draft name so next open of the alert starts fresh.
        saveDraftName = ""
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("Build your workout")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("Pick the stations you want in the order you want them. Repeat stations as many times as you like.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // Editable sequence list. `List` with `.onMove` + `.onDelete`
    // handles drag-to-reorder and swipe-to-delete for free; the
    // EditButton in the toolbar activates reorder handles.
    private var sequenceList: some View {
        List {
            Section {
                ForEach(Array(sequence.enumerated()), id: \.offset) { index, station in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 24, alignment: .leading)
                        Text(station.displayName)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(station.target)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.surface)
                }
                .onMove { indices, newOffset in
                    sequence.move(fromOffsets: indices, toOffset: newOffset)
                }
                .onDelete { indices in
                    sequence.remove(atOffsets: indices)
                }
            } header: {
                Text("Sequence · \(sequence.count) station\(sequence.count == 1 ? "" : "s")")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.background)
        .environment(\.editMode, .constant(.active))  // always show reorder handles
    }

    // MARK: - Actions

    private var addButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Add Station")
            }
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.standardButtonHeight + 8)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surfaceElevated)
            )
        }
    }

    private var startButton: some View {
        Button {
            let built = sequence
            dismiss()
            onStart(built)
        } label: {
            Text(sequence.isEmpty ? "Add a Station to Start" : "Start Workout")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(sequence.isEmpty ? Color.accentDim : Color.accent)
                .foregroundStyle(Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        }
        .disabled(sequence.isEmpty)
    }
}

// MARK: - Station Picker

// Secondary sheet that shows the 9 canonical HYROX station types in a
// tappable list. Tap one → it gets appended to the builder's sequence
// and this sheet dismisses. Repeated taps = repeated stations, which is
// the intended behavior (building "3× Sled Push" shouldn't take 3 trips
// through a nav stack).
private struct StationPickerSheet: View {
    let onPick: (Station) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                List {
                    ForEach(Station.canonicalPickerOptions, id: \.rawValue) { station in
                        Button {
                            onPick(station)
                        } label: {
                            HStack {
                                Text(station.displayName)
                                    .font(.body)
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Text(station.target)
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .listRowBackground(Color.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.background)
            }
            .navigationTitle("Add Station")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }
}

// MARK: - Template Picker

// Nested sheet that lists the athlete's saved WorkoutTemplate rows.
// Tap a row → the onPick callback fires with the chosen template and
// this sheet dismisses. Swipe-to-delete removes a template permanently.
//
// Private to the builder because it's only useful in the "load a saved
// workout" flow; if template browsing becomes relevant elsewhere (e.g.
// a dedicated "My Workouts" tab), promote it to Features/Workouts/.
private struct WorkoutTemplatePickerSheet: View {
    let onPick: (WorkoutTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\WorkoutTemplate.createdAt, order: .reverse)])
    private var templates: [WorkoutTemplate]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                if templates.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .navigationTitle("My Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }

    // Shown when the athlete hasn't saved any templates yet. Points
    // them at the Save button in the builder's toolbar.
    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.textTertiary)
            Text("No saved workouts")
                .font(.sectionHeader)
                .foregroundStyle(Color.textPrimary)
            Text("Build a workout and tap the save icon to store it here for reuse.")
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var list: some View {
        List {
            ForEach(templates) { template in
                Button {
                    onPick(template)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                            Text("\(template.stationCount) station\(template.stationCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.surface)
            }
            .onDelete { indices in
                for i in indices {
                    modelContext.delete(templates[i])
                }
                try? modelContext.save()
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.background)
    }
}

#Preview {
    CustomWorkoutBuilderView { _ in }
}
#endif
