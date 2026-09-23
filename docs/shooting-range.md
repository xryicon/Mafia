# Blackwater shooting range

Players enter `/shooting-range` from Dashboard quick actions, Inventory equipment or the player menu. The page uses the shared game HUD and an original Blackwater warehouse interior with moving SVG paper targets. Desktop pointer, mobile tap and keyboard aiming are supported. Only the equipped primary or secondary weapon can fire, and its compatible ammunition must be in the Ammo slot. The first supported loadout is the existing homemade pistol and homemade bullets.

Each accepted shot consumes exactly one equipped bullet and applies the configured condition loss, including misses and already-scored targets. A target scores once per round. Empty ammunition and broken weapons stop firing. Weapon condition stays attached to the individual item when returned to inventory or moved into property storage. Completion XP uses the existing seasonal XP/respect balance; no items or cash are awarded. Personal session history and the season's best scores come from recorded shots.

## Server rules

`range_state`, `range_action` and `range_manage` use the existing active-account, season, Owner permission and private RPC patterns. No client writes to the underlying tables are allowed. Configurable weapon compatibility, condition, targets, timing and scoring live in PostgreSQL and have audited Owner controls. Sessions snapshot their settings and weapon rules; disabling the range or weapon stops firing immediately.

The server calculates deterministic moving target geometry. The browser supplies normalized aim coordinates and elapsed time, never an authoritative score or hit. Elapsed time is checked against server time with a bounded network allowance, strictly increasing shot timestamps, session duration and a server-clock fire interval. This prevents claimed hits/scores and stale/future shots; as with any browser aiming game it cannot establish whether a human or an aim-assistance script supplied valid coordinates. Completion XP is bounded by server-snapshotted rules, participation and a shared cooldown.

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

The range uses a recorded Colt 1911 shot, recorded 1911 reload and a quiet 60-second indoor-range field recording, played through Web Audio. The CC0 assets ship with the game; provenance and processing details are in [audio credits](../public/audio/range/CREDITS.md). No third-party audio requests are made. The old synthesized ventilation drone and randomly generated distant shots are removed. Audio unlocks on interaction, has saved mute/volume controls, stops on hidden tabs, and is closed when leaving the page. Gunshot and reload effects follow accepted server receipts, so retries cannot play duplicate shots. The range still works if audio is unavailable. Browser implementation follows the [Web Audio user-control and autoplay guidance](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API/Best_practices).

Additional PostgreSQL tests cover ten-round exhaustion, timed and partial reloads, session persistence, concurrent requests, equipment changes and bullet conservation. Browser tests verify the keyboard/button, mobile magazine layout, actual Web Audio source playback, mute persistence, lifecycle cleanup and interrupted reload replies. Asset checks verify the bundled MP3s and source credits; browser checks decode and play the real stereo recordings, verify muted/delayed loads, and confirm missing audio does not block firing.

## Paper impacts

Accepted shots leave torn-paper bullet holes at their exact target-relative positions. Geometry uses the shot's server-recorded elapsed_ms, not response arrival time. Marks sit inside each moving target group and are clipped to its paper edges; repeat shots and non-scoring hits on paper leave holes without changing score rules. Shots outside the paper leave no paper damage. Refresh responses are deduplicated by shot id, and the next round or session clears the visual damage. The corrected last_shot response supplies the required timing and coordinates from the existing shot records.

### Live shot-response regression

The original SQL alias x collided with the numeric x column, so to_jsonb(x) returned a single coordinate as last_shot. The real PostgreSQL tests now check the complete returned shot object on accepted hits, misses, retries and refreshes, including its id, coordinates, timestamp and round. The corrective migration returns explicit display fields and preserves the existing private function permissions and all recorded gameplay.


## Difficulty, precision and recovery

Players choose Beginner or Advanced before starting. Beginner defaults to the existing target size/speed and **up to 50 score XP**. Advanced uses **65% target size**, **250% movement speed** and **up to 150 score XP**. The same geometry drives server hit tests, client movement and persistent bullet holes. Owner controls expose target size/speed, both rewards, required round participation and cooldown, with audited edits. Active sessions keep their original settings; legacy sessions retain their earlier scoring without retrospective rewards.

New sessions score each eligible target from 50 points at the edge to 100 at the exact centre, interpolated by normalized radial distance and rounded to whole points. Both endpoints are configurable; each target still scores once per round.

