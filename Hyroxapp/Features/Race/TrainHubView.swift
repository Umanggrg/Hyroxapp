import SwiftUI
import SwiftData

// CLAUDE.md §14 Train tab — the action hub. Replaces the
// direct-to-RaceStartView entry the .race tab used to land on.
//
// Anatomy, top → bottom:
//   • Header strap  — caps "TRAIN" label + race-event countdown
//   • 2×2 grid      — 4 action cards covering every flavor of
//                     session the athlete might want to run
//                       🏁 Race Mode (hero, coral border)
//                       🔄 Race Simulation
//                       🏋️ Quick Station
//                       ⚡ Compromised
//   • Recommended  — Weakness-to-Workout Engine card (existing
//                    `RecommendedWorkoutCard`). Self-hides when
//                    no recommendation exists (no compromised-
//                    running data yet, or athlete is resilient
//                    on every station).
//
// Routing:
//   • Race Mode + Race Simulation push the existing RaceStartView
//     so the athlete keeps the target-time picker, Solo/Duo, and
//     event-countdown affordances they expect. Simulation tagging
//     (Race.kind enum) deferred until History needs to display
//     the distinction.
//   • Quick Station + Compromised present CustomWorkoutBuilderView
//     as a sheet, skipping the intermediate setup screen — these
//     are shorter-form training sessions where the athlete wants
//     to pick stations + go.
//
// The active-race resume path is unaffected: RaceView's phase
// machine still owns post-start UI; the Train hub is only
// rendered when `engine.state == .notStarted`.
struct TrainHubView: View {

    // Bindings threaded through to RaceStartView so the existing
    // Duo + pairing surfaces stay wired without TrainHubView
    // having to know what they do. RaceView owns these as
    // @State / @SceneStorage; we just pass them along.
    let viewModel: RaceViewModel
    @Binding var selectedMode: RaceMode
    @Binding var duoCoordinator: DuoCoordinator?
    @Binding var cloudDuoCoordinator: CloudDuoCoordinator?
    @Binding var duoController: DuoRaceController?
    @Binding var isPairingPresented: Bool
    @Binding var isCloudPairingPresented: Bool

    // Profile + races feed the Recommended for you card and the
    // Quick Station / Compromised sheet's start handler (reads
    // privacy default, countdown setting, live-activity toggle
    // — same fields RaceStartView reads).
    @Query(sort: [SortDescriptor(\UserProfile.createdAt, order: .forward)])
    private var profiles: [UserProfile]

    @Query(sort: [SortDescriptor(\Race.createdAt, order: .reverse)])
    private var allRaces: [Race]

    // Drives the navigation destination for the Race Mode +
    // Race Simulation cards. Item-based push because we want a
    // single shared destination view (RaceStartView) that
    // optionally branches on which card sent us there.
    @State private var pushedRaceStart: RaceStartIntent? = nil

    // Drives the Custom Workout Builder sheet for Quick Station
    // + Compromised cards. The enum carries the calling card so
    // the sheet's title / template prefilter can adapt.
    @State private var builderIntent: BuilderIntent? = nil

    enum RaceStartIntent: Hashable, Identifiable {
        case race
        case simulation
        var id: String {
            switch self {
            case .race: return "race"
            case .simulation: return "simulation"
            }
        }
    }

