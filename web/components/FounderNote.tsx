// Founder note. Left-aligned pull-quote with avatar block on the
// right — feels editorial, not corporate. Anchors the product
// to a real person training for HYROX.
export function FounderNote() {
  return (
    <section
      id="founder"
      className="relative bg-background border-y hairline overflow-hidden"
    >
      <div
        aria-hidden
        className="absolute inset-0 bg-hero-radial pointer-events-none opacity-40"
      />
      <div className="relative mx-auto max-w-6xl px-6 py-20 sm:py-24 lg:py-32 grid grid-cols-1 lg:grid-cols-12 gap-12 items-center">
        <div className="lg:col-span-8">
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-5">
            Behind the app
          </p>
          <p className="font-rounded font-bold text-2xl sm:text-4xl lg:text-5xl leading-[1.1] tracking-[-0.02em]">
            <span className="text-text-tertiary">"</span>
            I needed a tool that didn&apos;t feel like a spreadsheet. So I
            built the one I&apos;d want to{" "}
            <span className="text-accent">open before every session.</span>
            <span className="text-text-tertiary">"</span>
          </p>
          <p className="text-text-secondary mt-6 sm:mt-7 text-base sm:text-lg leading-relaxed max-w-2xl">
            I&apos;m Umang. I train HYROX, I race the Doubles format, and Trakr
            is what I built — evenings and weekends, native iOS and watchOS,
            pair-programmed end-to-end with Claude. Every screen is something
            I open during my own sessions.
          </p>
          <a
            href="mailto:umang.gurung35@gmail.com"
            className="mt-8 inline-flex items-center gap-2 text-sm text-text-primary border-b border-divider hover:border-accent transition pb-1"
          >
            Write to me directly
            <span aria-hidden>→</span>
          </a>
        </div>

        <div className="lg:col-span-4 flex lg:justify-end">
          <div className="relative">
            <div
              aria-hidden
              className="absolute -inset-6 bg-hero-radial blur-2xl opacity-80"
            />
            <div className="relative rounded-card bg-surface border border-divider/60 p-6 shadow-card max-w-xs">
              <div className="flex items-center gap-3">
                <div className="h-12 w-12 rounded-full bg-gradient-to-br from-accent to-accent-dim ring-2 ring-accent/40" />
                <div>
                  <p className="font-rounded font-bold text-base">Umang Gurung</p>
                  <p className="text-[11px] text-text-secondary">
                    Founder · solo dev
                  </p>
                </div>
              </div>
              <div className="mt-4 grid grid-cols-2 gap-2 text-center">
                <Stat value="HYROX" label="Athlete" />
                <Stat value="Florida" label="Based in" />
              </div>
              <div className="mt-3 rounded-xl border border-divider/60 bg-surface-elevated/60 p-3">
                <p className="text-[10px] uppercase tracking-caps text-text-tertiary">
                  Pair-programmed with
                </p>
                <p className="text-sm font-rounded font-semibold mt-0.5">
                  Claude · via Claude Code
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div className="rounded-lg bg-surface-elevated/60 border border-divider/60 px-3 py-2">
      <p className="font-rounded font-bold text-sm">{value}</p>
      <p className="text-[9px] uppercase tracking-caps text-text-tertiary mt-0.5">
        {label}
      </p>
    </div>
  );
}
