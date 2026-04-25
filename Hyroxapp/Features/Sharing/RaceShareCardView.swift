import SwiftUI

// The shareable race card — the SwiftUI view that gets baked into a
// PNG by `RaceShareRenderer` and handed off to iOS's share sheet.
//
// Design intent: HYROX's answer to a Strava activity card. Strava's
// hero is the GPS map — your route is the visual signature. We don't
// have GPS (see CLAUDE.md §1 non-goals), so the visual signature is
// the **race fingerprint**: 16 vertical bars, one per segment, with
// height proportional to segment duration and color coded run vs
// workout. Two athletes with identical total times will have totally
// different fingerprints — that's the shareable thing.
//
// Sized for a 1:1 export (1080×1080 at @3x renders as 360pt). Square
// works as an Instagram post and crops cleanly to story; one design
// covers both surfaces.
//
// Guarded `#if !os(watchOS)` because it leans on iOS Color.background
// + CGImage rendering and would never render from a Watch context.
#if !os(watchOS)

// Aspect ratio + sizing for the rendered share image. The canvas
// is laid out in points and rendered at 3× by `RaceShareRenderer`,
// so a 360pt-wide canvas exports as 1080px — Instagram quality.
//
//   • square — 1:1, ideal for IG feed posts and the share preview
//     thumbnail. The default.
//   • story  — 9:16, ideal for IG / Snapchat / TikTok stories.
//     Same content but with extra vertical breathing room and
//     scaled-up typography so the card fills the screen.
enum ShareCardFormat {
    case square
    case story

    var canvasSize: CGSize {
        switch self {
        case .square: return CGSize(width: 360, height: 360)
        case .story:  return CGSize(width: 360, height: 640)
        }
    }

    var heroFontSize: CGFloat {
        switch self {
        case .square: return 76
        case .story:  return 104
        }
    }

    var fingerprintHeight: CGFloat {
        switch self {
        case .square: return 70
        case .story:  return 130
        }
    }

    // Extra vertical padding that pushes content apart in story
    // mode — Spacer(minLength:) values bump up so the hero
    // floats high in the canvas with the footer pinned low.
    var verticalSpacing: CGFloat {
        switch self {
        case .square: return 0
        case .story:  return 20
        }
    }

    // File-name suffix, baked into the export name so square +
    // story exports of the same race don't collide on disk.
    var filenameSuffix: String {
        switch self {
        case .square: return "square"
        case .story:  return "story"
        }
    }

    // Human-friendly label for the format-picker menu.
    var menuLabel: String {
        switch self {
        case .square: return "Square (Post)"
        case .story:  return "Story (9:16)"
        }
    }
}

struct RaceShareCardView: View {

    let race: Race
    let profile: UserProfile?
    let allRaces: [Race]
    let format: ShareCardFormat

