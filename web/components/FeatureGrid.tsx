// Feature grid. Six cards, each with the same anatomy as the
// in-app section cards: caps label, headline, supporting copy,
// and a small visual signal (icon glyph + accent dot).
const FEATURES = [
  {
    label: "Race Mode",
    title: "One tap to start. One tap per station.",
    body: "Giant always-visible total timer, single huge advance button, splits captured automatically. The screen stays awake; the state survives a backgrounded app.",
    glyph: "▶︎",
  },
  {
    label: "Heart rate + zones",
    title: "Live HR, full Z1–Z5 breakdown.",
    body: "Avg, max, and current HR streamed from HealthKit. Per-station chips, time-in-zone bars, voice cues when you cross into Z4 or Z5.",
    glyph: "♥",
  },
  {
    label: "Roxzone discipline",
    title: "Track the seconds between stations.",
    body: "Optional two-step advance times your transitions. Total roxzone, average per station, and a discipline insight call out where the race actually slipped.",
    glyph: "↺",
  },
  {
    label: "Effort + readiness",
    title: "How hard you went. How ready you are.",
    body: "HR-time integration produces a per-race effort score, a recovery estimate, and a today's-readiness banner — Fresh, Partial, or Recovering.",
    glyph: "◐",
  },
  {
    label: "History + analytics",
    title: "Strava-shaped feed of your races.",
    body: "Cards with PB indicators, fatigue curves over the eight runs, compromised-running analysis, monthly + yearly recaps, and a calendar heatmap of training density.",
    glyph: "◇",
  },
  {
    label: "Challenges + streaks",
    title: "Reasons to come back this week.",
    body: "Pick from preset challenges — five races in 30 days, a sub-1:30 race, a 7-day streak. Streak banner, at-risk nudges, and earned badges live on your profile.",
    glyph: "◆",
  },
];

export function FeatureGrid() {
  return (
    <section
      id="features"
      className="mx-auto max-w-6xl px-6 py-20 sm:py-24 lg:py-28"
    >
      <div className="max-w-2xl mb-10 sm:mb-14">
        <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-3">
          What's inside
        </p>
        <h2 className="font-rounded font-bold text-3xl sm:text-5xl tracking-tight">
          Built like the racers we are.
        </h2>
        <p className="text-text-secondary mt-4 text-base sm:text-lg leading-relaxed">
          Every feature exists because we needed it on the gym floor. Nothing
          gets in your way mid-race; everything is waiting for you on the
          summary screen.
        </p>
      </div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {FEATURES.map((f) => (
          <article
            key={f.label}
            className="group relative rounded-card bg-surface border border-divider/60 p-6 hover:border-accent/40 transition shadow-card overflow-hidden"
          >
            <div className="absolute inset-x-0 top-0 h-px bg-card-edge" />
            <div className="flex items-center justify-between">
              <p className="text-[11px] uppercase tracking-caps text-text-tertiary">
                {f.label}
              </p>
              <span
                aria-hidden
                className="text-accent text-lg leading-none group-hover:scale-110 transition"
              >
                {f.glyph}
              </span>
            </div>
            <h3 className="mt-5 font-rounded font-semibold text-xl leading-tight">
              {f.title}
            </h3>
            <p className="mt-3 text-sm text-text-secondary leading-relaxed">
              {f.body}
            </p>
          </article>
        ))}
      </div>
    </section>
  );
}
