// Recorded sounds are bundled with the game; provenance and CC0 licenses are in public/audio/range/CREDITS.md.
export const RANGE_AUDIO = {
 shot: "/audio/range/colt-1911-shot.mp3",
 reload: "/audio/range/1911-reload.mp3",
 m4Shot: "/audio/range/m4-carbine-shot.mp3",
 m4Reload: "/audio/range/m4-carbine-reload.mp3",
 ambient: "/audio/range/indoor-range.mp3",
} as const;
type RangeSound = keyof typeof RANGE_AUDIO;
type RangeEffect = Exclude<RangeSound,"ambient">;

export class RangeAudio {
 private context: AudioContext | null = null;
 private master: GainNode | null = null;
 private ambient: AudioBufferSourceNode | null = null;
 private voices = new Set<AudioBufferSourceNode>();
 private buffers = new Map<RangeSound, AudioBuffer>();
 private loading = new Map<RangeSound, Promise<AudioBuffer>>();
 private abort = new AbortController();
 private closed = false;
 private enabled = true;
 private volume = .35;
 private generation = 0;

 constructor(private onError: () => void = () => {}) {}

 async unlock(enabled: boolean, volume: number, weaponGoodId?: string) {
  if (this.closed) return;
  this.enabled = enabled;
  this.volume = volume;
  if (!this.context) {
   const Context = window.AudioContext || (window as unknown as {webkitAudioContext?: typeof AudioContext}).webkitAudioContext;
   if (!Context) throw new Error("Audio is unavailable in this browser.");
   this.context = new Context();
   this.master = this.context.createGain();
   this.master.gain.value = 0;
   const compressor = this.context.createDynamicsCompressor();
   compressor.threshold.value = -12;
   compressor.knee.value = 12;
   compressor.ratio.value = 4;
   this.master.connect(compressor);
   compressor.connect(this.context.destination);
  }
  if (this.context.state === "suspended") await this.context.resume();
  if (this.closed) return;
  this.set(this.enabled, this.volume);
  // Small effect files load independently of the longer room recording.
  if (this.enabled) {
   const effects:RangeEffect[]=weaponGoodId==="m4-carbine"?["m4Shot","m4Reload"]:["shot","reload"];
   await Promise.all(effects.map(effect=>this.load(effect)));
  }
 }

 private load(kind: RangeSound): Promise<AudioBuffer> {
  const cached = this.buffers.get(kind);
  if (cached) return Promise.resolve(cached);
  const pending = this.loading.get(kind);
  if (pending) return pending;
  const context = this.context!;
  const task = (async () => {
   const response = await fetch(RANGE_AUDIO[kind], {
    signal: AbortSignal.any([this.abort.signal, AbortSignal.timeout(15000)]),
    credentials: "same-origin",
   });
   if (!response.ok) throw new Error("Range recording unavailable.");
   const buffer = await context.decodeAudioData(await response.arrayBuffer());
   if (this.closed || this.context !== context) throw new Error("Range closed.");
   this.buffers.set(kind, buffer);
   return buffer;
  })();
  this.loading.set(kind, task);
  void task.finally(() => this.loading.delete(kind)).catch(() => {});
  return task;
 }

 private canPlay() {
  return !!this.context && this.context.state === "running" && this.enabled && this.volume > 0 && !this.closed && !document.hidden;
 }

 private play(buffer: AudioBuffer, gain: number, rate = 1, offset = 0, loop = false) {
  if (!this.canPlay() || offset >= buffer.duration) return null;
  const context = this.context!, source = context.createBufferSource(), level = context.createGain();
  source.buffer = buffer;
  source.playbackRate.value = rate;
  source.loop = loop;
  // The real room recording stays behind the player's close pistol and mechanical sounds.
  level.gain.value = loop ? 0 : gain;
  if (loop) level.gain.setTargetAtTime(gain, context.currentTime, .2);
  source.connect(level);
  level.connect(this.master!);
  this.voices.add(source);
  source.onended = () => {
   source.disconnect();
   level.disconnect();
   this.voices.delete(source);
   if (this.ambient === source) this.ambient = null;
  };
  source.start(0, Math.max(0, offset));
  return source;
 }

 private async effect(kind: RangeEffect, milliseconds?: number, elapsed = 0) {
  if (!this.canPlay()) return;
  const generation = this.generation, started = performance.now();
  const buffer = await this.load(kind);
  if (generation !== this.generation || !this.canPlay()) return;
  const waited = performance.now() - started;
  // Never replay a stale shot after a slow download, mute, tab switch or navigation.
  if (kind === "shot" || kind === "m4Shot") {
   if (waited < 350) this.play(buffer, .8);
  } else if (milliseconds && milliseconds > 0) {
   this.play(buffer, .8, buffer.duration * 1000 / milliseconds, (elapsed + waited) * buffer.duration / milliseconds);
  }
 }

 shot(weaponGoodId?: string) { return this.effect(weaponGoodId==="m4-carbine"?"m4Shot":"shot"); }
 reload(milliseconds: number, elapsed = 0, weaponGoodId?: string) { return this.effect(weaponGoodId==="m4-carbine"?"m4Reload":"reload", milliseconds, elapsed); }

 private background() {
  if (this.ambient || !this.canPlay()) return;
  void this.load("ambient").then(buffer => {
   if (!this.ambient && this.canPlay()) this.ambient = this.play(buffer, .18, 1, 0, true);
  }).catch(() => { if (!this.closed) this.onError(); });
 }

 set(enabled: boolean, volume: number) {
  this.enabled = enabled;
  this.volume = Math.max(0, Math.min(1, volume));
  const context = this.context;
  if (!context || !this.master) return;
  this.master.gain.setTargetAtTime(enabled && !document.hidden ? this.volume : 0, context.currentTime, .035);
  if (this.canPlay()) this.background();
  else this.stopVoices();
 }

 private stopVoices() {
  this.generation++;
  for (const voice of this.voices) { try { voice.stop(); } catch { /* Already ended. */ } }
  this.voices.clear();
  this.ambient = null;
 }

 visibility() {
  if (document.hidden) {
   this.stopVoices();
   if (this.context?.state === "running") void this.context.suspend().catch(() => {});
  } else if (this.context && !this.closed) {
   void this.context.resume().then(() => this.set(this.enabled, this.volume)).catch(() => {});
  }
 }

 close() {
  this.closed = true;
  this.abort.abort();
  this.stopVoices();
  if (this.context) void this.context.close().catch(() => {});
  this.context = null;
  this.master = null;
  this.buffers.clear();
 }
}
