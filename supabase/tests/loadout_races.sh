#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('game.reason','CI actual carry limits concurrency',false);
update public.game_settings set value=100000 where key='inventory_weight_limit_grams';
do $$declare u uuid:='eeeeeeee-6000-4000-8000-000000000001';s uuid:=game_private.current_season();begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 update public.game_inventory set quantity=0 where player_id=u;
 update public.game_inventory set quantity=49 where player_id=u and good_id='whiskey';
 insert into public.game_inventory_deliveries(id,season_id,player_id,good_id,quantity,reason) values('eeeeeeee-6000-4000-8000-000000000002',s,u,'iron_ore',4,'CI guaranteed delivery');
end$$;
SQL
# Two distinct collections compete for the final 2 kg.
for nonce in 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=eeeeeeee-6000-4000-8000-00000000000$nonce" >"/tmp/loadout-claim-$nonce.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6000-4000-8000-000000000001',true);
select set_config('loadout.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('claim_delivery',jsonb_build_object('season_id',current_setting('loadout.test_season'),'delivery_id','eeeeeeee-6000-4000-8000-000000000002','quantity',2,'request_id',:'nonce'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-6000-4000-8000-000000000001';s uuid:=game_private.current_season();begin
 if (select grams from game_private.carried_load(s,u))<>100000 then raise exception 'Concurrent collection exceeded or underfilled capacity';end if;
 if (select quantity from public.game_inventory_deliveries where player_id=u)<>2 then raise exception 'Concurrent delivery duplicated or lost goods';end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 update public.game_inventory set quantity=0 where player_id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'pickaxe',1);
end$$;
SQL
# Equipping and listing cannot both consume the same pickaxe.
psql -At -v ON_ERROR_STOP=1 >/tmp/loadout-equip.txt <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6000-4000-8000-000000000001',true);
select set_config('loadout.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('equip',jsonb_build_object('season_id',current_setting('loadout.test_season'),'item_key','good:pickaxe','equipment_slot','utility','request_id','eeeeeeee-6000-4000-8000-000000000005'));
commit;
SQL
psql -At -v ON_ERROR_STOP=1 >/tmp/loadout-list.txt <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6000-4000-8000-000000000001',true);
set local role authenticated;
select public.game_action('list','{"good_id":"pickaxe","quantity":1,"unit_price":100}');
commit;
SQL
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-6000-4000-8000-000000000001';n bigint;begin
 select coalesce((select sum(quantity) from public.game_inventory where player_id=u and good_id='pickaxe'),0)+coalesce((select sum(quantity) from public.game_inventory_gear where player_id=u),0)+coalesce((select sum(quantity) from public.game_listings where seller_id=u and good_id='pickaxe' and status='active'),0) into n;
 if n<>1 then raise exception 'Equip versus trade duplicated equipment';end if;
end$$;
select 'PASS: concurrent final-weight collections and equip versus trade';
SQL
