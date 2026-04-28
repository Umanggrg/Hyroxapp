import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Trakr — Built for the modern hybrid athlete",
  description:
    "The training companion for hybrid-fitness racers. 16-station race mode, Apple Watch sync, real-time HR, Duo Mode, and zero tracking.",
  metadataBase: new URL("https://trakr.app"),
  openGraph: {
    title: "Trakr — Built for the modern hybrid athlete",
    description:
      "16-station race mode, Apple Watch sync, real-time HR, Duo Mode. Zero analytics, zero ads, all on-device.",
    type: "website",
  },
};

// Next 14 split viewport-related fields out of `metadata`.
// Setting `themeColor` here keeps Mobile Safari's address bar
// matching the page background.
export const viewport: Viewport = {
  themeColor: "#0A0A0B",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="bg-background">
      <body className="bg-background text-text-primary antialiased">
        {children}
      </body>
    </html>
  );
}
