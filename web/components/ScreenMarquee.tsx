import { PhoneFrame } from "./PhoneFrame";
import { HomeScreen } from "./screens/HomeScreen";
import { RaceScreen } from "./screens/RaceScreen";
import { SummaryScreen } from "./screens/SummaryScreen";
import { HistoryScreen } from "./screens/HistoryScreen";
import { ProfileScreen } from "./screens/ProfileScreen";

// A wide, edge-to-edge row of phones. Lets the page breathe and
// reinforces "this is a real, finished app" before the privacy
// + founder narrative closes the page out.
export function ScreenMarquee() {
  return (
    <section className="bg-background overflow-hidden py-16 sm:py-20 border-y hairline">
      <div className="mx-auto max-w-6xl px-6 mb-8 sm:mb-10">
        <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-3">
          The full surface
        </p>
        <h2 className="font-rounded font-bold text-2xl sm:text-4xl lg:text-5xl tracking-[-0.02em] leading-tight max-w-3xl">
          Every screen designed to feel like the same product.
        </h2>
      </div>
      <div
        className="flex items-end gap-4 sm:gap-8 px-6 sm:px-10 overflow-x-auto pb-6 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden snap-x snap-mandatory"
        style={{ scrollPaddingLeft: 24 }}
      >
        <Item kind="home" />
        <Item kind="race" />
        <Item kind="summary" />
        <Item kind="history" />
        <Item kind="profile" />
        {/* Pad the trailing edge so the last phone can scroll
            into the center on small screens. */}
        <span className="shrink-0 w-10" />
      </div>
    </section>
  );
}

function Item({
  kind,
}: {
  kind: "home" | "race" | "summary" | "history" | "profile";
}) {
  const labels: Record<typeof kind, string> = {
    home: "Home",
    race: "Race Mode",
    summary: "Summary",
    history: "History",
    profile: "Profile",
  };
  return (
    <div className="snap-center shrink-0 flex flex-col items-center gap-3 sm:gap-4">
      <div className="block sm:hidden">
        <PhoneFrame width={190}>
          {kind === "home" && <HomeScreen />}
          {kind === "race" && <RaceScreen />}
          {kind === "summary" && <SummaryScreen />}
          {kind === "history" && <HistoryScreen />}
          {kind === "profile" && <ProfileScreen />}
        </PhoneFrame>
      </div>
      <div className="hidden sm:block">
        <PhoneFrame width={240}>
          {kind === "home" && <HomeScreen />}
          {kind === "race" && <RaceScreen />}
          {kind === "summary" && <SummaryScreen />}
          {kind === "history" && <HistoryScreen />}
          {kind === "profile" && <ProfileScreen />}
        </PhoneFrame>
      </div>
      <p className="text-[10px] sm:text-[11px] uppercase tracking-caps text-text-tertiary">
        {labels[kind]}
      </p>
    </div>
  );
}
