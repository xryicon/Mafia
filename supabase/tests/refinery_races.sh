#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid;n int;begin
 for n in 1..4 loop
  u:=('eeeeeeee-4000-4000-8000-00000000000'||n)::uuid;insert into auth.users(id) values(u);
  perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
  perform set_config('game.reason','CI refinery concurrency funding',true);update public.game_players set cash=100000 where id=u;
  insert into public.game_inventory(season_id,player_id,good_id,quantity) values(game_private.current_season(),u,'coal',10),(game_private.current_season(),u,'iron-ore',20);
 end loop;
end $$;
SQL
for player in 1 2; do
 psql -At -v ON_ERROR_STOP=1 -v "player=eeeeeeee-4000-4000-8000-00000000000$player" >"/tmp/refinery-buy-$player.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
select set_config('refinery.quote',(select jsonb_build_object('season_id',r.season_id,'refinery_id',r.id,'plot_version',1,'total',p.base_price+ceil(p.base_price*.03),'request_id',gen_random_uuid())::text from public.game_refineries r join public.game_district_plots p on p.id=r.plot_id where r.season_id=game_private.current_season()),true);
set local role authenticated;
select public.refinery_action('buy',current_setting('refinery.quote')::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare r public.game_refineries;p public.game_district_plots;res jsonb;begin
 select * into r from public.game_refineries where season_id=game_private.current_season();select * into p from public.game_district_plots where id=r.plot_id;
 if(select count(*) from public.game_property_sales where plot_id=p.id)<>1 then raise exception 'Double refinery purchase';end if;
 perform set_config('request.jwt.claim.sub',p.owner_id::text,true);
 res:=public.refinery_action('stock',jsonb_build_object('season_id',r.season_id,'refinery_id',r.id,'version',r.version,'plot_version',p.version,'request_id',gen_random_uuid(),'quantity',5,'good_id','coal'));
 if res?'error' then raise exception 'Cannot stock test refinery: %',res;end if;
end $$;
SQL
for player in 3 4 3; do
 psql -At -v ON_ERROR_STOP=1 -v "player=eeeeeeee-4000-4000-8000-00000000000$player" >"/tmp/refinery-order-$player-$RANDOM.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
select set_config('refinery.quote',(select jsonb_build_object('season_id',r.season_id,'refinery_id',r.id,'version',r.version,'plot_version',p.version,'recipe_id','iron','recipe_version',1,'batches',1,'request_id','eeeeeeee-4000-4000-8000-000000000010')::text from public.game_refineries r join public.game_district_plots p on p.id=r.plot_id where r.season_id=game_private.current_season()),true);
set local role authenticated;
select public.refinery_action('refine',current_setting('refinery.quote')::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare r uuid;begin
 select id into r from public.game_refineries where season_id=game_private.current_season();
 if(select count(*) from public.game_refinery_receipts where refinery_id=r)<>1 then raise exception 'Concurrent orders duplicated output';end if;
 if(select quantity from public.game_refinery_fuel where refinery_id=r and good_id='coal')<>0 then raise exception 'Fuel underflow or duplicated consumption';end if;
 if(select sum(quantity) from public.game_inventory where player_id in('eeeeeeee-4000-4000-8000-000000000003','eeeeeeee-4000-4000-8000-000000000004') and good_id='iron-ingot')<>10 then raise exception 'Wrong combined customer output';end if;
 if(select sum(quantity) from public.game_inventory where player_id in('eeeeeeee-4000-4000-8000-000000000003','eeeeeeee-4000-4000-8000-000000000004') and good_id='iron-ore')<>20 then raise exception 'Failed order consumed input';end if;
 if(select sum(cash) from public.game_players where id in('eeeeeeee-4000-4000-8000-000000000003','eeeeeeee-4000-4000-8000-000000000004'))<>199980 then raise exception 'Repeated charge';end if;
end $$;
select 'PASS: competing refinery purchases and concurrent/retried orders for the final fuel batch';
SQL

