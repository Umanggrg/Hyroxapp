import { StatusBar } from "./StatusBar";
import { TabBar } from "./TabBar";

// HomeScreen — pixel-faithful mock of `RaceStartView.swift`.
// Top to bottom (matching the SwiftUI source):
//   • HeroBackdrop coral glow (rendered as a radial gradient)
//   • Caps "READY TO RACE" label
//   • Massive 76pt "HYROX" wordmark with coral shadow
//   • "Tap start when you're at the line" subhead
//   • Optional event countdown chip ("T-43 DAYS · HYROX MIAMI")
//   • Solo / Duo mode toggle
//   • Target Time row
//   • Start Race primary CTA (gradient coral, 80pt tall)
//   • Custom Workout secondary
//   • Tab bar pinned at bottom

type HomeScreenProps = {
  /** When false, the wordmark and CTA render dim/off — used by
   *  IntroAnimation to simulate a powered-down screen. */
  powered?: boolean;
};

export function HomeScreen({ powered = true }: HomeScreenProps) {
  return (
    <div className="h-full w-full bg-background flex flex-col text-text-primary relative overflow-hidden">
      {/* Coral radial glow — mirrors HeroBackdrop's spotlight. */}
      <div
        aria-hidden
        className="absolute inset-0 pointer-events-none opacity-90"
        style={{
          background:
            "radial-gradient(ellipse 80% 55% at 50% 30%, rgba(255,59,48,0.18) 0%, rgba(255,59,48,0) 70%)",
        }}
      />

      <StatusBar />

      {/* Hero block — wordmark anchors the screen. */}
      <div
        className={`relative flex-1 flex flex-col items-center justify-start pt-10 px-5 transition-opacity duration-700 ${
          powered ? "opacity-100" : "opacity-0"
        }`}
      >
        <p className="text-[10px] uppercase font-extrabold tracking-[0.2em] text-accent">
          Ready to Race
        </p>
        <h1
          className="font-rounded font-black text-[58px] sm:text-[68px] leading-none mt-1 text-text-primary"
          style={{
            letterSpacing: "0.12em",
            textShadow: "0 0 28px rgba(255,59,48,0.35)",
          }}
        >
          HYROX
        </h1>
        <p className="text-[12px] text-text-secondary font-medium mt-2 text-center">
          Tap start when you&apos;re at the line
        </p>

        {/* Event countdown chip */}
        <div className="mt-7 inline-flex items-center gap-2 px-3 py-1.5 rounded-pill bg-accent/10 border border-accent/50">
          <svg
            width="11"
            height="11"
            viewBox="0 0 16 16"
            fill="currentColor"
            className="text-accent"
            aria-hidden
          >
            <path d="M3 1.5v13a.5.5 0 001 0V9h8.5a.5.5 0 00.4-.8l-2.5-3.2 2.5-3.2a.5.5 0 00-.4-.8H4v-.5a.5.5 0 00-1 0z" />
          </svg>
          <span className="text-[10px] font-extrabold tabular tracking-[0.06em] text-accent">
            T-43 DAYS
          </span>
          <span className="text-accent/50">·</span>
          <span className="text-[10px] font-extrabold tracking-[0.06em] text-accent">
            HYROX MIAMI
          </span>
        </div>

        {/* Mode toggle */}
        <div className="grid grid-cols-2 gap-2.5 w-full mt-5">
          <ModeChip
            icon={
              <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
                <circle cx="8" cy="4" r="2.5" />
                <path d="M3 14c0-2.8 2.2-5 5-5s5 2.2 5 5" />
              </svg>
            }
            label="Solo"
            selected
          />
          <ModeChip
            icon={
              <svg width="16" height="14" viewBox="0 0 18 14" fill="currentColor" aria-hidden>
                <circle cx="6" cy="3.5" r="2.2" />
                <circle cx="12.5" cy="3.5" r="2.2" />
                <path d="M1 13c0-2.4 2-4.4 4.5-4.4S10 10.6 10 13M8 13c0-2.4 2-4.4 4.5-4.4S17 10.6 17 13" />
              </svg>
            }
            label="Duo"
            selected={false}
          />
        </div>

        {/* Target Time row */}
        <button
          aria-hidden
          className="mt-3 w-full h-12 px-4 rounded-xl bg-surface/80 border border-divider/60 flex items-center gap-3"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.6" className="text-accent" aria-hidden>
            <circle cx="8" cy="9" r="5.5" />
            <path d="M8 6v3l2 1.5M8 1.5h0M6.5 1.5h3" strokeLinecap="round" />
          </svg>
          <div className="flex flex-col text-left flex-1">
            <span className="text-[9px] font-extrabold tracking-[0.06em] text-text-secondary">
              TARGET TIME
            </span>
            <span className="text-[15px] font-rounded font-semibold tabular text-text-primary">
              1:30:00
            </span>
          </div>
          <span className="text-text-tertiary text-xs">›</span>
        </button>

        {/* Primary CTA */}
        <div
          className={`mt-3 w-full ${
            powered ? "" : "opacity-30"
          } transition-opacity duration-700`}
        >
          <div
            className="relative w-full h-[68px] rounded-card flex items-center justify-center gap-2 text-white font-rounded font-black text-[20px]"
            style={{
              background:
                "linear-gradient(135deg, #FF3B30 0%, rgba(255,59,48,0.85) 100%)",
              boxShadow: powered
                ? "0 0 40px -10px rgba(255,59,48,0.6), inset 0 1px 0 rgba(255,255,255,0.18)"
                : "none",
            }}
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden
            >
              <path d="M3 1.5v17a.5.5 0 001 0v-7h11.5a.5.5 0 00.4-.8l-3-3.7 3-3.7a.5.5 0 00-.4-.8H4v-.5a.5.5 0 00-1 0z" />
            </svg>
            Start Race
          </div>
        </div>

        {/* Custom Workout secondary */}
        <button
          aria-hidden
          className="mt-3 w-full h-11 rounded-xl bg-surface/80 border border-divider/60 flex items-center justify-center gap-2 text-[13px] font-rounded font-semibold text-text-primary"
        >
          <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" aria-hidden>
            <rect x="1" y="3" width="14" height="1.5" rx="0.5" />
            <circle cx="11" cy="3.75" r="2" fill="#FF3B30" />
            <rect x="1" y="7.25" width="14" height="1.5" rx="0.5" />
            <circle cx="5" cy="8" r="2" fill="#FF3B30" />
            <rect x="1" y="11.5" width="14" height="1.5" rx="0.5" />
            <circle cx="11" cy="12.25" r="2" fill="#FF3B30" />
          </svg>
          Custom Workout
        </button>
      </div>

      <TabBar active="home" />
    </div>
  );
}

function ModeChip({
  icon,
  label,
  selected,
}: {
  icon: React.ReactNode;
  label: string;
  selected: boolean;
}) {
  return (
    <div
      className={`h-[62px] rounded-xl flex flex-col items-center justify-center gap-1 transition ${
        selected
          ? "bg-accent/10 border border-accent/50"
          : "bg-surface/70 border border-divider/60"
      }`}
      style={selected ? { transform: "scale(1.03)" } : undefined}
    >
      <span className={selected ? "text-accent" : "text-text-secondary"}>
        {icon}
      </span>
      <span
        className={`text-[13px] font-rounded font-extrabold ${
          selected ? "text-text-primary" : "text-text-secondary"
        }`}
      >
        {label}
      </span>
    </div>
  );
}
