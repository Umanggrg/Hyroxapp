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

    // Active color scheme — drives the per-mode opacity scaling
    // and the fingerprint ink color (white on dark, near-black on
    // light). Read from the environment rather than passed in so
    // every consumer of HeroBackdrop adapts automatically when
    // the user flips Settings → Appearance.
    @Environment(\.colorScheme) private var colorScheme

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
            //
            // Glow opacity is scaled per mode via
            // `adaptiveGlowOpacity` — the same coral that reads as
            // subtle stadium light on near-black would read as a
            // heavy wash on warm off-white if you didn't dial it
            // back. Layer's blend mode also flips: screen lifts
            // dark backgrounds; on light bg we want plus-lighter /
            // multiply behavior is too muddy, so we use a plain
            // SourceOver compose and rely on the lower opacity to
            // keep things subtle.
            RadialGradient(
                colors: [
                    Color.accent.opacity(
                        adaptiveGlowOpacity(
                            base: intensity.glowOpacity,
                            scheme: colorScheme
                        )
                    ),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: 0.4),
                startRadius: 0,
                endRadius: 360
            )
            .blendMode(colorScheme == .dark ? .screen : .normal)

            // Layer 3: fingerprint watermark, bottom-anchored.
            // Reads as a subtle floor pattern, not a chart. Ink
            // color flips with the mode so it always reads as
            // texture against the bg, not as a contrast slap.
            VStack {
                Spacer()
                FingerprintWatermark(ink: Color.fingerprintInk)
                    .frame(height: 90)
                    .opacity(
                        adaptiveFingerprintOpacity(
                            base: intensity.fingerprintOpacity,
                            scheme: colorScheme
                        )
                    )
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
// Drawn as a stack at runtime rather than a static image so it
// stays sharp at any size. Ink color is caller-controlled — the
// hero backdrop passes `Color.fingerprintInk` (an adaptive
// token), share cards pass white, etc.
struct FingerprintWatermark: View {

    // Heights normalized 0.0–1.0, same rhythm as the icon. Even
    // indices are runs (R1 R2 ...), odd are workouts.
    private static let heights: [CGFloat] = [
        0.55, 0.85, 0.50, 0.95, 0.55, 0.92, 0.60, 0.78,
        0.65, 0.88, 0.65, 0.72, 0.70, 0.82, 0.72, 1.00
    ]

    let ink: Color

    init(ink: Color = .textPrimary) {
        self.ink = ink
    }

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
                        .fill(ink)
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
