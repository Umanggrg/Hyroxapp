import Foundation

// "What Went Wrong?" narrative engine — Pillar 5 from CLAUDE.md §18.
//
// Where `RaceInsight` produces a list of disconnected bullets ("HR
// drifted +14 bpm", "Recovery elite", "Decoupling 8%"), this
// produces ONE coherent paragraph that reads like a coach
// summarizing the race after walking the floor.
//
// The narrative arc has three beats:
//
//   1. Opening — set the scene. How did the race resolve against
//      target/PB? What's the overall engine quality readout?
//
//   2. Middle — describe the turning point and what drove it. We
//      use the same dominant-sub-metric detection from
//      `EngineScoreContext` (#18) to identify which of drift /
//      recovery / efficiency / decoupling deviated most from the
//      athlete's recent baseline. That one sentence is the
//      "what happened" half of the story.
//
//   3. Closing — the #1 fix. Coaching prescription tied to the
//      dominant driver. Drift problem → Z2 volume; decoupling
//      problem → long easy runs; recovery problem → easy-pace
//      conditioning; efficiency problem → strength + pacing
//      practice on the worst station.
//
// Same RaceStats data dependencies as the insight generator
// (HR samples, splits, Race object, history). v1 is rule-based;
// v2 (queued in §17.6) replaces the rule tables with an LLM
// call against the athlete's full history.
struct RaceStory: Equatable {
    /// The full multi-sentence narrative paragraph. 3-5
    /// sentences. Always non-empty; on a race with insufficient
    /// data the generator returns a short "thin race" fallback
    /// rather than an empty string so the card never renders
    /// blank.
    let paragraph: String

    /// Optional one-line headline — the dominant takeaway from
    /// the story rendered as a 3-5 word punch line for the top
    /// of the card. Reads as the title above the paragraph.
    let headline: String

    /// Tone of the story — drives the card's color treatment.
    /// `.celebration` (success green) for PBs / breakthroughs,
    /// `.steady` (textPrimary) for normal-range races,
    /// `.diagnostic` (warning amber) for off-days that need
    /// coaching action.
    let tone: Tone

    enum Tone: String, Equatable {
        case celebration
        case steady
        case diagnostic
    }
}

enum RaceStoryGenerator {

    // MARK: - Public

    /// Build the race story for a given race. Requires the full
    /// race + the athlete's race history (for sub-metric
    /// baselines) + max HR (for engine score normalization).
    /// Returns nil only when there's truly nothing to say —
    /// race not finished, or no signals at all to anchor a
    /// narrative against. In every other case, returns a story
    /// even if some sub-metrics are missing.
    static func generate(
        for race: Race,
        history: [Race],
        maxHR: Int
    ) -> RaceStory? {
        guard race.isFinished, let total = race.totalDuration else {
            return nil
        }

        // The engine-score context is our primary narrative
        // anchor. Without it (no HR data, first race ever, etc),
        // we fall back to a time-only story.
        let context = RaceStats.engineScoreContext(
            forRace: race,
            history: history,
            maxHR: maxHR
        )

        if let context {
            return richStory(
                race: race,
                total: total,
                context: context
            )
        } else {
            return thinStory(race: race, total: total)
        }
    }

    // MARK: - Rich narrative path (engine-score context available)

    private static func richStory(
        race: Race,
        total: TimeInterval,
        context: RaceStats.EngineScoreContext
    ) -> RaceStory {
        // Tone first — drives card color + headline framing.
        let tone: RaceStory.Tone = {
            if context.isAllTimeBest { return .celebration }
            switch context.position {
            case .breakthrough: return .celebration
            case .regression:   return .diagnostic
            case .normal:       return .steady
            }
        }()

        let opening = openingSentence(race: race, total: total, context: context)
        let middle = middleSentence(race: race, context: context)
        let closing = closingSentence(context: context)
        let headline = headlineFor(tone: tone, context: context)

        // Stitch with single spaces. Two-sentence races (when
        // middle returns empty) read as "X. Y." not "X.  . Y."
        let parts = [opening, middle, closing].filter { !$0.isEmpty }
        let paragraph = parts.joined(separator: " ")

        return RaceStory(
            paragraph: paragraph,
            headline: headline,
            tone: tone
        )
    }

    private static func openingSentence(
        race: Race,
        total: TimeInterval,
        context: RaceStats.EngineScoreContext
    ) -> String {
        let timeStr = RaceStats.format(total)
        let score = Int(context.thisRaceScore.rounded())

        if context.isAllTimeBest {
            return "You finished at \(timeStr) — your best engine race ever, scoring \(score)."
        }

        switch context.position {
        case .breakthrough:
            let delta = Int(context.delta.rounded())
            return "You finished at \(timeStr) with engine \(score) — \(delta) above your recent average."
        case .regression:
            let absDelta = Int(abs(context.delta).rounded())
            return "You finished at \(timeStr) with engine \(score) — \(absDelta) below your recent average."
        case .normal:
            // Pull the tier into the opening so the sentence
            // says something concrete even when the score is in
            // a normal range relative to history.
            return "You finished at \(timeStr) — engine \(score), \(context.tierLabel.lowercased())."
        }
    }

