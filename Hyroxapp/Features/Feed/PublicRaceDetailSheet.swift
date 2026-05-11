import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Modal sheet that renders one public race's detail when the
// user taps a feed card. Drives off
// `PublicRaceFeedService.detail(forRaceID:)`, which hits the
// `public_race_detail` view (splits projected to safe
// fields only).
//
// Sections:
//   1. Athlete header (avatar + name + handle, tappable)
//   2. Race title + kind subline
//   3. Optional photo hero
//   4. Total time hero stat
//   5. Per-station split list — same shape as RaceDetailView's
//      overview tab but read-only and without the athlete-
//      private extras.
struct PublicRaceDetailSheet: View {

    let raceID: String

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .loading
    @State private var selectedAthleteID: String?

    private enum Phase {
        case loading
        case loaded(RemotePublicRaceDetail)
        case notFound
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        switch phase {
                        case .loading:
                            loadingIndicator
                        case .loaded(let race):
                            content(race: race)
                        case .notFound:
                            notFoundCard
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, Layout.screenMargin)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Race")
            .hyroxNavigationBar(inline: true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .sheet(item: Binding(
                get: { selectedAthleteID.map(AthleteIDWrapper.init) },
                set: { selectedAthleteID = $0?.id }
            )) { wrapper in
                PublicProfileSheet(userID: wrapper.id)
            }
        }
    }

    private struct AthleteIDWrapper: Identifiable {
        let id: String
    }

    // MARK: - Load

    private func load() async {
        if let detail = await PublicRaceFeedService.detail(forRaceID: raceID) {
            phase = .loaded(detail)
        } else {
            phase = .notFound
        }
    }

    // MARK: - Content

    private func content(race: RemotePublicRaceDetail) -> some View {
        VStack(spacing: 18) {
            athleteHeader(race: race)
            titleBlock(race: race)
            #if canImport(UIKit)
            if let urlString = race.photoUrl,
               let url = URL(string: urlString) {
                photoHero(url: url)
            }
            #endif
            heroTime(race: race)
            if let partner = race.partner, !partner.isEmpty {
                partnerPill(partner: partner)
            }
            splitsSection(race: race)
        }
    }

    // MARK: - Sections

    private func athleteHeader(race: RemotePublicRaceDetail) -> some View {
        Button {
            selectedAthleteID = race.userId
        } label: {
            HStack(spacing: 12) {
                avatar(urlString: race.athleteAvatarUrl)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.divider, lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(race.athleteDisplayName)
                        .font(.body.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                    Text("@\(race.athleteHandle)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func avatar(urlString: String?) -> some View {
        #if canImport(UIKit)
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
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

    private var defaultAvatarSymbol: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(Color.textTertiary, Color.surfaceElevated)
    }

    private func titleBlock(race: RemotePublicRaceDetail) -> some View {
        VStack(spacing: 4) {
            Text(displayedTitle(for: race))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
            Text(kindLabel(for: race))
                .font(.caption.weight(.bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func displayedTitle(for race: RemotePublicRaceDetail) -> String {
        let trimmed = race.name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Race" : trimmed
    }

    private func kindLabel(for race: RemotePublicRaceDetail) -> String {
        if race.mode == "duo" {
            return "HYROX Duo"
        }
        return race.isHyroxRace ? "HYROX Race" : "Custom Workout"
    }

    #if canImport(UIKit)
    private func photoHero(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Color.surfaceElevated
            @unknown default:
                Color.surfaceElevated
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
    }
    #endif

    private func heroTime(race: RemotePublicRaceDetail) -> some View {
        VStack(spacing: 4) {
            Text(RaceStats.format(race.totalDuration))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
            Text("Total time")
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func partnerPill(partner: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2.weight(.bold))
            Text("with \(partner)")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Color.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.accent.opacity(0.12)))
    }

    @ViewBuilder
    private func splitsSection(race: RemotePublicRaceDetail) -> some View {
        if !race.splits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Splits")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 6) {
                    ForEach(Array(race.splits.enumerated()), id: \.element.id) { index, split in
                        splitRow(index: index, split: split)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func splitRow(index: Int, split: PublicSplit) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.textTertiary)
                .monospacedDigit()
                .frame(width: 20)

            // Station glyph — leading column so the eye can scan
            // the column for station-kind at a glance instead of
            // reading the label. Falls back to a minus when the
            // station enum doesn't recognize the raw value (a
            // future server-side station addition we don't know
            // about yet).
            Image(systemName: split.typedStation?.glyph ?? "minus")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(stationLabel(for: split))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if let roxzone = split.roxzoneSeconds, roxzone > 0 {
                    Text("Roxzone " + RaceStats.format(roxzone))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
            }

            Spacer()

            Text(RaceStats.format(split.duration))
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
    }

    private func stationLabel(for split: PublicSplit) -> String {
        split.typedStation?.displayName ?? "Station \(split.station)"
    }

    // MARK: - States

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.accent)
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private var notFoundCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.warning)
            Text("Race not found")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("It may have been deleted or set to private.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}
