#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='dddddddd-6000-4000-8000-000000000001';p uuid;s uuid:=game_private.current_season();begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 select id into p from public.game_district_plots where season_id=s and status='available' and owner_type='none' and zoning='industrial' order by code limit 1;
 update public.game_district_plots set owner_id=u,owner_type='player',status='owned' where id=p;
 insert into public.game_district_buildings(id,season_id,plot_id,building_type,owner_id,owner_type,construction_status,cost,ready_at) values('dddddddd-6000-4000-8000-000000000002',s,p,'warehouse',u,'player','ready',3000,now());
 update public.game_inventory set quantity=10 where season_id=s and player_id=u and good_id='whiskey';
 update public.game_storage_rules set capacity=6 where building_type='warehouse';
end$$;
SQL
# A retried request and another item compete for the final warehouse capacity.
for nonce in 3 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=dddddddd-6000-4000-8000-00000000000$nonce" >"/tmp/inventory-store-$nonce-$RANDOM.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','dddddddd-6000-4000-8000-000000000001',true);
select set_config('inventory.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('store',jsonb_build_object('season_id',current_setting('inventory.test_season'),'building_id','dddddddd-6000-4000-8000-000000000002','good_id','whiskey','quantity',6,'request_id',:'nonce'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select quantity from public.game_inventory where player_id='dddddddd-6000-4000-8000-000000000001' and good_id='whiskey')<>4 then raise exception 'Duplicated store debit';end if;
 if(select sum(quantity) from public.game_storage_inventory where building_id='dddddddd-6000-4000-8000-000000000002')<>6 then raise exception 'Capacity oversubscribed';end if;
 if(select count(*) from public.game_inventory_ledger where player_id='dddddddd-6000-4000-8000-000000000001' and request_id is not null)<>2 then raise exception 'Repeated storage ledger';end if;
end$$;
SQL
# Two retrievals cannot both remove the same protected goods.
for nonce in 5 6; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=dddddddd-6000-4000-8000-00000000000$nonce" >"/tmp/inventory-retrieve-$nonce.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','dddddddd-6000-4000-8000-000000000001',true);
select set_config('inventory.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('retrieve',jsonb_build_object('season_id',current_setting('inventory.test_season'),'building_id','dddddddd-6000-4000-8000-000000000002','good_id','whiskey','quantity',6,'request_id',:'nonce'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select quantity from public.game_inventory where player_id='dddddddd-6000-4000-8000-000000000001' and good_id='whiskey')<>10 then raise exception 'Retrieval duplicated items';end if;
 if(select sum(quantity) from public.game_storage_inventory where building_id='dddddddd-6000-4000-8000-000000000002')<>0 then raise exception 'Storage underflow';end if;
end$$;
SQL
# Carry-to-storage competes with a native market listing for the same 10 goods.
psql -At -v ON_ERROR_STOP=1 >/tmp/inventory-race-store.txt <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','dddddddd-6000-4000-8000-000000000001',true);
select set_config('inventory.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('store',jsonb_build_object('season_id',current_setting('inventory.test_season'),'building_id','dddddddd-6000-4000-8000-000000000002','good_id','whiskey','quantity',6,'request_id','dddddddd-6000-4000-8000-000000000007'));
commit;
SQL
psql -At -v ON_ERROR_STOP=1 >/tmp/inventory-race-market.txt <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','dddddddd-6000-4000-8000-000000000001',true);
set local role authenticated;
select public.game_action('list','{"good_id":"whiskey","quantity":6,"unit_price":100}');
commit;
SQL
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare units bigint;begin
 select coalesce((select sum(quantity) from public.game_inventory where player_id='dddddddd-6000-4000-8000-000000000001' and good_id='whiskey'),0)+coalesce((select sum(quantity) from public.game_storage_inventory where player_id='dddddddd-6000-4000-8000-000000000001'),0)+coalesce((select sum(quantity) from public.game_listings where seller_id='dddddddd-6000-4000-8000-000000000001' and status='active'),0) into units;
 if units<>10 then raise exception 'Market and storage duplicated items';end if;
 if(select quantity from public.game_inventory where player_id='dddddddd-6000-4000-8000-000000000001' and good_id='whiskey')<>4 then raise exception 'Race did not serialize a successful action';end if;
end$$;
select 'PASS: concurrent capacity claims, exact retries, retrievals and market-versus-storage conservation';
SQL
