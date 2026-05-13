import SwiftUI

// Wireframe §04.1 compact list-row layout. Replaces the larger
// RaceCardView when the athlete is in History List mode — the
// wireframe's logbook feel is dense and scannable, not card-y.
//
// Layout (left → right):
//   • 40×40 date badge — day-of-week caps + day-of-month, coral
//     when this row is a full HYROX race, neutral surface
//     elevated otherwise.
//   • Title + caps subtitle (e.g. "Sunday HYROX sim" / "FULL ·
//     8 STATIONS"; or "Sled Pull ladder" / "CUSTOM · 3 SETS";
//     or "Lunch — free run" / "5.2 KM").
//   • Finish time (right-aligned, monospaced) + optional PB
//     delta in green beneath.
//
// Single self-contained view that takes a `HistoryRowDescriptor`
// — a small VM-ish struct the parent builds from a Race / FreeRun
// / Custom workout row. Decoupling lets the same row type render
// all three model kinds.
struct HistoryListRowView: View {

    let descriptor: HistoryRowDescriptor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            dateBadge
            titleColumn
            Spacer(minLength: 8)
            timeColumn
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    // MARK: - Date badge (40×40)

    // Day-of-week caps + day-of-month stacked. Coral fill when this
    // row represents a full HYROX race; neutral surfaceElevated
    // otherwise (custom workouts, free runs, partials). The contrast
    // makes full races pop in a long scroll without needing a
    // separate badge.
    private var dateBadge: some View {
        let isFullRace = descriptor.isFullRace
        return VStack(spacing: 0) {
            Text(descriptor.dayOfWeekLabel)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(isFullRace ? Color.onAccent : Color.textSecondary)
            Text(descriptor.dayOfMonthLabel)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(isFullRace ? Color.onAccent : Color.textPrimary)
                .monospacedDigit()
        }
        .frame(width: 40, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFullRace ? Color.accent : Color.surfaceElevated)
        )
    }

    // Title + caps sub-line + optional row tags. Title is 11pt
    // bold (wireframe spec); sub-line is caps-label style with
    // type/length info. Tags row appears beneath when either flag
    // is set; renders inline as small grey/coral caps pills.
    private var titleColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(descriptor.title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(spacing: 4) {
                Text(descriptor.subtitleCaps)
                    .capsLabelStyle()

                // §14 — RaceKind tag. Sits first among the row
                // markers because it answers the most-fundamental
                // question ("what kind of session is this?")
                // before any partial / health-import metadata.
                // Tinted-fill instead of outlined-neutral so the
                // SIM / Q / T pop visually — these aren't
                // informational asides like PARTIAL, they're the
                // row's primary kind signal.
                if let label = descriptor.kindBadgeLabel,
                   let tint = descriptor.kindBadgeTint {
                    rowKindTag(label: label, tint: tint)
                }

                if descriptor.isPartial {
                    rowTag(label: "PARTIAL", tint: Color.textTertiary, border: Color.divider)
                }
                if descriptor.isImportedFromHealth {
                    rowTag(label: "↓ HEALTH", tint: Color.textSecondary, border: Color.divider)
                }
            }
        }
    }

    // Small caps pill for the PARTIAL / Health-imported tags.
    // Outlined neutral by default — these are informational
    // markers, not destructive flags. Tag colors are intentionally
    // muted so they don't compete with the row's primary content
    // (title + time).
    private func rowTag(label: String, tint: Color, border: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .stroke(border, lineWidth: 0.8)
            )
    }

    // §14 — solid-fill version for the RaceKind tag. Different
    // visual weight from `rowTag` because kind is the row's
    // primary categorization, not a side note. Same tracking +
    // size so the row's tag rhythm stays consistent.
    private func rowKindTag(label: String, tint: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(tint.opacity(0.16))
            )
    }

    // Finish time (mono digit, larger weight) + optional PB delta
    // beneath in green. Right-aligned per wireframe.
    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(descriptor.timeLabel)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if let pbDelta = descriptor.pbDeltaLabel {
                Text(pbDelta)
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.onPace)
                    .monospacedDigit()
            }
        }
    }
}

// Small VM-ish struct the parent assembles from each row model
// (Race / FreeRun / future Custom). Decouples the row view from
// the underlying SwiftData types so the same component renders
// every list-row variant.
struct HistoryRowDescriptor: Identifiable, Hashable {
    let id: String

    // For sorting + the date badge.
    let date: Date

    // "Sunday HYROX sim" — display name pulled from the model's
    // own name field (with fallback).
    let title: String

    // "FULL · 8 STATIONS" / "CUSTOM · 3 SETS" / "5.2 KM" — short
    // caps line summarizing the row's kind + scale.
    let subtitleCaps: String

    // "1:18:42" / "25:18" / "8:42" — pre-formatted finish time.
    let timeLabel: String

    // "−42s" / "−1:02" — optional PB delta. nil when this row
    // isn't a PB or PB tracking doesn't apply.
    let pbDeltaLabel: String?

    // True when this row is a full HYROX simulation — drives the
    // coral date-badge styling.
    let isFullRace: Bool

    // Wireframe §04.3 row tags. Either can be true; both can be
    // false (the common case). Rendered as small grey caps pills
    // beneath the title.
    //
    //   • isPartial — race ended early (endEarlyAndSave path);
    //     splits.count < totalSegments. Excluded from PB calcs
    //     elsewhere; tag warns the athlete + future viewers that
    //     this row isn't comparable to a full race time.
    //   • isImportedFromHealth — race row came from an Apple
    //     Health import flow rather than logged in-app. Tagged
    //     with a small ↓ glyph so the athlete remembers the
    //     metadata is thinner than a native row.
    let isPartial: Bool
    let isImportedFromHealth: Bool

    // §14 — short kind badge ("SIM" / "Q" / "T") and its tint.
    // Nil when the row is a default `.race` kind — the row's
    // subtitleCaps already says "FULL · 16 STATIONS" or similar
    // in that case, so a redundant RACE badge would be noise.
    // FreeRun rows also leave this nil (they have their own
    // subtitle vocabulary). Populated only for non-default
    // RaceKind values via the parent feed assembly.
    let kindBadgeLabel: String?
    let kindBadgeTint: Color?

    // Day-of-week label for the badge ("SUN", "WED", "MON").
    var dayOfWeekLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE"
        return fmt.string(from: date).uppercased()
    }

    // Day-of-month label for the badge ("9", "5", "3").
    var dayOfMonthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: date)
    }
}
