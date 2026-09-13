# Blackwater skills

The protected `/skills` page shares the game HUD, noir artwork and copper/iron styling. Dashboard quick actions and the player menu link to it. Crafting, Sharpshooting and Lockpicking each begin at level 1 and stop at level 20. Cards show saved XP, progress to the next level and the level-20 target. The interactive level grid shows every threshold; the latest 20 skill rewards show their activity and date.

Each skill initially requires 10,000 cumulative XP to reach level 20. Owner → Skills & progression controls each target independently (19–1,000,000,000 XP). For level L the cumulative threshold is `(L-1) + floor((target-19) * (L-1)^2 / 361)`. This guarantees strictly increasing thresholds, a zero-XP first level and an exact target at level 20. Definition changes recalculate levels without modifying earned XP. Extra XP remains recorded after level 20. Player-facing levels and thresholds come from the server; the browser formula only previews an Owner edit.

Skill XP uses verified activities, with a private immutable ledger and unique activity references:

- Crafting: collecting completed crafting jobs. Work time earns 10 XP per minute by default, rounded down with a minimum of 1 XP per job. Owner can adjust the rate. Each queued job snapshots its reward; recipe edits, season pauses and later rate edits cannot change it. Learning, queuing, cancelling and failed collections grant no XP.
- Sharpshooting: the actual score-based XP award from an eligible completed range session. This mirrors the existing range ledger without awarding general power again.
- Lockpicking: the recorded power reward for a successful prison break. Failed, expired or cancelled attempts grant none. Existing prison reward controls determine this amount.

Historical completed crafting jobs, range awards and successful breakouts populate the initial skill records. Gameplay rewards are added atomically by database triggers; exact retries cannot duplicate XP. Existing cash, items, general power and activity evidence are retained. Skill progression is season-scoped, with earlier ledger history preserved when a new season starts.

Owner updates require the `skills.manage` permission, current definition version, a unique retry reference and an audit reason. Moderator roles receive no automatic permission. Only authenticated players can load their own skills; direct ledger/configuration writes and direct calls to trigger helpers are denied. Both configuration changes and crafting-rate edits are audited. Refresh and background polling update an open Skills page.

Validation runs in GitHub: curve endpoints and strict monotonicity; level boundaries/cap; private reads; owner/moderator access; audited optimistic/idempotent saves; season isolation; and real crafting, range and prison action integration. Browser coverage includes navigation, art, all levels, mobile layout, owner recalculation with XP preservation, response recovery and existing gameplay regressions. No local app or database test server is used.
