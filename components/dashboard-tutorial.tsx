"use client";
import Link from "next/link";
import {useEffect,useRef,useState} from "react";
import steps from "@/lib/tutorial-steps.json";

export function DashboardTutorial({playerId}:{playerId:string}){
 const key="blackwater:tutorial:v1:"+playerId;
 const [hidden,setHidden]=useState(false),[ready,setReady]=useState(false),[open,setOpen]=useState(false),[step,setStep]=useState(0),[complete,setComplete]=useState(false),[muted,setMuted]=useState(false),[audioError,setAudioError]=useState(false),[storageError,setStorageError]=useState(false);
 const dialog=useRef<HTMLDialogElement>(null),audio=useRef<HTMLAudioElement>(null),trigger=useRef<HTMLButtonElement>(null);
 const current=steps[step];
 useEffect(()=>{
  try{const saved=JSON.parse(localStorage.getItem(key)||"null");if(saved&&Number.isInteger(saved.step)&&saved.step>=0&&saved.step<steps.length){setStep(saved.step);setComplete(saved.complete===true);setHidden(saved.complete===true&&saved.hidden===true);}}
  catch{setStorageError(true);}setReady(true);
 },[key]);
 function save(next:number,done=false){setStep(next);setComplete(done);try{localStorage.setItem(key,JSON.stringify({step:next,complete:done}));}catch{setStorageError(true);}}
 function close(done=false){audio.current?.pause();save(step,done);setOpen(false);dialog.current?.close();trigger.current?.focus();}
 useEffect(()=>{
  if(!open)return;
  dialog.current?.showModal();
  const candidates=Array.from(document.querySelectorAll<HTMLElement>(current.target));
  const target=candidates.find(el=>el.getClientRects().length>0);
  target?.classList.add("tutorial-highlight");
  target?.scrollIntoView({block:"start",behavior:"instant"});
  return()=>target?.classList.remove("tutorial-highlight");
 },[open,current]);
 useEffect(()=>{
  const element=audio.current;if(!element||!open)return;
  element.pause();element.currentTime=0;setAudioError(false);
  if(!muted)void element.play().catch(()=>setAudioError(true));
  return()=>element.pause();
 },[open,step,muted]);
 function replay(){const element=audio.current;if(!element)return;setMuted(false);setAudioError(false);element.currentTime=0;void element.play().catch(()=>setAudioError(true));}
 function hide(){if(!complete)return;try{localStorage.setItem(key,JSON.stringify({step,complete:true,hidden:true}));setHidden(true);}catch{setStorageError(true);}}
 if(!ready||hidden)return null;
 return <>
  <section className="tutorial-invite command-panel" aria-label="New player tutorial"><div><p className="eyebrow">A WORD FROM YOUR MENTOR</p><h2>{complete?"The city is yours to explore":"New to Blackwater?"}</h2><p>A guided introduction to your dashboard, the city, and warehouses.</p></div><button ref={trigger} className="command-button" disabled={!ready} onClick={()=>{if(complete)save(0);setOpen(true);}}>{complete?"Replay tutorial":step?"Resume tutorial":"Start tutorial"}</button>{complete&&<button className="command-button" onClick={hide}>Hide tutorial</button>}{storageError&&<p role="status">Your preference could not be saved in this browser.</p>}</section>
  {open&&<dialog ref={dialog} className="tutorial-dialog" aria-labelledby="tutorial-title" aria-describedby="tutorial-text" onCancel={event=>{event.preventDefault();close();}}>
   <div className="tutorial-top"><span>BLACKWATER · THE INTRODUCTION</span><button onClick={()=>close()} aria-label="Skip tutorial">Skip ×</button></div>
   <div aria-live="polite" aria-atomic="true"><p className="eyebrow">STEP {step+1} OF {steps.length}</p><h2 id="tutorial-title">{current.title}</h2><p id="tutorial-text">{current.text}</p></div>
   <audio ref={audio} src={"/audio/tutorial/"+current.id+".wav"} preload="auto" onError={()=>setAudioError(true)}/>
   <div className="tutorial-audio"><button onClick={()=>setMuted(!muted)} aria-pressed={muted}>{muted?"Unmute narration":"Mute narration"}</button><button onClick={replay}>Replay voice</button><span>AI narrator</span></div>
   {audioError&&<p role="status">Narration could not play. You can read every instruction above.</p>}
   {storageError&&<p role="status">Progress cannot be saved in this browser.</p>}
   {step===steps.length-1&&<nav className="tutorial-destinations" aria-label="Choose your first move"><Link href="/bin-diving" onClick={()=>close(true)}>Scavenging</Link><Link href="/districts" onClick={()=>close(true)}>Explore districts</Link><Link href="/inventory" onClick={()=>close(true)}>Inventory</Link></nav>}
   <footer><button className="command-button" disabled={step===0} onClick={()=>save(step-1)}>Back</button><progress aria-label="Tutorial progress" value={step+1} max={steps.length}/><button className="command-button" onClick={()=>step===steps.length-1?close(true):save(step+1)}>{step===steps.length-1?"Finish tutorial":"Next"}</button></footer>
  </dialog>}
 </>;
}
