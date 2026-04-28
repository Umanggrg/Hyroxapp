"use client";

import { useEffect, useRef, useState } from "react";
import { PhoneFrame } from "./PhoneFrame";
import { RaceScreen } from "./screens/RaceScreen";
import { SummaryScreen } from "./screens/SummaryScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { ProfileScreen } from "./screens/ProfileScreen";

// AppShowcase — two layouts under the hood:
//
//   Desktop (lg+): sticky scroll-driven section. The phone pins
//   to the right while four narrative panels scroll past on the
//   left. IntersectionObserver tracks which panel is "active"
//   and cross-fades the screen accordingly.
//
//   Mobile (<lg): a clean stacked story flow. Each story's
//   narrative is followed by its phone — readable on a narrow
//   viewport without forcing the user through multiple viewport
//   heights of empty scroll for the sticky to re-trigger.
//
// The desktop branch is heavier (refs, observer, layered
// screens). It renders only when the viewport is wide enough so
// the IntersectionObserver doesn't fire on a layout it can't
// drive.

const STORIES = [
  {
    label: "Race Mode",
    title: "The race is the product.",
    body: "One tap to start. Single huge button to advance. The screen stays awake; the timer never drifts; the state survives a backgrounded app. Pace, projected finish, and live HR zone are visible without ever leaving the timer.",
    screen: "race" as const,
  },
  {
    label: "Summary",
    title: "Every second, accounted for.",
    body: "Total time, splits, station-level HR, calories, roxzone, and PB indicators land the moment you tap finish. Tap any split to drill into per-station trend, race-day weight projection, and historical context.",
    screen: "summary" as const,
  },
  {
    label: "History",
    title: "A feed shaped like Strava.",
    body: "Every race lives as a card with title, hero time, supporting stats, tags, and effort. Filter by Solo, Duo, PB, or any tag you've used. Compare any two races side-by-side. The feed is built for the social future, not against it.",
    screen: "history" as const,
  },
  {
    label: "Profile",
    title: "Identity, performance, ready-to-race.",
    body: "Performance score across Strength, Endurance, and Engine. Today's readiness banner pulled from your last race plus recovery. Streaks, badges, monthly + yearly recaps, and a calendar heatmap of training density.",
    screen: "profile" as const,
  },
];

type Screen = (typeof STORIES)[number]["screen"];

function ScreenFor({ kind }: { kind: Screen }) {
  if (kind === "race") return <RaceScreen />;
  if (kind === "summary") return <SummaryScreen />;
  if (kind === "history") return <HistoryScreen />;
  return <ProfileScreen />;
}

export function AppShowcase() {
  return (
    <section
      id="showcase"
      className="relative bg-background border-y hairline"
    >
      <div className="mx-auto max-w-6xl px-6 py-20 sm:py-24 lg:py-32">
        <div className="max-w-2xl mb-12 sm:mb-16 lg:mb-24">
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-3">
            The tour
          </p>
          <h2 className="font-rounded font-bold text-3xl sm:text-5xl lg:text-6xl tracking-[-0.03em] leading-[1]">
            Four screens. One uninterrupted training arc.
          </h2>
        </div>

        {/* Mobile: stacked story flow. */}
        <div className="lg:hidden space-y-20">
          {STORIES.map((s) => (
            <div
              key={s.screen}
              className="flex flex-col items-center text-center"
            >
              <p className="text-[11px] uppercase tracking-caps text-accent font-semibold mb-3">
                {s.label}
              </p>
              <h3 className="font-rounded font-bold text-3xl sm:text-4xl tracking-[-0.02em] leading-[1.05] mb-4 max-w-md">
                {s.title}
              </h3>
              <p className="text-text-secondary text-base sm:text-lg leading-relaxed max-w-md mb-8">
                {s.body}
              </p>
              <PhoneFrame width={240}>
                <ScreenFor kind={s.screen} />
              </PhoneFrame>
            </div>
          ))}
        </div>

        {/* Desktop: sticky scroll-driven layout. */}
        <DesktopShowcase />
      </div>
    </section>
  );
}

function DesktopShowcase() {
  const [active, setActive] = useState<Screen>("race");
  const refs = useRef<Array<HTMLDivElement | null>>([]);

  useEffect(() => {
    if (!window.matchMedia("(min-width: 1024px)").matches) return;
    const observers: IntersectionObserver[] = [];
    refs.current.forEach((el, i) => {
      if (!el) return;
      const obs = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) setActive(STORIES[i].screen);
          });
        },
        { rootMargin: "-45% 0px -45% 0px", threshold: 0 },
      );
      obs.observe(el);
      observers.push(obs);
    });
    return () => observers.forEach((o) => o.disconnect());
  }, []);

  return (
    <div className="hidden lg:grid lg:grid-cols-12 gap-16 items-start">
      <div className="lg:col-span-7 space-y-[55vh]">
        {STORIES.map((s, i) => (
          <div
            key={s.screen}
            ref={(el) => {
              refs.current[i] = el;
            }}
            className="max-w-xl"
          >
            <p className="text-[11px] uppercase tracking-caps text-accent font-semibold mb-3">
              {s.label}
            </p>
            <h3 className="font-rounded font-bold text-3xl sm:text-5xl tracking-[-0.02em] leading-[1.05] mb-5">
              {s.title}
            </h3>
            <p className="text-text-secondary text-lg leading-relaxed">
              {s.body}
            </p>
          </div>
        ))}
      </div>

      <div className="lg:col-span-5 lg:sticky lg:top-24">
        <div className="relative mx-auto" style={{ width: 340 }}>
          <div
            aria-hidden
            className="absolute -inset-12 bg-hero-radial blur-3xl opacity-80 pointer-events-none"
          />
          <PhoneFrame width={340}>
            <div className="relative h-full w-full">
              {STORIES.map((s) => (
                <ScreenLayer key={s.screen} visible={active === s.screen}>
                  <ScreenFor kind={s.screen} />
                </ScreenLayer>
              ))}
            </div>
          </PhoneFrame>
        </div>

        <div className="flex justify-center gap-2 mt-8">
          {STORIES.map((s) => (
            <span
              key={s.screen}
              className={`h-1.5 rounded-pill transition-all duration-500 ${
                active === s.screen ? "w-8 bg-accent" : "w-2 bg-divider"
              }`}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function ScreenLayer({
  visible,
  children,
}: {
  visible: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className={`absolute inset-0 transition-opacity duration-700 ease-out ${
        visible ? "opacity-100" : "opacity-0 pointer-events-none"
      }`}
    >
      {children}
    </div>
  );
}
