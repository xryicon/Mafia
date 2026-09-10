# Seasons and leaderboards

## Owner workflow
Open Seasons & leaderboards from the game sidebar, then Owner controls.

1. Create and configure the next draft season (name, starting cash/stock, optional UTC dates, Hall of Fame places).
2. Configure ranking categories, order, banned-player eligibility, awards and inventory book values.
3. Lock the current season. Gameplay and economic adjustments stop. Moderation remains available.
4. Snapshot final results. This freezes scores, ranks, display names and board labels. Finalization cannot be repeated or reopened.
5. Archive leaderboards. Hall of Fame entries are created from the frozen results, including tied ranks.
6. Select the new draft. Either prepare a reset and open it later, or reset and launch in one transaction. Type the exact displayed reset phrase and provide an audit reason.

Preparing a reset closes the old wallets and initializes new-season wallets while gameplay stays paused. Opening a prepared season requires its configured start time to have arrived. A configured end time blocks gameplay immediately; the Owner then locks, snapshots and archives. No scheduled process launches or resets a season automatically.

## Data retained
The founding season adopts current gameplay without a reset. Auth accounts, handles, subscription entitlement data, roles, session revocations, sanctions, bans, reports, tickets, evidence and audit history are permanent. Archived scores and Hall of Fame records reject updates, deletion and truncation.

A reset changes the active season key; it never deletes old gameplay. Wallet closing and opening entries remain in the immutable ledger. The old season-player row retains its final balance, XP, level and skills. Inventory, businesses, market orders, events and financial entries carry season IDs. New season assets, gangs/memberships, loans, crafting/production/construction queues and statistics start empty. Levels start at one, skills empty, XP zero, cash and starter stock use draft configuration.

## Leaderboard definitions
Cash and respect use season player records. Factory value includes existing production businesses. Net worth is cash plus inventory and market escrow at Owner book values, plus businesses and owned asset values, less outstanding loans. Asking prices never value inventory. Production counts collected units; trading counts gross sales value; crime counts completed street operations; construction counts acquired businesses. Equal scores share SQL RANK, so subsequent rank numbers can have gaps.

The founding season's activity counters begin when this migration is installed. Earlier financial history remains available, but old activity counts are not fabricated. New seasons count activity from launch.

Land, company/factory assets, gangs, loans, crafting and combat gameplay modules are not implemented by this phase. Season-scoped storage and metric categories are provided for them. Their inactive categories are disabled by default and explicitly labeled in Owner controls. Future server modules must record metrics through the private record_metric helper and use season-scoped tables; no browser or moderator can submit arbitrary scores. No claim is made that adding a category implements its gameplay system.

## Transaction safety
Game actions, player initialization and staff actions hold a shared transaction advisory lock. Season transitions take its exclusive counterpart, preventing actions and eligibility changes during snapshots/resets. Owner permissions are rechecked after waiting for the lock. Economic writes reject closed seasons. Stale season IDs and old market listings cannot operate in a new season. Direct client writes to season tables, scores and archived records are revoked.

## Validation
GitHub Actions runs migration/seed checks, existing economy and authorization regressions, the season lifecycle/reset suite, and mobile leaderboard/profile/Owner navigation tests. Reset regression tests run only in isolated CI, never against live gameplay. Production rollout only adopts the current world as the founding season.
