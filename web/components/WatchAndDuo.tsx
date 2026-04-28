"use client";

import { useEffect, useState } from "react";
import { PhoneFrame } from "./PhoneFrame";
import { WatchFrame } from "./WatchFrame";
import { RaceScreen } from "./screens/RaceScreen";
import { WatchScreen } from "./screens/WatchScreen";

// Watch + Duo callouts. The internal device compositions are
// fixed-width PhoneFrame/WatchFrame instances, so we shrink
// them on small screens by setting smaller `width` props
// rather than relying on CSS scale (which would still consume
// the original layout box and force horizontal overflow).

export function WatchAndDuo() {
  const [isMobile, setIsMobile] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(max-width: 640px)");
    const sync = () => setIsMobile(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);

  // Reduced sizes on mobile keep the device cluster inside the
  // card's content box without horizontal scroll.
  const watchCardPhone = isMobile ? 130 : 180;
  const watchCardWatch = isMobile ? 90 : 130;
  const duoPhone = isMobile ? 120 : 170;

  return (
    <section className="mx-auto max-w-6xl px-6 py-20 sm:py-24 lg:py-32">
      <div className="max-w-2xl mb-10 sm:mb-12">
        <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-3">
          Built for two surfaces, then two athletes
        </p>
        <h2 className="font-rounded font-bold text-3xl sm:text-5xl lg:text-6xl tracking-[-0.03em] leading-[1.0]">
          The phone runs the race. <br />
          <span className="text-text-secondary">
            The watch and your partner stay in sync.
          </span>
        </h2>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Watch sync card */}
        <article className="rounded-card bg-surface border border-divider/60 p-6 sm:p-8 shadow-card relative overflow-hidden min-h-[420px] sm:min-h-[480px] flex flex-col">
          <div
            aria-hidden
            className="absolute -right-32 -top-32 h-80 w-80 rounded-full bg-accent/10 blur-3xl"
          />
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary">
            Apple Watch · companion app
          </p>
          <h3 className="mt-3 font-rounded font-bold text-2xl sm:text-3xl lg:text-4xl leading-tight">
            Race from the wrist.
          </h3>
          <p className="mt-3 text-text-secondary leading-relaxed max-w-md text-sm sm:text-base">
            Phone and watch stay glued together via a single Codable snapshot
            shipped over WatchConnectivity. Tap advance from either; both
            screens update instantly.
          </p>

          <div className="relative mt-auto flex items-end justify-center gap-4 sm:gap-8 pt-6">
            <PhoneFrame width={watchCardPhone} rotate={-4}>
              <RaceScreen />
            </PhoneFrame>
            <svg
              aria-hidden
              className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 pointer-events-none"
              width="100"
              height="2"
              viewBox="0 0 100 2"
            >
              <line
                x1="0"
                y1="1"
                x2="100"
                y2="1"
                stroke="#FF3B30"
                strokeWidth="1"
                strokeDasharray="4 4"
                opacity="0.5"
              />
            </svg>
            <WatchFrame width={watchCardWatch} rotate={4}>
              <WatchScreen />
            </WatchFrame>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            <Tag>WatchConnectivity</Tag>
            <Tag>Snapshot sync</Tag>
            <Tag>Hold-to-finish</Tag>
          </div>
        </article>

        {/* Duo card */}
        <article className="rounded-card bg-surface border border-divider/60 p-6 sm:p-8 shadow-card relative overflow-hidden min-h-[420px] sm:min-h-[480px] flex flex-col">
          <div
            aria-hidden
            className="absolute -left-32 -bottom-32 h-80 w-80 rounded-full bg-accent/10 blur-3xl"
          />
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary">
            Duo Mode · HYROX Doubles
          </p>
          <h3 className="mt-3 font-rounded font-bold text-2xl sm:text-3xl lg:text-4xl leading-tight">
            Two phones, one race.
          </h3>
          <p className="mt-3 text-text-secondary leading-relaxed max-w-md text-sm sm:text-base">
            Two iPhones at the same gym pair over Bluetooth + Wi-Fi Direct — no
            backend, encrypted by default. Either partner can advance; both
            histories save the race.
          </p>

          <div className="relative mt-auto flex items-end justify-center gap-1 sm:gap-2 pt-6">
            <PhoneFrame width={duoPhone} rotate={-6}>
              <RaceScreen />
            </PhoneFrame>
            <div className="px-2 sm:px-3 py-1.5 rounded-pill bg-accent/15 border border-accent/30 text-[9px] sm:text-[10px] uppercase tracking-caps font-bold text-accent self-center -mx-2 sm:-mx-4 z-10 backdrop-blur whitespace-nowrap">
              <span className="inline-block h-1.5 w-1.5 rounded-full bg-accent mr-1 sm:mr-1.5 animate-pulseDot" />
              Paired
            </div>
            <PhoneFrame width={duoPhone} rotate={6}>
              <RaceScreen />
            </PhoneFrame>
          </div>

          <div className="mt-6 flex flex-wrap gap-2">
            <Tag>MultipeerConnectivity</Tag>
            <Tag>Host-authoritative</Tag>
            <Tag>Bidirectional HR</Tag>
          </div>
        </article>
      </div>
    </section>
  );
}

function Tag({ children }: { children: React.ReactNode }) {
  return (
    <span className="text-[10px] sm:text-[11px] uppercase tracking-caps font-semibold text-text-secondary px-2 sm:px-2.5 py-1 rounded-pill bg-surface-elevated border border-divider/60">
      {children}
    </span>
  );
}
