// iOS tab bar mock — three tabs matching Trakr's actual tab
// layout (Home / History / Profile). The active tab is `accent`.
type Tab = "home" | "history" | "profile";

export function TabBar({ active }: { active: Tab }) {
  return (
    <div className="absolute bottom-0 inset-x-0 backdrop-blur bg-background/85 border-t border-divider/60">
      <div className="grid grid-cols-3 px-4 pt-2 pb-3">
        <TabItem
          glyph="◉"
          label="Home"
          activeState={active === "home"}
        />
        <TabItem
          glyph="≡"
          label="History"
          activeState={active === "history"}
        />
        <TabItem
          glyph="◎"
          label="Profile"
          activeState={active === "profile"}
        />
      </div>
    </div>
  );
}

function TabItem({
  glyph,
  label,
  activeState,
}: {
  glyph: string;
  label: string;
  activeState: boolean;
}) {
  return (
    <div
      className={`flex flex-col items-center gap-0.5 ${
        activeState ? "text-accent" : "text-text-tertiary"
      }`}
    >
      <span className="text-base leading-none">{glyph}</span>
      <span className="text-[9px] font-semibold uppercase tracking-caps">
        {label}
      </span>
    </div>
  );
}
