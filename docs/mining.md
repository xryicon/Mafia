# Mines & Quarries

The dashboard's seven named areas now open dedicated district pages with one click or Enter/Space. The city directory uses the same map as the dashboard. Existing Waterfront properties and Telegram Office remain intact. The other five districts use the existing registry, local market, activity and territory tabs, ready for Owner-authored plots and businesses.

## Player flow

Open Mines & Quarries and explore the site map, resource filters and illustrated deposit cards. Pickaxes cannot be purchased; the equipment panel explains that finding equipment is coming in a future update. Players with existing usable pickaxes can select a public site and start a timed shift. Return to collect its resources into market inventory. One active shift is allowed per player; cancelling returns reserved resources to the deposit but does not restore pickaxe wear. Raw resources can be listed or auctioned in the existing player market. They are excluded from generic factory purchases.

Mine owners can gather manually at their own private sites, collect elapsed production, and auction their seasonal extraction rights. Public access remains governed by the city's site rules. Auctions pause extraction, reserve the complete bid plus buyer tax, refund outbid players, and transfer the property with remaining reserves. City auction proceeds are a cash sink; they never pay the administering Owner personally.

## Owner flow

Owner → Mines & Quarries selects each of ten seeded sites. Open/close/reserve a site; choose public/private access; set yield, duration, wear, reserves, base value and map positions. Every change requires an audit reason. Open city claims can be auctioned here; player-owned mines can only be resold by their owner. Active shifts and auctions protect advertised terms from edits.

Global pickaxe condition, respect, offline production cap and auction duration limits are database settings in Economy & production. Raw resource net-worth valuations are editable in the season controls. Site defaults carry forward to new seasons; titles, equipment, inventories and remaining deposits are seasonal. Opening defaults do not create recurring auctions.

## Authority and lifecycle

All mutable mining tables are RPC-only with RLS enabled and direct browser privileges revoked. Public invoker functions call authenticated, permission-checked private functions. No service key is used in the browser. Owner-only mines.manage is separate from Moderator permissions.

A shared season lock followed by the existing district transaction lock serializes bids, mining reservations, Owner edits and title transfers. UUID request references make interrupted successful actions safe to retry. Balance changes pass through the existing wallet/ledger trigger. Immutable extraction and deposit ledgers record resource movement. Database checks prevent negative reserves and inventory overflow. Rejected transactions roll back their complete economic changes.

Pickaxe shifts reserve resources and snapshot rewards when started. Auctions wait for those shifts to finish. Production starts from acquisition and is capped by editable offline cycles. Locked seasons pause shifts, production and auction clocks. Final-season snapshots cancel/refund unfinished mine auctions and release unclaimed shift reservations; historical records remain intact.

On installations with pg_cron, blackwater-mine-auctions settles elapsed auctions every minute. Opening the district also settles elapsed auctions, and the interface provides settlement after expiry. There is no automatic bidding or resource sale.

## Validation and release

GitHub CI runs TypeScript/build, existing unit/browser/economy regressions, mining SQL authorization and conservation checks, and concurrent starts/claims. Browser coverage includes seven dashboard destinations, public extraction and market inventory, Owner opening and auctions, safe retry, mobile drawers, and responsive overflow checks. No local app server is used.

The initial three mining migrations shipped in PR #17. The subsequent mining_found_equipment migration removes the purchase path, including stale browser requests, while retaining existing equipment and financial records. Check that the district catalog has seven districts, the current season has ten mine sites, the Telegram Office remains singular, and existing cash/ledger totals are preserved. Cloudflare's GitHub build deploys the frontend. The deployment probe verifies protected routes and the six mining scene WebP files and all fifteen new resource WebP files.

## Original artwork

Generated using the built-in image generation tool, with no external stock imagery. Prompts below produced a text-free map and two portrait assets; code renders interactive labels and data. Assets are optimized for delivery in public/art/mining: map.webp, map-small.webp, mine.webp, mine-small.webp, quarry.webp, quarry-small.webp. The supplied screenshot inspired the mining layout; the artwork and UI use Blackwater's established palette and HUD.

### map

Use case: stylized-concept. Asset for Blackwater Mafia, a 1920s noir browser strategy game. Match the established game's richly detailed painterly cinematic realism, near-black blue charcoal and iron palette, muted copper-gold highlights, warm amber lamps, deep atmospheric shadows, restrained contrast, elegant premium crime-economy world. No text, labels, numbers, lettering, logos, UI panels, markers, borders, characters, or watermarks. This is a production background illustration, all interface will be drawn separately. Wide landscape composition, around 2:1. An elevated three-quarter city-planning view of a large rugged mining valley near Blackwater harbor at blue hour. Connected winding haul roads, railway tracks and a rail loading terminal at the bottom left, ten distinct small industrial mine/stone-quarry locations spread evenly through the rocky landscape, iron pit high left, terraced stone quarry upper center, copper excavation upper right, limestone quarry right center, coal mine center with headframe and warm entry tunnel, riverbed and unopened rocky claims lower half. Mining valley fills the composition edge to edge, mountains around it and a narrow river through the center. Keep separation between locations so clickable markers can be overlaid. Distant Blackwater industrial skyline in mist. Heavy dark mineral rock, fine terraced detail, steam, timber and steel headframes, glowing windows.

### mine

Use case: stylized-concept. Asset for Blackwater Mafia, a 1920s noir browser strategy game. Match the established game's richly detailed painterly cinematic realism, near-black blue charcoal and iron palette, muted copper-gold highlights, warm amber lamps, deep atmospheric shadows, restrained contrast, elegant premium crime-economy world. No text, labels, numbers, lettering, logos, UI panels, markers, borders, characters, or watermarks. This is a production background illustration, all interface will be drawn separately. Portrait 3:4 composition. A dramatic iron mine entrance in a rugged valley at night, timber shoring and an aged steel headframe, narrow-gauge tracks with ore carts leading into a warm glowing tunnel, a low brick sorting house, mineral stone, charcoal smoke and amber work lamps. No people. Clear industrial landmark, detailed materials, same distant noir harbor atmosphere as the game.

### quarry

Use case: stylized-concept. Asset for Blackwater Mafia, a 1920s noir browser strategy game. Match the established game's richly detailed painterly cinematic realism, near-black blue charcoal and iron palette, muted copper-gold highlights, warm amber lamps, deep atmospheric shadows, restrained contrast, elegant premium crime-economy world. No text, labels, numbers, lettering, logos, UI panels, markers, borders, characters, or watermarks. This is a production background illustration, all interface will be drawn separately. Portrait 3:4 composition. A dramatic terraced limestone and stone quarry in a rugged Blackwater valley at night, pale gray cut rock steps descending into a deep extraction pit, small old-fashioned cranes, winding haul road and a rail wagon, industrial sheds and subtle amber work lamps. No people. Strong layered composition and detailed mineral stone textures, same noir harbor atmosphere as the game.


## Resource illustrations

Iron ore, copper ore, coal, stone and limestone use original noir illustrations throughout mines and the player market. [Artwork files and generation prompts](resource-artwork.md).