    enum BuilderIntent: Hashable, Identifiable {
        case quickStation
        case compromised
        var id: String {
            switch self {
            case .quickStation: return "quickStation"
            case .compromised: return "compromised"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                        .padding(.top, 8)

                    actionGrid

                    RecommendedWorkoutCard(races: allRaces)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, Layout.screenMargin)
                .padding(.bottom, 24)
            }
            .background(Color.background.ignoresSafeArea())
            .navigationDestination(item: $pushedRaceStart) { _ in
                // Both .race and .simulation push the same
                // RaceStartView. The intent enum is forward-compat
                // for when we want to preset the simulation flag
                // here (drives Race.kind = .simulation on start).
                RaceStartView(
                    viewModel: viewModel,
                    selectedMode: $selectedMode,
                    duoCoordinator: $duoCoordinator,
                    cloudDuoCoordinator: $cloudDuoCoordinator,
                    duoController: $duoController,
                    isPairingPresented: $isPairingPresented,
                    isCloudPairingPresented: $isCloudPairingPresented
                )
            }
            #if canImport(UIKit)
            .sheet(item: $builderIntent) { intent in
                CustomWorkoutBuilderView(
                    onStart: { sequence in
                        Haptics.impact(.medium)
                        viewModel.startRaceWithCountdown(
                            sequence: sequence,
                            targetDuration: nil,
                            countdownEnabled: countdownEnabled,
                            defaultPrivate: defaultRacePrivate,
                            liveActivityEnabled: liveActivityEnabled
                        )
                        builderIntent = nil
                    }
                )
            }
            #endif
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("TRAIN")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(2.0)
                .foregroundStyle(Color.accent)

            Spacer()

            if let event = nextEvent {
                eventCountdown(event)
            }
        }
        .padding(.vertical, 4)
    }

    private func eventCountdown(_ event: RaceEvent) -> some View {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: event.date)
        ).day ?? 0

        return HStack(spacing: 4) {
            Image(systemName: "flag.checkered")
                .font(.caption2.weight(.bold))
            Text(days == 0 ? "RACE DAY" : "T-\(days) days")
                .font(.caption.weight(.heavy))
                .tracking(0.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.surface)
                .overlay(
                    Capsule()
                        .stroke(Color.divider, lineWidth: 1)
                )
        )
    }

    private var nextEvent: RaceEvent? {
        // Lightweight @Query equivalent — pulled inline because
        // we only need it for this one optional render. Reuses
        // the existing RaceEvent model + sort. If we end up
        // needing the event in multiple places, promoting to a
        // @Query is cheap.
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<RaceEvent>(
            predicate: nil,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        guard let context = profiles.first?.modelContext,
              let events = try? context.fetch(descriptor) else { return nil }
        return events.first { $0.date >= today }
    }

    // MARK: - Action grid

    // 2×2 grid. Race Mode is the hero — coral accent border + a
    // touch larger visual weight via the icon glow. The other
    // three are surface-fill cards. All four are tappable; press
    // feedback via .pressableCard.
    private var actionGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            actionCard(
                icon: "flag.checkered",
                title: "Race Mode",
                subtitle: "Full 16-segment HYROX timing",
                isHero: true,
                action: { pushedRaceStart = .race }
            )
            actionCard(
                icon: "arrow.triangle.2.circlepath",
                title: "Race Simulation",
                subtitle: "Train against race format",
                isHero: false,
                action: { pushedRaceStart = .simulation }
            )
            actionCard(
                icon: "dumbbell.fill",
                title: "Quick Station",
                subtitle: "Single station, fast timer",
                isHero: false,
                action: { builderIntent = .quickStation }
            )
            actionCard(
                icon: "bolt.fill",
                title: "Compromised",
                subtitle: "Run → station → run",
                isHero: false,
                action: { builderIntent = .compromised }
            )
        }
    }

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        isHero: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(isHero ? Color.accent : Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .padding(Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(isHero ? Color.accent.opacity(0.08) : Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .stroke(
                        isHero ? Color.accent.opacity(0.45) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.pressableCard)
    }

    // MARK: - Profile-driven settings

    // Mirror the same fields RaceStartView reads from the
    // active profile so the start handler inside the builder
    // sheet has the right values without us threading bindings.
    private var countdownEnabled: Bool {
        profiles.first?.countdownEnabled ?? true
    }
    private var defaultRacePrivate: Bool {
        profiles.first?.defaultRacePrivate ?? false
    }
    private var liveActivityEnabled: Bool {
        profiles.first?.liveActivityEnabled ?? true
    }
}
