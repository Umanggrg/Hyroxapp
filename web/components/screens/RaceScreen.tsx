import { StatusBar } from "./StatusBar";

// RaceScreen — pixel-faithful mock of `RaceView.swift` mid-race.
// Top to bottom (matching SwiftUI):
//   • Header row: splits chip · station label · pace chip · HR chip ·
//                 pause · cancel
//   • Station headline (centered) — station name + target
//   • Massive race timer (96pt-equivalent) + segment + target +
//     projected
//   • UP NEXT station preview
//   • Advance button (80pt, accent gradient)
export function RaceScreen() {
  return (
    <div className="h-full w-full bg-background flex flex-col text-text-primary relative">
      <StatusBar />

      {/* Header row */}
      <div className="flex items-center gap-1.5 px-3 pt-2">
        <span className="text-[9px] font-bold uppercase tracking-caps px-2 py-1 rounded-pill bg-surface text-text-secondary">
          2 Splits
        </span>
        <span className="text-[9px] uppercase tracking-caps font-bold text-text-secondary">
          Station 6 of 16
        </span>
        <span className="ml-auto inline-flex items-center gap-1 text-[9px] font-bold px-1.5 py-1 rounded-pill bg-success/15 text-success">
          <span className="text-[10px]">▼</span>
          0:18
        </span>
        <span className="inline-flex items-center gap-1 text-[9px] font-bold px-1.5 py-1 rounded-pill bg-accent/15 text-accent">
          <HeartGlyph />
          172 Z4
        </span>
      </div>

      {/* Station headline — centered above the timer */}
      <div className="flex-1 flex flex-col items-center justify-center px-4 -mt-2">
        <p className="font-rounded font-black text-[26px] leading-tight text-center">
          Burpee Broad Jumps
        </p>
        <p className="text-[11px] text-text-secondary mt-1">80m · target</p>

        {/* Hero timer */}
        <p className="font-rounded font-black tabular text-[64px] leading-none mt-7 tracking-[-0.04em]">
          1<span className="text-text-tertiary">:</span>14
          <span className="text-text-tertiary">:</span>32
        </p>
        <p className="text-[10px] uppercase tracking-caps text-text-tertiary mt-2 tabular">
          segment 3:21
        </p>
        <p className="text-[10px] uppercase tracking-caps text-text-tertiary tabular">
          target 1:30:00
        </p>
        <p className="text-[10px] uppercase tracking-caps text-success font-bold mt-1 tabular">
          projected 1:28:14
        </p>

        {/* UP NEXT */}
        <div className="mt-6 text-center">
          <p className="text-[9px] uppercase tracking-[0.16em] font-extrabold text-text-tertiary mb-1">
            Up Next
          </p>
          <p className="text-[14px] font-rounded font-bold text-text-secondary">
            Run 4 · 1km
          </p>
        </div>
      </div>

      {/* Advance button */}
      <div className="px-4 pb-7">
        <div
          className="w-full h-[64px] rounded-card flex items-center justify-center text-white font-rounded font-black text-[20px]"
          style={{
            background:
              "linear-gradient(135deg, #FF3B30 0%, rgba(255,59,48,0.85) 100%)",
            boxShadow:
              "0 0 30px -8px rgba(255,59,48,0.55), inset 0 1px 0 rgba(255,255,255,0.18)",
          }}
        >
          Next Station
        </div>
      </div>
    </div>
  );
}

function HeartGlyph() {
  return (
    <svg
      width="9"
      height="9"
      viewBox="0 0 16 16"
      fill="currentColor"
      className="animate-pulseDot"
      aria-hidden
    >
      <path d="M8 14s-6-3.7-6-8a3.5 3.5 0 016-2.4A3.5 3.5 0 0114 6c0 4.3-6 8-6 8z" />
    </svg>
  );
}
