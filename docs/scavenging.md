# District scavenging

Scavenging replaces the Bin Diving player page at its existing `/bin-diving` URL, preserving district bookmarks and inventory links. Select a live district, enter its street map, and click a crossing, bin or parked car to walk there. Keyboard users can focus a location and press Enter or Space. Zoom and scroll support small screens.

The server supplies a persistent, private set of seven bins and three cars per player, district and season. Street labels use the district's named streets; districts without named streets receive contextual fallback labels. New unarchived districts appear through the existing live catalog. Streets currently use a generic connected 5-by-3 grid; this is an exploration layer, not a cadastral property map.

Movement supports any position along a road, with server-validated routes and travel time. Players can change direction mid-walk without teleporting. Search actions require arrival at that exact location, an open district and season, and no active search or shared loot cooldown. A searched location remains depleted through navigation and refresh. Sessions and sites are season-scoped; history is retained.

Police patrols follow shared, timed district routes. Walking or standing near police is safe. During an active bin search or car lockpick, entering a patrol's marked detection area results in arrest and a Blackwater Island sentence. The server sweeps the entire active search interval (up to completion), so late collection, cancelling after contact, refreshing, or reconnecting cannot bypass detection. Arrest cancels the attempt without loot or XP; consumed lockpicks and site depletion remain. Each arrest has retained history and uses the existing audited prison system.

Owner → Economy controls `scavenging_patrol_enabled` (0/1), `scavenging_patrol_count`, `scavenging_patrol_seconds_per_block`, `scavenging_patrol_radius_percent` (percentage of one block), and `scavenging_patrol_sentence_minutes` (default 5). Patrol rules are snapshotted when a search starts; edits affect future searches. Existing searches at migration time retain their old risk rules. Cosmetic street-activity controls never hide gameplay police patrols. Apply `20260920220000_scavenging_police_patrols.sql` before deploying the police interface.

Cars consume one carried lockpick when the attempt starts. Completed successful attempts roll the existing Owner-configured loot table and award Lockpicking XP; a failed lock consumes the tool, awards nothing and starts the normal loot cooldown. Abandoning an attempt does not refund a lockpick or replenish its location. Car opening is a timed chance-based action, not the prison-break minigame.

Owner → Bin diving & loot controls the shared loot chances and city cooldown. Owner → Economy exposes `scavenging_walk_seconds`, `scavenging_search_seconds`, `scavenging_lock_seconds`, `scavenging_restock_seconds`, `scavenging_car_success_percent`, and `scavenging_lock_xp`. Car chance and XP are snapshotted when the attempt starts. Existing setting changes are permission-checked and audited.

All mutations use the existing economic transaction lock, active-player and season guards, and idempotency receipts. Cash uses the existing ledger; inventory capacity and XP use existing systems. The old public direct-dive action rejects calls, while private reward-engine regression tests continue to exercise the underlying loot logic. New PostgreSQL tests cover the public scavenging interface.

Apply `20260920140000_scavenging.sql` before deploying this interface. This migration does not delete or reset existing money, items, skill XP or history. GitHub CI supplies build, browser, database and regression validation; the app is not run locally.


## Street operations

Scavenging now has timed courier/supply opportunities and police sweeps, plus three configurable parked-vehicle models. Car lockpicking still searches for the established loot; **Steal vehicle** spends one lockpick and attempts an ignition bypass instead. A successful theft awards configured Lockpicking XP and starts a persistent pursuit. Walking normally remains safe.

A responding police unit follows the player's street destination. Both patrol and player movement are swept over the complete elapsed interval, including route corners. Reloading, leaving the page or polling less often cannot erase the pursuit. Reach the marked exit after the minimum escape time, fight back with compatible equipped ammunition, or abandon the car. The cordon deadline leads to prison and seizure. Combat consumes ammunition, wears the gun, applies return fire to armour then health, and can escape, continue or arrest an incapacitated player.

A successful getaway stores the vehicle in an accessible player-owned or leased garage with an empty vehicle bay. Without space, including a lease expiring mid-pursuit, it sells immediately through the cash ledger. Garage vehicles remain private to their player, can be sold from the garage or Scavenging, and retain their acquisition-time resale value. Former tenants' vehicles can still be recovered by sale and do not occupy a new tenant's bays. Vehicles currently provide storage and resale, not general-world driving. All vehicle and operation records retain their season; next-season queries start a fresh collection while history remains retained.

Blackwater Island has separate patrol count/speed/radius, pursuing-unit speed, sentence length and cash multiplier settings. Base item percentages remain controlled by the existing loot rules. Opportunity cash multipliers combine with the island cash multiplier. All new balance settings are under Owner → Economy (`scavenging_*`); vehicle availability and resale prices are in Owner → Bin diving & loot. Owner changes are audited and active operations retain their risk snapshots.

Two migrations introduce private vehicle/event/history state, guarded actions and a private garage collection RPC. No direct browser table access is granted. Tests cover early completion, proximity, tools, duplicate requests, ledger credits, vehicle ownership, equipment consumption, armour/health, custody, island rewards and swept collisions. Browser tests exercise events, responsive pursuit controls, no-garage sale, garage storage and uncertain-response retry.

### Artwork

`public/art/scavenging/street-operations.webp` was generated for this feature with ImageGen and optimized to WebP. Final art direction: cinematic landscape 1930s Blackwater backstreet at night, wet cobblestones, deep blue-black and charcoal, muted copper/gold streetlights, unbranded period sedan on the right, bins on the left, distant police patrol, dark readable space on the left; no text, logos or modern objects. The established overhead street artwork and navigable road coordinates remain aligned.
