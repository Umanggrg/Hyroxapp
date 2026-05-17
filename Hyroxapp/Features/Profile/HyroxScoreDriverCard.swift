import SwiftUI

// §35 Whoop pattern 4 — causal narrative card for the HYROX
// Score. Renders one line of context immediately below the
// HyroxScoreView hero so the static 0-1000 number stops being
// mute. Either it celebrates an improvement and names the
// dimension that drove it, flags a regression with the
// dimension to watch, or — when steady — calls out the
// athlete's strongest pillar so they know which lever they're
// pushing.
//
// Self-hiding on:
//   • fewer than 2 finished races (no baseline to compare)
//   • computation failure (defensive — shouldn't happen but
//     better to hide than render garbage)
//
// Visual contract:
//   • Same card chrome as the HyroxScoreView above
//     (surface bg, cardCornerRadius, cardPadding) so the two
//     cards read as a connected pair — one is the number, the
//     other is the explanation.
//   • A small accent sparkles icon + caps "WHAT'S DRIVING IT"
//     label anchors the card. Same icon pattern Race Story
//     uses for its narrative insights, so the visual language
//     of "this is a narrative, not a number" is consistent.
//   • Delta number colored by direction — success-green on
//     improvement, warning-amber on regression, textSecondary
//     when steady.
struct HyroxScoreDriverCard: View {

    let races: [Race]
    let division: Division
    let maxHR: Int

    var body: some View {
        if let driver = RaceStats.hyroxScoreDriver(
            across: races,
            division: division,
            maxHR: maxHR
        ) {
            card(driver: driver)
        }
    }

    static func hasEnoughData(in races: [Race], division: Division, maxHR: Int) -> Bool {
        RaceStats.hyroxScoreDriver(across: races, division: division, maxHR: maxHR) != nil
    }

    // MARK: - Card

    @ViewBuilder
    private func card(driver: RaceStats.HyroxScoreDriver) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.heavy))
                Text("WHAT'S DRIVING IT")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.accent)

            // Render the narrative with the delta + driver names
            // tinted by direction so the eye lands on the meaning
            // immediately. Using AttributedString gives us inline
            // color without breaking into HStacks per-word.
            Text(attributedNarrative(driver: driver))
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Layout.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // Build an AttributedString that tints the delta + driver
    // label per direction. Three branches mirror the three
    // narrative tones from `RaceStats.hyroxScoreDriver`.
    private func attributedNarrative(driver: RaceStats.HyroxScoreDriver) -> AttributedString {
        var attr = AttributedString(driver.narrative)

        // Color the driver label in accent so the eye jumps to
        // "this is the dimension you should care about." Search-
        // and-color the label text inside the narrative.
        if let range = attr.range(of: driver.driverLabel) {
            attr[range].foregroundColor = Color.accent
        }

        // Color the signed delta number per direction so the
        // trajectory is readable at a glance — same green/amber
        // semantic the Engine Score insight card uses.
        let signedDelta = driver.driverDelta >= 0
            ? "+\(driver.driverDelta)"
            : "\(driver.driverDelta)"
        if let range = attr.range(of: "(\(signedDelta))") {
            attr[range].foregroundColor =
                driver.driverDelta >= 0 ? Color.success : Color.warning
        }

        return attr
    }
}
