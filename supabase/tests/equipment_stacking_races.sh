#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('game.reason','CI ammunition concurrency',false);
do $$declare u uuid:='eeeeeeee-6600-4000-8000-000000000001';s uuid:=game_private.current_season();begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 update public.game_inventory set quantity=0 where player_id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-bullets',100);
end$$;
SQL
# Two requests for 80 bullets compete for the same 100-round carried stack.
for nonce in 2 3; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=eeeeeeee-6600-4000-8000-00000000000$nonce" >"/tmp/ammo-equip-$nonce.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6600-4000-8000-000000000001',true);
select set_config('ammo.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('equip',jsonb_build_object('season_id',current_setting('ammo.test_season'),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',80,'request_id',:'nonce'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-6600-4000-8000-000000000001';begin
 if (select quantity from public.game_inventory where player_id=u and good_id='homemade-bullets')<>20 or (select sum(quantity) from public.game_inventory_gear where player_id=u)<>80 then raise exception 'Concurrent ammo equip lost or duplicated bullets';end if;
 if (select count(*) from public.game_inventory_gear where player_id=u and location='equipped')<>1 then raise exception 'Ammo split across equipment slots';end if;
end$$;
SQL
# Two retries of the same unequip request return all 80 rounds exactly once.
for run in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/ammo-unequip-$run.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6600-4000-8000-000000000001',true);
select set_config('ammo.test_season',game_private.current_season()::text,true);
select set_config('ammo.test_gear',(select id::text from public.game_inventory_gear where player_id='eeeeeeee-6600-4000-8000-000000000001' order by created_at limit 1),true);
set local role authenticated;
select public.inventory_action('unequip',jsonb_build_object('season_id',current_setting('ammo.test_season'),'item_key','gear:'||current_setting('ammo.test_gear'),'request_id','eeeeeeee-6600-4000-8000-000000000004'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-6600-4000-8000-000000000001';begin
 if (select quantity from public.game_inventory where player_id=u and good_id='homemade-bullets')<>100 or exists(select 1 from public.game_inventory_gear where player_id=u and quantity>0) then raise exception 'Concurrent unequip retries lost or duplicated bullets';end if;
 if (select sum(delta) from public.game_inventory_ledger where player_id=u and gear_id is not null)<>0 then raise exception 'Equipment ledger does not balance';end if;
end$$;
select 'PASS: concurrent ammo quantities and duplicate unequip retries preserve every round';
SQL
