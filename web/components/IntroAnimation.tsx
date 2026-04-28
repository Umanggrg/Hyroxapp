"use client";

import { useEffect, useRef, useState } from "react";
import { PhoneFrame } from "./PhoneFrame";
import { HomeScreen } from "./screens/HomeScreen";

// IntroAnimation — Apple-style scroll-pinned product reveal.
//
// Section is 220vh on mobile / 300vh on desktop; inside, a sticky
// 100vh stage holds the phone. Scroll progress (0..1) drives four
// overlapping stages:
//
//   • Slide-in   (0.00 — 0.30): phone flies in from off-screen
//                 left, rotated and small. Screen is off (black).
//   • Rotate     (0.30 — 0.55): phone rotates upright (rotateY +
//                 rotateZ both interpolating to 0).
//   • Power-on   (0.55 — 0.75): black screen overlay fades, the
//                 HomeScreen "boots up" with a slight scale.
//   • Settle     (0.75 — 1.00): phone shifts to make room for the
//                 headline. On desktop the phone moves right and
//                 the headline reveals on the left. On mobile the
//                 phone moves up and the headline reveals below
//                 it — keeps both readable on a narrow viewport.
//
// Reduced-motion users see the final state with no scroll
// dependency. Mobile uses a gentler arc so the phone stays
// readable across the choreography.

const clamp = (v: number, min: number, max: number) =>
  Math.max(min, Math.min(max, v));

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;

// easeInOutCubic — slow start, fast middle, slow end.
const ease = (t: number) =>
  t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;

