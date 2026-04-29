import type { Metadata } from "next";
import Link from "next/link";
import { Nav } from "@/components/Nav";
import { Footer } from "@/components/Footer";

// The full Trakr privacy policy. Hosted at /privacy so it can be
// referenced as the canonical URL from App Store Connect, the in-app
// Settings → Privacy link, and the TestFlight invite. Source of truth
// is `docs/PRIVACY.md`; if that file changes, update this page too.
export const metadata: Metadata = {
  title: "Privacy Policy — Trakr",
  description:
    "How Trakr handles your data. Short version: it doesn't leave your phone.",
  robots: { index: true, follow: true },
};

export default function PrivacyPage() {
  return (
    <main className="min-h-screen bg-background">
      <Nav />

      {/* Hero — kept compact and on-brand. The TL;DR up top is the
          most important thing on the page; reviewers and readers
          should be able to grasp the policy in 5 seconds. */}
      <section className="relative overflow-hidden border-b hairline">
        <div
          aria-hidden
          className="absolute inset-0 bg-hero-radial pointer-events-none"
        />
        <div className="relative mx-auto max-w-3xl px-6 pt-16 pb-12 sm:pt-24 sm:pb-16">
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-4">
            Privacy Policy
          </p>
          <h1 className="font-rounded font-bold text-4xl sm:text-5xl tracking-tight leading-[1.05]">
            Your data never{" "}
            <span className="text-accent">leaves your phone.</span>
          </h1>
          <p className="mt-6 text-text-secondary text-lg leading-relaxed">
            This is a plain-English privacy policy. The short version: Trakr
            stores your training data on your device. It does not collect,
            transmit, sell, or share your data with anyone.
          </p>
          <p className="mt-3 text-sm text-text-tertiary">
            Last updated: April 25, 2026 · Effective: April 25, 2026
          </p>
        </div>
      </section>

      {/* Body — long-form prose. We don't use a markdown renderer
          because the design system has specific spacing/typography
          requirements that are easier expressed inline. */}
      <article className="mx-auto max-w-3xl px-6 py-16 sm:py-20 prose-body">
        <Callout>
          Trakr is an independent app, not affiliated with, endorsed by, or
          sponsored by HYROX GmbH. &quot;HYROX&quot; is a registered trademark
          of HYROX GmbH; we use it only descriptively to refer to the race
          format athletes train for.
        </Callout>

        <p className="text-text-secondary leading-relaxed mt-8">
          If anything in this document is unclear, email{" "}
          <a
            href="mailto:umang.gurung35@gmail.com"
            className="text-text-primary underline underline-offset-4 hover:text-accent transition"
          >
            umang.gurung35@gmail.com
          </a>{" "}
          and we&apos;ll fix it.
        </p>

        <Section number="1" title="Who runs this app">
          <p>
            Trakr is built and maintained by Umang Gurung (the
            &quot;developer,&quot; &quot;we,&quot; or &quot;us&quot;). It is a
            personal project, not a company, and does not operate any servers,
            accounts, or back-end services at this time.
          </p>
        </Section>

        <Section number="2" title="What data Trakr uses">
          <p>
            Trakr is a fitness companion for hybrid-fitness athletes. To do its
            job, it works with the following kinds of information — all of
            which stay on your device unless you explicitly export or share
            them:
          </p>
          <ul>
            <li>
              <strong>Race data you create.</strong> Splits, total times,
              station-level reps and weights, race-day notes, race photos,
              custom workout templates, target finish times, race-event
              countdowns. Saved locally via SwiftData.
            </li>
            <li>
              <strong>Profile data you enter.</strong> Display name, handle,
              location, bio, division (Men&apos;s Open / Women&apos;s Open /
              etc.), max heart rate, avatar photo. All saved locally.
            </li>
            <li>
              <strong>HealthKit data you allow.</strong> When you grant access,
              Trakr reads your heart rate (during a race and as per-station
              summary statistics) and your active-energy-burned (calorie
              estimate per station). Apple HealthKit governs that access; you
              can revoke it at any time in <em>Settings → Privacy &amp;
              Security → Health → Trakr</em>.
            </li>
            <li>
              <strong>Photos you attach.</strong> When you add a photo to a
              race, Trakr uses the iOS PhotosPicker to receive that single
              photo. The photo is stored alongside the race in local storage.
              We do not access any other photos in your library.
            </li>
            <li>
              <strong>App preferences.</strong> Toggles for voice cues,
              countdowns, notifications, Roxzone (transition) tracking, etc.
            </li>
          </ul>
          <p>
            We do <strong>not</strong> collect or store: your real name (unless
            you type it as your display name), email address, phone number,
            location coordinates, IP address, device identifiers, advertising
            IDs, or browsing activity inside other apps.
          </p>
        </Section>

        <Section number="3" title="What we do not do">
          <ul>
            <li>
              We do not run analytics. There is no Firebase, Mixpanel,
              Amplitude, App Store Connect Analytics opt-in, or equivalent SDK
              in the app.
            </li>
            <li>
              We do not run crash reporting other than what Apple&apos;s
              standard <code>MetricKit</code> exposes anonymously to the App
              Store dashboard, and only if you have opted in to share crash
              data with developers in iOS settings.
            </li>
            <li>
              We do not show advertising and do not integrate with any ad
              networks.
            </li>
            <li>
              We do not sell, rent, or otherwise transfer any of your data to
              third parties.
            </li>
            <li>We do not track you across other apps or websites.</li>
          </ul>
        </Section>

        <Section number="4" title="HealthKit specifics">
          <p>
            Apple&apos;s HealthKit framework requires a special privacy
            disclosure. Per Apple&apos;s developer policy:
          </p>
          <ul>
            <li>
              Trakr uses HealthKit <strong>only</strong> to support the
              features in §2 (read your heart rate and active-energy-burned
              values, and write completed races back to Health as workouts so
              they appear alongside your other Apple Fitness data).
            </li>
            <li>
              Trakr does <strong>not</strong> use HealthKit data for
              advertising, marketing, or other use-based data mining.
            </li>
            <li>
              Trakr does <strong>not</strong> disclose HealthKit data to any
              third party.
            </li>
            <li>HealthKit data never leaves your device.</li>
          </ul>
          <p>
            You can revoke HealthKit permissions at any time in <em>iOS
            Settings → Privacy &amp; Security → Health → Trakr</em>. The app
            continues to work without HealthKit; heart rate / calorie fields
            simply remain blank for new races.
          </p>
        </Section>

        <Section number="5" title="Live Activities and notifications">
          <p>
            If you enable Live Activities, the active race timer can render on
            your Lock Screen and in the Dynamic Island via Apple&apos;s
            standard ActivityKit. The data shown there (race timer, current
            station) is delivered locally on your device — no remote server is
            involved.
          </p>
          <p>
            If you enable notifications, Trakr uses Apple&apos;s local
            notification system to remind you about training streaks and
            upcoming race events. These notifications are scheduled on-device.
            We do <strong>not</strong> send push notifications from any
            server.
          </p>
        </Section>

        <Section number="6" title="Sharing and exporting">
          <p>
            Some screens (the post-race summary, monthly/yearly recaps,
            profile) offer a &quot;Share&quot; button that renders a portable
            PNG image of your data. When you tap that button, you control where
            the image goes — it is handed off to iOS&apos;s standard share
            sheet. Trakr does not transmit a copy elsewhere.
          </p>
        </Section>

        <Section number="7" title="Where your data lives">
          <p>
            Right now, on your iPhone (and your paired Apple Watch, when you
            opt in to the Watch companion). Specifically:
          </p>
          <ul>
            <li>SwiftData store inside the app&apos;s sandbox container.</li>
            <li>
              Apple Health (only the workouts you let Trakr write back).
            </li>
            <li>
              Standard iOS application backups via iCloud / Finder, which are
              encrypted by Apple and managed under Apple&apos;s own privacy
              terms.
            </li>
          </ul>
          <p>
            If you delete the app, the local database goes with it. Any
            workouts already written to Apple Health remain in Apple Health
            under your control.
          </p>
        </Section>

        <Section number="8" title="Future cloud sync">
          <p>
            A future version of Trakr will offer optional cloud sync (planned
            via Supabase) so the same account can be used across multiple
            devices and to support social features. <strong>That capability
            is not active in the current version.</strong> When it ships, this
            document will be updated to spell out exactly what gets synced,
            where it is stored, the legal basis, and how you can delete it.
            You will be asked to opt in before any data leaves your device.
          </p>
        </Section>

        <Section number="9" title="Children">
          <p>
            Trakr is not directed to children under 13 (or the equivalent
            minimum age in your jurisdiction). If you are a parent or guardian
            and believe a child has used the app, you can simply uninstall it;
            no remote data exists to be deleted.
          </p>
        </Section>

        <Section number="10" title="Your rights">
          <p>
            Because Trakr does not transmit your data anywhere, the practical
            mechanism for exercising rights like access, deletion, or
            portability is the iOS device itself:
          </p>
          <ul>
            <li>
              <strong>Access / portability.</strong> The Settings screen
              exposes data export options for your race history.
            </li>
            <li>
              <strong>Deletion.</strong> You can delete individual races from
              the History screen, or delete the entire app from your home
              screen to wipe the local database.
            </li>
            <li>
              <strong>Withdrawal of HealthKit consent.</strong> See §4.
            </li>
          </ul>
          <p>
            If a future cloud-sync version is released, additional access and
            deletion mechanisms will be added at that time.
          </p>
        </Section>

        <Section number="11" title="Security">
          <p>
            Trakr relies on the security guarantees of iOS — sandboxed file
            storage, Data Protection class encryption when the device is
            locked, secure enclave for biometrics. We do not attempt to bypass
            or weaken these protections.
          </p>
          <p>
            No system is perfectly secure, and we make no guarantee of
            absolute security. If you become aware of a security issue
            affecting Trakr, please email{" "}
            <a
              href="mailto:umang.gurung35@gmail.com"
              className="text-text-primary underline underline-offset-4 hover:text-accent transition"
            >
              umang.gurung35@gmail.com
            </a>
            .
          </p>
        </Section>

        <Section number="12" title="Changes to this policy">
          <p>
            If material changes are made — for example, when cloud sync ships —
            this document will be updated and the &quot;Last updated&quot;
            date at the top will change. Continued use of the app after the
            change indicates acceptance of the updated policy.
          </p>
        </Section>

        <Section number="13" title="Contact">
          <p>
            Questions, requests, or concerns about this privacy policy:
          </p>
          <p className="mt-4">
            <strong className="text-text-primary">Umang Gurung</strong>
            <br />
            Email:{" "}
            <a
              href="mailto:umang.gurung35@gmail.com"
              className="text-text-primary underline underline-offset-4 hover:text-accent transition"
            >
              umang.gurung35@gmail.com
            </a>
          </p>
        </Section>

        <div className="mt-16 pt-10 border-t hairline">
          <Link
            href="/"
            className="inline-flex items-center gap-2 text-sm text-text-secondary hover:text-text-primary transition"
          >
            <span aria-hidden>←</span> Back to Trakr
          </Link>
        </div>
      </article>

      <Footer />
    </main>
  );
}

