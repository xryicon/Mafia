#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid;begin
 for u in select x::uuid from unnest(array['eeeeeeee-8000-4000-8000-000000000001','eeeeeeee-8000-4000-8000-000000000002'])x loop
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();perform set_config('game.reason','CI concurrent city rental funding',true);update public.game_players set cash=10000 where id=u;
 end loop;
 perform public.district_state('the-waterfront');
 update public.game_storage_rules set capacity=200,enabled=true where building_type='garage';
end$$;
SQL
# Distinct tenants and an exact retry compete for one city garage.
pids=()
for player in 1 2 1; do
 psql -At -v ON_ERROR_STOP=1 -v "player=eeeeeeee-8000-4000-8000-00000000000$player" >"/tmp/property-rent-$player-$RANDOM.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
select set_config('property.test.payload',jsonb_build_object('season_id',p.season_id,'plot_id',p.id,'version',t.version,'rent',t.rent,'request_id',:'player')::text,true)
 from public.game_district_plots p join public.game_property_lease_terms t on t.template_id=p.template_id where p.season_id=game_private.current_season() and p.code='W25';
set local role authenticated;
select public.property_action('rent',current_setting('property.test.payload')::jsonb);
commit;
SQL
 pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare n int;begin
 select count(*) into n from public.game_property_leases where player_id in('eeeeeeee-8000-4000-8000-000000000001','eeeeeeee-8000-4000-8000-000000000002') and released_at is null;
 if n<>1 then raise exception 'City garage double leased';end if;
 if (select sum(cash) from public.game_players where id in('eeeeeeee-8000-4000-8000-000000000001','eeeeeeee-8000-4000-8000-000000000002'))<>19700 then raise exception 'City rent double charged or lost';end if;
 if (select count(*) from game_private.property_requests where player_id in('eeeeeeee-8000-4000-8000-000000000001','eeeeeeee-8000-4000-8000-000000000002'))<>1 then raise exception 'Duplicate rent request committed';end if;
end$$;
select 'PASS: concurrent city leases and exact retry charge once';
SQL
