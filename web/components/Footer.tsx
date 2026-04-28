// Footer. The TestFlight CTA is the real ask of the page, so we
// give it its own oversized moment right above the legal strip.
export function Footer() {
  return (
    <>
      <section
        id="testflight"
        className="relative overflow-hidden border-y hairline"
      >
        <div
          aria-hidden
          className="absolute inset-0 bg-hero-radial pointer-events-none"
        />
        <div className="relative mx-auto max-w-4xl px-6 py-20 sm:py-24 lg:py-28 text-center">
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-4">
            Beta · iOS 17+ · Apple Watch optional
          </p>
          <h2 className="font-rounded font-bold text-3xl sm:text-5xl lg:text-6xl tracking-tight leading-[1.02]">
            Train with the app you'd <br className="hidden sm:block" />
            <span className="text-accent">have built yourself.</span>
          </h2>
          <p className="mt-6 text-text-secondary text-lg max-w-xl mx-auto">
            TestFlight is open to a small group while we polish v1. Drop your
            email and we'll send you the invite as slots open.
          </p>
          <form
            className="mt-9 flex flex-wrap items-center justify-center gap-3"
            action="mailto:umang.gurung35@gmail.com"
            method="post"
            encType="text/plain"
          >
            <label htmlFor="email" className="sr-only">
              Email address
            </label>
            <input
              id="email"
              name="email"
              type="email"
              required
              placeholder="you@athlete.app"
              className="px-4 py-3 rounded-pill bg-surface border border-divider text-text-primary text-sm focus:outline-none focus:border-accent w-full sm:w-80"
            />
            <button
              type="submit"
              className="px-5 py-3 rounded-pill bg-accent text-white font-semibold text-sm hover:bg-accent/90 transition shadow-glow"
            >
              Request invite
            </button>
          </form>
          <p className="mt-4 text-xs text-text-tertiary">
            We use your email only to send the TestFlight code. Nothing else.
          </p>
        </div>
      </section>

      <footer className="bg-background">
        <div className="mx-auto max-w-6xl px-6 py-10 flex flex-col sm:flex-row items-start sm:items-center gap-6 sm:gap-0 justify-between text-xs text-text-tertiary">
          <div className="flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-accent" />
            <span className="font-rounded font-bold tracking-caps uppercase text-text-primary">
              Trakr
            </span>
            <span className="ml-3">
              © {new Date().getFullYear()} Umang Gurung
            </span>
          </div>
          <div className="flex items-center gap-5">
            <a className="hover:text-text-primary transition" href="#privacy">
              Privacy
            </a>
            <a
              className="hover:text-text-primary transition"
              href="mailto:umang.gurung35@gmail.com"
            >
              Contact
            </a>
            <span>
              HYROX™ is a registered trademark of HYROX GmbH. Trakr is not
              affiliated with HYROX GmbH.
            </span>
          </div>
        </div>
      </footer>
    </>
  );
}
