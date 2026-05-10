import SwiftUI
import AuthenticationServices

#if canImport(UIKit)

// First-launch / signed-out gate. Renders a single Sign in with Apple
// button. On success, AuthService.user becomes non-nil and the app's
// auth gate flips through to the main UI.
//
// Visual language: the same brand fingerprint watermark used on the
// History empty state, with a clean centered layout. Sign in is a
// gentle moment, not a marketing surface — we keep copy minimal and
// let the brand do the talking. No social-proof testimonials, no
// feature list. The athlete already downloaded the app; they're
// signing in to start using it, not being convinced to keep using
// it.
struct SignInView: View {

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

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
        }
    }

    // Centered brand block — wordmark + tagline. Same TRAKRR
    // typography Settings's About section uses, scaled up.
    private var brandHero: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.fill")
                .font(.system(size: 44, weight: .black))
                .foregroundStyle(Color.accent)
                .rotationEffect(.degrees(-90))

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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

#endif
