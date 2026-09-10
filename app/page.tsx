import Link from "next/link";
import { GameIcon } from "@/components/game-icon";
export default function Home() {
  return <div className="front-page">
    <section className="front-hero">
      <div className="front-copy"><p className="eyebrow"><span className="red-dot" /> A PERSISTENT CRIME STRATEGY GAME</p><p className="city-kicker">WELCOME TO BLACKWATER</p><h1>The city is<br />up for <em>grabs.</em></h1><p className="front-lede">Start with a little cash and a name nobody knows. Build your businesses. Trade with real players. Turn your first deal into an empire.</p><div className="hero-buttons"><Link className="button" href="/signup">Build your empire <GameIcon name="arrow" /></Link><Link className="button ghost" href="/login">Continue your story</Link></div><p className="start-note"><span>$10,000</span> starting cash <b>·</b> <span>5 crates</span> in your stash <b>·</b> Your next move is yours.</p></div>
      <div className="front-coordinate"><span>BLACKWATER // THE DOCKS</span><span>01 — TERRITORY OF OPPORTUNITY</span></div>
    </section>
    <section className="front-features" aria-label="How to play"><article><span className="feature-number">01</span><GameIcon name="operations" size={25}/><h2>Make your name.</h2><p>Complete operations for cash and respect. Rise from associate to underboss.</p></article><article><span className="feature-number">02</span><GameIcon name="businesses" size={25}/><h2>Own the supply.</h2><p>Buy a distillery, workshop, or foundry. Collect the goods your businesses produce.</p></article><article><span className="feature-number">03</span><GameIcon name="market" size={25}/><h2>Set the price.</h2><p>Players make the market. List your goods, buy another player's stock, and close the deal.</p></article></section>
    <div className="front-bottom"><span className="eyebrow">NO EMPIRE WAS BUILT ALONE.</span><Link href="/signup">Take your first step <span aria-hidden="true">↗</span></Link></div>
  </div>;
}
