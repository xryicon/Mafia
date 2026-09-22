# First-person street audio

The street soundscape uses short, self-hosted recorded sounds. Playback never contacts the source websites.

## Recordings and licenses

- `public/audio/streets/harbor-ambience.mp3` is the low-bandwidth MP3 preview of **“Harbor Ambience 1”** by clif_creates. It was recorded at Marina del Rey with boats, water and rigging at the dock and released under **CC0 1.0**. Source and license declaration: https://freesound.org/people/clif_creates/sounds/254125/  Served source: https://cdn.freesound.org/previews/254/254125_3530854-lq.mp3
- `public/audio/streets/concrete-footsteps.mp3` is the high-quality MP3 preview of **“concrete footsteps”** by seth-m. The recordist describes it as a seamless concrete-sidewalk walking loop recorded with a Roland Edirol R-09HR and released it under **CC0 1.0**. Source and license declaration: https://freesound.org/people/seth-m/sounds/271039/  Served source: https://cdn.freesound.org/previews/271/271039_3366749-hq.mp3
- `public/audio/streets/distant-police-siren.mp3` is Wikimedia Commons’ MP3 transcode of **“American police siren i”** by lezer, a natural recording made in Washington, DC. The author released it into the **public domain** through PDSounds. Source, provenance and public-domain declaration: https://commons.wikimedia.org/wiki/File:American_police_siren_i.ogg  Served transcode: https://upload.wikimedia.org/wikipedia/commons/transcoded/a/ae/American_police_siren_i.ogg/American_police_siren_i.ogg.mp3
- Confirmed return fire may reuse `public/audio/range/colt-1911-shot.mp3`. Its CC0 source and processing details are already recorded in `public/audio/range/CREDITS.md`.

Licenses and descriptions were checked on 2026-09-22. Attribution for the CC0 and public-domain recordings is retained as a courtesy.

## Integration API

`createStreetAudio()` creates four isolated channels: looping harbor ambience, looping footsteps, looping distant siren, and disposable confirmed gunshots. It does not store settings. The caller owns saved mute and volume preferences.

Call `update()` every rendered movement frame. `moving` must mean that the displayed street position changed during that frame, rather than that a movement key is merely held. Pass the nearest active pursuit patrol’s distance in district blocks; set `pursuit` false outside a pursuit. The engine clamps the frame delta and applies subdued channel levels.

```ts
const audio=createStreetAudio();
audio.setEnabled(savedEnabled);
audio.setVolume(savedVolume); // 0..1

// Pointer/touch lock is a user gesture, so it can unlock browser audio.
audio.update({moving:false,sprinting:false,pursuit:false,locked:true,deltaSeconds:0});
await audio.start();

// Per frame, after the next displayed position has been calculated:
audio.update({
  moving:Math.hypot(next[0]-previous[0],next[1]-previous[1])>1e-5,
  sprinting:input.sprint,
  pursuit:!!pursuit,
  policeDistance:nearestPatrolDistance,
  locked,
  deltaSeconds:dt,
});

// Only after the server confirms a successful return-fire action:
await audio.playConfirmedGunshot();

audio.pause();   // unlock, blur, hidden page, overview or failure
await audio.resume(); // next user gesture
audio.dispose(); // component teardown
```

The engine also listens for page visibility loss and window blur. `dispose()` removes both listeners, stops every loop and one-shot, clears media sources, and releases its tracked resources.
