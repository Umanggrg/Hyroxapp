import SwiftUI

// The canonical race card. Strava-inspired anatomy described in CLAUDE.md §5:
// header (title + relative time) → hero stat (total time) → supporting stats
// (3-up grid) → optional badges (e.g. PB). Lives in Shared/Components/ so it
// can appear anywhere we need to render a race row:
//   - History feed (primary consumer today)
//   - Profile "Recent races" section
//   - Future v1 social feed — a flag for social actions (like/comment/share)
//     will slot in at the bottom without changing the rest of the card.
//
// The PB badge is derived from `allRaces`, not a property on the race model
// itself, because "was this a PB at the time it was set?" depends on every
// earlier race. Passing the slice at render time keeps the model clean and
// lets callers decide what pool of races to evaluate against (all races,
// this month, just this user's, etc. when social lands).
struct RaceCardView: View {

    let race: Race
    let allRaces: [Race]

    // Athlete's max HR — drives the effort-category chip in the
    // badge row. Defaults to 190 (matches `UserProfile.maxHeartRate`'s
    // own default) so callers that don't have access to the user
    // profile (recap previews, share-card render passes) still get
    // a defensible chip if HR data is present. Pass the real value
    // from any call site that's already querying UserProfile.
    var maxHR: Int = 190

    // Drives the badge entrance animation — PB and effort chips
    // scale in with a spring on first appear so they feel earned
    // rather than just static decoration. Initial state false; flips
    // to true 0.1s after onAppear (one runloop tick) so the layout
    // settles before the spring fires.
    @State private var badgesRevealed = false

    // Presents `PublicProfileSheet` when the partner's name is
    // tapped on a duo race card. Only fires when
    // `race.partnerUserID` is non-nil — the gesture is hidden
    // otherwise.
    @State private var isShowingPartnerSheet = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPB: Bool {
        RaceStats.wasPBWhenSet(race, among: allRaces)
    }

