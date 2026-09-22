#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-3200-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-3200-4000-8000-000000000001',false);
select public.game_state();
select set_config('game.reason','CI vehicle concurrency fixtures',false);
update public.game_settings set value=100 where key='scavenging_theft_success_percent';
insert into public.game_inventory(season_id,player_id,good_id,quantity) values(game_private.current_season(),auth.uid(),'lockpick',2);
select public.scavenging_action('enter',jsonb_build_object('season_id',game_private.current_season(),'district_id',(select id from public.game_districts where slug='the-waterfront'),'request_id',gen_random_uuid()));
do $$declare car jsonb;begin
 select x into car from game_private.scav_maps m cross join lateral jsonb_array_elements(m.targets)x where player_id=auth.uid() and x->>'kind'='car' limit 1;
 update game_private.scav_sessions set node=(car->>'node')::int,route_points=jsonb_build_array(jsonb_build_array((car->>'node')::int%5,(car->>'node')::int/5)),arrives_at=clock_timestamp()-interval '1 second' where player_id=auth.uid();
end$$;
SQL
for i in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/street-start-$i.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3200-4000-8000-000000000001',true);
select public.scavenging_action('steal',jsonb_build_object('season_id',game_private.current_season(),'request_id','eeeeeeee-3200-4000-8000-000000000009','target_id',(select x->>'id' from game_private.scav_maps m cross join lateral jsonb_array_elements(m.targets)x join game_private.scav_sessions v on v.player_id=m.player_id and v.node=(x->>'node')::int where m.player_id=auth.uid() and x->>'kind'='car' limit 1)));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select quantity from public.game_inventory where player_id='eeeeeeee-3200-4000-8000-000000000001' and good_id='lockpick')<>1 then raise exception 'Concurrent theft duplicated tool consumption';end if;
 update game_private.scav_sessions set pending=jsonb_set(pending,'{ready_at}',to_jsonb(clock_timestamp()-interval '1 second')) where player_id='eeeeeeee-3200-4000-8000-000000000001';
end$$;
SQL
for i in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/street-finish-$i.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3200-4000-8000-000000000001',true);
set local role authenticated;
select public.scavenging_action('finish',jsonb_build_object('season_id',game_private.current_season(),'request_id','eeeeeeee-3200-4000-8000-000000000010','attempt_id','eeeeeeee-3200-4000-8000-000000000009'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select count(*) from game_private.street_vehicles where player_id='eeeeeeee-3200-4000-8000-000000000001')<>1 then raise exception 'Concurrent collection lost or duplicated car';end if;
 update game_private.scav_sessions set route_points='[[0,0]]',arrives_at=clock_timestamp()-interval '1 second',pursuit=jsonb_set(pursuit,'{started_at}',to_jsonb(clock_timestamp()-interval '10 seconds')) where player_id='eeeeeeee-3200-4000-8000-000000000001';
end$$;
SQL
for i in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/street-sale-$i.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3200-4000-8000-000000000001',true);
set local role authenticated;
select public.scavenging_action('escape',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid()));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select count(*) from public.game_ledger where player_id='eeeeeeee-3200-4000-8000-000000000001' and reason like 'Stolen vehicle sale:%')<>1 then raise exception 'Concurrent getaway duplicated or lost ledger credit';end if;
 if not exists(select 1 from game_private.street_vehicles where player_id='eeeeeeee-3200-4000-8000-000000000001' and status='sold') then raise exception 'Concurrent getaway failed to sell car';end if;
 if(select sum(delta) from game_private.skill_xp_ledger where player_id='eeeeeeee-3200-4000-8000-000000000001' and skill_id='lockpicking')<>60 then raise exception 'Concurrent theft XP duplicated';end if;
end$$;
select set_config('game.reason','Restore theft balance after CI concurrency fixtures',false);
update public.game_settings set value=55 where key='scavenging_theft_success_percent';
select 'PASS: concurrent theft, collection and getaway award one car and one ledger credit';
SQL
