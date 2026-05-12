import SwiftUI
import AuthenticationServices
import Network

#if canImport(UIKit)

// First-launch / signed-out gate. Renders a single Sign in with Apple
// button. On success, AuthService.user becomes non-nil and the app's
// auth gate flips through to the main UI.
//
// Visual language: clean centered layout with the coral triangle
// brand mark. Sign in is a gentle moment, not a marketing surface —
// we keep copy minimal and let the brand do the talking. No
// social-proof testimonials, no feature list.
//
// Two states:
//   1. Online   — brand hero + Sign in with Apple button
//   2. Offline  — centered warning + "Can't reach Trakrr" + Try again
//                 (wireframe §01.E: Apple's auth flow needs network,
//                 so we surface the offline state up-front rather
//                 than letting the user tap Sign in and watch it
//                 fail).
struct SignInView: View {

    @Environment(\.colorScheme) private var colorScheme

    // Network reachability monitor. Updated on every path change
    // via NWPathMonitor. Default to true so the initial render
    // doesn't flash the offline state for a frame on cold launch
    // before the monitor reports.
    @State private var isOnline: Bool = true

    // Holds the pathMonitor so it lives for the view's lifetime.
    // Cancelled on disappear so we don't leak a background timer.
    @State private var pathMonitor: NWPathMonitor?

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            Group {
                if isOnline {
                    onlineLayout
                } else {
                    offlineLayout
                }
            }
            .animation(.smooth(duration: 0.3), value: isOnline)
        }
        .onAppear(perform: startMonitoringNetwork)
        .onDisappear {
            pathMonitor?.cancel()
            pathMonitor = nil
        }
    }

    // Standard sign-in layout — brand mark + button + disclaimer.
    private var onlineLayout: some View {
        VStack(spacing: 28) {
            Spacer()

            brandHero

            Spacer()

            signInButton

            disclaimer
        }
        .padding(.horizontal, Layout.screenMargin)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .transition(.opacity)
    }

    // Wireframe §01.E — centered ⚠ + voice-aligned copy + Try again.
    // Copy is intentionally short: "Can't reach Trakrr." names the
    // actor (Trakrr) rather than "Network error" which sounds like
    // a system pop-up. "We'll wait." reads as observational, not
    // pleading — same tone the rest of the app uses on empty
    // states.
    private var offlineLayout: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.bottom, 4)

                Text("Can't reach Trakrr.")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)

                Text("Sign-in needs internet. We'll wait.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                Haptics.impact(.light)
                // Force-refresh the monitor's path. The monitor
                // already updates automatically on any path
                // change, so this is really just a UX nicety: tap
                // means "retry now" rather than "wait passively."
                // The actual recheck happens because we restart
                // the monitor, which re-fires its update handler
                // synchronously.
                restartMonitoringNetwork()
            } label: {
                Text("Try again")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .fill(Color.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                            .stroke(Color.divider, lineWidth: 1)
                    )
            }
            .buttonStyle(.pressableCard)
        }
        .padding(.horizontal, Layout.screenMargin)
        .padding(.top, 60)
        .padding(.bottom, 40)
        .transition(.opacity)
    }

    // MARK: - Network monitoring

    private func startMonitoringNetwork() {
        // Idempotent — only kick off a fresh monitor if one
        // isn't already running. Re-renders triggered by the
        // app's normal scene phase changes shouldn't create
        // duplicate monitors.
        guard pathMonitor == nil else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            // Compute the Sendable Bool inside the closure (on the
            // monitor's own queue) so we don't try to capture the
            // non-Sendable NWPath across the MainActor boundary.
            // Swift 6 strict concurrency rejects passing NWPath
            // into an @MainActor Task block; bridging via a Bool
            // sidesteps that without changing behavior.
            let online = (path.status == .satisfied)
            Task { @MainActor in
                isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "trakrr.signin.network"))
        pathMonitor = monitor
    }

    private func restartMonitoringNetwork() {
        pathMonitor?.cancel()
        pathMonitor = nil
        startMonitoringNetwork()
    }

    // Centered brand block — coral triangle mark + wordmark +
    // tagline. The triangle is mountain-up ("earned"), NOT a play
    // glyph rotated — wireframe §01.1 is explicit on this: it
    // reads as "up," not "play." Sized 60×54 to match the
    // wireframe's CSS clip-path; rendered via `BrandTriangle` below.
    // Dark mode gets a soft coral glow (wireframe spec equivalent
    // of `box-shadow: 0 0 30px rgba(255,69,48,.4)`) — the brand
    // "lives at night."
    private var brandHero: some View {
        VStack(spacing: 14) {
            BrandTriangle()
                .fill(Color.accent)
                .frame(width: 60, height: 54)
                .shadow(
                    color: Color.accent.opacity(colorScheme == .dark ? 0.45 : 0.0),
                    radius: colorScheme == .dark ? 30 : 0,
                    x: 0,
                    y: 0
                )

            Text("TRAKRR")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .tracking(3.0)
                .foregroundStyle(Color.textPrimary)

            Text("Race · Track · Compete")
                .font(.callout.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // Apple's reference Sign in with Apple button. AuthService
    // provides the request prep + result handling so the view
    // stays a thin shell over the data flow.
    //
    // Style chooses dark-on-light vs light-on-dark based on the
    // current color scheme — Apple's HIG actually mandates this:
    // the button must visually contrast its surroundings.
    private var signInButton: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                AuthService.shared.prepareAppleRequest(request)
            },
            onCompletion: { result in
                AuthService.shared.handleAppleAuthorization(result)
            }
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 56)
        // Token-aligned to `Layout.cardCornerRadius` (16
        // post-v1). 56pt button sits at the card/sheet
        // boundary; card-tier is the right call since the
        // Sign-In-with-Apple button reads as a list-style row
        // here, not a hero pressable.
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .padding(.horizontal, 8)
    }

    // Tiny privacy disclaimer below the button. Builds trust
    // ("Apple's privacy promise still applies") and gives us a
    // location for the eventual Terms / Privacy links.
    private var disclaimer: some View {
        Text("Sign in privately with your Apple ID.\nWe never see your password or email recovery info.")
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }
}

// Mountain-up triangle for the Trakrr brand mark. The wireframe
// uses CSS clip-path `polygon(50% 8%, 100% 92%, 0 92%)` to draw
// it — peak slightly inset from the top edge so the triangle
// doesn't look top-clipped, base extended slightly beyond the
// bottom edge so the base reads as a stable foundation rather
// than a midline. Same three vertices here, translated into Path
// coordinates relative to the rect SwiftUI hands us.
//
// The shape is brand-canonical — it appears wherever Trakrr is
// "the brand" (splash, App Store icon source, share-card watermarks).
// Pulled into a reusable `Shape` so every surface that wants the
// mark gets pixel-identical geometry.
struct BrandTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Peak — horizontally centered, 8% inset from top
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08))
        // Bottom-right vertex — extends to the right edge at 92% down
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.92))
        // Bottom-left vertex — extends to the left edge at 92% down
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.92))
        path.closeSubpath()
        return path
    }
}

#endif
