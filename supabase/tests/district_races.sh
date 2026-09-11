#!/usr/bin/env bash
set -euo pipefail
# Only the disposable GitHub PostgreSQL service is permitted.
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-0000-4000-8000-000000000001'),('eeeeeeee-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000001',false);
select public.game_state();
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000002',false);
select public.game_state();
select set_config('game.reason','Disposable CI concurrency fixture',false);
update public.game_players set cash=100000 where id in('eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000002');
SQL
quote=$(psql -At -v ON_ERROR_STOP=1 -c "select jsonb_build_object('plot_id',p.id,'season_id',p.season_id,'version',p.version,'total',p.base_price+ceil(p.base_price*.03)) from public.game_district_plots p join public.game_districts d on d.id=p.district_id where d.slug='the-waterfront' and p.code='W10' and p.season_id=game_private.current_season()")
for player in 1 2; do
 psql -At -v ON_ERROR_STOP=1 -v "quote=$quote" -v "player=eeeeeeee-0000-4000-8000-00000000000$player" >"/tmp/district-race-$player.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'player',true);
set local role authenticated;
select public.district_action('buy',:'quote'::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$
declare p public.game_district_plots;
begin
 select x.* into p from public.game_district_plots x join public.game_districts d on d.id=x.district_id where d.slug='the-waterfront' and x.code='W10' and x.season_id=game_private.current_season();
 if (select count(*) from public.game_property_sales where plot_id=p.id)<>1 then raise exception 'Concurrent double-purchase prevention failed';end if;
 if (select count(*) from public.game_plot_ownership_history where plot_id=p.id)<>1 then raise exception 'Duplicate ownership transfer';end if;
 if (select sum(cash) from public.game_players where id in('eeeeeeee-0000-4000-8000-000000000001','eeeeeeee-0000-4000-8000-000000000002'))<>200000-p.base_price-ceil(p.base_price*.03) then raise exception 'Concurrent wallets failed conservation';end if;
end $$;
select 'PASS: two independent database connections race to buy the same plot; exactly one sale and one debit' as result;
SQL
