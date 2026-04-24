import SwiftUI

// Strava-style horizontal row of three social stats, shown under a profile's
// bio. In v1 only "Races" is live — "Followers" and "Following" are rendered
// as placeholders (muted styling, em-dash value) to foreshadow the social
// layer without faking data. Once Supabase auth + a follow graph ship in
// v2, we flip `isPlaceholder` off and wire real values.
//
// Generic by design: takes an array of `Stat` items rather than hard-coding
// three slots. The same row will live on future feed-side profile peeks
// ("who wrote this post?") where the set of stats may differ.
//
// Layout mirrors Strava's profile header — three centered columns with
// hairline vertical dividers between cells. Numbers use `.monospacedDigit`
// so changing counts don't cause horizontal jitter.
struct SocialStatsRow: View {

    struct Stat: Identifiable {
        let label: String
        let value: String
        // Muted styling + ignores tap (for now). Used for cells whose backend
        // hasn't been wired yet. Keeps the shape visible without lying.
        var isPlaceholder: Bool = false
        var id: String { label }
    }

    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                cell(stat)

                // Divider between cells only — not on the trailing edge.
                if index < stats.count - 1 {
                    Rectangle()
                        .fill(Color.divider)
                        .frame(width: 1, height: 28)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func cell(_ stat: Stat) -> some View {
        VStack(spacing: 4) {
            Text(stat.value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(stat.isPlaceholder ? Color.textTertiary : Color.textPrimary)

            Text(stat.label)
                .capsLabelStyle()
                // `capsLabelStyle()` already uses `textSecondary`. For a
                // placeholder we push it one step further to `textTertiary`
                // so the whole cell reads as "not active yet."
                .foregroundStyle(stat.isPlaceholder ? Color.textTertiary : Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Live + placeholders") {
    ZStack {
        Color.background.ignoresSafeArea()
        SocialStatsRow(stats: [
            .init(label: "Races", value: "12"),
            .init(label: "Followers", value: "—", isPlaceholder: true),
            .init(label: "Following", value: "—", isPlaceholder: true)
        ])
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("All live") {
    ZStack {
        Color.background.ignoresSafeArea()
        SocialStatsRow(stats: [
            .init(label: "Races", value: "42"),
            .init(label: "Followers", value: "1.2k"),
            .init(label: "Following", value: "87")
        ])
        .padding()
    }
    .preferredColorScheme(.dark)
}
