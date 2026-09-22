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


The companion `public/art/scavenging/materials/dockside-asphalt.webp` uses this built-in image-generation prompt:

> Create a square seamless repeating game environment ALBEDO MATERIAL texture, perfectly flat orthographic straight down, edge to edge only surface, no perspective, no scene. A weathered 1930s industrial dockside street in Blackwater Mafia: very fine dark blue-charcoal asphalt with subtle old stone aggregate, small worn cobble repairs, cracks and rain-damp uneven patches. Photorealistic microtexture at human scale. Muted iron-gray and charcoal with restrained brown dirt in cracks, subtle lighter middle-dark variation. Diffuse neutral even lighting for use under real 3D lights, NO baked reflections, NO puddle reflections, NO lamps, NO shadows, NO painted road markings, NO objects, NO text, NO borders. Tile seamless on all four edges. Enough visible detailed material variation to make a real 3D street feel tactile. 1024 by 1024 square.


## Graphics and responsiveness update

The dockside scene now uses varied adjoining façades, warehouse signs, pitched roofs, shared bevelled period-car geometry, wet pavement and a detailed panoramic harbor. Geometry is instanced by both material and geometry, including lamp posts and vehicles. GPU resources are released when targets retire or the street view closes.

Graphics defaults to Auto, which bounds rendered pixels and adapts to sustained frame times. High and Performance can be selected and persist on the device. Decorative rain respects reduced motion; Performance reduces light effects. Graphics preferences never change movement speed, patrol rules or rewards.

New generated artwork: `public/art/scavenging/materials/blackwater-harbor-panorama.webp` (202 KB). Built-in image generation; the original is preserved at `C:/Users/dylut/.codex/generated_images/01a08d05-4e6d-7f32-8946-ab91e935d80a/exec-8d2fd88b-0ed1-450a-ad22-43c7ef6d64cc.png`.

Prompt: Production game asset for Blackwater Mafia first-person browser streets: a cinematic seamless horizontal 360-degree 2:1 equirectangular panorama of a dark 1930s industrial waterfront at human eye height. Distant art deco skyscrapers, domed and peaked warehouses, cranes, smokestacks and cargo ships, warm amber windows reflected in blue-black water, layered moonlit charcoal clouds. Refined realistic crime-film atmosphere; desaturated slate and iron blue, copper highlights and clear architectural detail. Level horizon at vertical center, matching left/right edges, lower quarter dark water only. No nearby foreground objects, text, labels, logos, people, modern cars or interface.


The street HUD includes a six-slot equipment strip using the authenticated existing inventory read. Slots inspect the current loadout and link to Inventory; they do not create a second equipment authority. Camera-space gloves and sleeves show unarmed hands or the server-selected equipped weapon. Movement, sound and hands stop on pause, exit or hidden tabs. Actual movement drives footfalls, so pushing against a building does not keep the walking loop running. Sound and volume preferences are device-local; audio starts only after player interaction. Recorded asset sources and licenses are documented in `audio-streets.md`.

Connection handling serializes inputs, discards intermediate queued directions, predicts within the accepted movement lease, reconciles without smoothing through buildings, and sends a final stop when leaving. Browser regressions cover delayed replies, stopping, touch controls, equipment inspection, fullscreen and saved preferences.
