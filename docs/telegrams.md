# Blackwater Telegram Office

One strategic office serves the entire city. The existing Waterfront property is retained. Messages deliver atomically with fee settlement; ownership follows the district property title. Office owners receive aggregate traffic and revenue only, never private subjects, bodies or recipient lists.

Personal messages, drafts, blocks and folder preferences survive season changes. A new season resets the office to city ownership and its configured default fee, retaining previous financial and ownership records. Moderation can inspect only a specifically reported message after the report enters investigation and the reviewer has both report and evidence permissions. Evidence reads are audited without copying private text into general audit records.

Artwork: `public/art/telegram-office.jpg` (web asset) and `public/art/telegram-office.png` (source), generated with the built-in image generation tool. Prompt: cinematic 1920s waterfront Telegram Office, dark stone and copper-framed amber windows, rainy cobbles, harbour cranes, deep blue-black and muted gold, three-quarter architectural view, no UI or statistics.

Production migrations were applied on 2026-09-11 as `20260911190107_telegram_city_office` and `20260911190501_telegram_delivery_and_controls`. The complete Telegram transaction/privacy suite also passed against production inside a rolled-back transaction. The founding season remains open; one city-owned office remains at Waterfront W06 with a $25 fee and a $15,000 property listing (district tax additional).


## Command desk, groups and shared portraits

Telegrams uses the same charcoal command panels, serif headings and copper accents as the dashboard. On mobile, opening a conversation switches to the reader with a Mailbox back button. The office panel and its controls remain available below. Direct messages, folders, drafts, reports, blocks, fees, singleton ownership and settlement use the existing Telegram system.

Players create invite-only groups and manage invitations through View members. Invitees must accept before receiving messages. Owners can rename groups, cancel invitations, remove members, transfer ownership and close the group. Closed groups retain their history and free the owner's active-group allowance. Limits for active groups, members and names are editable through the existing Owner economy settings.

Gang conversations derive access from game_season_gang_members in the current season. Clients cannot supply a gang roster or appoint themselves to a gang. Any actual member can open the gang's unique conversation. Leaving the gang immediately removes access; next-season gangs get a different conversation. Direct and private-group correspondence remains account-linked across seasons.

A group send is one telegram: the sender pays the current office fee once, irrespective of recipient count. Both the normal and group send paths retain the same office checks, ledger transfers, receipts, rate limits, sanctions and retry key. An immutable delivery snapshot records the eligible recipients of each group message. New members receive future messages, not earlier private correspondence. Blocks exclude the blocked pairing from future group delivery. Membership changes and send actions use the same coordinator lock; gang roster actions acquire it before economic locks.

Only accessible threads and delivered messages enter the mailbox queries. Message text and membership history remain in the private schema. Office operators receive aggregate traffic and revenue; evidence access still requires an investigating report with explicit moderation permissions.

Profile portraits are saved on the player's existing identity, independent of gameplay seasons. Account and own-profile pages accept an HTTPS image URL or the default Blackwater portrait. A shared avatar component displays that same picture in the header, profile, dashboard, conversation list, member list and sent messages, with a fallback for broken images and no referrer sent to the image host. This release does not introduce file uploads.

Validation runs in GitHub, including existing direct-message/office/season regression suites, group authorization and privacy, invitation handling, blocking, reports, fee conservation, exactly-once concurrent group sends, desktop/mobile UI, portrait consistency and lost-confirmation retries.

