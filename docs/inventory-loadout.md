# Inventory loadout

Carried inventory has 20 saved stack positions and a 100 kg weight limit. Six equipment spaces use existing goods and database compatibility: Primary weapon, Secondary weapon, Ammo, Armor, Utility and Medical. Equipped goods still weigh something; secure property storage does not count toward carried capacity.

Drag to move, swap or equip. Touch users select an item, press Move and select a target. Reorders use a bag version and idempotent requests. Individual equipment preserves condition across unequipping and storage. Used equipment is separate from fresh commodity stacks; existing market trades use fresh stacks. Mining consumes the equipped Utility pickaxe's condition.

Owner inventory controls edit item weights and equipment compatibility. Global settings control slot and weight limits. All mutations enforce ownership and current season. Existing over-capacity goods remain intact and can be stored or sold. Further manual acquisitions require capacity. Guaranteed auction deliveries and other-player payments wait for collection if full. The delivery ledger preserves ownership and season valuation. No new collectible items are seeded.

CI runs existing bulk economy scenarios with a high configured weight capacity, then tests the actual 20-slot/100kg limits separately, including full-bag purchase rollback and auction return collection. Builds, database checks and browser tests run in GitHub Actions.


## Equipment stacking and ammunition

Unused equipment returns to the normal carried or property stack. Equipment with a condition value stays individual, except pristine pickaxes at the current configured starting durability. Worn pickaxes retain their exact wear. Returning an item into an existing stack does not require another carried slot.

Ammo supports a chosen whole quantity through the equip dialog, drag-and-drop, and touch Move. Equipping more of the same ammunition adds to the equipped quantity; other equipment remains one item per slot. The server validates ownership, availability, season, compatibility and transfer limits, and serializes economic actions with the existing inventory coordinator. Request IDs make retries safe.

Converted equipment rows are retained with zero quantity in a retired location. They remain linked to immutable inventory ledger entries but are excluded from usable inventory, storage and equipment. The migration repairs existing unused carried and stored entries in the current season, without changing equipped ammunition, damaged equipment, or historical seasons. The internal restacking helper conserves carried weight and never increases used slots, including when an Owner has lowered capacity below existing holdings.
