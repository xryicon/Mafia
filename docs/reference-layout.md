# Reference game layout

The supplied property-screen reference defines the protected game's layout: a charcoal-teal background, warm brass accents, serif headings, wide original artwork, compact production cards and a property control column.

The exact primary navigation is Dashboard, Market, Properties, Districts, Gangs, Profile. Properties reuses existing production businesses; Districts provides the existing operations. Gangs reads the seasonal gang register; this design change does not add gang creation, invites or combat. Profile opens the signed-in player's current and archived rankings.

Public chat is removed from all game screens. Existing moderation evidence remains in the Owner office. Online presence, usernames, private tickets, rankings, seasons and Owner access are retained. The player menu opens their secondary destinations.

All property quantities, batches, prices, cash and level use existing server records. The UI does not invent workers, fuel, equipment durability, property profits or mine upgrades. Production and market actions retain the existing transactional RPCs and ledger protections.

The compact city_status endpoint maintains session presence and returns only the header's own account, status and recent activity; it excludes chat and ticket data. The gang directory excludes private metadata and aggregates visible current-season members. Both endpoints require an active account.
