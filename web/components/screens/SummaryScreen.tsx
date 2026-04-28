import { StatusBar } from "./StatusBar";

// SummaryScreen — mirrors `RaceSummaryView.swift`. Hero is the
// finish-time celebration: success ribbon, PB rosette, 88pt
// total time with coral glow, and a splits card with effort
// dots in the left gutter.
export function SummaryScreen() {
  const splits = [
    { name: "1km Run", time: "4:42", effort: "moderate", hr: "168" },
    { name: "Sled Push", time: "3:54", effort: "veryHigh", hr: "176", pb: true },
    { name: "1km Run", time: "4:48", effort: "high", hr: "172" },
    { name: "Sled Pull", time: "4:12", effort: "high", hr: "174" },
    { name: "1km Run", time: "4:51", effort: "moderate", hr: "170" },
    { name: "Burpee BJ", time: "5:18", effort: "veryHigh", hr: "182", pb: true },
  ];

  const dotColor = (e: string) =>
    e === "veryHigh"
      ? "bg-accent"
      : e === "high"
      ? "bg-warning"
      : e === "moderate"
      ? "bg-success"
      : "bg-text-tertiary";

  return (
    <div className="h-full w-full bg-background flex flex-col text-text-primary relative overflow-hidden">
      {/* HeroBackdrop */}
      <div
        aria-hidden
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            "radial-gradient(ellipse 90% 50% at 50% 22%, rgba(255,59,48,0.22) 0%, rgba(255,59,48,0) 65%)",
        }}
      />

      <StatusBar />

      <div className="relative flex-1 overflow-hidden px-4 pt-3 pb-3">
        {/* Finish hero */}
        <div className="text-center pt-3">
          <p className="inline-flex items-center gap-1.5 text-[10px] font-extrabold tracking-[0.16em] uppercase text-success">
            <CheckGlyph /> Finished
          </p>

          <div className="mt-2 inline-flex items-center gap-1.5 text-[10px] font-extrabold tracking-[0.1em] uppercase px-2.5 py-1 rounded-pill bg-[rgba(255,214,10,0.15)] border border-[rgba(255,214,10,0.4)]"
            style={{ color: "#FFD60A" }}
          >
            <RosetteGlyph />
            New Personal Best
          </div>

          <p
            className="font-rounded font-black tabular text-[58px] leading-none mt-3 tracking-[-0.03em]"
            style={{ textShadow: "0 0 28px rgba(255,59,48,0.4)" }}
          >
            1<span className="text-text-tertiary">:</span>14
            <span className="text-text-tertiary">:</span>32
          </p>
          <p className="text-[10px] uppercase tracking-[0.16em] font-extrabold text-text-secondary mt-2">
            Total Time
          </p>

          <div className="mt-3 flex items-center justify-center gap-3 text-[10px] tabular">
            <span className="font-semibold text-accent">892 kcal</span>
            <span className="text-text-tertiary">·</span>
            <span className="font-semibold text-warning">1:48 roxzone</span>
            <span className="text-text-tertiary">·</span>
            <span className="font-semibold text-accent">Effort 78</span>
          </div>
        </div>

        {/* Goal met card */}
        <div className="mt-4 rounded-xl bg-surface border border-success/30 px-3 py-2 flex items-center gap-2">
          <span className="text-success">
            <CheckGlyph />
          </span>
          <span className="text-[10px] uppercase tracking-caps font-extrabold text-success">
            Goal met
          </span>
          <span className="ml-auto text-[10px] tabular text-text-secondary">
            Target 1:30:00 · 15:28 ahead
          </span>
        </div>

        {/* Splits card */}
        <div className="mt-3 rounded-xl bg-surface border border-divider/60 overflow-hidden">
          {splits.map((s, i) => (
            <div
              key={i}
              className={`flex items-center gap-2.5 px-3 py-2.5 ${
                i < splits.length - 1 ? "border-b border-divider/60" : ""
              }`}
            >
              <span
                className={`h-1.5 w-1.5 rounded-full ${dotColor(s.effort)}`}
                aria-hidden
              />
              <div className="flex-1">
                <p className="text-[12px] font-semibold leading-tight">
                  {s.name}
                </p>
                <p className="text-[10px] tabular text-accent/80 font-semibold">
                  {s.hr} bpm
                </p>
              </div>
              {s.pb && (
                <span className="text-[9px] font-extrabold uppercase tracking-caps text-success">
                  PB
                </span>
              )}
              <span className="tabular font-rounded font-semibold text-[14px]">
                {s.time}
              </span>
              <span className="text-text-tertiary text-xs">›</span>
            </div>
          ))}
        </div>

        {/* Done button */}
        <div className="mt-3">
          <div className="w-full h-12 rounded-card bg-surface-elevated border border-divider/60 flex items-center justify-center text-text-primary font-rounded font-bold text-[16px]">
            Done
          </div>
        </div>
      </div>
    </div>
  );
}

function CheckGlyph() {
  return (
    <svg width="10" height="10" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden>
      <path d="M2 6l3 3 5-6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function RosetteGlyph() {
  return (
    <svg width="10" height="10" viewBox="0 0 12 12" fill="currentColor" aria-hidden>
      <circle cx="6" cy="5" r="3" />
      <path d="M4 7l-1.5 4 3-1 3 1L7 7z" />
    </svg>
  );
}