export function IntroAnimation() {
  const sectionRef = useRef<HTMLElement>(null);
  const [progress, setProgress] = useState(0);
  const [reducedMotion, setReducedMotion] = useState(false);
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const motionMQ = window.matchMedia("(prefers-reduced-motion: reduce)");
    const sizeMQ = window.matchMedia("(max-width: 1023px)");
    const sync = () => {
      setReducedMotion(motionMQ.matches);
      setIsMobile(sizeMQ.matches);
    };
    sync();
    motionMQ.addEventListener("change", sync);
    sizeMQ.addEventListener("change", sync);
    return () => {
      motionMQ.removeEventListener("change", sync);
      sizeMQ.removeEventListener("change", sync);
    };
  }, []);

  useEffect(() => {
    if (reducedMotion) {
      setProgress(1);
      return;
    }
    let raf: number | null = null;
    const onScroll = () => {
      if (raf !== null) cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        const section = sectionRef.current;
        if (!section) return;
        const rect = section.getBoundingClientRect();
        const total = section.offsetHeight - window.innerHeight;
        const scrolled = -rect.top;
        setProgress(clamp(scrolled / Math.max(1, total), 0, 1));
      });
    };
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll);
    return () => {
      if (raf !== null) cancelAnimationFrame(raf);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
    };
  }, [reducedMotion]);

  // Stage progress (each 0..1 within its band).
  const slide = clamp(progress / 0.3, 0, 1);
  const rotate = clamp((progress - 0.3) / 0.25, 0, 1);
  const power = clamp((progress - 0.55) / 0.2, 0, 1);
  const settle = clamp((progress - 0.75) / 0.25, 0, 1);

  // Phone transform values. Mobile gets a gentler arc that doesn't
  // push the phone as far off-screen — keeps it visible even
  // mid-scroll on slower hardware where the choreography may
  // otherwise feel like a flicker.
  const startX = isMobile ? -160 : -360;
  const startScale = isMobile ? 0.72 : 0.55;
  const tx = lerp(startX, 0, ease(slide));
  const ty = lerp(isMobile ? 16 : 30, 0, ease(slide));
  const rotZ = lerp(isMobile ? -16 : -22, 0, ease(rotate));
  const rotY = lerp(isMobile ? 45 : 60, 0, ease(rotate));
  const scl = lerp(startScale, 1, ease(slide));

  // Final settle — on desktop the phone slides right so the
  // headline can appear on the left. On mobile the phone slides
  // upward so the headline can appear below.
  const settleX = isMobile ? 0 : lerp(0, 130, ease(settle));
  const settleY = isMobile ? lerp(0, -110, ease(settle)) : 0;

  const screenOffOpacity = 1 - ease(power);
  const screenScale = lerp(0.96, 1, ease(power));

  const bootLineY = lerp(0, 100, ease(power));
  const bootLineOpacity = power > 0 && power < 0.95 ? 1 : 0;

  // Phone size scales down on small screens. We pick three sizes
  // rather than fluid because PhoneFrame internals (corner radii,
  // Dynamic Island) are tuned to whole-pixel widths.
  const phoneWidth = isMobile ? 220 : 340;

  return (
    <section
      ref={sectionRef}
      className="relative bg-background"
      style={{ height: isMobile ? "220vh" : "300vh" }}
      aria-label="Trakr product introduction"
    >
      {/* Sticky stage — pins for 100vh while the section's slack
          scrolls past beneath it. */}
      <div className="sticky top-0 h-screen overflow-hidden">
        {/* Ambient backdrop. */}
        <div
          aria-hidden
          className="absolute inset-0 pointer-events-none"
          style={{
            background:
              "radial-gradient(ellipse 80% 60% at 50% 35%, rgba(255,59,48,0.18) 0%, rgba(255,59,48,0) 70%)",
            opacity: lerp(0.4, 1, ease(power)),
          }}
        />

        {/* Phone layer — absolutely centered, transformed by scroll. */}
        <div
          className="absolute inset-0 flex items-center justify-center"
          style={{ perspective: "1600px" }}
        >
          <div
            style={{
              transform: `translate3d(${tx + settleX}px, ${ty + settleY}px, 0) rotateY(${rotY}deg) rotateZ(${rotZ}deg) scale(${scl})`,
              transformStyle: "preserve-3d",
              willChange: "transform",
            }}
          >
            <div
              style={{
                transform: `scale(${screenScale})`,
                transition: "transform 200ms linear",
              }}
            >
              <PhoneFrame width={phoneWidth}>
                <div className="relative h-full w-full">
                  <HomeScreen powered={power > 0.4} />
                  <div
                    aria-hidden
                    className="absolute inset-0 bg-black"
                    style={{ opacity: screenOffOpacity }}
                  />
                  <div
                    aria-hidden
                    className="absolute left-0 right-0 h-px pointer-events-none"
                    style={{
                      top: `${bootLineY}%`,
                      opacity: bootLineOpacity,
                      background:
                        "linear-gradient(90deg, transparent, #FF3B30 50%, transparent)",
                      boxShadow: "0 0 16px 2px rgba(255,59,48,0.7)",
                    }}
                  />
                </div>
              </PhoneFrame>
            </div>
          </div>
        </div>

        {/* Headline layer — positioned differently per breakpoint
            so it doesn't fight the phone for screen real estate.
            Desktop: anchored to the left, vertically centered.
            Mobile: anchored to the bottom of the viewport. */}
        <div
          className="
            absolute pointer-events-none px-6
            bottom-10 left-1/2 -translate-x-1/2 w-full max-w-sm text-center
            lg:left-12 lg:top-1/2 lg:-translate-x-0 lg:-translate-y-1/2 lg:bottom-auto lg:max-w-lg lg:text-left lg:px-0
          "
          style={{
            opacity: ease(settle),
            transform: undefined, // overridden by responsive classes above; we use opacity only
          }}
        >
          <div
            className="pointer-events-auto"
            style={{
              opacity: ease(settle),
              transform: `translateY(${lerp(20, 0, ease(settle))}px)`,
            }}
          >
            <p className="hidden sm:inline-flex items-center gap-2 text-[10px] sm:text-[11px] uppercase tracking-caps text-text-secondary mb-3 sm:mb-4">
              <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulseDot" />
              Now in TestFlight beta
            </p>
            <h1 className="font-rounded font-bold tracking-[-0.04em] text-[34px] sm:text-[56px] lg:text-[88px] leading-[0.95]">
              Race the format.
              <br className="hidden sm:block" />
              <span className="bg-gradient-to-br from-accent via-accent to-[#ff7a6f] text-transparent bg-clip-text">
                Master the seconds.
              </span>
            </h1>
            <p className="hidden sm:block mt-4 sm:mt-5 text-base sm:text-lg text-text-secondary max-w-md mx-auto lg:mx-0 leading-relaxed">
              The training companion for the modern hybrid athlete.
              Sixteen stations, every split, every heart rate zone.
            </p>
            <div className="mt-5 sm:mt-7 flex flex-wrap items-center justify-center lg:justify-start gap-2 sm:gap-3">
              <a
                href="#testflight"
                className="inline-flex items-center gap-2 px-4 sm:px-5 py-2.5 sm:py-3 rounded-pill bg-accent text-white font-semibold text-xs sm:text-sm hover:bg-accent/90 transition shadow-glow"
              >
                Get TestFlight
                <span aria-hidden>→</span>
              </a>
              <a
                href="#showcase"
                className="hidden sm:inline-flex items-center gap-2 px-5 py-3 rounded-pill bg-surface border border-divider text-text-primary font-semibold text-sm hover:bg-surface-elevated transition"
              >
                Watch the tour
              </a>
            </div>
          </div>
        </div>

        {/* Scroll hint — desktop only; on mobile the headline
            already telegraphs that more is coming. */}
        <div
          className="hidden sm:block absolute bottom-10 left-1/2 -translate-x-1/2 text-text-tertiary"
          style={{ opacity: 1 - ease(slide) }}
        >
          <div className="flex flex-col items-center gap-2">
            <span className="text-[10px] uppercase tracking-caps font-semibold">
              Scroll to begin
            </span>
            <svg
              width="16"
              height="20"
              viewBox="0 0 16 20"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.4"
              aria-hidden
            >
              <rect x="1" y="1" width="14" height="18" rx="7" />
              <line
                x1="8"
                y1="5"
                x2="8"
                y2="9"
                strokeLinecap="round"
                className="animate-pulseDot"
              />
            </svg>
          </div>
        </div>
      </div>
    </section>
  );
}
