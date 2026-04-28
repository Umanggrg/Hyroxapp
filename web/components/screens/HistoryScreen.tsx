import { StatusBar } from "./StatusBar";
import { TabBar } from "./TabBar";

// HistoryScreen — mirrors `HistoryView.swift`. Top stats hero,
// horizontal filter chips, then a feed of RaceCardView mocks
// with effort gutter dots and tag pills.
export function HistoryScreen() {
  const races = [
    {
      title: "Sub-1:15 attempt",
      time: "1:14:32",
      ago: "2h",
      pb: true,
      tags: ["sub-1:15", "focus"],
      avg: "172",
      effort: "78",
    },
    {
      title: "Easy Sunday rox",
      time: "1:32:08",
      ago: "3d",
      pb: false,
      tags: ["recovery"],
      avg: "148",
      effort: "52",
    },
    {
      title: "Doubles · Sarah",
      time: "1:11:42",
      ago: "1w",
      pb: false,
      tags: ["duo"],
      avg: "168",
      effort: "74",
    },
  ];

  return (
    <div className="h-full w-full bg-background flex flex-col text-text-primary relative">
      <StatusBar />

      {/* History hero */}
      <div className="px-4 pt-3 pb-3">
        <div className="flex items-baseline justify-between">
          <h2 className="font-rounded font-black text-[24px]">History</h2>
          <span className="text-[9px] uppercase tracking-caps font-bold text-text-tertiary tabular">
            37 races
          </span>
        </div>
        <div className="grid grid-cols-3 gap-1.5 mt-2">
          <HeroStat label="PB" value="1:14" />
          <HeroStat label="Avg" value="1:24" />
          <HeroStat label="Streak" value="12d" />
        </div>
      </div>

      {/* Filter chips */}
      <div className="flex gap-1.5 px-4 pb-3 overflow-hidden">
        {["All", "PBs", "Solo", "Duo", "Photo"].map((c, i) => (
          <span
            key={c}
            className={`text-[10px] uppercase tracking-caps font-bold px-2.5 py-1 rounded-pill border whitespace-nowrap ${
              i === 0
                ? "bg-accent text-white border-accent"
                : "bg-surface text-text-secondary border-divider/60"
            }`}
          >
            {c}
          </span>
        ))}
      </div>

      {/* Feed */}
      <div className="flex-1 overflow-hidden px-3 space-y-2 pb-24">
        {races.map((r, i) => (
          <article
            key={i}
            className="rounded-xl bg-surface border border-divider/60 p-3"
          >
            <div className="flex items-center justify-between">
              <span className="text-[12px] font-bold">{r.title}</span>
              {r.pb ? (
                <span className="text-[9px] font-extrabold uppercase tracking-caps text-success">
                  PB
                </span>
              ) : (
                <span className="text-[9px] uppercase tracking-caps text-text-tertiary">
                  {r.ago} ago
                </span>
              )}
            </div>
            <p className="font-rounded font-black tabular text-[30px] mt-1 leading-none tracking-[-0.02em]">
              {r.time}
            </p>
            <div className="flex items-center mt-2 gap-1">
              {/* Effort gutter dots — 16 stations */}
              {Array.from({ length: 14 }).map((_, j) => (
                <span
                  key={j}
                  className={`h-1 flex-1 rounded-pill ${
                    j < 11
                      ? r.effort > "70"
                        ? "bg-accent"
                        : "bg-success"
                      : "bg-divider"
                  }`}
                />
              ))}
            </div>
            <div className="flex items-center justify-between mt-2.5">
              <div className="flex gap-1.5">
                {r.tags.map((t) => (
                  <span
                    key={t}
                    className="text-[9px] uppercase tracking-caps text-accent bg-accent/12 border border-accent/30 px-1.5 py-0.5 rounded-pill"
                  >
                    {t}
                  </span>
                ))}
              </div>
              <div className="flex items-center gap-2 text-[10px] text-text-secondary tabular">
                <span>♥ {r.avg}</span>
                <span>·</span>
                <span>Effort {r.effort}</span>
              </div>
            </div>
          </article>
        ))}
      </div>

      <TabBar active="history" />
    </div>
  );
}

function HeroStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-surface border border-divider/60 px-2 py-1.5 text-center">
      <p className="font-rounded font-black tabular text-[15px] leading-tight">
        {value}
      </p>
      <p className="text-[8px] uppercase tracking-caps font-bold text-text-tertiary mt-0.5">
        {label}
      </p>
    </div>
  );
}