To earn completion XP, stay until the session ends and fire in the required number of distinct rounds (default: every round). Merely starting and waiting, or ending early, earns no XP. The server records each award once in an immutable private XP ledger, updates the existing player XP and season projection atomically, and adds a personal activity event. Replayed completion requests and concurrent refresh/finish calls cannot pay twice. Expiry on refresh also settles eligible sessions. Season locking settles completed sessions before rankings freeze and stops unfinished attempts; historical awards remain retained.

A shared **600-second cooldown** starts when the session finishes or is ended early. It survives reloads, equipment changes and difficulty changes, and resets with seasonal gameplay. The UI shows the server deadline and automatically re-enables entry when it expires. Database tests include the real scoring RPC, participation, early/idle sessions, reward ledger reconciliation, snapshots, season boundaries, concurrent starts/finishes and cooldown enforcement. Browser tests cover both difficulty choices, smaller targets, completion rewards and mobile recovery displays.


## Score XP and bullseye accuracy

For new sessions, XP is `floor(maximum XP × score / maximum possible score)`, capped at the snapshotted maximum. The maximum possible score is rounds × targets per round × bullseye points. Default Beginner and Advanced maxima remain 50 and 150 XP; a half-score session earns 25 or 75. Finishing the session and meeting the round-participation requirement remain necessary. Zero score grants no XP, and creates no reward ledger entry. Existing paid awards and active session reward snapshots remain unchanged.

Accuracy now measures physical precision: each accepted shot gets 100% at the nearest target's centre, decreasing linearly by normalized elliptical distance to 0% at its edge; misses are 0%. Repeated hits keep their physical accuracy but cannot score the same target twice. An immutable private precision row is stored with each shot in the same transaction. Historical precision is reconstructed from retained shot coordinates, aim timing and session geometry without modifying original shot evidence or awarded XP.

The live scoreboard and last-shot readout show server precision; session history and best accuracy use saved precision, not binary hit rate. Advanced average accuracy is the shot-weighted mean across recorded Advanced attempts in the current season, including misses and early exits. Sessions with no shots show no accuracy, and Beginner attempts are excluded. Both raw shots and saved precision survive season archiving.

The current-score XP preview comes from the server. Actual awards refresh the shared power/rank HUD through the existing game update event. Cloud tests exercise partial-score rewards, caps and rounding, zero-score expiry, radial and diagonal precision, retries, weighted averages, early exits, history and live HUD updates alongside the existing reload, sound, wear, bullet-hole and cooldown regressions.

## Indoor 3D range

The optional 3D view opens in a fixed first-person indoor firing booth, with lane partitions, overhead lights, target carriers and a backstop. It uses the existing Three.js dependency and custom procedural M4 and pistol models; it does not load the street scene or external model assets. The equipped weapon has an animated magazine and support hand, accepted-shot recoil, muzzle flash and pistol-slide movement. The M4 retains automatic fire; the pistol fires once per press. Mouse/touch aims and fires, arrow keys adjust aim, Space fires (hold for M4), and R reloads.

3D rays intersect one scoring plane and convert back to the existing 0–100 coordinates. Paper targets use the same snapshotted target motion and hit geometry as the database. The current server clock supplies shot elapsed time. Accuracy, points, repeated-target rules, ammo, condition, XP, ownership and rate limits remain in the existing range RPCs. No database migration is needed. An uncertain reply blocks firing until the same request is retried; visible recoil follows accepted shots. Reload animation derives from the stored start/deadline and cannot refill ammunition or restart the timer.

Classic targets remain available in the view selector and are the automatic fallback when WebGL is unavailable or lost. Both views use the same session and scoring. The renderer stops drawing while hidden/offscreen, caps pixel ratio, disposes GPU resources on exit and honors reduced motion. Automatic fire stops on release, blur, cancellation, hidden tabs or a view/session change. View preference is saved locally when storage is available.

Validation: projection/ray round trips across phone and desktop aspect ratios; server-deadline animation tests; real-WebGL browser tests for M4, pistol, accuracy, automatic fire, ammo/wear, reloads, view switching, uncertain replies and context loss; existing range regression coverage runs against Classic targets.

The original target range is the default again. Only Advanced is offered for new practice; existing sessions retain their stored rules. Classic feedback shows the accepted last shot’s precision and points, a target-round countdown bar, and the server reload deadline. A versioned view preference resets the former 3D default while allowing explicit future selection. Historical Beginner results remain intact.
