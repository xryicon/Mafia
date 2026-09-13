# Property crafting

Open a garage or warehouse from Districts → Your properties & leases. Install its crafting station and choose **Open crafting menu**. The page uses the shared Blackwater HUD, existing waterfront artwork, illustrated stock cards and a responsive three-panel workspace.

Learn a recipe using one existing blueprint. Learning consumes the blueprint, is private to the player, and lasts for the current season. Spare blueprints can still be traded. Knowledge works at all of that player's installed tables. Starting another season starts with no learned recipes; previous-season learning and transaction history remain retained.

## Initial configurable recipes

These are fictional game recipes, expressed solely in existing inventory goods.

| Recipe | Blueprint | Materials | Output | Duration |
| --- | --- | --- | --- | --- |
| Homemade pistol | Existing homemade pistol blueprint | 4 iron ingots, 2 copper ingots | 1 secondary weapon | 150 seconds |
| Homemade bullets | Existing homemade bullet blueprint | 1 iron ingot, 1 copper ingot | 12 ammunition units | 60 seconds |

Owner → Crafting & blueprints edits materials, quantities, duration, output and availability with a required audit reason. Owner economy settings contain the per-table queue limit (initially 3) and maximum batches per job (20). Existing inventory controls edit item weight, compatible equipment slots and storage capacity. Initial crafted item weights are 2 kg per pistol and 30 g per ammunition unit; existing carried limits remain 20 slots and 100 kg. Existing season controls manage net-worth valuations. No items, blueprints, cash, buildings or stations are granted to players by the release.

## Materials, queues and storage

- Choose carried inventory, this property's storage, or both. Combined mode consumes property stock first.
- Jobs run sequentially per installed table. Materials are reserved immediately, and requirements, output and duration are captured when queued.
- Collect ready jobs into the carried inventory or the job's original property. Existing slot, weight and storage checks apply.
- Cancellation returns the reserved materials to Inventory deliveries, which can be collected when space is available. It leaves following jobs' scheduled times unchanged.
- A lease must cover the entire new job. Returning keys or removing the station requires collecting or cancelling its pending jobs first.
- Completed jobs can still be collected into carried inventory after a lease expires. Property collection requires current property access.
- Locking a season pauses unfinished crafting timers. Reopening shifts their completion times; a season reset cancels remaining old-season jobs.
- Finished goods work with existing storage, player market and equipment systems. Crafting does not add combat mechanics.

## Authority and retained history

The existing economic transaction lock serializes learning, crafting, leases, storage and trades. The server validates current season, authenticated identity, actual materials, learned recipe, recipe version, station and property access, lease expiry, queue space, completion time and destination capacity. Exact request retries return the recorded result. Atomic failures preserve inputs and output.

New tables deny direct browser access. Public APIs are security invoker wrappers around private authenticated functions with an empty search path. Learning and requests are immutable; completed/cancelled job records are retained. Existing inventory ledger triggers record material consumption and collection. Reserved input values continue to count in season net worth.

## Verification

GitHub Actions runs the app build, TypeScript and existing test suite. PostgreSQL tests cover consuming one blueprint, duplicate/retry learning, another player's privacy, station ownership, material deductions, premature collection, full inventories/storage, Owner permissions and versioning, lease restrictions, cancellation deliveries, paused seasons and seasonal learning reset. Concurrent tests race learning, the last available inputs and output collection.

Browser tests cover the property-to-table route, desktop/mobile layouts, blueprint consumption, queues, storage collection, retrieving/equipping outputs, cancellation deliveries, interrupted replies and Owner configuration. Browser fixtures run only in isolated CI. The deployment probe checks the protected crafting route and public item assets without accessing player data.

## Artwork provenance

Generated with the built-in image-generation tool. The user reference guided the interface composition; existing Blackwater art supplies the background.

Originals: `art-source/crafting/homemade-pistol.png`, `art-source/crafting/homemade-bullets.png`.
Optimized delivery: `public/art/crafting/{homemade-pistol,homemade-bullets}{,-256,-96}.webp`.

Pistol prompt: square game inventory artwork of one finished fictional worn pistol, premium dark noir crime-economy style, charcoal iron and warm copper light, weathered dark workbench, readable silhouette, no hands, text, labels, diagrams or instructions.

Ammunition prompt: square game inventory artwork of a closed worn ammunition carton with intact generic cartridges, matching dark noir Blackwater inventory style, charcoal workbench and warm amber light, no labels, technical diagrams, disassembled parts, hands or instructions.
