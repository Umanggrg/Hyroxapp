import SwiftUI

// §37 Whoop pattern 6 — pre-race journal sheet.
//
// Three quick-tap questions before the race starts:
//   1. Sleep last night — Poor / OK / Good / Great
//   2. Stress this week — Low / Moderate / High
//   3. Anything sore — free-form text
//
// All optional. Skip button at top-left bails without writing
// any fields. Continue button passes the captured values up
// through the `onContinue` closure, which the parent uses to
// invoke RaceViewModel.startRaceWithCountdown with the journal
// parameters.
//
// The point of the journal isn't the in-the-moment value — it's
// the dataset it builds over time. Once an athlete has logged
// 5+ races with sleep/stress, the post-race analytics layer can
// surface "your back-half pace drops 14% on poor-sleep weeks"
// kinds of insights. Pre-Phase-37 races don't carry this data
// so the insights only fire on Phase-37+ races. Slow-burn
// feature, intentional.
//
// Aesthetic: dark Trakrr cathedral feel, Volt accents on
// selected pills, generous breathing room. Same visual register
// as RaceStartView so the journal feels like a natural
// pre-flight check, not a popup.
struct PreRaceJournalSheet: View {

    // Captured values. Parent reads these via the onContinue
    // closure; sheet doesn't persist anything itself.
    @State private var sleepRating: SleepRating? = nil
    @State private var stressLevel: StressLevel? = nil
    @State private var soreNotes: String = ""

    // Parent's hook. Called when athlete taps Continue with the
    // current (possibly-nil, possibly-empty) journal values.
    // Skip routes through here too with all-nil values.
    let onContinue: (String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss

    enum SleepRating: String, CaseIterable {
        case poor, ok, good, great
        var label: String {
            switch self {
            case .poor:  return "Poor"
            case .ok:    return "OK"
            case .good:  return "Good"
            case .great: return "Great"
            }
        }
    }

    enum StressLevel: String, CaseIterable {
        case low, moderate, high
        var label: String {
            switch self {
            case .low:      return "Low"
            case .moderate: return "Moderate"
            case .high:     return "High"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    headerRow

                    Text("Three quick taps.\nWe'll tell you why later.")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .lineSpacing(2)
                        .padding(.top, 4)

                    sleepSection
                    stressSection
                    soreSection
                    explainerCallout
                }
                .padding(20)
                .padding(.bottom, 90)
            }

            VStack {
                Spacer()
                continueButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button("Skip") {
                onContinue(nil, nil, nil)
                dismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)

            Spacer()

            Text("BEFORE YOU START")
                .font(.caption2.weight(.heavy))
                .tracking(1.4)
                .foregroundStyle(Color.textTertiary)

            Spacer()

            // Invisible spacer to balance the layout — same
            // width as the Skip button so the caps label
            // stays optically centered.
            Text("Skip")
                .font(.subheadline)
                .foregroundStyle(Color.clear)
        }
    }

    // MARK: - Sleep section

    private var sleepSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SLEEP LAST NIGHT")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 6) {
                ForEach(SleepRating.allCases, id: \.self) { rating in
                    pillButton(
                        label: rating.label,
                        isSelected: sleepRating == rating
                    ) {
                        sleepRating = rating
                    }
                }
            }
        }
    }

    // MARK: - Stress section

    private var stressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STRESS THIS WEEK")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            HStack(spacing: 6) {
                ForEach(StressLevel.allCases, id: \.self) { level in
                    pillButton(
                        label: level.label,
                        isSelected: stressLevel == level
                    ) {
                        stressLevel = level
                    }
                }
            }
        }
    }

    // MARK: - Sore section

    private var soreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTHING SORE?")
                .font(.caption2.weight(.heavy))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)

            TextField(
                "",
                text: $soreNotes,
                prompt: Text("e.g. left hip flexor, lower back…")
                    .foregroundStyle(Color.textTertiary)
            )
            .font(.subheadline)
            .foregroundStyle(Color.textPrimary)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.divider, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Why-this-matters callout

    private var explainerCallout: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color.accent)
                .padding(.top, 2)

            Text("Lets Trakrr say things like \"your back-half pace dropped 14% on poor-sleep weeks\" after a few races.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - Continue button

    private var continueButton: some View {
        Button {
            // Empty sore notes → store nil, not "" — keeps the
            // schema clean and avoids "(empty)" rendering
            // anywhere downstream.
            let trimmedSore = soreNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            onContinue(
                sleepRating?.rawValue,
                stressLevel?.rawValue,
                trimmedSore.isEmpty ? nil : trimmedSore
            )
            dismiss()
        } label: {
            Text("Continue to race")
                .font(.headline)
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accent)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func pillButton(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    isSelected ? Color.onAccent : Color.textSecondary
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accent : Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.divider,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
