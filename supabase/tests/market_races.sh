#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-1000-4000-8000-000000000001'),('eeeeeeee-1000-4000-8000-000000000002'),('eeeeeeee-1000-4000-8000-000000000003');
select set_config('request.jwt.claim.sub','eeeeeeee-1000-4000-8000-000000000001',false);
select public.game_state();
select set_config('request.jwt.claim.sub','eeeeeeee-1000-4000-8000-000000000002',false);
select public.game_state();
select set_config('request.jwt.claim.sub','eeeeeeee-1000-4000-8000-000000000003',false);
select public.game_state();
update public.game_players set cash=10000 where id::text like 'eeeeeeee-1000-%';
SQL
auction=$(psql -At -v ON_ERROR_STOP=1 <<'SQL' | tail -n 1
select set_config('request.jwt.claim.sub','eeeeeeee-1000-4000-8000-000000000001',false);
select public.market_auction_action('create',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid(),'good_id','whiskey','quantity',3,'starting_bid',300,'duration_minutes',5))->>'auction_id';
SQL
)
for player in 2 3; do
 psql -At -v ON_ERROR_STOP=1 -v "auction=$auction" -v "player=eeeeeeee-1000-4000-8000-00000000000$player" >"/tmp/market-bid-$player.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
set local role authenticated;
select public.market_auction_action('bid',jsonb_build_object('auction_id',:'auction','season_id',game_private.current_season(),'request_id',gen_random_uuid(),'amount',300));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 -v "auction=$auction" <<'SQL'
do $$
begin
 if (select sum(bid_count) from public.game_market_auctions where seller_id='eeeeeeee-1000-4000-8000-000000000001')<>1 then raise exception 'Same-price race accepted duplicate leaders';end if;
 if (select sum(cash) from public.game_players where id::text like 'eeeeeeee-1000-%')<>29700 then raise exception 'Bid race charged twice';end if;
end $$;
update public.game_market_auctions set ends_at=clock_timestamp()-interval '1 second' where id=:'auction'::uuid;
SQL
for player in 2 3; do
 psql -At -v ON_ERROR_STOP=1 -v "auction=$auction" -v "player=eeeeeeee-1000-4000-8000-00000000000$player" >"/tmp/market-settle-$player.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
set local role authenticated;
select public.market_auction_action('settle',jsonb_build_object('auction_id',:'auction','season_id',game_private.current_season(),'request_id',gen_random_uuid()));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
 if (select sum(cash) from public.game_players where id::text like 'eeeeeeee-1000-%')<>29985 then raise exception 'Settlement race money conservation failed';end if;
 if (select sum(quantity) from public.game_inventory where player_id::text like 'eeeeeeee-1000-%' and good_id='whiskey' and season_id=game_private.current_season())<>15 then raise exception 'Settlement race duplicated inventory';end if;
 if (select count(*) from public.game_ledger where player_id='eeeeeeee-1000-4000-8000-000000000001' and reason like 'Auction sale:%')<>1 then raise exception 'Settlement race paid twice';end if;
end $$;
select 'PASS: simultaneous equal bids and simultaneous settlement preserve stock, cash and one sale ledger entry';
SQL

