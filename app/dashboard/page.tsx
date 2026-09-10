import Link from "next/link";
import { requireUser } from "@/lib/auth";
import { LogoutButton } from "@/components/logout-button";

export const dynamic = "force-dynamic";
export const metadata = { title: "Your dashboard" };

export default async function Dashboard({ searchParams }: { searchParams: Promise<{ updated?: string }> }) {
  const user = await requireUser();
  const params = await searchParams;
  return <section className="dashboard">
    <div className="dashboard-heading"><div><p className="eyebrow"><span className="dot" /> YOU'RE IN</p><h1>Welcome to<br /><em>the circle.</em></h1><p className="lede">Your own corner of Mafia. Make yourself at home.</p></div><LogoutButton /></div>
    {params.updated === "1" && <p className="notice" role="status">Your password has been updated.</p>}
    <div className="dashboard-grid"><article className="panel"><p className="eyebrow">YOUR MEMBERSHIP</p><h2>A seat with your name on it.</h2><dl><dt>Email address</dt><dd>{user.email}</dd><dt>Member since</dt><dd>{new Intl.DateTimeFormat("en", { dateStyle: "long", timeZone: "UTC" }).format(new Date(user.created_at))}</dd></dl><span className="badge">● Account active</span></article>
    <article className="panel dark-panel"><span className="small-spade" aria-hidden="true">♠</span><p className="eyebrow">ACCOUNT SETTINGS</p><h2>Keep your<br />seat secure.</h2><p>Manage your password whenever you need a fresh start.</p><Link className="button light" href="/update-password">Change password <span aria-hidden="true">↗</span></Link></article></div>
  </section>;
}
