# Active chop shops

Enter from Inventory or any garage vehicle panel, at `/chop-shop`.

## Player flow
- Travel to the shop district and choose a stored stolen vehicle.
- Review the entry fee and explicitly confirm permanent dismantling. The vehicle cannot be driven, refuelled or sold afterward. The non-refundable fee is paid once when joining, including queued jobs.
- Choose wheels, doors, battery or engine. Remove four highlighted fasteners, disconnect the fittings, then drag the part to the tray (or use the keyboard-accessible lift button).
- Remove the battery before the engine. Each group awards real tradable inventory goods: four wheels, two doors, one battery or one engine. Inventory capacity applies atomically; a full inventory never consumes an unclaimed part.
- Each removed group adds 4 personal district heat by default. Scrap the shell for 2 scrap metal. Scrapping early permanently loses attached parts.
- Progress survives reloads and pauses. Pausing immediately frees the bay; resuming joins the queue again without another fee. Five minutes without work automatically pauses the job. Merely viewing an active job does not retain its bay. Queue polling maintains presence; absent queued players also pause.

## Shops
- A city shop at the Waterfront supplies separate bays for every player, with a default $350 entry fee.
- Install a shop in a player-owned ready garage for $5,000. Rented garages are not eligible.
- Two bays initially; each $4,000 upgrade adds two, to a maximum of six. Owner jobs count toward capacity.
- Owners set a fee between $0 and $300 by default; their own jobs are free. Owners receive customer fees without being online.
- Jobs queue FIFO; resuming joins the back. Fees are snapshotted, and a changed quote requires review.
- Shops at unavailable or transferred properties stop accepting work. Existing customers retain progress and may scrap the remaining shell; the previous owner cannot manage the sold property.

## Economy / security
Owner economy settings: `chop_shop_cost`, `chop_upgrade_cost`, `chop_city_fee`, `chop_max_fee`, `chop_heat_per_part`, `chop_idle_seconds`.

Migration: `20260924220000_chop_shops.sql`. Apply before deploying the UI. Private RLS-protected shop/job/request tables; authenticated RPCs validate ownership, season, location, custody, street activity and server-side fees. The existing transaction lock serializes bay allocation, sales, travel and rewards. Each tool step has a fresh server token and minimum 500ms delay. This verifies ordered progression, not proof of human input or anti-bot protection. Retried requests return their original receipt.

Salvaged parts can be traded/stored now. Vehicle repairs, condition-based rewards, buyer contracts and tool upgrades are future extensions, not included.

Validation: database integration suite `supabase/tests/chop_shops.sql`; browser suite `tests/e2e/chop-shop.spec.ts`.
