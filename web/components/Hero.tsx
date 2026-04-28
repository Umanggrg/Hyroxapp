import { PhoneFrame } from "./PhoneFrame";
import { WatchFrame } from "./WatchFrame";
import { RaceScreen } from "./screens/RaceScreen";
import { SummaryScreen } from "./screens/SummaryScreen";
import { ProfileScreen } from "./screens/ProfileScreen";
import { WatchScreen } from "./screens/WatchScreen";

// Hero composition — oversized typography on top, three phones
// + a watch fanned across the bottom with subtle 3D rotation.
// The composition mirrors Apple's "fanned device family" hero
// pattern (think the iPhone keynote pages) but uses Trakr's
// actual app screens so it doubles as a product showcase.
export function Hero() {
  return (
    <section className="relative overflow-hidden grain bg-hero-radial pt-20 sm:pt-28 pb-16 sm:pb-24">
      <div className="mx-auto max-w-6xl px-6 text-center animate-riseIn">
        <p className="inline-flex items-center gap-2 text-[11px] uppercase tracking-caps text-text-secondary mb-6">
          <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulseDot" />
          Now in TestFlight beta · iOS 17+ · Apple Watch ready
        </p>
        <h1 className="font-rounded font-bold tracking-[-0.04em] text-[44px] sm:text-[88px] lg:text-[120px] leading-[0.92]">
          Race the format. <br />
          <span className="bg-gradient-to-br from-accent via-accent to-[#ff7a6f] text-transparent bg-clip-text">
            Master the seconds.
          </span>
        </h1>
        <p className="mt-7 text-lg sm:text-2xl text-text-secondary max-w-2xl mx-auto leading-relaxed">
          The training companion for the modern hybrid athlete. Sixteen
          stations, every split, every heart rate zone — phone, watch, and duo
          partner all in sync.
        </p>
        <div className="mt-10 flex flex-wrap items-center justify-center gap-3">
          <a
            href="#testflight"
            className="inline-flex items-center gap-2 px-6 py-3.5 rounded-pill bg-accent text-white font-semibold text-sm hover:bg-accent/90 transition shadow-glow"
          >
            Get the TestFlight invite
            <span aria-hidden>→</span>
          </a>
          <a
            href="#showcase"
            className="inline-flex items-center gap-2 px-6 py-3.5 rounded-pill bg-surface border border-divider text-text-primary font-semibold text-sm hover:bg-surface-elevated transition"
          >
            Watch the tour
          </a>
        </div>
      </div>

      {/* Device family. Three phones + watch, fanned. The middle
          phone takes center stage; the side phones rotate slightly
          inward to create depth. Watch sits forward-left. */}
      <div className="relative mx-auto mt-20 sm:mt-24 max-w-6xl px-6">
        <div
          aria-hidden
          className="absolute inset-0 bg-hero-radial blur-3xl opacity-90 pointer-events-none"
        />

        <div className="relative flex items-end justify-center gap-[-32px]">
          <div className="hidden md:block translate-y-12 -mr-16 lg:-mr-24 z-10">
            <PhoneFrame width={240} tilt={18} rotate={-6}>
              <ProfileScreen />
            </PhoneFrame>
          </div>

          <div className="relative z-20 -mt-8 sm:-mt-12">
            <PhoneFrame width={300}>
              <RaceScreen />
            </PhoneFrame>
            {/* Live Activity-style pill that floats above the phone,
                visually advertising the Dynamic Island integration. */}
            <div className="hidden sm:flex absolute -top-4 left-1/2 -translate-x-1/2 items-center gap-2 px-3 py-1.5 rounded-pill bg-black/95 ring-1 ring-divider/60 backdrop-blur shadow-glow">
              <span className="h-1.5 w-1.5 rounded-full bg-accent animate-pulseDot" />
              <span className="text-[10px] tabular text-text-primary font-semibold">
                1:14:32
              </span>
              <span className="text-[10px] uppercase tracking-caps text-text-tertiary">
                Burpee BJ
              </span>
            </div>
          </div>

          <div className="hidden md:block translate-y-12 -ml-16 lg:-ml-24 z-10">
            <PhoneFrame width={240} tilt={-18} rotate={6}>
              <SummaryScreen />
            </PhoneFrame>
          </div>
        </div>

        {/* Floating watch, bottom-left of the phone cluster. */}
        <div className="hidden lg:block absolute left-6 bottom-2 z-30">
          <WatchFrame width={150} rotate={-8}>
            <WatchScreen />
          </WatchFrame>
        </div>

        {/* Floating "PB" toast, bottom-right. Reinforces the
            celebratory moment from the summary screen. */}
        <div className="hidden lg:flex absolute right-10 bottom-6 z-30 items-center gap-2 px-3 py-2 rounded-pill bg-success/15 border border-success/40 backdrop-blur">
          <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulseDot" />
          <span className="text-[10px] uppercase tracking-caps font-bold text-success">
            New PB · −2:08
          </span>
        </div>
      </div>

      {/* Trust strip — small reassurances. */}
      <div className="relative mx-auto mt-16 max-w-3xl px-6">
        <ul className="grid grid-cols-2 sm:grid-cols-4 gap-x-6 gap-y-3 text-[11px] uppercase tracking-caps text-text-tertiary justify-items-center">
          <li className="flex items-center gap-2">
            <span className="h-1 w-1 rounded-full bg-success" />
            Native iOS + watchOS
          </li>
          <li className="flex items-center gap-2">
            <span className="h-1 w-1 rounded-full bg-success" />
            Zero tracking
          </li>
          <li className="flex items-center gap-2">
            <span className="h-1 w-1 rounded-full bg-success" />
            All on-device
          </li>
          <li className="flex items-center gap-2">
            <span className="h-1 w-1 rounded-full bg-success" />
            Free, no IAP
          </li>
        </ul>
      </div>
    </section>
  );
}
