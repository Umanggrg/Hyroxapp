import SwiftUI
import SwiftData

// Edit sheet for a single RaceEvent — used both for creating a
// new upcoming race and for editing an existing one. The caller
// passes either the existing event (edit mode) or nil (create
// mode); the sheet handles both with the same form layout.
//
// Form sections:
//   • Race details (name, date, location)
//   • Competition (division, target time)
//   • Delete button when editing an existing event
//
// Save persists via the injected modelContext. Dismiss on save
// or cancel. Date stored as start-of-day in the user's calendar
// so countdown math is calendar-day-accurate.
//
// Guarded `#if !os(watchOS) && canImport(UIKit)`.
#if !os(watchOS) && canImport(UIKit)
struct RaceEventEditSheet: View {

    let existing: RaceEvent?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Working state — initialized from the existing event or
    // sensible defaults for a new one. SwiftUI doesn't let
    // @State be initialized from a stored property at declaration
    // time, so we lean on init() to seed each field.
    @State private var name: String
    @State private var date: Date
    @State private var location: String
    @State private var division: Division
    @State private var targetDuration: TimeInterval?

    @State private var isShowingTargetPicker = false
    @State private var isShowingDeleteConfirm = false

    init(existing: RaceEvent?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _date = State(initialValue: existing?.date ?? Self.defaultRaceDate)
        _location = State(initialValue: existing?.location ?? "")
        _division = State(initialValue: existing?.resolvedDivision ?? .mensOpen)
        _targetDuration = State(initialValue: existing?.targetDuration)
    }

    // Default date for a new event: 8 weeks out at 9am — typical
    // training-block window for an athlete eyeing a HYROX. Saves
    // a couple of taps for the common "I'm planning my next
    // race" case.
    private static var defaultRaceDate: Date {
        let cal = Calendar.current
        let date = cal.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
        return cal.startOfDay(for: date)
    }

    // Body deliberately stays thin. The Swift type-checker timed
    // out on an earlier monolithic version where the toolbar +
    // ternary title + sheet + alert all chained on the same
    // `Form { ... }` expression. Breaking each concern into its
    // own computed property / builder gives the inferencer
    // bite-sized chunks it can resolve quickly.
    var body: some View {
        NavigationStack {
            formContent
        }
        .preferredColorScheme(.dark)
    }

    private var formContent: some View {
        Form {
            detailsSection
            competitionSection
            if existing != nil {
                deleteSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.background)
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { editorToolbar }
        .sheet(isPresented: $isShowingTargetPicker) {
            TargetDurationPickerSheet(
                duration: $targetDuration,
                isPresented: $isShowingTargetPicker
            )
            .preferredColorScheme(.dark)
        }
        .alert(
            "Delete this race?",
            isPresented: $isShowingDeleteConfirm,
            actions: { deleteAlertButtons },
            message: { deleteAlertMessage }
        )
    }

    // Title resolved as a String let so the .navigationTitle
    // modifier doesn't have to type-check a ternary inline.
    private var navigationTitleText: String {
        existing == nil ? "New Race" : "Edit Race"
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(Color.textSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            saveButton
        }
    }

    private var saveButton: some View {
        // Color resolved on a separate line so the modifier chain
        // type-checks fast. Same pattern that fixed the parent body.
        let saveColor: Color = canSave ? Color.accent : Color.textTertiary
        return Button("Save") {
            save()
            dismiss()
        }
        .fontWeight(.bold)
        .foregroundStyle(saveColor)
        .disabled(!canSave)
    }

    @ViewBuilder
    private var deleteAlertButtons: some View {
        Button("Cancel", role: .cancel) { }
        Button("Delete", role: .destructive) {
            deleteExisting()
            dismiss()
        }
    }

    private var deleteAlertMessage: some View {
        Text("Removes this upcoming race from your training plan. Doesn't affect any of your race history.")
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section {
            TextField("Race name (e.g. HYROX Miami)", text: $name)
                .listRowBackground(Color.surface)

            DatePicker(
                "Race day",
                selection: $date,
                displayedComponents: .date
            )
            .listRowBackground(Color.surface)

            TextField("Location (optional)", text: $location)
                .listRowBackground(Color.surface)
        } header: {
            Text("Race details")
        }
    }

    private var competitionSection: some View {
        Section {
            Picker("Division", selection: $division) {
                ForEach(Division.allCases) { d in
                    Text(d.displayName).tag(d)
                }
            }
            .listRowBackground(Color.surface)

            // Target time: tappable row that opens the existing
            // H:M:S picker we use elsewhere. Same component the
            // pre-race screen uses, so the UX is consistent.
            Button {
                isShowingTargetPicker = true
            } label: {
                HStack {
                    Text("Target time")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(targetDuration.map(RaceStats.format) ?? "Not set")
                        .monospacedDigit()
                        .foregroundStyle(targetDuration == nil ? Color.textTertiary : Color.accent)
                }
            }
            .listRowBackground(Color.surface)
        } header: {
            Text("Competition")
        } footer: {
            Text("Division drives wall ball reps and race-day weight defaults. Target time is optional but powers the countdown banner.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isShowingDeleteConfirm = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete this race")
                    Spacer()
                }
            }
            .listRowBackground(Color.surface)
        }
    }

    // MARK: - Persistence

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        // Snap date to start-of-day so daysUntil math is
        // calendar-day-accurate regardless of when in the day
        // the user picked.
        let snappedDate = Calendar.current.startOfDay(for: date)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)

        if let existing {
            existing.name = trimmedName
            existing.date = snappedDate
            existing.location = trimmedLocation
            existing.resolvedDivision = division
            existing.targetDuration = targetDuration
        } else {
            let event = RaceEvent(
                name: trimmedName,
                date: snappedDate,
                division: division,
                targetDuration: targetDuration,
                location: trimmedLocation
            )
            modelContext.insert(event)
        }
        try? modelContext.save()
    }

    private func deleteExisting() {
        guard let existing else { return }
        modelContext.delete(existing)
        try? modelContext.save()
    }
}
#endif
