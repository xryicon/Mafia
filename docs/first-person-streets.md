# First-person streets

Enter an open district on Scavenging and choose **First-person streets**. Desktop uses WASD, mouse look, Shift to run, E to interact and Escape to release the cursor. Touch devices use a left movement pad and right drag area. The toolbar switches to a 3D aerial overview or returns to the existing interactive map. WebGL2 is required only for street view; unsupported devices retain the map.

The scene is a shared street-layout framework for every open district. Street names, targets, patrols, available cars, equipment, health and economic results come from existing district state. Buildings and vehicles are presentation geometry, not new purchasable property. The same collision width shapes the visible city and server movement. Existing loot, garage selection, immediate vehicle sale, weapon costs and prison records remain authoritative.

## Movement authority

`street_motion` accepts a controller UUID, monotonically increasing sequence and a normalized world direction; it does not accept a destination, speed or duration. Each accepted input leases at most the configured duration of movement. The next input begins at the interpolated server position, so flooding requests cannot increase speed. Old sequences do not restart a lease and stale controllers cannot steer another tab. The client predicts motion, reconciles server replies and stops prediction after a lost connection. Server leases expire independently of the browser.

Owner Economy settings include walking speed, sprint multiplier, road width, input lease/rate and interaction radius. Search/loot costs, timers and proximity remain in the existing transaction handlers. Changing to aerial travel invalidates the street controller. A new controller must explicitly reconnect.

## Police

By default, a detected search is interrupted without loot and starts an on-foot pursuit. The first detection time anchors its warning period and cordon deadline, including missed/offline contact. The player can reach the district exit, use the existing armed confrontation action, or surrender. Ordinary walking causes no offence. The responding unit follows the player's current visible position, then searches the last observed position when buildings block its sight. Existing car thefts still start vehicle pursuits. Capture is swept over the whole elapsed movement interval; closing the page does not cancel custody.

Owner settings include `scavenging_search_chase_enabled` (0 retains immediate arrests), on-foot pursuer speed, island pursuer speed, capture distance and police vision. Existing chase duration, grace, sentence and combat settings are reused. Historic records remain retained. The map remains an accessible alternative to pointer-lock controls.

## Artwork and rendering

Three.js is dynamically imported only on entering street view. Static architecture is instanced by material, rendering pauses when hidden, resolution is capped, and GPU resources are released on exit. Camera bob respects reduced motion.

`public/art/scavenging/materials/warehouse-brick.webp` was generated using the built-in image tool, then exported to WebP. Prompt:

> Create a production-ready seamless repeating texture for weathered 1930s dockside brick warehouse walls in a photorealistic browser 3D noir game called Blackwater Mafia. Square image 1024x1024. PERFECTLY FLAT ORTHOGRAPHIC FRONT VIEW, a single uniform material tile filling the entire frame edge to edge, no perspective whatsoever. Small horizontal old dark charcoal-brown soot-stained clay bricks, irregular aged mortar, nuanced surface chips, rain-darkened color variations, subtle moss traces, premium realistic detailed PBR albedo texture. Even diffuse neutral illumination, no directional shadows, no lit windows, no doors, no signs, no text, no logos, no objects, no border. Seamless continuous brick courses across left and right edges and matching top and bottom. Bright enough middle-dark material values to allow actual game lighting; avoid a near-black image. Slightly warm iron/brown brick palette with muted cool-gray mortar. It is a tiled wall material, not a picture of a whole building.

## Verification

GitHub runs unit collision/speed checks, PostgreSQL input authority/proximity/pursuit/custody checks, browser rendering and keyboard interaction tests, graphics fallback checks, and the full existing game regression suite. Legacy immediate-arrest tests explicitly retain their old configured mode; new tests enable and verify chase mode. Local app execution is not required.
