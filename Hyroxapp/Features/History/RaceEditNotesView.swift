import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
import PhotosUI
#endif

// Wireframe §04.2 Edit-Notes screen. Presented from the existing
// pencil toolbar button (and from the Edit Notes overflow row).
// Layout, top → bottom:
//   • Header — back ← / "Edit notes" centered title / Save coral
//   • CAPTION caps + multi-line caption editor
//   • CONDITIONS caps + rows for Gym, Sled weight (sticky), Felt,
//     Slept (last night)
//   • PHOTOS caps + photo row (existing + Photos picker tile)
//
// Race fields:
//   • caption → race.notes (existing)
//   • Gym → race.gym
//   • Felt → race.feltRating (1-10)
//   • Sleep → race.sleepHoursLast
//   • Sled weight → derived from the heaviest split's weightKg
//     (sled-push / sled-pull splits). Display-only here; the
//     athlete can edit per-split weight in the existing
//     StationStatsSheet (referenced from RaceDetailView).
struct RaceEditNotesView: View {

    @Bindable var race: Race
    let onDismiss: () -> Void

    // Wireframe §05.2 — "where I trained" auto-fill. When the
    // race has no gym set yet, pre-seed the Gym text field with
    // the athlete's profile-level home gym. The user can edit
    // before saving; if they save unchanged, this becomes
    // race.gym. Passed by the caller (RaceDetailView) so this
    // view doesn't need its own UserProfile @Query.
    var homeGymDefault: String = ""

    @State private var captionText: String = ""
    @State private var feltText: String = ""    // local input buffer (1-10 typed)
    @State private var sleepText: String = ""   // local input buffer (hours)
    @State private var gymText: String = ""

    #if canImport(UIKit)
    @State private var photoPickerItem: PhotosPickerItem?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Layout.screenMargin)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    captionSection
                    conditionsSection
                    photosSection
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 24)
            }
        }
        .background(Color.background.ignoresSafeArea())
        .onAppear(perform: seedFromRace)
    }

    // MARK: - Header

    // ← / "Edit notes" / Save row. Save persists every field
    // back to the race and calls onDismiss. Back / drag-dismiss
    // commits whatever's currently typed (no destructive
    // "discard changes" prompt — athletes shouldn't lose work
    // on accidental swipe).
    private var header: some View {
        HStack {
            Button(action: commitAndDismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityLabel("Close")

            Spacer()

            Text("Edit notes")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Button(action: commitAndDismiss) {
                Text("Save")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.accent)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Caption section

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAPTION").capsLabelStyle()

            TextField(
                "How did this race feel?",
                text: $captionText,
                axis: .vertical
            )
            .lineLimit(3...8)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surfaceElevated)
            )
        }
    }

    // MARK: - Conditions section

    // Four rows — Gym (text field), Sled weight (display-only,
    // derived from per-split weightKg), Felt (1-10 stepper-ish),
    // Slept (hours decimal). Each row is a self-contained
    // surface card so they read as separate editable fields.
    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONDITIONS").capsLabelStyle()

            VStack(spacing: 4) {
                conditionRow(label: "Gym") {
                    TextField("Where did you train?", text: $gymText)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Color.textPrimary)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: 180)
                }

                conditionRow(label: "Sled weight") {
                    Text(sledWeightDisplay)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }

                conditionRow(label: "Felt") {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Color.accent)
                        TextField("1-10", text: $feltText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Color.accent)
                            .font(.system(size: 12, weight: .heavy))
                            .frame(maxWidth: 60)
                            .onChange(of: feltText) { _, newValue in
                                feltText = sanitizeFeltInput(newValue)
                            }
                        Text("/ 10")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                conditionRow(label: "Slept") {
                    HStack(spacing: 4) {
                        TextField("7.2", text: $sleepText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Color.textSecondary)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: 60)
                        Text("hours")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    private func conditionRow<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surfaceElevated)
        )
    }

    // Sled weight derived from the heaviest weightKg captured on
    // any sled-push or sled-pull split. Sleds are the only HYROX
    // station where weight matters per the standard format; we
    // show the heaviest of the two (athletes don't pull lighter
    // than push, but defensive max). Falls back to "Not set"
    // when no weight was logged.
    private var sledWeightDisplay: String {
        let sledSplits = race.splits.filter {
            $0.station == .sledPush || $0.station == .sledPull
        }
        let weights = sledSplits.compactMap(\.weightKg)
        if let maxWeight = weights.max() {
            return String(format: "%.0f kg", maxWeight)
        }
        return "Not set"
    }

    // MARK: - Photos section

    @ViewBuilder
    private var photosSection: some View {
        #if canImport(UIKit)
        VStack(alignment: .leading, spacing: 6) {
            Text("PHOTOS").capsLabelStyle()

            HStack(spacing: 6) {
                if let data = race.photoData,
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                race.photoData = nil
                                photoPickerItem = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16, weight: .heavy))
                                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                        }
                }

                PhotosPicker(
                    selection: $photoPickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color.textSecondary)
                        Text("add")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.divider, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .onChange(of: photoPickerItem) { _, newItem in
                    Task { await loadSelectedPhoto(from: newItem) }
                }

                Spacer()
            }
        }
        #endif
    }

    #if canImport(UIKit)
    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            race.photoData = data
        }
    }
    #endif

    // MARK: - State seeding + commit

    private func seedFromRace() {
        captionText = race.notes
        // Gym soft-default: if the race already has a gym (user
        // edited before, or auto-fill happened on an earlier
        // session), preserve it. Otherwise inherit from the
        // athlete's profile-level home gym so the field comes
        // pre-filled with the most common answer. The user can
        // still edit/clear before saving.
        gymText = race.gym.isEmpty ? homeGymDefault : race.gym
        if let felt = race.feltRating {
            feltText = "\(felt)"
        }
        if let sleep = race.sleepHoursLast {
            // 7.2 not "7.200000"
            sleepText = String(format: "%.1f", sleep)
                .replacingOccurrences(of: ".0", with: "")
        }
    }

    private func commitAndDismiss() {
        Haptics.impact(.light)
        race.notes = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
        race.gym = gymText.trimmingCharacters(in: .whitespacesAndNewlines)
        race.feltRating = parseFelt(feltText)
        race.sleepHoursLast = parseSleep(sleepText)
        onDismiss()
    }

    private func parseFelt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let intVal = Int(trimmed), intVal >= 1, intVal <= 10 else { return nil }
        return intVal
    }

    private func parseSleep(_ text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")  // EU decimal input
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    // Felt input sanitizer — clamps to 1-10, strips non-digits.
    // Live as the user types so the UI doesn't accept invalid
    // entries (which would silently get nil'd at parse time).
    private func sanitizeFeltInput(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        // Truncate to 2 chars max so "10" stays a valid value
        // but anything longer falls off.
        let clamped = String(digits.prefix(2))
        if let intVal = Int(clamped), intVal > 10 {
            return "10"
        }
        return clamped
    }
}
