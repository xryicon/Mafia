# Dashboard health and armour

The dashboard shows Cash → Health → Armour, followed by the existing operations and district heat. The shared top bar no longer shows carried stock and no longer fetches the full game state just to count it. Inventory remains accessible from navigation.

Health starts at 100/100. Armour starts at 0/100. Values are private, season-aware and server-controlled; they are not added to public player profiles. Unavailable health data displays a dash rather than an invented full-health value.

Database settings define the normal health maximum (100), future boosted maximum (120), armour maximum (100), and temporary overheal decay (initially one point per 60 seconds). Existing Owner economy controls can edit these settings. This release adds no drug, armour item, damage action or player-accessible stat modification.

Health above the normal maximum decreases with server time, stopping at the normal maximum. Injured health and zero health remain unchanged. Decay continues while offline. A new season starts with normal full health and no armour; previous season data is retained.

Future consumable/combat actions must use the existing economy/season locking conventions, validate the actor and item/equipment, materialize the effective health from game_private.vitals_state() before changing it, and consume items/update health in one transaction. Never use browser health as an input. Updating stored health resets its time anchor; health/armour changes are audited. Armour equipment integration can update the private armour value when its gameplay rules are introduced.

GitHub validation covers initial values, unauthorized updates, per-player privacy, overheal decay, the 100 lower bound, injuries, zero health and seasonal resets. Browser checks verify visible desktop/mobile bars, missing-data handling, temporary boost presentation and stock-counter removal across the shared HUD.
