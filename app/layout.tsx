import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Mafia — The inner circle", template: "%s · Mafia" },
  description: "Your place at the table. Join Mafia and enter your private dashboard.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>
    <a className="skip" href="#main">Skip to content</a>
    <header className="header"><Link className="brand" href="/" aria-label="Mafia home"><span aria-hidden="true">M.</span> MAFIA</Link>
      <nav aria-label="Main navigation"><Link href="/dashboard" prefetch={false}>Dashboard</Link><Link className="nav-login" href="/login">Log in <span aria-hidden="true">↗</span></Link></nav>
    </header>
    <main id="main">{children}</main>
    <footer><span>MAFIA / THE INNER CIRCLE</span><span>A place at the table.</span></footer>
  </body></html>;
}
