import Link from "next/link";

export default function Home() {
  return <div className="landing">
    <section className="hero">
      <p className="eyebrow"><span className="dot" /> YOUR NEXT CHAPTER STARTS HERE</p>
      <h1>Every circle<br />starts with<br /><em>someone.</em></h1>
      <p className="lede">Make your entrance. Create your account and find your place in the inner circle.</p>
      <div className="actions"><Link className="button" href="/signup">Take your seat <span aria-hidden="true">↗</span></Link><Link className="text-link" href="/login">Already a member? Log in</Link></div>
      <div className="hero-note"><span aria-hidden="true">✳</span><p>YOUR ACCOUNT. YOUR SPACE.<br /><span>A private dashboard, just for you.</span></p></div>
    </section>
    <aside className="art" aria-label="Decorative Mafia membership card">
      <div className="orbit orbit-one" /><div className="orbit orbit-two" />
      <div className="member-card"><div className="card-top">MAFIA <span>MEMBER ACCESS</span></div><div className="monogram" aria-hidden="true">M<span>♠</span></div><div className="card-bottom"><span>THE INNER CIRCLE</span><span>EST. 2026</span></div></div>
      <span className="art-caption">GOOD COMPANY. NEW POSSIBILITIES.</span>
    </aside>
  </div>;
}
