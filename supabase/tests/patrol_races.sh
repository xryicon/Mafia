#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-3100-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-3100-4000-8000-000000000001',false);
select public.game_state();
select public.scavenging_action('enter',jsonb_build_object('season_id',game_private.current_season(),'district_id',(select id from public.game_districts where slug='the-waterfront'),'request_id',gen_random_uuid()));
select public.scavenging_action('move',jsonb_build_object('season_id',game_private.current_season(),'node',(select (x->>'node')::int from game_private.scav_maps m cross join lateral jsonb_array_elements(m.targets)x where player_id=auth.uid() and x->>'kind'='bin' limit 1),'request_id',gen_random_uuid()));
update game_private.scav_sessions set arrives_at=clock_timestamp()-interval '1 second' where player_id=auth.uid();
select public.scavenging_action('search',jsonb_build_object('season_id',game_private.current_season(),'target_id',(select x->>'id' from game_private.scav_maps m cross join lateral jsonb_array_elements(m.targets)x join game_private.scav_sessions v on v.player_id=m.player_id and v.node=(x->>'node')::int where m.player_id=auth.uid() limit 1),'request_id','eeeeeeee-3100-4000-8000-000000000009'));
do $$declare v game_private.scav_sessions;point jsonb;t timestamptz:=clock_timestamp()-interval '3 seconds';begin
 select * into v from game_private.scav_sessions where player_id=auth.uid();if v.pending is null then raise exception 'Patrol race search not initialized';end if;point:=v.route_points->-1;
 update game_private.scav_sessions set pending=pending||jsonb_build_object('patrol_sentence_minutes',5,'started_at',t,'ready_at',t+interval '2 seconds','patrols',jsonb_build_array(jsonb_build_object('id','race-patrol','epoch',extract(epoch from t),'seconds_per_block',1,'radius',.2,'route_points',jsonb_build_array(point,jsonb_build_array(case when (point->>0)::int=4 then 3 else (point->>0)::int+1 end,point->1),point)))) where player_id=auth.uid();
end$$;
SQL
for action in read prison finish cancel; do
 psql -At -v ON_ERROR_STOP=1 -v "action=$action" >"/tmp/patrol-race-$action.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-3100-4000-8000-000000000001',true);
set local role authenticated;
select case when :'action'='read' then public.bin_diving_state() when :'action'='prison' then public.prison_state() else public.scavenging_action(:'action',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid(),'attempt_id','eeeeeeee-3100-4000-8000-000000000009')) end;
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select count(*) from game_private.scav_arrests where player_id='eeeeeeee-3100-4000-8000-000000000001')<>1 then raise exception 'Concurrent arrest duplicated or lost';end if;
 if(select count(*) from public.game_prison_sentences where player_id='eeeeeeee-3100-4000-8000-000000000001' and release_at>clock_timestamp())<>1 then raise exception 'Concurrent arrest sentence invalid';end if;
 if exists(select 1 from public.game_bin_dives where player_id='eeeeeeee-3100-4000-8000-000000000001') then raise exception 'Concurrent arrested search paid loot';end if;
end$$;
select 'PASS: concurrent read, prison refresh, collect and cancel create one arrest and no reward';
SQL
