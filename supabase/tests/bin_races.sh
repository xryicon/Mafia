#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-3000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-3000-4000-8000-000000000001',false);
select public.game_state();
update public.game_bin_rules set cash_chance=0,pickaxe_chance=100,pistol_blueprint_chance=0,bullet_blueprint_chance=0;
SQL
for attempt in 1 2 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "attempt=$attempt" >"/tmp/bin-race-$attempt.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3000-4000-8000-000000000001',true);
select set_config('bin.district',(select id::text from public.game_districts where slug=case when :'attempt' in ('1','2') then 'the-waterfront' else 'old-town' end),true);
set local role authenticated;
select public.bin_diving_action('dive',jsonb_build_object('season_id',game_private.current_season(),'district_id',current_setting('bin.district'),'request_id',case when :'attempt' in ('1','2') then 'eeeeeeee-3000-4000-8000-000000000002'::uuid else gen_random_uuid() end));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select count(*) from public.game_bin_dives where player_id='eeeeeeee-3000-4000-8000-000000000001')<>1 then raise exception 'Concurrent dives bypassed shared cooldown';end if;
 if(select quantity from public.game_inventory where player_id='eeeeeeee-3000-4000-8000-000000000001' and good_id='pickaxe')<>1 then raise exception 'Concurrent requests duplicated loot';end if;
end$$;
select 'PASS: concurrent identical requests and different district requests award one result';
SQL

# The same spare cannot be equipped, listed and auctioned concurrently.
for action in equip list auction; do
 psql -At -v ON_ERROR_STOP=1 -v "action=$action" >"/tmp/loot-race-$action.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3000-4000-8000-000000000001',true);
set local role authenticated;
select case when :'action'='equip' then public.bin_diving_action('equip',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid()))
 when :'action'='list' then public.game_action('list','{"good_id":"pickaxe","quantity":1,"unit_price":100}'::jsonb)
 else public.market_auction_action('create',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid(),'good_id','pickaxe','quantity',1,'starting_bid',100,'duration_minutes',5)) end;
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare uid uuid:='eeeeeeee-3000-4000-8000-000000000001';n int;begin
 select coalesce((select sum(quantity) from public.game_inventory where player_id=uid and good_id='pickaxe'),0)
 +coalesce((select sum(quantity) from public.game_listings where seller_id=uid and good_id='pickaxe' and status='active'),0)
 +coalesce((select sum(quantity) from public.game_market_auctions where seller_id=uid and good_id='pickaxe' and status='open'),0)
 +(select count(*) from public.game_mining_tools where player_id=uid and durability>0) into n;
 if n is distinct from 1 then raise exception 'Concurrent equip/list/auction duplicated or lost the spare: %',n;end if;
end $$;
select 'PASS: concurrent equip, fixed listing and auction conserve one pickaxe';
SQL
