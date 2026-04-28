// A thin band of dramatic numerals that establishes the depth
// of the build right after the hero. Each cell is meant to
// reward the second-glance reader — the first glance just sees
// "wow, big numbers."
const STATS = [
  { value: "300+", label: "Shipped tasks" },
  { value: "10K+", label: "Lines of Swift" },
  { value: "16", label: "Race-format segments" },
  { value: "0", label: "Trackers, ads, IAPs" },
];

export function StatsBar() {
  return (
    <section className="relative border-y hairline bg-background">
      <div className="mx-auto max-w-6xl px-6 py-10 sm:py-16 grid grid-cols-2 sm:grid-cols-4 gap-y-8 gap-x-4">
        {STATS.map((s) => (
          <div key={s.label} className="text-center">
            <p className="font-rounded font-bold tabular text-3xl sm:text-5xl lg:text-6xl tracking-[-0.03em]">
              {s.value}
            </p>
            <p className="text-[10px] sm:text-[11px] uppercase tracking-caps text-text-tertiary mt-2">
              {s.label}
            </p>
          </div>
        ))}
      </div>
    </section>
  );
}
