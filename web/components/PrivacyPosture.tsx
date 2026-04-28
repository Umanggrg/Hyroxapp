// Privacy is a positioning advantage, not a footnote. We give it
// a full section because every other "fitness social" app runs
// on tracking, and Trakr deliberately doesn't.
export function PrivacyPosture() {
  return (
    <section
      id="privacy"
      className="border-y hairline bg-surface/30"
    >
      <div className="mx-auto max-w-6xl px-6 py-20 sm:py-24 lg:py-28 grid grid-cols-1 lg:grid-cols-12 gap-10">
        <div className="lg:col-span-5">
          <p className="text-[11px] uppercase tracking-caps text-text-tertiary mb-3">
            Privacy by architecture
          </p>
          <h2 className="font-rounded font-bold text-3xl sm:text-5xl lg:text-6xl tracking-tight leading-[1.05]">
            Your data never{" "}
            <span className="text-accent">leaves your phone.</span>
          </h2>
          <p className="text-text-secondary mt-5 leading-relaxed">
            Trakr stores your training data on-device via SwiftData. No
            analytics SDKs. No advertising IDs. No third-party crash reporting.
            HealthKit reads stay in HealthKit. Race history stays in your app.
            Multipeer Duo Mode is peer-to-peer with no server in the middle.
          </p>
          <div className="mt-7 flex flex-wrap gap-3">
            <a
              href="https://github.com"
              className="text-sm text-text-secondary hover:text-text-primary underline underline-offset-4"
            >
              Read the Privacy Policy →
            </a>
          </div>
        </div>

        <div className="lg:col-span-7 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <PrivacyCell
            label="Analytics SDKs"
            value="None"
            note="No Firebase, Mixpanel, Amplitude, or App Store Connect Analytics opt-in."
          />
          <PrivacyCell
            label="Tracking domains"
            value="0"
            note="Privacy Manifest declares zero tracking domains. Required since Spring 2024."
          />
          <PrivacyCell
            label="Collected data types"
            value="0"
            note="No data types collected and sent off-device. Honestly empty."
          />
          <PrivacyCell
            label="HealthKit usage"
            value="On-device"
            note="Read HR + active calories, write workouts back to Health. Never disclosed to third parties."
          />
        </div>
      </div>
    </section>
  );
}

function PrivacyCell({
  label,
  value,
  note,
}: {
  label: string;
  value: string;
  note: string;
}) {
  return (
    <div className="rounded-card bg-surface border border-divider/60 p-5">
      <p className="text-[11px] uppercase tracking-caps text-text-tertiary">
        {label}
      </p>
      <p className="font-rounded font-bold text-3xl tabular mt-2">{value}</p>
      <p className="text-xs text-text-secondary mt-2 leading-relaxed">{note}</p>
    </div>
  );
}
