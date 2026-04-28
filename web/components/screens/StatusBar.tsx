// Tiny iOS-style status bar so the screens read as real
// screenshots. The clock is fake — set to 9:41 because that's
// what every Apple marketing image shows.
export function StatusBar({ tone = "light" }: { tone?: "light" | "dark" }) {
  const fg = tone === "light" ? "text-text-primary" : "text-black";
  return (
    <div
      className={`flex items-center justify-between px-5 pt-2 pb-1 text-[10px] font-semibold ${fg}`}
    >
      <span className="tabular">9:41</span>
      <div className="flex items-center gap-1">
        {/* signal */}
        <svg width="14" height="9" viewBox="0 0 14 9" fill="currentColor">
          <rect x="0" y="6" width="2" height="3" rx="0.5" />
          <rect x="3.5" y="4" width="2" height="5" rx="0.5" />
          <rect x="7" y="2" width="2" height="7" rx="0.5" />
          <rect x="10.5" y="0" width="2" height="9" rx="0.5" />
        </svg>
        {/* wifi */}
        <svg width="12" height="9" viewBox="0 0 12 9" fill="currentColor">
          <path d="M6 8.5a1 1 0 100-2 1 1 0 000 2z" />
          <path
            d="M2.5 5.2a4.95 4.95 0 017 0"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.2"
            strokeLinecap="round"
          />
          <path
            d="M0.5 3a8.4 8.4 0 0111 0"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.2"
            strokeLinecap="round"
          />
        </svg>
        {/* battery */}
        <svg width="22" height="10" viewBox="0 0 22 10" fill="none">
          <rect
            x="0.5"
            y="0.5"
            width="18"
            height="9"
            rx="2"
            stroke="currentColor"
            strokeOpacity="0.5"
          />
          <rect x="2" y="2" width="14" height="6" rx="1" fill="currentColor" />
          <rect
            x="20"
            y="3"
            width="1.5"
            height="4"
            rx="0.5"
            fill="currentColor"
            opacity="0.5"
          />
        </svg>
      </div>
    </div>
  );
}
