# Fresh game frame

The latest header reference replaces the earlier property-screen navigation: brass line icons above Dashboard, Market, Properties, Districts, Gangs and Telegrams. Profile is removed from the navigation. The live wallet sits beside the account portrait; the player menu retains Owner/Staff controls, Support, players, seasons, rankings, financial history and account security.

Dashboard, Properties and Districts deliberately render blank protected canvases, including old query-string variants. They do not mount the old gameplay views or poll game_state. Telegrams is also a blank protected starting point; messaging functionality has not been added.

Market and its inventory view continue to use the existing server-authoritative trading actions. Gangs retains the current seasonal register. Financial history now lives at /ledger, so Dashboard stays empty. Historical profile/ranking links still work through the player directory.

No database records, balances, properties, moderation history or archived rankings are reset. Public chat remains absent. city_status continues to supply trusted header data and session presence.

The clearer masthead shows online presence below the Blackwater wordmark, an opaque cash panel, and power plus rank under the username. Power is the existing respect (XP) score; city_status computes the rank using the Owner's configured thresholds. The empty canvases remain free of gameplay panels over an atmospheric harbor background.
