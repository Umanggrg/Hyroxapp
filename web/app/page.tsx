import { Nav } from "@/components/Nav";
import { IntroAnimation } from "@/components/IntroAnimation";
import { StatsBar } from "@/components/StatsBar";
import { RaceFormatStrip } from "@/components/RaceFormatStrip";
import { AppShowcase } from "@/components/AppShowcase";
import { ScreenMarquee } from "@/components/ScreenMarquee";
import { WatchAndDuo } from "@/components/WatchAndDuo";
import { FeatureGrid } from "@/components/FeatureGrid";
import { PrivacyPosture } from "@/components/PrivacyPosture";
import { FounderNote } from "@/components/FounderNote";
import { Footer } from "@/components/Footer";

export default function Page() {
  return (
    <main className="min-h-screen bg-background">
      <Nav />
      <IntroAnimation />
      <StatsBar />
      <RaceFormatStrip />
      <AppShowcase />
      <ScreenMarquee />
      <WatchAndDuo />
      <FeatureGrid />
      <PrivacyPosture />
      <FounderNote />
      <Footer />
    </main>
  );
}
