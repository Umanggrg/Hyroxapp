import SwiftUI

// Section break for the redesigned Profile screen. Distinct from
// the existing `capsLabelStyle()` because that's a card-internal
// label; THIS is a page-level rhythm-breaker that visually says
// "you're entering a new domain of content."
//
// Anatomy (left-to-right):
//   • Optional system-image icon (12pt, accent or secondary)
//   • CAPS title (12pt heavy, tracked)
//   • Thin horizontal accent rule that fills the remaining width
//   • Optional trailing text (e.g. counter, "5 of 12")
//
// The thin rule is the unique element — gives each section a
// horizon line that frames its content. Stops the page from
// reading as a homogeneous stack of cards.
//
// Used by the v2 Profile redesign to delimit the six sections:
// NEXT UP, SUMMARY, PERFORMANCE, TRAINING, PERSONAL BESTS, RECENT.
struct ProfileSectionHeader: View {

    let title: String
    let icon: String?
    let trailing: String?
    let accent: Bool

    init(
        title: String,
        icon: String? = nil,
        trailing: String? = nil,
        accent: Bool = false
    ) {
        self.title = title
        self.icon = icon
        self.trailing = trailing
        self.accent = accent
    }

    private var primaryColor: Color {
        accent ? Color.accent : Color.textSecondary
    }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(primaryColor)
            }

            Text(title)
                .font(.caption2.weight(.heavy))
                .tracking(1.6)
                .textCase(.uppercase)
                .foregroundStyle(primaryColor)

            // The horizontal rule. Linear gradient from the
            // accent (or divider) color into transparent so the
            // line has a directional "into the section" feel
            // rather than a flat horizontal bar.
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            (accent ? Color.accent : Color.divider).opacity(0.6),
                            Color.divider.opacity(0.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            if let trailing {
                Text(trailing)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}
