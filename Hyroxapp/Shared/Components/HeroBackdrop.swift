import SwiftUI

// Reusable hero backdrop for screens that need to feel like a
// moment — race start, race finish, countdown, monthly recap entry.
// Three layers, painted bottom-up:
//
//   1. Pure-black base
//   2. Subtle radial coral glow centered behind the hero element,
//      6% opacity at center, fading to 0 at the edges. Gives the
//      "stadium spotlight" energy without being a coral wash.
//   3. The 16-bar fingerprint as a low-opacity decorative
//      watermark, anchored bottom-center. Recurring brand element
//      — the same shape used on the app icon and share cards. At
//      4% opacity it reads as texture, not data.
//
// Three intensity options — `.calm` (everything dialed back, used
// behind dense content like splits), `.standard` (default),
// `.intense` (race-defining moments like the finish, glow turned
// up). Behavior identical otherwise; the variant just nudges
// opacities.
//
// Designed to be `.ignoresSafeArea()` and used as a ZStack base
// layer below the actual content.
struct HeroBackdrop: View {

    enum Intensity {
        case calm
        case standard
        case intense

        var glowOpacity: Double {
            switch self {
            case .calm:     return 0.04
            case .standard: return 0.08
            case .intense:  return 0.18
            }
        }

        var fingerprintOpacity: Double {
            switch self {
            case .calm:     return 0.03
            case .standard: return 0.05
            case .intense:  return 0.07
            }
        }
    }

    let intensity: Intensity

    init(_ intensity: Intensity = .standard) {
        self.intensity = intensity
    }

    var body: some View {
        ZStack {
            Color.background

            // Layer 2: stadium-spotlight radial glow. Centered
            // slightly above geometric center so the visual weight
            // sits where the eye naturally lands on a phone (~40%
            // from top).
            RadialGradient(
                colors: [
                    Color.accent.opacity(intensity.glowOpacity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 360
            )
            .blendMode(.screen)

            // Layer 3: fingerprint watermark, bottom-anchored.
            // Reads as a subtle floor pattern, not a chart.
            VStack {
                Spacer()
                FingerprintWatermark()
                    .frame(height: 90)
                    .opacity(intensity.fingerprintOpacity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 80)
            }
        }
        .ignoresSafeArea()
    }
}

// The 16-bar fingerprint silhouette, rendered as decoration
// rather than data. Heights match the same hand-tuned rhythm we
// used on the app icon and share-card hero — keeps the brand
// signature consistent across surfaces.
//
// Drawn as a Canvas at runtime rather than a static image so it
// stays sharp at any size and respects the current foreground
// style. Caller controls color via tint; default is white so
// `.opacity(...)` at the call site does the dimming.
struct FingerprintWatermark: View {

    // Heights normalized 0.0–1.0, same rhythm as the icon. Even
    // indices are runs (R1 R2 ...), odd are workouts.
    private static let heights: [CGFloat] = [
        0.55, 0.85, 0.50, 0.95, 0.55, 0.92, 0.60, 0.78,
        0.65, 0.88, 0.65, 0.72, 0.70, 0.82, 0.72, 1.00
    ]

    var body: some View {
        GeometryReader { geo in
            let n = Self.heights.count
            let gap: CGFloat = 4
            let totalGap = gap * CGFloat(n - 1)
            let barWidth = (geo.size.width - totalGap) / CGFloat(n)
            let barRadius = barWidth * 0.4

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<n, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barRadius)
                        .fill(Color.textPrimary)
                        .frame(
                            width: barWidth,
                            height: max(geo.size.height * Self.heights[i], 4)
                        )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
    }
}
