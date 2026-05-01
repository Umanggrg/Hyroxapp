// The 16-station HYROX-style race format, visualized as a strip
// of pills. Reinforces the product's specificity in one glance —
// this is not a generic workout logger.
const STATIONS: Array<{ short: string; kind: "run" | "station" }> = [
  { short: "1km Run", kind: "run" },
  { short: "Sled Push", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Sled Pull", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Burpee BJ", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Row 1km", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Farmers", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Sandbag", kind: "station" },
  { short: "1km Run", kind: "run" },
  { short: "Wall Balls", kind: "station" },
];

export function RaceFormatStrip() {
  return (
    <section className="border-y hairline bg-background">
      <div className="mx-auto max-w-6xl px-6 py-10">
        <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-5">
          The race format · 16 segments · indoor‑first · no GPS
        </p>
        <div className="flex flex-wrap gap-2">
          {STATIONS.map((s, i) => (
            <span
              key={i}
              className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-pill text-xs font-medium border ${
                s.kind === "run"
                  ? "text-text-secondary bg-surface border-divider/60"
                  : "text-text-primary bg-surface-elevated border-divider"
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${
                  s.kind === "run" ? "bg-text-tertiary" : "bg-accent"
                }`}
              />
              {s.short}
            </span>
          ))}
        </div>
        <p className="text-xs text-text-tertiary mt-5 max-w-2xl">
          Eight runs, eight stations, alternating. Trakrr ships the canonical
          sequence pre-loaded — start a race in one tap, advance with a single
          giant button, and let the timer never drift.
        </p>
      </div>
    </section>
  );
}
