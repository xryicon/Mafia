# Blackwater Island Prison

Blackwater Island is the prison district at `/districts/blackwater-island`. Visitors can view the island. Jailed players are routed there on protected page loads, refresh, sign-in and navigation; the shared city header checks for newly issued sentences during its normal polling and after game actions. Support, account/password access and permission-protected staff offices remain reachable.

Sentences are stored in Supabase, scoped to the current season. The server decides custody from the release timestamp, so time continues offline and no scheduled job is needed. The countdown is a display estimate; the page checks the server every five seconds and at expiry before showing release. Early release also requires a successful server response.

Owner panel → Blackwater Island Prison provides timed imprisonment (1 minute–7 days), a current-inmate register and early release with a required reason. Ordinary players cannot issue sentences or edit custody rows. Retries cannot extend an active sentence and early release must match the current sentence ID. All sentence changes use the existing immutable audit history.

The existing game has no automatic arrest outcome. This change adds no random arrests to jobs. Future trusted gameplay code can call `game_private.imprison`; clients have no permission to execute it. Current imprisonment is issued by the Owner. No existing player is jailed by this migration.

The shared open-season gameplay guard blocks new economic/gameplay actions while jailed, including direct RPC calls. Read-only data and existing cleanup/settlement actions remain available under their original rules. Browsing a district is not a persistent free-player location; while jailed, the player's custody location is always Blackwater Island. A new season starts without old-season custody, retaining audit history.

Validation: `supabase/tests/prison.sql` checks authorization, privacy, persistence, direct job restrictions, duplicate sentencing, stale release, early release, expiry and season boundaries. `tests/e2e/prison.spec.ts` checks routing, refresh, timed release, Owner controls and mobile layout.

