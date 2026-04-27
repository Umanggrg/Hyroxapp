import SwiftUI
import SwiftData

// Sheet for picking a new active Challenge from preset templates.
// Three template families (raceCount / fastestRace / streakLength)
// each with two pre-tuned defaults — gives the athlete six tap-
// once options without a full custom builder. Custom targets and
// custom durations are a v2 polish pass.
//
// Layout: hero header ("Pick your challenge") → six template
// cards in a vertical list → coral primary CTA at the bottom
// that activates the selected template. Same one-active-challenge-
// at-a-time invariant as RaceEvent — picking a new one replaces
// any existing active challenge.
//
// Guarded `#if !os(watchOS)` because Challenge / Race are iOS-only.
#if !os(watchOS)
struct ChallengeSetupSheet: View {

    // The currently-active challenge (if any). The sheet replaces
    // it on commit. nil means there's no active challenge yet —
    // commit just inserts.
    let existingChallenge: Challenge?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTemplate: Template?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                            .padding(.horizontal, Layout.screenMargin)
                            .padding(.top, 12)

                        VStack(spacing: 10) {
                            ForEach(Template.presets) { template in
                                templateCard(template)
                            }
                        }
                        .padding(.horizontal, Layout.screenMargin)

                        Spacer(minLength: 24)
                    }
                }

                VStack {
                    Spacer()
                    activateButton
                        .padding(.horizontal, Layout.screenMargin)
                        .padding(.bottom, 24)
                }
            }
            .hyroxNavigationBar(inline: true)
            .navigationTitle("New Challenge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PICK YOUR GOAL")
                .font(.caption.weight(.heavy))
                .tracking(1.2)
                .foregroundStyle(Color.accent)

            Text("Commit to one for the next stretch")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.textPrimary)

            Text("Hitting 100% locks in a completion. You can swap challenges anytime.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Template card

    private func templateCard(_ template: Template) -> some View {
        let isSelected = selectedTemplate?.id == template.id
        let tint = Color.accent

        return Button {
            Haptics.impact(.light)
            selectedTemplate = template
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(isSelected ? 0.30 : 0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: template.type.symbol)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)

                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Color.textTertiary)
            }
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(isSelected ? tint.opacity(0.5) : Color.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.pressableCard)
    }

    // MARK: - Activate button

    private var activateButton: some View {
        Button {
            commit()
        } label: {
            Text(existingChallenge == nil ? "Start Challenge" : "Replace & Start")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.raceButtonHeight)
                .background(
                    LinearGradient(
                        colors: [Color.accent, Color.accent.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.35 : 0.20),
                    radius: 18,
                    y: 0
                )
                .opacity(selectedTemplate == nil ? 0.4 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(selectedTemplate == nil)
    }

    // Commit handler — replaces the existing active challenge (if
    // any) with a fresh one based on the selected template. The
    // single-active-challenge invariant: deleting the old one is
    // simpler than mutating it, and the Profile UI naturally
    // re-queries.
    private func commit() {
        guard let template = selectedTemplate else { return }

        Haptics.success()

        if let existing = existingChallenge {
            modelContext.delete(existing)
        }

        let challenge = Challenge(
            type: template.type,
            targetValue: template.targetValue,
            startDate: Date(),
            endDate: Calendar.current.date(
                byAdding: .day,
                value: template.durationDays,
                to: Date()
            ) ?? Date()
        )
        modelContext.insert(challenge)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Template

// Preset challenge shape with a hand-tuned target + duration.
// Six total — two of each type — gives the athlete an immediate
// answer to "what should I commit to?" without overwhelming
// choice. Custom targets land in v2.
struct Template: Identifiable, Hashable, Sendable {
    let id: String
    let type: ChallengeType
    let targetValue: Double
    let durationDays: Int
    let title: String
    let subtitle: String

    static let presets: [Template] = [
        // Race count — the most common challenge shape. Two
        // tiers: a habit-builder (5 in 30) and a serious-volume
        // option (10 in 30) for athletes ramping toward an event.
        Template(
            id: "rc-5-30",
            type: .raceCount,
            targetValue: 5,
            durationDays: 30,
            title: "5 races in 30 days",
            subtitle: "Habit-builder pace. ~1 race every 6 days."
        ),
        Template(
            id: "rc-10-30",
            type: .raceCount,
            targetValue: 10,
            durationDays: 30,
            title: "10 races in 30 days",
            subtitle: "Serious volume. Race-prep cadence."
        ),

        // Fastest race — sub-time targets calibrated to typical
        // HYROX finishing times. 1:30 is the "competitive amateur"
        // benchmark; 1:15 is the "elite-adjacent" benchmark.
        Template(
            id: "fr-90-30",
            type: .fastestRace,
            targetValue: 5400,  // 90 min
            durationDays: 30,
            title: "Sub-1:30 race in 30 days",
            subtitle: "Competitive amateur benchmark."
        ),
        Template(
            id: "fr-75-60",
            type: .fastestRace,
            targetValue: 4500,  // 75 min
            durationDays: 60,
            title: "Sub-1:15 race in 60 days",
            subtitle: "Elite-adjacent. Stretch goal."
        ),

        // Streak length — consistency-focused. 7-day is the
        // minimum-viable habit; 14-day is real commitment.
        Template(
            id: "sl-7-14",
            type: .streakLength,
            targetValue: 7,
            durationDays: 14,
            title: "7-day training streak",
            subtitle: "Build the habit. Two weeks to lock it in."
        ),
        Template(
            id: "sl-14-30",
            type: .streakLength,
            targetValue: 14,
            durationDays: 30,
            title: "14-day training streak",
            subtitle: "Real commitment. Show up every day."
        ),
    ]
}
#endif
