# Waterfront district system

Blackwater's city atlas uses an original commissioned noir city illustration with database-defined clickable district boundaries. The Waterfront is the first district: 24 plots, six city/company businesses, a Telegram Office, harbor strategic site, checkpoint and resource infrastructure.

## Player routes

- /districts: city map and district dossiers.
- /districts/the-waterfront: Overview, Plots, Businesses, Resources, Market, Territory and Activity.
- Plot selection is preserved in tab/plot URL parameters. A side panel on desktop becomes a modal bottom drawer on mobile.
- The directory links businesses to plots and opens the business detail.
- The existing /market supports district sell listings, funded buy orders, and returns to inventory without replacing the established marketplace.
- Territory supports seasonal gang founding, open recruitment, paid influence, and multi-party wars. The founding player remains in their gang for the season.

## Authority and accounting

Authenticated RPCs require an active player, rate-limit requests, and take the shared season lock before acting. District mutations serialize using advisory transaction lock 4704020; wallet pairs lock in UUID order, matching the original market. Purchases compare a server-calculated quote and plot version. Money changes use the existing game.reason wallet trigger, which appends immutable ledger entries.

Plot purchases and accepted offers/auctions transfer the plot, attached building and business atomically. Auctions and offers hold cash in reserve; outbid players and cancelled offers receive refunds. Duplicate purchases, premature settlements, self trades, invalid zoning and insufficient funds are rejected. Construction requirements, cost, duration, production and influence rules come from the database. Buy orders reserve their full value and can only be filled once using actual supplier inventory.

Sales, title history, escrow movements, trades and public events cannot be rewritten or deleted. Auction and offer records are retained. Event visibility uses a separate audited record. Owner mutations have explicit reasons and audit entries.

## Seasons

Catalog districts, zoning, building types, plot and site templates persist. Gameplay plots, businesses, buildings, resources and territory are instantiated separately for each season. Old titles and financial records remain available. New records start with catalog ownership; no player land carries into the next season. Net worth includes land, buildings and reserved bids, offers and buy orders. Locked-season timers shift when a season reopens.

## Owner editing

Owner panel → Districts & properties, or /districts/manage. Supports district text, imagery, city boundaries, tax/status/value indicators, plot geometry, sizes, zoning, prices, infrastructure, strategic designations, resource sites, building assignment/removal, building production rules, zoning permissions, control/influence, multi-party wars/operations, event publication and visibility. Moderators receive no district economic permission by default; districts.manage may be explicitly granted.

Seeded entities are fictional city/company operators, not fake player accounts. Registered-business events describe actual seed registrations. Prices and revenue summaries use real records; empty markets show empty states.

## Validation and deployment

All application execution happens in GitHub Actions, per the project owner's preference. Tests include existing unit/browser/database regressions, district transactions, escrow conservation, gang participation and two concurrent purchase connections against disposable PostgreSQL. Visual captures cover desktop city/district/plot views and mobile drawers/Owner forms.

Apply all district migrations in order only after isolated tests pass. Record actual Supabase migration versions in repository filenames. Never run the committed-fixture race script against production; it explicitly requires GitHub CI's local disposable PostgreSQL environment. Production smoke tests must roll back.
