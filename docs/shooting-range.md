# Blackwater shooting range

Players enter `/shooting-range` from Dashboard quick actions, Inventory equipment or the player menu. The page uses the shared game HUD and an original Blackwater warehouse interior with moving SVG paper targets. Desktop pointer, mobile tap and keyboard aiming are supported. Only the equipped primary or secondary weapon can fire, and its compatible ammunition must be in the Ammo slot. The first supported loadout is the existing homemade pistol and homemade bullets.

Each accepted shot consumes exactly one equipped bullet and applies the configured condition loss, including misses and already-scored targets. A target scores once per round. Empty ammunition and broken weapons stop firing. Weapon condition stays attached to the individual item when returned to inventory or moved into property storage. There are no artificial reward items, cash grants or XP rewards. Personal session history and the season's best scores come from recorded shots.

## Server rules

`range_state`, `range_action` and `range_manage` use the existing active-account, season, Owner permission and private RPC patterns. No client writes to the underlying tables are allowed. Configurable weapon compatibility, condition, targets, timing and scoring live in PostgreSQL and have audited Owner controls. Sessions snapshot their settings and weapon rules; disabling the range or weapon stops firing immediately.

The server calculates deterministic moving target geometry. The browser supplies normalized aim coordinates and elapsed time, never an authoritative score or hit. Elapsed time is checked against server time with a bounded network allowance, strictly increasing shot timestamps, session duration and a server-clock fire interval. This prevents claimed hits/scores and stale/future shots; as with any browser aiming game it cannot establish whether a human or an aim-assistance script supplied valid coordinates. Practice awards no economy rewards.

Start, fire and finish requests have immutable idempotency receipts. An interrupted response can retry its exact reference safely and receives a fresh clock/state. Each shot locks the shared inventory coordinator, player, session and equipment records. Ammunition reductions use the existing inventory ledger; the final bullet retires its zero-quantity gear row without deleting history. Immutable shot records preserve ammo before/after, condition before/after, timing, coordinates and the calculated result. Session and shot evidence is retained across seasons; current records and leaderboards are season-scoped.

## Verification

GitHub Actions runs the full application checks and existing regression suites. Dedicated checks cover target geometry and bounds; real PostgreSQL ownership, score calculation, bullet/condition conservation, timing, replay, broken weapons, equipment changes, Owner permissions/audits and season isolation; simultaneous shots and duplicate retries; and browser loadouts, moving targets, misses, safe response retries, mobile layouts and Owner configuration. The deployment probe checks route protection and artwork delivery. No local application server or local test database is used.

## Original artwork

Asset: `public/art/shooting-range.png`. Generated through the built-in `image_gen` tool in generation mode, without a reference image supplied to the tool. User reference informed the overall interaction/layout; existing Blackwater item artwork and icons are reused.

Prompt:

> Use case: historical-scene. Asset type: panoramic background artwork for the interactive Blackwater Mafia browser-game shooting range. Create a cinematic, realistic noir underground firing range inside a 1920s dockside warehouse. Player viewpoint from behind a scuffed timber firing bench looking straight down a long deep brick-and-concrete hall, suspended copper industrial lamps, warm amber pools of light, dusty smoke shafts, dark iron overhead target rails, old battered partitions and crates at the far edges. Spacious clear central shooting lane with enough dark neutral background for moving paper targets to be added by game code. Blackwater's blue-black charcoal palette, restrained aged copper, warm muted gold, beautiful tactile premium crime-economy aesthetic, dramatic but legible and richly detailed. Wide landscape composition roughly 16:9. No people, no weapons, no ammunition, no targets, no crosshair, no letters, no logos, no interface or borders. This is the background ONLY; all targets and equipped weapon information will be real functional UI overlays.

## Magazines and sound

The homemade pistol has a 10-round magazine and a 1.8-second manual reload. Both values are editable per weapon under Owner → Shooting range and snapshotted per session. Press **R** or the **Reload** button. Tactical reloads preserve the remaining ammunition; low supplies fill only the available rounds. The displayed reserve is the equipped quantity minus loaded rounds. Reloading prepares ammunition but does not debit it: each accepted shot still consumes exactly one bullet from the equipped Ammo stack.

Magazine state persists by weapon across refreshes and range sessions. Removing a weapon or its ammunition unloads it and cancels pending reloads. Reload completion uses database time without holding a transaction open; shots are blocked during the reload and cannot claim an aim timestamp from before completion. Reload request receipts are immutable and idempotent. Existing active sessions adopt the magazine requirement without changing items or condition.

Original procedural sounds include a pistol report with warehouse reflections, magazine handling/slide clicks and a quiet ventilation/distant-fire ambience. They are generated in the browser with Web Audio; no external audio files, requests or permissions are needed. Audio unlocks on interaction, has saved mute/volume controls, stops on hidden tabs, and is closed when leaving the page. Gunshot and reload effects follow accepted server receipts, so retries cannot play duplicate shots. The range still works if audio is unavailable. Browser implementation follows the [Web Audio user-control and autoplay guidance](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices).

Additional PostgreSQL tests cover ten-round exhaustion, timed and partial reloads, session persistence, concurrent requests, equipment changes and bullet conservation. Browser tests verify the keyboard/button, mobile magazine layout, actual Web Audio source playback, mute persistence, lifecycle cleanup and interrupted reload replies. Waveform tests check finite, bounded samples and fades.
