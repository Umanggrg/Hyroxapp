// Sticky top nav. Intentionally minimal — the product is the
// hero, not the navigation. Brand left, single CTA right.
export function Nav() {
  return (
    <header className="sticky top-0 z-30 backdrop-blur-md bg-background/70 border-b border-divider/60">
      <div className="mx-auto max-w-6xl px-6 h-14 flex items-center justify-between">
        <a href="/" className="flex items-center gap-2 group">
          <span
            aria-hidden
            className="h-2.5 w-2.5 rounded-full bg-accent shadow-glow animate-pulseDot"
          />
          <span className="font-rounded font-bold tracking-caps uppercase text-sm">
            Trakrr
          </span>
        </a>
        <nav className="hidden sm:flex items-center gap-7 text-sm text-text-secondary">
          <a href="/#features" className="hover:text-text-primary transition">
            Features
          </a>
          <a href="/privacy" className="hover:text-text-primary transition">
            Privacy
          </a>
          <a href="/#founder" className="hover:text-text-primary transition">
            About
          </a>
        </nav>
        <a
          href="/#testflight"
          className="text-xs font-semibold uppercase tracking-caps px-3 sm:px-3.5 py-2 rounded-pill bg-accent text-white hover:bg-accent/90 transition"
        >
          <span className="sm:hidden">Beta</span>
          <span className="hidden sm:inline">Get TestFlight</span>
        </a>
      </div>
    </header>
  );
}
