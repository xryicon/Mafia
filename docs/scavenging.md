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
