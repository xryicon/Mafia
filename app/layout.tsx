import type { Metadata } from "next";
import { SiteChrome } from "@/components/site-chrome";
import "./globals.css";
export const metadata: Metadata = {
  title: { default: "Mafia — Blackwater", template: "%s · Mafia" },
  description: "Build a criminal empire in Blackwater. Run businesses, trade with other players, and make your name in a persistent browser strategy game.",
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body><a className="skip" href="#main">Skip to content</a><SiteChrome>{children}</SiteChrome></body></html>;
}
