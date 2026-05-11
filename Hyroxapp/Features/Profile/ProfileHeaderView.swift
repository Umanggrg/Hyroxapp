import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// The top portion of the Profile screen: avatar + name + handle + bio +
// a Strava-style social stats row (Races live, Followers / Following as
// placeholders). Takes a `UserProfile` model and the finished-race count;
// the race count lives a level up in `ProfileView` where the `@Query` fires,
// so we accept it as a param rather than re-querying here. When Supabase
// auth + the follow graph ship, the two placeholder cells get real values
// wired from a remote profile record — the view shape is already in place.
struct ProfileHeaderView: View {
    let profile: UserProfile
    let raceCount: Int

    var body: some View {
        VStack(spacing: 14) {
            avatar
            name
            subtitle
            bioLine
            socialStats
        }
        .frame(maxWidth: .infinity)
    }

    // Display order:
    //   1. Local bytes (`avatarData`) — zero-latency, ALWAYS preferred
    //      when present. Set by EditProfileView's photo picker; persists
    //      across launches in SwiftData.
    //   2. Remote URL (`avatarURL`) — synced from Supabase profiles
    //      row. Used when this device has the URL but not the bytes
    //      (e.g. signed in on a new phone after avatar was uploaded
    //      from another device).
    //   3. SF Symbol fallback — neither bytes nor URL available.
    //
    // AsyncImage handles the URL fetch + cache via URLSession's
    // shared cache. We don't write the fetched bytes back to
    // `avatarData` on purpose — that'd create a cross-device
    // sync loop (each pull would mark the local row dirty).
    // The cache layer keeps re-fetches cheap.
    private var avatar: some View {
        Group {
            #if canImport(UIKit)
            if let data = profile.avatarData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let urlString = profile.avatarURL,
                      let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        defaultAvatarSymbol
                    @unknown default:
                        defaultAvatarSymbol
                    }
                }
            } else {
                defaultAvatarSymbol
            }
            #else
            defaultAvatarSymbol
            #endif
        }
        .frame(width: 96, height: 96)
        .clipShape(Circle())
        .overlay(
            Circle().strokeBorder(Color.divider, lineWidth: 1)
        )
    }

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    private var name: some View {
        Text(profile.displayName)
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(Color.textPrimary)
    }

    // "@handle · Location" — location is dropped gracefully if the user
    // hasn't filled it in, so a bare handle still looks intentional.
    @ViewBuilder
    private var subtitle: some View {
        let parts: [String] = {
            var list: [String] = [profile.handle]
            let trimmedLocation = profile.location.trimmingCharacters(in: .whitespaces)
            if !trimmedLocation.isEmpty {
                list.append(trimmedLocation)
            }
            return list
        }()

        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("·")
                }
                Text(part)
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
    }

    @ViewBuilder
    private var bioLine: some View {
        let trimmed = profile.bio.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            Text(trimmed)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // Three-cell social-stats row. Only "Races" is real in v1; the two
    // follow-graph cells render as placeholders so the user sees where
    // the social layer is going without us fabricating numbers.
    private var socialStats: some View {
        SocialStatsRow(stats: [
            .init(label: "Races", value: "\(raceCount)"),
            .init(label: "Followers", value: "—", isPlaceholder: true),
            .init(label: "Following", value: "—", isPlaceholder: true)
        ])
        .padding(.top, 4)
    }
}
