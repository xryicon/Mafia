# Inventory and secure property storage

Inventory replaces Properties in the shared navigation. The old /properties link redirects to /inventory. Existing items and art are reused; this release creates no collectible goods, weapons, ammunition, rarity tiers or starter gifts.

The existing game_inventory remains carried stock. All existing purchases, loot, collected production, mine rewards, refinery output and Owner grants already arrive there. Cash remains in the wallet and can go to the National Bank. Equipped mining tools, reserved market goods and loaded refinery fuel are shown separately.

Completed, personally owned district garages and warehouses provide secure storage. A new garage building type joins the existing construction/zoning system. Warehouse capacity starts at 2,000 units and garage capacity at 200; both are database rules editable from Owner → Inventory & storage. One item consumes one capacity unit. Prices and construction requirements remain editable under Districts & properties.

Moving goods is an authenticated atomic transaction with exact-payload request IDs, the existing district/season/wallet lock order, sufficient-stock checks and capacity validation. Stored goods cannot be sold, equipped or refined until retrieved. Storage does not add a theft/raid mechanic to carried items. Stocked buildings cannot be sold, auctioned, replaced or reassigned. Disabling new deposits or reducing capacity never deletes items or prevents retrieval.

An immutable inventory ledger records existing quantity baselines and future carried/storage changes. Private inventory reads are scoped to the authenticated player. Stored stock retains its seasonal book value in net-worth rankings. New seasons have new inventories and property ownership; old stock and history remain preserved in their original season.

The page includes category/location filters, search, sort, grid/list views, existing artwork, quantities by location, pickaxe equipment, property capacity, transfers and paginated inventory history. Future registered goods automatically join the same system; Owner controls edit their category and description.

Validation runs in GitHub Actions, not a local application server: type checks, production build, all game regression suites, isolated PostgreSQL ownership/capacity/rollback/season tests, independent-connection race tests, and responsive browser screenshots.
