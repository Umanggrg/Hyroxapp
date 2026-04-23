import SwiftUI

// Pre-race screen: HYROX header, Solo/Duo toggle (Duo greyed out with
// "Coming soon" per CLAUDE-2.md §4.5 until Supabase Realtime sync lands in
// v2), and the big Start Race button.
//
// Takes the owning `RaceViewModel` as a parameter rather than creating its
// own — the VM lives for the entire race flow (pre → in-progress → summary),
// and is owned by `RaceView`.
struct RaceStartView: View {
    let viewModel: RaceViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("HYROX")
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(Color.textPrimary)
                Text("Race Mode")
                    .capsLabelStyle()
            }

            Spacer()

            modeToggle

            Button {
                Haptics.impact(.medium)
                viewModel.startRace()
            } label: {
                Text("Start Race")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.raceButtonHeight)
                    .background(Color.accent)
                    .foregroundStyle(Color.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            }
            .padding(.bottom, 24)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 12) {
            modeChip(.solo)
            modeChip(.duo)
        }
    }

    private func modeChip(_ mode: RaceMode) -> some View {
        // Solo is the only selectable mode in v0.1; Duo is laid out now so
        // the pattern exists in v2 when Supabase Realtime wires it up.
        let isSelected = (mode == .solo)
        let available = mode.isAvailable

        return VStack(spacing: 4) {
            Text(mode.displayName)
                .font(.system(size: 18, weight: .semibold))
            if !available {
                Text("Coming soon")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(isSelected ? Color.surfaceElevated : Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .strokeBorder(isSelected ? Color.accent : Color.divider, lineWidth: 1)
        )
        .foregroundStyle(available ? Color.textPrimary : Color.textTertiary)
        .opacity(available ? 1.0 : 0.55)
    }
}
