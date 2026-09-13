#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='ffffffff-9000-4000-8000-000000000001';s uuid;pid uuid;q jsonb;begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();s:=game_private.current_season();
 perform set_config('game.reason','CI crafting concurrency fixtures',true);update public.game_players set cash=10000 where id=u;
 update public.game_settings set value=300 where key='actions_per_minute';
 update public.game_storage_rules set capacity=2000,enabled=true where building_type='warehouse';
 select id into pid from public.game_district_plots where season_id=s and code='W26';
 q:=public.property_action('rent',jsonb_build_object('season_id',s,'plot_id',pid,'version',1,'rent',1500,'request_id',gen_random_uuid()));if q?'error' then raise exception 'Rent: %',q;end if;
 q:=public.property_action('install_station',jsonb_build_object('season_id',s,'plot_id',pid,'cost',500,'space',20,'request_id',gen_random_uuid()));if q?'error' then raise exception 'Station: %',q;end if;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'pistol_blueprint',2),(s,u,'iron-ingot',4),(s,u,'copper-ingot',2);
end$$;
SQL
# Distinct actions and an exact retry race to learn, reserve the last inputs and collect.
for action in learn start collect; do
 if [[ "$action" == collect ]]; then
 psql -v ON_ERROR_STOP=1 -c "update public.game_season_jobs set ready_at=clock_timestamp()-interval '1 second' where player_id='ffffffff-9000-4000-8000-000000000001';"
 fi
 pids=()
 for n in 1 2 1; do
 psql -At -v ON_ERROR_STOP=1 -v "action=$action" -v "nonce=ffffffff-9000-4000-8000-00000000000$n" >"/tmp/crafting-$action-$n-$RANDOM.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','ffffffff-9000-4000-8000-000000000001',true);
select set_config('craft.test.payload',jsonb_build_object('season_id',p.season_id,'recipe_id','homemade-pistol','version',1,'source','carried','batches',1,'building_id',b.id,'destination','carried',
'job_id',case when :'action'='collect' then (select id from public.game_season_jobs where player_id='ffffffff-9000-4000-8000-000000000001' and kind='crafting' order by ready_at limit 1) else null end,
'request_id',md5(:'nonce'||:'action')::uuid)::text,true)
from public.game_district_plots p join public.game_district_buildings b on b.plot_id=p.id where p.season_id=game_private.current_season() and p.code='W26';
set local role authenticated;
select public.crafting_action(:'action',current_setting('craft.test.payload')::jsonb);
commit;
SQL
 pids+=($!)
 done
 for pid in "${pids[@]}"; do wait "$pid"; done
done
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='ffffffff-9000-4000-8000-000000000001';s uuid:=game_private.current_season();begin
 if (select count(*) from public.game_learned_blueprints where player_id=u and season_id=s)<>1 then raise exception 'Learning failed or duplicated';end if;
 if (select quantity from public.game_inventory where player_id=u and season_id=s and good_id='pistol_blueprint')<>1 then raise exception 'Blueprint consumed twice';end if;
 if (select count(*) from public.game_season_jobs where player_id=u and status='completed')<>1 then raise exception 'Craft duplicated or failed';end if;
 if (select quantity from public.game_inventory where player_id=u and season_id=s and good_id='homemade-pistol')<>1 then raise exception 'Output duplicated or missing';end if;
 if (select sum(quantity) from public.game_inventory where player_id=u and season_id=s and good_id in('iron-ingot','copper-ingot'))<>0 then raise exception 'Material reservation wrong';end if;
 if (select count(*) from game_private.crafting_requests where player_id=u)<>3 then raise exception 'Unexpected successful request count';end if;
 if (select sum(delta) from public.game_inventory_ledger where player_id=u and good_id='homemade-pistol')<>1 then raise exception 'Output ledger wrong';end if;
end$$;
select 'PASS: concurrent blueprint learning, input reservations, completion and exact retries';
SQL
