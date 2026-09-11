#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-2000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-2000-4000-8000-000000000001',false);
select public.game_state();
insert into public.game_mining_tools(season_id,player_id,durability) values(game_private.current_season(),auth.uid(),game_private.setting('mining_pickaxe_durability'));
SQL
for attempt in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/mining-start-$attempt.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-2000-4000-8000-000000000001',true);
select set_config('mining.test_id',(select m.id::text from public.game_mines m join public.game_district_plots p on p.id=m.plot_id where p.code='MQ-01' and m.season_id=game_private.current_season()),true);
set local role authenticated;
select public.mining_action('start',jsonb_build_object('season_id',game_private.current_season(),'mine_id',current_setting('mining.test_id'),'request_id','eeeeeeee-2000-4000-8000-000000000002'));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
 if (select count(*) from public.game_mining_runs where player_id='eeeeeeee-2000-4000-8000-000000000001')<>1 then raise exception 'Duplicate shift in start race';end if;
 if (select durability from public.game_mining_tools where player_id='eeeeeeee-2000-4000-8000-000000000001')<>game_private.setting('mining_pickaxe_durability')-1 then raise exception 'Race consumed extra pickaxe condition';end if;
 if (select sum(quantity) from public.game_mining_runs where player_id='eeeeeeee-2000-4000-8000-000000000001')<>4 then raise exception 'Race reserved wrong quantity';end if;
end $$;
update public.game_mining_runs set ready_at=clock_timestamp()-interval '1 second' where player_id='eeeeeeee-2000-4000-8000-000000000001';
SQL
for attempt in 1 2; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/mining-claim-$attempt.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-2000-4000-8000-000000000001',true);
select set_config('mining.test_run',(select id::text from public.game_mining_runs where player_id=auth.uid()),true);
select set_config('mining.test_id',(select mine_id::text from public.game_mining_runs where player_id=auth.uid()),true);
set local role authenticated;
select public.mining_action('claim',jsonb_build_object('season_id',game_private.current_season(),'mine_id',current_setting('mining.test_id'),'run_id',current_setting('mining.test_run'),'request_id',gen_random_uuid()));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
 if (select quantity from public.game_inventory where player_id='eeeeeeee-2000-4000-8000-000000000001' and good_id='iron-ore' and season_id=game_private.current_season()) is distinct from 4 then raise exception 'Claim race duplicated or lost resources';end if;
 if (select count(*) from public.game_mining_yields where player_id='eeeeeeee-2000-4000-8000-000000000001')<>1 then raise exception 'Claim race duplicated extraction ledger';end if;
end $$;
select 'PASS: concurrent mining start retries and different claim requests grant exactly one reward';
SQL

# Two different players compete for the final six units of the same public deposit.
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-2000-4000-8000-000000000003');
select set_config('request.jwt.claim.sub','eeeeeeee-2000-4000-8000-000000000003',false);
select public.game_state();
insert into public.game_mining_tools(season_id,player_id,durability) values(game_private.current_season(),auth.uid(),game_private.setting('mining_pickaxe_durability'));
update public.game_mines m set remaining=6 where m.season_id=game_private.current_season() and exists(select 1 from public.game_district_plots p where p.id=m.plot_id and p.code='MQ-10');
SQL
for player in 1 3; do
 psql -At -v ON_ERROR_STOP=1 -v "player=eeeeeeee-2000-4000-8000-00000000000$player" >"/tmp/mining-final-reserve-$player.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
select set_config('mining.test_id',(select m.id::text from public.game_mines m join public.game_district_plots p on p.id=m.plot_id where p.code='MQ-10' and m.season_id=game_private.current_season()),true);
set local role authenticated;
select public.mining_action('start',jsonb_build_object('season_id',game_private.current_season(),'mine_id',current_setting('mining.test_id'),'request_id',gen_random_uuid()));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$
begin
 if (select m.remaining from public.game_mines m join public.game_district_plots p on p.id=m.plot_id where p.code='MQ-10' and m.season_id=game_private.current_season()) is distinct from 0::bigint then raise exception 'Final resource race did not exhaust exactly six units';end if;
 if (select count(*) from public.game_mining_runs r join public.game_district_plots p on p.id=(select plot_id from public.game_mines where id=r.mine_id) where p.code='MQ-10' and r.season_id=game_private.current_season())<>1 then raise exception 'Final resources promised to more than one player';end if;
end $$;
select 'PASS: competing players cannot double-reserve an exhausted deposit';
SQL