    // Race-wide effort category — pull avg HR across all splits with
    // data, divide by maxHR, bucket. Returns nil for races without
    // HR data so the chip just doesn't render rather than showing
    // a misleading "Recovery" for an unmeasured race.
    private var effortCategory: RaceStats.EffortCategory? {
        let scoredSplits = race.splits.compactMap { split -> (avg: Double, duration: TimeInterval)? in
            guard let avg = split.heartRateAvgBPM, avg > 0, split.duration > 0 else {
                return nil
            }
            return (avg, split.duration)
        }
        guard !scoredSplits.isEmpty else { return nil }

        // Duration-weighted average HR across the race — same shape as
        // a single-split fraction, just summed across the race.
        // Long stations weigh more than short ones, which matches how
        // an athlete experiences the day.
        let totalDuration = scoredSplits.reduce(0) { $0 + $1.duration }
        guard totalDuration > 0 else { return nil }
        let weightedAvg = scoredSplits.reduce(0) { $0 + ($1.avg * $1.duration) } / totalDuration
        let fraction = weightedAvg / Double(maxHR)

        switch fraction {
        case ..<0.65:
            return .recovery
        case ..<0.75:
            return .moderate
        case ..<0.85:
            return .high
        default:
            return .veryHigh
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Photo (when present) sits flush at the top of the card
            // with no padding so it reads as a true hero image —
            // exactly the way Strava's activity cards anchor on the
            // route map. Without a photo, this branch is skipped and
            // the card renders compact, identical to before.
            #if canImport(UIKit)
            // Display preference order:
            //   1. Local bytes (photoData) — zero-latency, ALWAYS
            //      preferred when present.
            //   2. Remote URL (photoURL) — synced from another
            //      device. Loads via AsyncImage; URLSession's
            //      shared cache amortizes re-fetches.
            //   3. No hero — card renders compact, identical to
            //      pre-photo layouts.
            if let data = race.photoData, let image = UIImage(data: data) {
                photoHero(image: image)
            } else if let urlString = race.photoURL,
                      let url = URL(string: urlString) {
                photoHeroRemote(url: url)
            }
            #endif

            VStack(alignment: .leading, spacing: 14) {
                header
                hero
                supportingStats
                // Badge row — PB and effort category each render
                // independently. Wrapped in HStack so they sit
                // side-by-side when both are present without an
                // extra wrapper view.
                if isPB || effortCategory != nil {
                    HStack(spacing: 10) {
                        if isPB {
                            pbBadge
                                .scaleEffect(badgesRevealed ? 1.0 : 0.6)
                                .opacity(badgesRevealed ? 1.0 : 0)
                        }
                        if let category = effortCategory {
                            effortBadge(category: category)
                                .scaleEffect(badgesRevealed ? 1.0 : 0.6)
                                .opacity(badgesRevealed ? 1.0 : 0)
                        }
                        Spacer()
                    }
                    // Spring entrance for the badge row. Small
                    // overshoot from the .spring damping ratio
                    // (0.65) gives a satisfying "lands with weight"
                    // feel. Reduce-motion bypass for accessibility.
                    .animation(
                        reduceMotion ? .none : .spring(response: 0.45, dampingFraction: 0.65).delay(0.15),
                        value: badgesRevealed
                    )
                }

                // Tag chips — small lowercase pills under the
                // badge row. Capped at 3 visible to avoid
                // crowding; remaining count shown as "+N".
                // Hidden when no tags. Match the tint used on
                // the editor (accent at 0.12 fill).
                if !race.tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(race.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(Color.accent.opacity(0.10))
                                )
                        }
                        if race.tags.count > 3 {
                            Text("+\(race.tags.count - 3)")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(Layout.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                .fill(Color.surface)
        )
        // Clip the entire card so the photo's top corners follow the
        // card's rounded shape; without this the image overflows the
        // background's rounded rectangle on the top edge.
        .clipShape(RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
        .sheet(isPresented: $isShowingPartnerSheet) {
            if let partnerUserID = race.partnerUserID {
                PublicProfileSheet(userID: partnerUserID)
            }
        }
        .onAppear {
            // Spring-in the badge row one runloop tick after the
            // card lands. Cards in a long History feed reveal as
            // the user scrolls them into view (SwiftUI re-fires
            // onAppear when off-screen views become visible),
            // turning the History scroll into a series of small
            // flourishes rather than a static grid.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                badgesRevealed = true
            }
        }
    }

    // MARK: - Photo hero (top banner when race has a photo)

    #if canImport(UIKit)
    private func photoHero(image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipped()
            .modifier(PhotoHeroFadeModifier())
    }

    // Remote-URL variant. Same chrome (180pt fixed height,
    // bottom gradient fade) as the local-bytes path so the
    // card looks identical regardless of which source rendered
    // the hero. While loading or on failure, shows a muted
    // placeholder card-surface band — visually less abrupt
    // than collapsing the layout to no-photo height.
    private func photoHeroRemote(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .empty, .failure:
                Color.surfaceElevated
            @unknown default:
                Color.surfaceElevated
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .clipped()
        .modifier(PhotoHeroFadeModifier())
    }
    #endif

    // Shared bottom-gradient fade applied to both the local-
    // bytes and remote-URL hero variants. Subtle taper from
    // transparent → 50% surface so the image feels like part
    // of the card rather than a stamped-on rectangle.
    private struct PhotoHeroFadeModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            Color.surface.opacity(0),
                            Color.surface.opacity(0.5)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            // Show user-set title when present; fall back to the
            // generic "HYROX Race" label otherwise. Two-line stack
            // when a custom name exists so the kind indicator
            // ("HYROX RACE" caps) stays visible — same pattern
            // Strava uses for activities with a custom title.
            //
            // Duo races also surface the partner's name as a
            // sub-line ("Duo · with Sarah"), so a duo entry in
            // History reads as a shared moment rather than a
            // generic race.
            VStack(alignment: .leading, spacing: 2) {
                if !race.name.isEmpty {
                    Text(race.mode == .duo ? "DUO RACE" : "HYROX RACE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.6)
                        .foregroundStyle(race.mode == .duo ? Color.accent : Color.textTertiary)
                    Text(race.name)
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    if race.mode == .duo, let partner = race.partner, !partner.isEmpty {
                        partnerLine(partner: partner)
                    }
                } else {
                    Text(race.mode == .duo ? "Duo Race" : "HYROX Race")
                        .font(.cardTitle)
                        .foregroundStyle(Color.textPrimary)
                    if race.mode == .duo, let partner = race.partner, !partner.isEmpty {
                        partnerLine(partner: partner)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(race.startedAt.formatted(.relative(presentation: .named)))
                    .font(.metadata)
                    .foregroundStyle(Color.textSecondary)

                // Private indicator — small lock icon when this race is
                // flagged private. Forward-compatible with the v1 social
                // feed: athletes scanning their own History at a glance
                // can tell which races would be hidden if/when public
                // surfaces ship. Hidden entirely for public races to
                // keep the card clean.
                if race.isPrivate {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .heavy))
                        Text("PRIVATE")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                    }
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.warning.opacity(0.16))
                    )
                }
            }
        }
    }

    // "with Sarah" sub-line for duo races, plus an optional
    // "· left at MM:SS" annotation when the partner dropped
    // mid-race. Single helper so both branches of the title
    // block (named race / unnamed race) render the same shape.
    @ViewBuilder
    private func partnerLine(partner: String) -> some View {
        if let leftAt = race.partnerDisconnectedAt,
           let elapsed = partnerLeftElapsed(at: leftAt) {
            HStack(spacing: 4) {
                partnerWithLabel(partner: partner)
                Text("· left at \(RaceStats.format(elapsed))")
                    .foregroundStyle(Color.warning)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
        } else {
            partnerWithLabel(partner: partner)
                .font(.caption.weight(.semibold))
        }
    }

    // "with Sarah" rendering — splits into "with " (plain) + the
    // partner name. When `race.partnerUserID` is non-nil
    // (cloud-tier duo), the name becomes a tap target that opens
    // `PublicProfileSheet` for that user. Solo races and Tier 1
    // Multipeer duo races (no Supabase auth concept) render as
    // plain text — same visual style, no tap affordance.
    //
    // Why a Button-inside-NavigationLink works: SwiftUI prefers
    // the innermost gesture handler. The card-wrapping
    // NavigationLink picks up taps outside this Button; this
    // Button captures taps on the name itself and presents the
    // sheet.
    @ViewBuilder
    private func partnerWithLabel(partner: String) -> some View {
        if let partnerUserID = race.partnerUserID, !partnerUserID.isEmpty {
            HStack(spacing: 0) {
                Text("with ")
                    .foregroundStyle(Color.textSecondary)
                Button {
                    isShowingPartnerSheet = true
                } label: {
                    Text(partner)
                        .foregroundStyle(Color.accent)
                        .underline(true, color: Color.accent.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("with \(partner)")
                .foregroundStyle(Color.textSecondary)
        }
    }

    // Convert the absolute disconnect timestamp to "race-relative"
    // elapsed time. nil when the race had no startedAt or the
    // disconnect was logged before the start (shouldn't happen,
    // defensive). Used by partnerLine to render the "left at MM:SS"
    // annotation in race-time terms rather than wall-clock.
    private func partnerLeftElapsed(at disconnect: Date) -> TimeInterval? {
        let elapsed = disconnect.timeIntervalSince(race.startedAt)
        return elapsed >= 0 ? elapsed : nil
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(RaceStats.totalTime(race))
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
            Text("TOTAL TIME")
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.0)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var supportingStats: some View {
        HStack(spacing: 0) {
            statTile(value: RaceStats.bestRun(race), label: "Best Run")
            statDivider
            statTile(value: RaceStats.avgRun(race), label: "Avg Run")
            statDivider
            statTile(value: RaceStats.wallBalls(race), label: "Wall Balls")
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.divider)
            .frame(width: 1, height: 32)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var pbBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.caption)
            Text("New PB")
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.success)
    }

    // Effort category badge — small chip showing how hard this race
    // was overall (Recovery / Moderate / High / Very High). Color
    // matches the StationDetailView per-station chip and the
    // EffortCategory enum's symbol contract, so the same language
    // shows up at every effort surface in the app. Hidden when no
    // HR data was captured for the race.
    private func effortBadge(category: RaceStats.EffortCategory) -> some View {
        let tint: Color = {
            switch category {
            case .recovery: return .success
            case .moderate: return .textPrimary
            case .high:     return .warning
            case .veryHigh: return .accent
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.caption)
            Text(category.displayName)
                .font(.caption.weight(.bold))
                .tracking(0.3)
                .textCase(.uppercase)
        }
        .foregroundStyle(tint)
    }
}
