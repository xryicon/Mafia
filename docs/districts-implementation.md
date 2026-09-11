# District implementation

Build the first complete district, The Waterfront, using the existing Supabase RPC, Auth, immutable wallet ledger, permissions, seasonal records, settings, and audit patterns.

## Navigation and UI
/districts is the city map. /districts/[slug] is the detailed district. Seven working tabs: Overview, Plots, Businesses, Resources, Market, Territory, Activity. Deep links preserve tab and selected plot/business. SVG maps use database geometry, support pan/zoom, keyboard/touch selection, ownership and business filters, and a desktop detail panel/mobile modal sheet. Keep the approved masthead, background and the blank Dashboard/Properties pages.

## World and persistence
Permanent district/plot/building/zoning templates create season-specific plots, buildings, businesses, resources, territory and wars. New seasons instantiate fresh municipal properties, not old player ownership. Property sales, ownership history, bids, money movements and events are retained. User content is archived; activity visibility is separately moderated. Seed 24 plots, six real municipal/company businesses, one Telegram Office, Harbor strategic site, resources and honest creation events. Never invent transactions or real player ownership.

## Transactions
Server RPCs validate active sessions, current/open season, permission, ownership, zoning, capacity, availability, configuration and expected quotes. Acquire the shared season lock and a district economy transaction lock; lock affected wallets in UUID order. Set game.reason before balance changes so the existing wallet trigger creates ledger entries. Implement purchase/list/withdraw, funded offers and auctions with refund/settlement, construction start/completion, business opening/management/production, watchlists, and territory contributions. Transfers include attached building/business title and write immutable sales/history/events. Financial requests reject stale quotes. No browser money/ownership/prices are authoritative.

## Integration
The local market summarizes real listings and new trade records and links to the existing full market. Record location on listings and successful trades; accept listing location only after server validation. Include land/building values and reserved property funds in season scoring without double-counting. Preserve historical records on reset. Territory supports multiple gang rows and multi-party wars; neutral is valid. Show objectives, operations, convoys, supply, defenses and participation when a war exists.

## Owner controls
Add Districts & properties to the Owner workspace and a permission-protected management route for explicitly authorized staff. Forms manage districts, geometry/plots/zoning/prices/status, building types and allowed zoning, resources and strategic sites, building assignment/removal, tax, gang control/war data, images/descriptions and activity visibility. Require reasons and audit all changes. New economic permission is not granted to Moderators by default.

## Verification
Use GitHub-hosted TypeScript/build and browser tests plus PostgreSQL transaction/security regressions and two-connection purchase/bid races. Review screenshots at desktop and phone sizes. Apply tested migrations to Supabase, reconcile their actual versions with repository names, merge and confirm Cloudflare deployment. No local application execution.
