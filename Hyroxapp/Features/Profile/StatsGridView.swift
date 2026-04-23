import SwiftUI

// A reusable grid of labeled stat tiles, styled as a single rounded card.
//
// Takes arbitrary `Item`s so it can render Profile aggregates today and
// later the same shape for things like "This month" or "Last 10 races"
// sections. Shows tiles in a 2-column grid; callers supply any even count.
struct StatsGridView: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 0
        ) {
            ForEach(items) { item in
                tile(item)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func tile(_ item: Item) -> some View {
        VStack(spacing: 6) {
            Text(item.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text(item.label)
                .capsLabelStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}