    // Backwards-compat default — pre-existing call sites that
    // didn't take a format keep rendering as 1:1 squares.
    init(
        race: Race,
        profile: UserProfile?,
        allRaces: [Race],
        format: ShareCardFormat = .square
    ) {
        self.race = race
        self.profile = profile
        self.allRaces = allRaces
        self.format = format
    }

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.horizontal, 28)

                Spacer(minLength: format.verticalSpacing)

                heroTime

                if let pbRibbon = pbRibbonText {
                    pbRibbon_view(pbRibbon)
                        .padding(.top, 10)
                }

                Spacer(minLength: format.verticalSpacing)

                fingerprint
                    .padding(.horizontal, 28)
                    .padding(.bottom, 16)

                statsRow
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)

                athleteFooter
                    .padding(.horizontal, 28)
                    .padding(.bottom, 18)
            }
        }
        .frame(width: format.canvasSize.width, height: format.canvasSize.height)
        .background(Color.background)
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }

    // Background layer — chooses between the user's attached photo
    // (rendered full-canvas, slightly blurred, dark-overlaid for
    // legibility) and the default coral radial gradient. The photo
    // path makes shared cards feel personal: it's no longer just a
    // template, it's THIS race, with my gym selfie behind the
    // numbers. Apple Music's lyrics-over-album-art treatment.
    @ViewBuilder
    private var backgroundLayer: some View {
        if let data = race.photoData,
           let uiImage = UIImage(data: data) {
            ZStack {
                // Photo fills the canvas, blurred 8pt so the data
                // layer reads above it as the focal point. Without
                // the blur, fine detail in the photo would compete
                // with the time + fingerprint typography.
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: format.canvasSize.width,
                        height: format.canvasSize.height
                    )
                    .clipped()
                    .blur(radius: 8)

                // Dark overlay for legibility — 65% opacity gives
                // enough darkness for white text without erasing
                // the photo entirely. Same overlay strength Apple
                // uses on iOS lock-screen wallpapers when an
                // overlay-friendly clock is shown.
                Color.background.opacity(0.65)

                // Coral wash at the bottom keeps the brand color
                // present in the composition even when the photo
                // is monochrome / cool-toned. Subtle — 12% opacity.
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.accent.opacity(0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            // No-photo fallback: the original coral radial gradient.
            // Same look the share card had before photos shipped, so
            // existing race exports stay visually unchanged.
            RadialGradient(
                colors: [
                    Color.accent.opacity(0.18),
                    Color.background
                ],
                center: .center,
                startRadius: 20,
                endRadius: format.canvasSize.height * 0.7
            )
            .background(Color.background)
        }
    }

    // MARK: - Header (caps wordmark + date)

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 11, weight: .bold))
                Text("HYROX RACE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
            }
            .foregroundStyle(Color.accent)

            Spacer()

            Text(dateString)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - Hero time

    private var heroTime: some View {
        VStack(spacing: 4) {
            Text(RaceStats.format(totalDuration))
                .font(.system(size: format.heroFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 16)

            Text("TOTAL TIME")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - PB ribbon (only if this race set a new PB)

    private var pbRibbonText: String? {
        // PB ribbon shows when this race's total time is the best
        // ever. We compare against `allRaces` filtered to finished;
        // any race finishing on or before this race's endedAt with
        // a faster total would disqualify the ribbon.
        guard let endedAt = race.endedAt else { return nil }
        let priorBest = allRaces
            .filter { otherRace in
                guard let otherEnd = otherRace.endedAt else { return false }
                return otherRace.id != race.id && otherEnd <= endedAt
            }
            .compactMap(\.totalDuration)
            .min()

        guard let priorBest else { return "NEW PB" }
        if totalDuration < priorBest {
            let delta = priorBest - totalDuration
            return "NEW PB · \(RaceStats.format(delta)) faster"
        }
        return nil
    }

    private func pbRibbon_view(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rosette")
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .monospacedDigit()
        }
        .foregroundStyle(Color(hex: 0xFFD60A))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: 0xFFD60A).opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: 0xFFD60A).opacity(0.4), lineWidth: 1)
                )
        )
    }

    // MARK: - Race fingerprint (the visual signature)

    // 16 vertical bars (or N for custom workouts), one per segment.
    // Bar height scales linearly with segment duration relative to
    // the slowest segment. Run bars are muted (textSecondary) and
    // workout bars are HYROX coral (.accent). The result reads as a
    // "barcode" of the athlete's race.
    private var fingerprint: some View {
        let splits = race.splits
        let maxDuration = splits.map(\.duration).max() ?? 1

        return GeometryReader { geo in
            let trackHeight = geo.size.height
            let totalGap: CGFloat = CGFloat(max(splits.count - 1, 0)) * 4
            let barWidth = max((geo.size.width - totalGap) / CGFloat(max(splits.count, 1)), 4)

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(splits.enumerated()), id: \.offset) { _, split in
                    let normalized = maxDuration > 0
                        ? CGFloat(split.duration / maxDuration)
                        : 0
                    // Floor at 12% so the shortest bar is still visibly
                    // a bar — without this, very fast runs collapse to
                    // almost nothing relative to a slow Wall Balls.
                    let height = max(trackHeight * normalized, trackHeight * 0.12)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: split.station))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(width: geo.size.width, height: trackHeight, alignment: .bottom)
        }
        .frame(height: format.fingerprintHeight)
    }

    private func barColor(for station: Station) -> Color {
        switch station.kind {
        case .run:     return Color.textSecondary.opacity(0.85)
        case .workout: return Color.accent
        }
    }

    // MARK: - Stats row (3-up tile grid)

    // Three tiles: best run, average HR (or stations completed if no
    // HR data), total active calories (or splits count). Picks the
    // most informative trio available; gracefully degrades when
    // HealthKit data is absent.
    private var statsRow: some View {
        HStack(spacing: 8) {
            statTile(value: bestRunString, label: "BEST RUN")
            statTile(value: secondaryStatValue, label: secondaryStatLabel)
            statTile(value: tertiaryStatValue, label: tertiaryStatLabel)
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.surface)
        )
    }

    // MARK: - Athlete footer

    // Row: avatar (or coral initial circle) + display name + handle
    // + division. Pulls from `profile`; falls back to placeholders
    // when no profile exists yet (defensive — by v0.1 a profile is
    // always bootstrapped on first launch).
    private var athleteFooter: some View {
        HStack(spacing: 10) {
            avatar
                .frame(width: 32, height: 32)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(profile?.displayName ?? "HYROX Athlete")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let handle = profile?.handle, !handle.isEmpty {
                        Text("@\(handle)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    if let div = profile?.resolvedDivision.displayName {
                        Text("·")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                        Text(div)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .lineLimit(1)
            }

            Spacer()

            // Branded wordmark on the right so the card reads as
            // unmistakably "from Hyroxapp" when it lands in someone
            // else's feed. Coral over pill for visual weight without
            // shouting.
            Text("HYROXAPP")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .stroke(Color.accent.opacity(0.5), lineWidth: 1)
                )
        }
    }

    // Avatar: profile's saved photo if present, otherwise a coral
    // circle with the first letter of the display name (Strava-style
    // fallback initials).
    @ViewBuilder
    private var avatar: some View {
        if let data = profile?.avatarData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(Color.accent.opacity(0.25))
                Text(initial)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.accent)
            }
        }
    }

    private var initial: String {
        let name = profile?.displayName ?? "H"
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - Computed values

    private var totalDuration: TimeInterval {
        race.totalDuration ?? race.splits.reduce(0) { $0 + $1.duration }
    }

    private var dateString: String {
        let date = race.endedAt ?? race.startedAt
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }

    private var bestRunString: String {
        let runs = race.splits.filter { $0.station.kind == .run }
        guard let best = runs.map(\.duration).min() else { return "—" }
        return RaceStats.format(best)
    }

    // Secondary tile prefers Avg HR when available; falls back to
    // station count to ensure all three tiles always have content.
    private var secondaryStatValue: String {
        let hrs = race.splits.compactMap(\.heartRateAvgBPM)
        if !hrs.isEmpty {
            let avg = hrs.reduce(0, +) / Double(hrs.count)
            return "\(Int(avg.rounded()))"
        }
        return "\(race.splits.count)"
    }
    private var secondaryStatLabel: String {
        race.splits.contains(where: { $0.heartRateAvgBPM != nil })
            ? "AVG HR"
            : "STATIONS"
    }

    // Tertiary tile prefers calories; falls back to a workout-only
    // bestSplit (fastest workout station).
    private var tertiaryStatValue: String {
        if let kcal = RaceStats.totalActiveCalories(race) {
            return "\(Int(kcal.rounded()))"
        }
        return "\(race.splits.filter { $0.station.kind == .workout }.count)"
    }
    private var tertiaryStatLabel: String {
        RaceStats.totalActiveCalories(race) != nil ? "KCAL" : "WORKOUTS"
    }
}
#endif
