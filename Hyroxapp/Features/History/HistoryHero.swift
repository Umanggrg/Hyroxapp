import SwiftUI

// Small at-a-glance stats summary at the top of the History
// feed. Three numbers in a single horizontal row — total races,
// PB, and most recent race date. Earns the "history" page some
// visual identity beyond just being a feed of cards.
//
// Sized small on purpose — this is supplementary context, not a
// hero. The CARDS are the hero of History; this row is just
// "here's what you're scrolling through" framing.
//
// Hidden by the parent when races.isEmpty (the empty state has
// its own hero treatment).
struct HistoryHero: View {

    let races: [Race]

    private var pbDisplay: String {
        RaceStats.personalBest(races).map(RaceStats.format) ?? "—"
    }

    private var lastRaceDisplay: String {
        guard let mostRecent = races
            .filter(\.isFinished)
            .compactMap(\.endedAt)
            .max()
        else { return "—" }

        // Relative date format ("3 days ago" / "yesterday") for
        // recent races; falls back to absolute when older. iOS's
        // RelativeDateTimeFormatter handles the choice naturally.
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: mostRecent, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            cell(value: "\(races.filter(\.isFinished).count)", label: "RACES")
            divider
            cell(value: pbDisplay, label: "PB", accent: true)
            divider
            cell(value: lastRaceDisplay, label: "LAST RACE")
        }
        .padding(.vertical, 14)
        // Token-aligned to `Layout.cardCornerRadius` (16 post-v1).
        // Was a hardcoded 14pt that pre-dated the token roll-up.
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                        .stroke(Color.divider, lineWidth: 1)
                )
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 24)
    }

    private func cell(
        value: String,
        label: String,
        accent: Bool = false
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent ? Color.accent : Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
