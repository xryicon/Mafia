# Player profiles

Players open a dossier at /players/[id], from the respect directory, season standings or Telegram sender names. /profile opens the signed-in player's own dossier. The page reuses Blackwater artwork, profile portraits, identity, presence, ranks, gang membership and business ownership.

Descriptions are permanent identity fields, capped at 300 characters by the Owner-editable profile_description_limit setting (hard ceiling 1,000). Authenticated players edit only themselves through profile_description, with an optimistic version and a per-player rate limit. The existing immutable identity audit records prior and new text, including clearing a description. Text is rendered as text, never HTML. Pictures keep the existing HTTPS URL editor and appear consistently in the header, directory and Telegrams.

The player_profile endpoint explicitly selects public identity and gameplay standings. Health, achievements, Hall of Fame awards, inventory, equipment, private messages, cash balances and subscription data are absent. Configured public leaderboard scores remain visible. Banned/deleted players follow the existing directory visibility rule. Profile edits never accept another player's identifier or browser-provided respect/ownership values.

Send Telegram opens an addressed composer; sending still uses the existing fee, block checks and delivery rules. The district footprint describes owned plots, not a fabricated current player location. Business lists use actual current-season ownership; private revenue is not published.

GitHub Actions verifies description ownership, limits, stale versions, immutable audit history, public-data boundaries, portrait consistency, businesses and season persistence. Browser checks cover safe text rendering, editing, mobile layouts, Telegram navigation and missing players. The app is not run locally.