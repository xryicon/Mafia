#!/usr/bin/env bash
set -euo pipefail
# Independent CI players; real concurrent requests, no live credentials or assets.
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('game.reason','CI concurrent range completion and recovery',false);
update public.game_settings set value=1 where key='range_rounds';
update public.game_settings set value=2 where key='range_round_seconds';
update public.game_settings set value=0 where key in ('range_move_amplitude','range_move_vertical');
insert into auth.users(id) values('eeeeeeee-7800-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-7800-4000-8000-000000000001',false);
select public.game_state();
select set_config('range.test_season',game_private.current_season()::text,false);
insert into public.game_inventory(season_id,player_id,good_id,quantity) values(game_private.current_season(),auth.uid(),'homemade-pistol',1),(game_private.current_season(),auth.uid(),'homemade-bullets',10);
select public.inventory_action('equip',jsonb_build_object('season_id',current_setting('range.test_season'),'request_id',gen_random_uuid(),'item_key','good:homemade-pistol','equipment_slot','secondary'));
select public.inventory_action('equip',jsonb_build_object('season_id',current_setting('range.test_season'),'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',10));
SQL
for i in 1 2; do
psql -v ON_ERROR_STOP=1 > /tmp/range-start-$i.log <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-7800-4000-8000-000000000001',true);
select set_config('range.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.range_action('start',jsonb_build_object('season_id',current_setting('range.test_season'),'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','beginner'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('request.jwt.claim.sub','eeeeeeee-7800-4000-8000-000000000001',false);
do $$declare v public.game_range_sessions;r jsonb;begin
 if (select count(*) from public.game_range_sessions where player_id=auth.uid())<>1 then raise exception 'Concurrent starts created multiple sessions';end if;
 select * into v from public.game_range_sessions where player_id=auth.uid();
 r:=public.range_action('fire',jsonb_build_object('season_id',v.season_id,'request_id',gen_random_uuid(),'session_id',v.id,'x',50,'y',45,'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int));
 if r?'error' then raise exception 'Concurrent setup shot: %',r;end if;
end$$;
select pg_sleep(2.1);
SQL
for i in 1 2; do
psql -v ON_ERROR_STOP=1 > /tmp/range-finish-$i.log <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-7800-4000-8000-000000000001',true);
select set_config('range.test_session',id::text,true) from public.game_range_sessions where player_id=auth.uid();
select set_config('range.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.range_action('finish',jsonb_build_object('season_id',current_setting('range.test_season'),'request_id',gen_random_uuid(),'session_id',current_setting('range.test_session')));
select public.range_action('start',jsonb_build_object('season_id',current_setting('range.test_season'),'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','advanced'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-7800-4000-8000-000000000001';begin
 if (select count(*) from public.game_range_sessions where player_id=u)<>1 then raise exception 'Concurrent mode changes bypassed recovery';end if;
 if (select count(*) from game_private.range_xp_ledger where player_id=u)<>1 or (select xp from public.game_players where id=u)<>16 or (select xp_awarded from public.game_range_sessions where player_id=u)<>16 then raise exception 'Concurrent finish did not award exactly one completion';end if;
end$$;
select set_config('game.reason','Restore range defaults after CI reward race',false);
update public.game_settings set value=10 where key='range_rounds';
update public.game_settings set value=5 where key='range_round_seconds';
update public.game_settings set value=10 where key='range_move_amplitude';
update public.game_settings set value=8 where key='range_move_vertical';
select 'PASS: concurrent starts, completions and mode switching preserve XP and cooldown';
SQL
