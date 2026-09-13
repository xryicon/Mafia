// Original procedural effects: no external recordings, downloads or audio tracking.
export type RangeSound="shot"|"reload"|"ambient";
export function rangeSound(kind:RangeSound,rate:number){
 const seconds=kind==="shot"?.85:kind==="reload"?1.8:8,out=new Float32Array(Math.ceil(rate*seconds));let seed=kind==="shot"?17:kind==="reload"?59:113,brown=0;
 const reflections=[[0,1],[.07,.3],[.15,.16],[.29,.08]],mechanics=[[.035,.035,1600,.38],[.24,.11,600,.18],[.77,.15,420,.1],[1.12,.055,1800,.43],[1.46,.13,900,.32]];
 const noise=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/2147483648-1;};
 for(let i=0;i<out.length;i++){
  const t=i/rate,n=noise();brown=(brown+n*.035)*.98;let v=0;
  if(kind==="shot"){
   // Sharp initial report, low muzzle thump and damped warehouse reflections.
   for(const [delay,gain]of reflections){const u=t-delay;if(u>=0)v+=gain*(n*Math.exp(-u*52)*.58+Math.sin(2*Math.PI*(105*u-32*u*u))*Math.exp(-u*23)*.32+brown*Math.exp(-u*7)*.5);}
  }else if(kind==="reload"){
   // Release, magazine handling, seating click and slide return.
   for(const [at,length,pitch,level]of mechanics){const u=t-at;if(u>=0&&u<length)v+=level*(n*.65+Math.sin(u*pitch*2*Math.PI)*.35)*Math.exp(-u/length*5)*Math.min(1,u*1800);}
  }else{
   // Quiet ventilation and resonant room air, loop endpoints cross-faded.
   v=(brown*.75+Math.sin(t*2*Math.PI*48)*.009+Math.sin(t*2*Math.PI*73)*.006)*Math.min(1,t/.25,(seconds-t)/.25);
  }
  out[i]=Math.max(-.9,Math.min(.9,v))*Math.min(1,t*rate/5,(seconds-t)*80);
 }
 return out;
}
export class RangeAudio{
 private context:AudioContext|null=null;private master:GainNode|null=null;private ambient:AudioBufferSourceNode|null=null;private distant:ReturnType<typeof setTimeout>|null=null;
 private voices=new Set<AudioBufferSourceNode>();private buffers=new Map<RangeSound,AudioBuffer>();private closed=false;private enabled=true;private volume=.35;
 async unlock(enabled:boolean,volume:number){
  if(this.closed)return;this.enabled=enabled;this.volume=volume;
  if(!this.context){const Context=window.AudioContext||(window as unknown as {webkitAudioContext?:typeof AudioContext}).webkitAudioContext;if(!Context)throw new Error("Audio is unavailable in this browser.");this.context=new Context();this.master=this.context.createGain();this.master.gain.value=0;const compressor=this.context.createDynamicsCompressor();compressor.threshold.value=-12;compressor.knee.value=12;compressor.ratio.value=4;this.master.connect(compressor);compressor.connect(this.context.destination);}
  if(this.context.state==="suspended")await this.context.resume();if(this.closed)return;this.set(enabled,volume);
 }
 private buffer(kind:RangeSound){const cached=this.buffers.get(kind);if(cached)return cached;const c=this.context!,values=rangeSound(kind,c.sampleRate),b=c.createBuffer(1,values.length,c.sampleRate);b.copyToChannel(values,0);this.buffers.set(kind,b);return b;}
 private play(kind:RangeSound,gain=1,rate=1,offset=0,pan=0){
  const c=this.context;if(!c||c.state!=="running"||!this.enabled||this.closed||document.hidden)return;
  const source=c.createBufferSource(),level=c.createGain(),position=c.createStereoPanner();source.buffer=this.buffer(kind);source.playbackRate.value=rate;level.gain.value=gain;position.pan.value=pan;source.connect(level);level.connect(position);position.connect(this.master!);this.voices.add(source);
  source.onended=()=>{source.disconnect();level.disconnect();position.disconnect();this.voices.delete(source);};source.start(0,Math.min(offset,source.buffer.duration-.01));return source;
 }
 shot(){this.play("shot",.8);}
 reload(milliseconds:number,elapsed=0){this.play("reload",.7,1800/milliseconds,Math.max(0,elapsed)*1.8/milliseconds);}
 private background(){if(this.ambient||!this.context||!this.enabled||document.hidden)return;this.ambient=this.play("ambient",.7)??null;if(this.ambient)this.ambient.loop=true;this.scheduleDistant();}
 private scheduleDistant(){if(this.distant)clearTimeout(this.distant);this.distant=setTimeout(()=>{this.distant=null;if(this.closed||!this.enabled||document.hidden)return;this.play("shot",.09,.78,0,Math.random()*.9-.45);this.scheduleDistant();},3500+Math.random()*4500);}
 set(enabled:boolean,volume:number){this.enabled=enabled;this.volume=Math.max(0,Math.min(1,volume));const c=this.context;if(!c||!this.master)return;this.master.gain.setTargetAtTime(enabled&&!document.hidden?this.volume:0,c.currentTime,.035);if(enabled&&!document.hidden&&c.state==="running")this.background();else this.stopVoices();}
 private stopVoices(){if(this.distant)clearTimeout(this.distant);this.distant=null;for(const voice of this.voices){try{voice.stop();}catch{/* Already ended. */}}this.voices.clear();this.ambient=null;}
 visibility(){if(document.hidden){this.stopVoices();if(this.context?.state==="running")void this.context.suspend().catch(()=>{});}else if(this.context&&!this.closed){void this.context.resume().then(()=>this.set(this.enabled,this.volume)).catch(()=>{});}}
 close(){this.closed=true;this.stopVoices();if(this.context)void this.context.close().catch(()=>{});this.context=null;this.master=null;this.buffers.clear();}
}
