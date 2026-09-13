#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('game.reason','CI range concurrency setup',false);
update public.game_settings set value=5000 where key='range_fire_interval_ms';
update public.game_settings set value=2000 where key='range_lag_tolerance_ms';
do $$declare u uuid:='eeeeeeee-7700-4000-8000-000000000001';s uuid:=game_private.current_season();r jsonb;begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 update public.game_inventory set quantity=0 where player_id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-pistol',1),(s,u,'homemade-bullets',3);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-pistol','equipment_slot','secondary'));if r?'error' then raise exception '%',r;end if;
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',3));if r?'error' then raise exception '%',r;end if;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary'));if r?'error' then raise exception '%',r;end if;
end$$;
SQL
# Competing shots must be serialized: only one passes the fire interval.
for nonce in 2 3; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=eeeeeeee-7700-4000-8000-00000000000$nonce" >"/tmp/range-shot-$nonce.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-7700-4000-8000-000000000001',true);
select set_config('range.test_season',game_private.current_season()::text,true);
select set_config('range.test_session',id::text,true),set_config('range.test_elapsed',floor(extract(epoch from(clock_timestamp()-started_at))*1000)::int::text,true) from public.game_range_sessions where player_id=auth.uid();
set local role authenticated;
select public.range_action('fire',jsonb_build_object('season_id',current_setting('range.test_season'),'session_id',current_setting('range.test_session'),'request_id',:'nonce','elapsed_ms',current_setting('range.test_elapsed')::int,'x',0,'y',0));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-7700-4000-8000-000000000001';begin
 if (select count(*) from public.game_range_shots where player_id=u)<>1 or (select quantity from public.game_inventory_gear where player_id=u and equipment_slot='ammo')<>2 or (select condition from public.game_inventory_gear where player_id=u and equipment_slot='secondary')<>99 then raise exception 'Concurrent shots duplicated ammunition or weapon wear';end if;
end$$;
SQL
# Replay the successful request simultaneously; both return the same receipt.
for run in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/range-retry-$run.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-7700-4000-8000-000000000001',true);
select set_config('range.test_payload',payload::text,true) from game_private.range_requests where player_id=auth.uid() and action='fire';
set local role authenticated;
select public.range_action('fire',current_setting('range.test_payload')::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-7700-4000-8000-000000000001';begin
 if (select count(*) from public.game_range_shots where player_id=u)<>1 or (select quantity from public.game_inventory_gear where player_id=u and equipment_slot='ammo')<>2 or (select condition from public.game_inventory_gear where player_id=u and equipment_slot='secondary')<>99 then raise exception 'Retry duplicated a range shot';end if;
 if (select sum(delta) from public.game_inventory_ledger where player_id=u and gear_id=(select id from public.game_inventory_gear where player_id=u and equipment_slot='ammo'))<>2 then raise exception 'Ammo ledger does not equal remaining equipment';end if;
end$$;
select set_config('game.reason','Restore range defaults after CI concurrency test',false);
update public.game_settings set value=500 where key='range_fire_interval_ms';
update public.game_settings set value=1000 where key='range_lag_tolerance_ms';
select 'PASS: concurrent shots and retries preserve ammunition, condition and shot evidence';
SQL
