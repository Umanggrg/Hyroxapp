import { StatusBar } from "./StatusBar";
import { TabBar } from "./TabBar";

// ProfileScreen — mirrors `ProfileView.swift`. ProfileHero on
// top, then Next Up (event countdown + readiness banner), then
// the HYROX Performance Score, then a streak banner.
export function ProfileScreen() {
  return (
    <div className="h-full w-full bg-background flex flex-col text-text-primary relative">
      <StatusBar />

      <div className="flex-1 overflow-hidden px-4 pt-2 pb-24 space-y-3">
        {/* Profile hero */}
        <div className="flex items-center gap-3">
          <div className="h-12 w-12 rounded-full bg-gradient-to-br from-accent to-accent-dim ring-2 ring-accent/30" />
          <div className="flex-1">
            <p className="font-rounded font-black text-[16px] leading-tight">
              Umang
            </p>
            <p className="text-[10px] text-text-secondary">
              @umang · Men&apos;s Open
            </p>
          </div>
          <div className="grid grid-cols-3 gap-1.5">
            <HeroTile value="1:14" label="PB" />
            <HeroTile value="37" label="Races" />
            <HeroTile value="12d" label="Streak" />
          </div>
        </div>

        {/* Section header */}
        <SectionHeader icon="🏁" title="Next Up" accent />

        {/* Race event banner */}
        <div className="rounded-xl bg-surface border border-accent/40 p-3">
          <div className="flex items-start gap-3">
            <div className="flex-1">
              <p className="text-[9px] uppercase tracking-caps font-extrabold text-accent mb-0.5">
                Next Race
              </p>
              <p className="font-rounded font-black text-[18px] leading-tight">
                HYROX Miami
              </p>
              <p className="text-[10px] text-text-secondary">
                Miami, FL · Men&apos;s Open
              </p>
            </div>
            <div className="text-right">
              <p className="font-rounded font-black text-[28px] leading-none tabular text-accent">
                T-43
              </p>
              <p className="text-[8px] uppercase tracking-caps font-extrabold text-accent">
                Days
              </p>
            </div>
          </div>
        </div>

        {/* Readiness banner */}
        <div className="rounded-xl bg-surface border border-success/40 p-2.5 flex items-center gap-2.5">
          <div className="relative h-7 w-7 rounded-full bg-success/15 flex items-center justify-center">
            <div className="h-3 w-3 rounded-full bg-success animate-pulseDot" />
          </div>
          <div>
            <p className="text-[10px] uppercase tracking-caps font-extrabold text-success">
              Fresh — race ready
            </p>
            <p className="text-[10px] text-text-secondary leading-tight">
              Last race +18h · HRV trending up
            </p>
          </div>
        </div>

        {/* Performance section */}
        <SectionHeader icon="⚡" title="Performance" />
        <div className="rounded-xl bg-surface border border-divider/60 p-3">
          <div className="flex items-center justify-between mb-2.5">
            <p className="text-[10px] uppercase tracking-caps font-extrabold text-text-tertiary">
              HYROX Score
            </p>
            <p className="font-rounded font-black tabular text-[15px]">
              82<span className="text-text-tertiary text-[11px]">/100</span>
            </p>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <Pillar label="Strength" value={78} />
            <Pillar label="Endurance" value={88} />
            <Pillar label="Engine" value={80} />
          </div>
        </div>

        {/* Streak banner */}
        <div className="rounded-xl bg-surface border border-divider/60 p-2.5 flex items-center gap-3">
          <span className="text-2xl text-warning animate-pulseDot">🔥</span>
          <div className="flex-1">
            <p className="font-rounded font-black tabular text-[18px] leading-tight">
              12 day streak
            </p>
            <p className="text-[10px] text-text-secondary">
              Longest yet · keep it alive
            </p>
          </div>
        </div>
      </div>

      <TabBar active="profile" />
    </div>
  );
}

function HeroTile({ value, label }: { value: string; label: string }) {
  return (
    <div className="rounded-lg bg-surface border border-divider/60 px-1.5 py-1 text-center">
      <p className="font-rounded font-black tabular text-[12px] leading-tight">
        {value}
      </p>
      <p className="text-[7px] uppercase tracking-caps font-bold text-text-tertiary">
        {label}
      </p>
    </div>
  );
}

function SectionHeader({
  icon,
  title,
  accent,
}: {
  icon: string;
  title: string;
  accent?: boolean;
}) {
  return (
    <div className="flex items-center gap-2 mt-1">
      <span
        className={`text-sm ${accent ? "text-accent" : "text-text-secondary"}`}
        aria-hidden
      >
        {icon}
      </span>
      <p
        className={`font-rounded font-bold text-[14px] ${
          accent ? "text-text-primary" : "text-text-primary"
        }`}
      >
        {title}
      </p>
      <div className="flex-1 h-px bg-divider/60" />
    </div>
  );
}

function Pillar({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex flex-col items-center">
      <div className="relative h-9 w-9 rounded-full border-2 border-divider/60 flex items-center justify-center">
        <div
          className="absolute inset-0 rounded-full"
          style={{
            background: `conic-gradient(#FF3B30 ${value}%, transparent 0)`,
            mask: "radial-gradient(circle, transparent 55%, black 56%)",
            WebkitMask: "radial-gradient(circle, transparent 55%, black 56%)",
          }}
        />
        <span className="font-rounded font-black tabular text-[11px]">
          {value}
        </span>
      </div>
      <p className="text-[8px] uppercase tracking-caps font-bold text-text-tertiary mt-1">
        {label}
      </p>
    </div>
  );
}
