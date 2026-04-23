import SwiftUI

// The top portion of the Profile screen: avatar + name + handle + bio.
//
// Strava-style layout — when v1 ships real accounts this view starts reading
// a user record instead of hardcoded strings. The shape is stable so the
// Profile tab already looks like a social-app profile, even for a single
// user with no network.
struct ProfileHeaderView: View {

    // Hardcoded placeholders for v0.1. Real profile editing + avatar upload
    // lands with auth + Supabase in v1.
    private let displayName = "Umang"
    private let handle = "@umang"
    private let location = "Florida"
    private let bio = "HYROX athlete in training."

    var body: some View {
        VStack(spacing: 14) {
            avatar
            name
            subtitle
            bioLine
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 96, height: 96)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
            .overlay(
                Circle()
                    .strokeBorder(Color.divider, lineWidth: 1)
            )
    }

    private var name: some View {
        Text(displayName)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Color.textPrimary)
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            Text(handle)
            Text("·")
            Text(location)
        }
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
    }

    private var bioLine: some View {
        Text(bio)
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }
}
