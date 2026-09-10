"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

export function SiteChrome({ children }: { children: React.ReactNode }) {
  const game = usePathname().startsWith("/dashboard");
  if (game) return <main id="main">{children}</main>;
  return <>
    <header className="site-header"><Link className="wordmark" href="/">MAFIA<span>BLACKWATER</span></Link><nav aria-label="Main navigation"><Link href="/dashboard" prefetch={false}>Enter the city</Link><Link className="button small" href="/login">Log in <span aria-hidden="true">↗</span></Link></nav></header>
    <main id="main">{children}</main>
    <footer className="site-footer"><span>MAFIA / BLACKWATER</span><span>A player-driven world. Every fortune starts somewhere.</span><span>FICTIONAL GAME CURRENCY</span></footer>
  </>;
}
