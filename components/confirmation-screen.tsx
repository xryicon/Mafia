import Link from "next/link";
import {ResendConfirmation} from "./resend-confirmation";
import {Brand} from "./brand";
import {GameIcon} from "./game-icon";
export function ConfirmationScreen({state}:{state:"confirmed"|"invalid"|"pending"}){
 const confirmed=state==="confirmed",invalid=state==="invalid";
 return <div className="confirmation-page">
  <section className="confirmation-hero">
   <img className="confirmation-backdrop" src="/art/email/waterfront.webp" alt="Blackwater's waterfront and illuminated city skyline at night" width={1600} height={1067} fetchPriority="high"/>
   <header className="confirmation-brandbar"><Brand/><p>A PLAYER-DRIVEN<br/>CRIME ECONOMY</p></header>
   <div className="confirmation-welcome"><p>WELCOME TO</p><div>Blackwater</div><span/><p>FORTUNES ARE BUILT.<br/>YOUR STORY STARTS HERE.</p></div>
  </section>
  <section className="confirmation-message" aria-labelledby="confirmation-title">
   <span className={"confirmation-seal "+(invalid?"invalid":"")}><GameIcon name={confirmed?"shield":invalid?"clock":"mail"} size={27}/></span>
   <p className="confirmation-kicker">{confirmed?"YOUR PLACE IN THE CITY IS SECURED":invalid?"THE CITY IS STILL WAITING":"ONE LAST STEP"}</p>
   <h1 id="confirmation-title">{confirmed?"Account confirmed.":invalid?"This link has expired.":"Check your invitation."}</h1>
   <p className="confirmation-copy">{confirmed?<>Your email is verified. Welcome to Blackwater Mafia.<br/>Build your business, make your first deal, and leave your mark on the city.</>:invalid?<>This confirmation link is invalid, expired, or has already been used.<br/>If you confirmed your account earlier, you can log in below.</>:<>Open the confirmation link in your email to verify your account.<br/>Already confirmed on another device? Log in to enter the city.</>}</p>
   <Link className="confirmation-button" href={confirmed?"/dashboard":"/login"}>{confirmed?"ENTER BLACKWATER":"LOG IN TO BLACKWATER"}<GameIcon name="arrow" size={23}/></Link>
   {!confirmed&&<ResendConfirmation/>}
   <span className="confirmation-small">{confirmed?"PRODUCE. TRADE. RISE.":"Your account is confirmed only after the email link is verified."}</span>
  </section>
  <section className="confirmation-opportunity" aria-label="A city of opportunity"><div className="confirmation-divider"><span/>A CITY OF OPPORTUNITY<span/></div><div className="confirmation-features">
   {[["economy","PLAYER-DRIVEN ECONOMY","Produce. Trade. Set your price."],["empire","BUILD YOUR EMPIRE","From small deals to a lasting legacy."],["gangs","GANGS AND TERRITORY","Form alliances. Take control."],["browser","PLAY IN YOUR BROWSER","No download required."]].map(([icon,title,description])=><article key={icon}><img src={"/art/email/"+icon+".png"} width={52} height={61} alt=""/><h2>{title}</h2><p>{description}</p></article>)}
  </div></section>
  <section className="confirmation-motto"><p>Every fortune<br/>has a dark side.</p><span>SAME PLAYERS.<br/>A DIFFERENT TOMORROW.</span></section>
  <footer className="confirmation-footer"><Brand/><div><Link href="/">The city</Link><Link href="/login">Log in</Link><Link href="/support">Help</Link><p>THE WATERFRONT NEVER FORGETS.</p></div></footer>
 </div>;
}
