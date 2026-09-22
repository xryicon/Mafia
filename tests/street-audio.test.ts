import {strict as assert} from "node:assert";
import {readFileSync} from "node:fs";
import {test} from "node:test";
import {createStreetAudio,STREET_AUDIO,streetSirenLevel,type StreetAudioOptions} from "../lib/street-audio";

class FakeAudio{
 paused=true;muted=false;loop=false;preload="";volume=1;playbackRate=1;currentTime=0;playCalls=0;pauseCalls=0;loadCalls=0;src:string;
 private listeners=new Map<string,Set<()=>void>>();
 constructor(src:string){this.src=src;}
 async play(){this.paused=false;this.playCalls++;}
 pause(){this.paused=true;this.pauseCalls++;}
 removeAttribute(name:string){if(name==="src")this.src="";}
 load(){this.loadCalls++;}
 addEventListener(type:string,listener:()=>void){const listeners=this.listeners.get(type)??new Set();listeners.add(listener);this.listeners.set(type,listeners);}
 removeEventListener(type:string,listener:()=>void){this.listeners.get(type)?.delete(listener);}
}
class FakeEvents{
 hidden=false;listeners=new Map<string,Set<EventListenerOrEventListenerObject>>();
 addEventListener(type:string,listener:EventListenerOrEventListenerObject){const listeners=this.listeners.get(type)??new Set();listeners.add(listener);this.listeners.set(type,listeners);}
 removeEventListener(type:string,listener:EventListenerOrEventListenerObject){this.listeners.get(type)?.delete(listener);}
 fire(type:string){for(const listener of this.listeners.get(type)??[])typeof listener==="function"?listener(new Event(type)):listener.handleEvent(new Event(type));}
}
class DelayedAudio extends FakeAudio{
 finish:()=>void=()=>{};
 override play(){this.playCalls++;return new Promise<void>(resolve=>{this.finish=()=>{this.paused=false;resolve();};});}
}

test("recorded street sounds are bounded, self-hosted MP3 assets with source documentation",()=>{
 const credits=readFileSync("docs/audio-streets.md","utf8");
 for(const path of [STREET_AUDIO.ambience,STREET_AUDIO.footsteps,STREET_AUDIO.siren]){
  assert.ok(path.startsWith("/audio/streets/"));const bytes=readFileSync("public"+path);
  assert.ok(bytes.length>50_000&&bytes.length<750_000);assert.ok(bytes.subarray(0,3).toString()==="ID3"||(bytes[0]===255&&(bytes[1]&224)===224),"MP3 header");
  assert.ok(credits.includes(path.split("/").at(-1)!));
 }
 assert.ok(credits.includes("CC0 1.0")&&credits.includes("254125")&&credits.includes("271039")&&credits.includes("American_police_siren_i"));
 assert.equal(STREET_AUDIO.gunshot,"/audio/range/colt-1911-shot.mp3");
});

test("street audio follows actual movement and pursuit distance, then releases resources",async()=>{
 const nodes:FakeAudio[]=[],doc=new FakeEvents(),win=new FakeEvents();
 const engine=createStreetAudio({createAudio:source=>{const audio=new FakeAudio(source);nodes.push(audio);return audio as unknown as HTMLAudioElement;},document:doc as unknown as StreetAudioOptions["document"],window:win as unknown as StreetAudioOptions["window"]});
 const [ambience,steps,siren]=nodes;
 engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});assert.equal(await engine.start(),true);assert.equal(ambience.playCalls,1);assert.equal(steps.playCalls,0);
 engine.update({moving:true,sprinting:false,pursuit:false,locked:true,deltaSeconds:.25});assert.equal(steps.playCalls,1);assert.equal(steps.playbackRate,.92);
 engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});assert.equal(steps.paused,true);assert.equal(steps.currentTime,0);
 engine.update({moving:false,sprinting:false,pursuit:true,policeDistance:0,locked:true,deltaSeconds:.25});const nearby=siren.volume;assert.equal(siren.playCalls,1);
 engine.update({moving:false,sprinting:false,pursuit:true,policeDistance:4,locked:true,deltaSeconds:.25});assert.ok(siren.volume<nearby);assert.ok(streetSirenLevel(true,0)>streetSirenLevel(true,4));
 engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});assert.equal(siren.paused,true);
 assert.equal(await engine.playConfirmedGunshot(),true);assert.equal(nodes.length,4);
 doc.hidden=true;doc.fire("visibilitychange");assert.equal(ambience.paused,true);assert.equal(nodes[3].paused,true);
 doc.hidden=false;engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});assert.equal(ambience.paused,true);assert.equal(await engine.resume(),true);
 engine.setEnabled(false);assert.ok(nodes.every(node=>node.paused));
 engine.dispose();assert.ok(nodes.every(node=>node.src===""&&node.loadCalls===1));assert.equal(doc.listeners.get("visibilitychange")?.size,0);assert.equal(win.listeners.get("blur")?.size,0);
});

test("a gesture can prime audio before pointer lock without duplicate pending plays",async()=>{
 const nodes:FakeAudio[]=[];const engine=createStreetAudio({createAudio:source=>{const audio=new FakeAudio(source);nodes.push(audio);return audio as unknown as HTMLAudioElement;}});
 assert.equal(await engine.start(),true);assert.ok(nodes.every(node=>node.playCalls===1&&node.paused&&!node.muted));
 engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});
 assert.equal(nodes[0].playCalls,2);assert.equal(nodes[1].playCalls,1);assert.equal(nodes[2].playCalls,1);
 engine.dispose();
});

test("construction never autoplays and frame updates share an in-flight play request",async()=>{
 const nodes:DelayedAudio[]=[];const engine=createStreetAudio({createAudio:source=>{const audio=new DelayedAudio(source);nodes.push(audio);return audio as unknown as HTMLAudioElement;}});
 assert.ok(nodes.every(node=>node.playCalls===0));
 engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});
 const starting=engine.start();engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});engine.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:.016});
 assert.equal(nodes[0].playCalls,1);nodes[0].finish();assert.equal(await starting,true);engine.dispose();
});