// A small intro callout used for the HYROX trademark disclosure.
// Visually distinct from body prose so reviewers/readers spot it.
function Callout({ children }: { children: React.ReactNode }) {
  return (
    <div className="rounded-card bg-surface border border-divider/60 p-5 text-sm text-text-secondary leading-relaxed">
      {children}
    </div>
  );
}

// Section wrapper with consistent numbering + heading typography.
// Numbered sections match the source-of-truth in docs/PRIVACY.md
// so an App Review note like "see §4" still maps cleanly.
function Section({
  number,
  title,
  children,
}: {
  number: string;
  title: string;
  children: React.ReactNode;
}) {
  return (
    <section className="mt-12 first:mt-0 scroll-mt-24" id={`section-${number}`}>
      <h2 className="font-rounded font-bold text-2xl sm:text-3xl tracking-tight">
        <span className="text-text-tertiary mr-3 tabular">{number}.</span>
        {title}
      </h2>
      <div className="mt-5 space-y-4 text-text-secondary leading-relaxed [&_ul]:list-disc [&_ul]:pl-6 [&_ul]:space-y-2 [&_ul]:my-4 [&_strong]:text-text-primary [&_em]:text-text-primary [&_em]:not-italic [&_code]:text-text-primary [&_code]:bg-surface [&_code]:px-1.5 [&_code]:py-0.5 [&_code]:rounded [&_code]:text-[0.9em]">
        {children}
      </div>
    </section>
  );
}
