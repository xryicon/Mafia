# Bin diving
Players enter from Dashboard → Bin Diving, a district header, or the mining equipment panel.

- The live, unarchived district catalog supplies every option; new districts appear on refresh (and the 20-second live poll). City and seasonal lockdowns prevent searches.
- Each free dive awards one server-selected outcome. Defaults: cash 35%, pickaxe 8%, homemade pistol blueprint 3%, homemade bullet blueprint 4%, nothing 50%.
- Cash finds default to $25–$150. A shared two-minute player cooldown applies across the city. Owner → Bin diving & loot controls all chances, cash range, cooldown and the enabled switch. Existing cooldowns are not retroactively shortened.
- Pickaxes enter a spare equipment stash. Equipping consumes one spare and uses the existing mining durability setting. Replacing a worn tool discards remaining condition, and is blocked during an active mining shift or at full condition.
- Blueprints are fictional inventory collectibles for future crafting. This feature adds no crafting recipes, trade listings or equipment purchases.
- Rules and inventory changes are audited. Cash awards use the existing wallet/ledger transaction. Immutable dive receipts and idempotency records prevent repeat awards after network retries.
- Stash, tools, cooldown and history shown to players belong to the current season. Prior receipts and inventory remain stored for audit; no reset deletes them.
- Authenticated RPC-only reads show the caller's own inventory and history. Players and moderators cannot directly change rules, stock, rolls or cash.

## Release validation
GitHub Actions runs the production build, TypeScript checks, browser flows at desktop/mobile sizes, the full existing regression suite, PostgreSQL ownership/accounting tests, and parallel request tests. No app or database is run locally.
Apply only the new bin_diving migration after these checks pass, then merge the prepared release to trigger Cloudflare deployment.

## Artwork
Mode: built-in image generation. Asset: public/art/bin-diving.png.
Prompt: Ultra-wide original cinematic background for Blackwater Mafia, a deserted 1920s dockside alley at night with old metal dustbins, wooden crates, wet cobblestones, warm amber wall lantern, distant harbor cranes and muted gold city windows. Deep blue-black charcoal and iron palette, copper accents, darker left half for HTML heading. No people, weapons, text, logos or interface.
The generated image was inspected for palette and composition. Loot cards use the existing SVG icon system; blueprint cards contain collectible markings, not technical diagrams.

