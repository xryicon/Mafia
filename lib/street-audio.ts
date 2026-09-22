export const STREET_AUDIO={
 ambience:"/audio/streets/harbor-ambience.mp3",
 footsteps:"/audio/streets/concrete-footsteps.mp3",
 siren:"/audio/streets/distant-police-siren.mp3",
 gunshot:"/audio/range/colt-1911-shot.mp3",
} as const;

export type StreetAudioFrame={
 moving:boolean;
 sprinting:boolean;
 pursuit:boolean;
 policeDistance?:number|null;
 locked:boolean;
 deltaSeconds:number;
};

type AudioFactory=(source:string)=>HTMLAudioElement;
type DocumentEvents=Pick<Document,"hidden"|"addEventListener"|"removeEventListener">;
type WindowEvents=Pick<Window,"addEventListener"|"removeEventListener">;
export type StreetAudioOptions={
 createAudio?:AudioFactory;
 document?:DocumentEvents;
 window?:WindowEvents;
};
export type StreetAudioEngine={
 start:()=>Promise<boolean>;
 resume:()=>Promise<boolean>;
 pause:()=>void;
 setEnabled:(enabled:boolean)=>void;
 setVolume:(volume:number)=>void;
 update:(frame:StreetAudioFrame)=>void;
 playConfirmedGunshot:()=>Promise<boolean>;
 dispose:()=>void;
};

const clamp=(value:number,minimum=0,maximum=1)=>Math.max(minimum,Math.min(maximum,value));
export function streetSirenLevel(pursuit:boolean,distance?:number|null){
 if(!pursuit)return 0;
 if(distance==null||!Number.isFinite(distance))return .1;
 return .38*clamp(1-Math.max(0,distance)/5,.12,1);
}

export function createStreetAudio(options:StreetAudioOptions={}):StreetAudioEngine{
 const create=options.createAudio??((source:string)=>new Audio(source));
 const doc=options.document??(typeof document!=="undefined"?document:undefined);
 const win=options.window??(typeof window!=="undefined"?window:undefined);
 const ambience=create(STREET_AUDIO.ambience),footsteps=create(STREET_AUDIO.footsteps),siren=create(STREET_AUDIO.siren),loops=[ambience,footsteps,siren];
 let enabled=true,started=false,suspended=false,disposed=false,volume=1;
 let frame:StreetAudioFrame={moving:false,sprinting:false,pursuit:false,policeDistance:null,locked:false,deltaSeconds:0};
 const shots=new Set<HTMLAudioElement>(),pending=new Map<HTMLAudioElement,Promise<boolean>>(),shotReleases=new Map<HTMLAudioElement,()=>void>();
 for(const audio of loops){audio.preload="auto";audio.loop=true;audio.volume=0;}
 footsteps.playbackRate=.92;

 const canPlay=()=>!disposed&&started&&enabled&&!suspended&&volume>0&&frame.locked&&!doc?.hidden;
 const play=(audio:HTMLAudioElement)=>{if(!audio.paused)return Promise.resolve(true);const existing=pending.get(audio);if(existing)return existing;const request=(async()=>{try{await audio.play();return true;}catch{if(loops.includes(audio))suspended=true;return false;}finally{pending.delete(audio);}})();pending.set(audio,request);return request;};
 const stop=(audio:HTMLAudioElement,rewind=false)=>{audio.pause();if(rewind)try{audio.currentTime=0;}catch{}};
 const stopLoops=()=>{stop(ambience);stop(footsteps,true);stop(siren,true);};
 const applyLevels=(immediate=false)=>{
  const stepTarget=frame.moving?(frame.sprinting?.27:.19):0,sirenTarget=streetSirenLevel(frame.pursuit,frame.policeDistance),seconds=clamp(frame.deltaSeconds,0,.25),blend=immediate?1:1-Math.exp(-seconds*5);
  ambience.volume=clamp(volume*.2);
  footsteps.volume=clamp(footsteps.volume+(volume*stepTarget-footsteps.volume)*blend);
  siren.volume=clamp(siren.volume+(volume*sirenTarget-siren.volume)*blend);
  for(const shot of shots)shot.volume=clamp(volume*.42);
  footsteps.playbackRate=frame.sprinting?1.12:.92;
 };
 const sync=()=>{
  applyLevels();
  if(!canPlay()){stopLoops();return;}
  void play(ambience);
  if(frame.moving)void play(footsteps);else stop(footsteps,true);
  if(frame.pursuit)void play(siren);else stop(siren,true);
 };
 const activate=async()=>{
   if(disposed)return false;started=true;suspended=false;applyLevels(true);
  if(!enabled||!volume||doc?.hidden){stopLoops();return true;}
  if(!frame.locked){
   const primed=await Promise.all(loops.map(async audio=>{const muted=audio.muted;audio.muted=true;const played=await play(audio);stop(audio,true);audio.muted=muted;return played;}));applyLevels(true);if(frame.locked)sync();return primed.every(Boolean);
  }
   const wanted=[ambience,...(frame.moving?[footsteps]:[]),...(frame.pursuit?[siren]:[])];
   return (await Promise.all(wanted.map(play))).every(Boolean);
  };
 const pause=()=>{suspended=true;stopLoops();for(const shot of shots)stop(shot);};
 const visibility=()=>{if(doc?.hidden)pause();};
 const blur=()=>pause();
 doc?.addEventListener("visibilitychange",visibility);
 win?.addEventListener("blur",blur);

 return {
  start:activate,
  resume:activate,
  pause,
  setEnabled(value){enabled=value;if(!enabled){stopLoops();for(const shot of shots)stop(shot);}else{suspended=false;sync();}},
  setVolume(value){volume=clamp(Number.isFinite(value)?value:0);applyLevels(true);if(!volume){stopLoops();for(const shot of shots)stop(shot);}else sync();},
  update(next){frame={...next,deltaSeconds:clamp(next.deltaSeconds,0,.25)};if(!frame.locked){stopLoops();return;}sync();},
  async playConfirmedGunshot(){
   if(!canPlay())return false;
   const shot=create(STREET_AUDIO.gunshot);shots.add(shot);shot.preload="auto";shot.volume=clamp(volume*.42);
   const release=()=>{shots.delete(shot);shotReleases.delete(shot);shot.removeEventListener("ended",release);stop(shot,true);shot.removeAttribute("src");shot.load();};shotReleases.set(shot,release);shot.addEventListener("ended",release,{once:true});
   const played=await play(shot);if(!played)release();return played;
  },
  dispose(){
   if(disposed)return;disposed=true;doc?.removeEventListener("visibilitychange",visibility);win?.removeEventListener("blur",blur);stopLoops();
   for(const release of [...shotReleases.values()])release();for(const audio of loops){stop(audio,true);audio.removeAttribute("src");audio.load();}pending.clear();
  },
 };
}
