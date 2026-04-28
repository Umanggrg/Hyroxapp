// Watch race screen mock. Constrained typography because real
// estate is brutal — big timer, micro station label, HR pulse,
// next-station glyph at the bottom.
export function WatchScreen() {
  return (
    <div className="h-full w-full bg-background flex flex-col items-center justify-center px-2 text-text-primary">
      <p className="text-[8px] uppercase tracking-caps text-text-tertiary">
        Burpee BJ
      </p>
      <p className="font-rounded font-bold tabular text-[28px] leading-none mt-1">
        1:14:32
      </p>
      <p className="text-[8px] uppercase tracking-caps text-text-secondary mt-1">
        Seg · 3:21
      </p>
      <div className="mt-2 inline-flex items-center gap-1 text-[9px] font-semibold text-accent">
        <span className="h-1 w-1 rounded-full bg-accent animate-pulseDot" />
        ♥ 172
      </div>
      <button
        aria-hidden
        className="mt-3 w-full h-7 rounded-pill bg-accent text-white text-[10px] font-rounded font-bold"
      >
        Next
      </button>
    </div>
  );
}