    private static func middleSentence(
        race: Race,
        context: RaceStats.EngineScoreContext
    ) -> String {
        // Normal-range races without a dominant sub-metric get
        // a generic "balanced" middle. Otherwise we name the
        // sub-metric and describe the specific signal.
        guard let driver = context.dominantSubMetric else {
            switch context.position {
            case .breakthrough: return "Every system was firing today."
            case .regression:   return "No single metric collapsed — the whole engine was a step off."
            case .normal:       return "Balanced effort across the engine systems."
            }
        }

        let isPositive = context.position == .breakthrough || context.isAllTimeBest

        switch driver {
        case .drift:
            if isPositive {
                if let drift = RaceStats.heartRateDrift(for: race) {
                    let bpm = Int(drift.driftBPM.rounded())
                    return "HR drift held to \(bpm) bpm across the runs — the aerobic base showed up."
                }
                return "Cardiac drift was minimal — engine held steady through every run."
            } else {
                if let drift = RaceStats.heartRateDrift(for: race) {
                    let bpm = Int(drift.driftBPM.rounded())
                    return "HR climbed \(bpm) bpm across the runs while pace tried to hold — the engine faded."
                }
                return "HR climbed across the runs — the aerobic base couldn't sustain race pace."
            }

        case .recovery:
            if isPositive {
                if let recovery = RaceStats.recoveryScore(for: race) {
                    let bpm = Int(recovery.averageDrop30s.rounded())
                    return "Between-station recovery was elite — HR dropped \(bpm) bpm in 30s on average."
                }
                return "Recovery between stations was tight — the conditioning paid off."
            } else {
                if let recovery = RaceStats.recoveryScore(for: race) {
                    let bpm = Int(recovery.averageDrop30s.rounded())
                    return "Recovery between stations was slow — only \(bpm) bpm drop in 30s on average."
                }
                return "Recovery between stations couldn't keep up — HR stayed elevated into the next run."
            }

        case .efficiency:
            if isPositive {
                return "Output-per-HR ratio was strong — you produced more pace at lower HR cost than usual."
            } else {
                return "Output-per-HR ratio dropped — the engine worked harder than usual for the same pace."
            }

        case .decoupling:
            if isPositive {
                if let decoupling = RaceStats.aerobicDecoupling(for: race) {
                    let pct = Int((decoupling.decouplingFraction * 100).rounded())
                    return "Pace-per-HR ratio held — only \(pct)% decoupling across the runs."
                }
                return "Aerobic decoupling was minimal — the engine held its output gracefully."
            } else {
                if let decoupling = RaceStats.aerobicDecoupling(for: race) {
                    let pct = Int((decoupling.decouplingFraction * 100).rounded())
                    return "Pace-per-HR ratio decoupled \(pct)% across the run halves — the aerobic gap is the story."
                }
                return "The pace-per-HR ratio fell off in the back half — significant aerobic decoupling."
            }
        }
    }

    private static func closingSentence(
        context: RaceStats.EngineScoreContext
    ) -> String {
        // Normal-range races without a driver get a generic
        // affirmation. With a driver, prescribe the standard
        // fix for that sub-metric.
        guard let driver = context.dominantSubMetric else {
            switch context.position {
            case .breakthrough: return "Maintain the volume and add quality."
            case .regression:   return "Recovery week — pull volume, sleep extra, come back fresh."
            case .normal:       return "Hold the rhythm — this is race-fit conditioning."
            }
        }

        let isPositive = context.position == .breakthrough || context.isAllTimeBest

        switch driver {
        case .drift:
            return isPositive
                ? "Lock in the long Z2 work — that's the engine you just raced."
                : "Long Z2 weeks build the aerobic base that prevents this drift."

        case .recovery:
            return isPositive
                ? "Keep the easy-pace volume — recovery is your weapon."
                : "Add easy-pace volume to teach your engine to bring HR down faster."

        case .efficiency:
            return isPositive
                ? "Strength + pacing practice keeps this efficiency curve climbing."
                : "Train compromised running on the worst-efficiency station to close the gap."

        case .decoupling:
            return isPositive
                ? "Hold this aerobic base — long Z2 keeps decoupling minimal."
                : "Long easy weeks fix decoupling — durability is a separate gear from speed."
        }
    }

    private static func headlineFor(
        tone: RaceStory.Tone,
        context: RaceStats.EngineScoreContext
    ) -> String {
        if context.isAllTimeBest {
            return "Best engine race"
        }
        switch tone {
        case .celebration: return "Breakthrough day"
        case .steady:      return "Race-fit performance"
        case .diagnostic:  return "Off-day engine"
        }
    }

    // MARK: - Thin narrative path (no HR / no engine context)

    // Falls back to a time + tier story when the rich engine
    // context isn't available — typical first-race-with-HR or
    // races logged without a Watch. The narrative is shorter
    // (no sub-metric driver to point at) but still reads as a
    // coherent observation rather than an empty card.
    private static func thinStory(race: Race, total: TimeInterval) -> RaceStory {
        let timeStr = RaceStats.format(total)
        let opening = "You finished at \(timeStr)."

        let middle: String = {
            if let target = race.targetDuration {
                let delta = total - target
                if abs(delta) < 30 {
                    return "Right on target — clean race execution."
                } else if delta < 0 {
                    let ahead = RaceStats.format(abs(delta))
                    return "\(ahead) ahead of your goal — strong execution."
                } else {
                    let behind = RaceStats.format(delta)
                    return "\(behind) over target — a hard-fought race that landed long of the goal."
                }
            }
            return "A solid completion — every segment captured."
        }()

        let closing = "Capture HR data on the next race and we can break down the why."

        return RaceStory(
            paragraph: [opening, middle, closing].joined(separator: " "),
            headline: "Race recap",
            tone: .steady
        )
    }
}

// Small extension for the headline / opening sentence to read
// the tier as a clean lowercase string ("steady" / "elite" /
// "building"). Living next to the generator since it's only
// used here.
private extension RaceStats.EngineScore.Tier {
    var label: String { displayName }
}

extension RaceStats.EngineScoreContext {
    /// Short label for the tier this race's engine score lands
    /// in. Used by the narrative generator to compose a fluent
    /// opening sentence.
    var tierLabel: String {
        RaceStats.EngineScore.tier(forScore: thisRaceScore).displayName
    }
}
