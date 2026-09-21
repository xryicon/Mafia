#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('eeeeeeee-6900-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-6900-4000-8000-000000000001',false);
select public.game_state();
select set_config('game.reason','CI concurrent bandage fixture',false);
update public.game_settings set value=20 where key='bandage_heal_amount';
update public.game_season_players set health=40 where player_id=auth.uid() and season_id=game_private.current_season();
insert into public.game_inventory(season_id,player_id,good_id,quantity) values(game_private.current_season(),auth.uid(),'bandages',1);
SQL
pids=()
for attempt in 1 2 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "attempt=$attempt" >"/tmp/bandage-race-$attempt.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-6900-4000-8000-000000000001',true);
select set_config('bandage.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.inventory_action('use_bandage',jsonb_build_object('season_id',current_setting('bandage.test_season'),'item_key','good:bandages','request_id',case when :'attempt' in ('1','2') then 'eeeeeeee-6900-4000-8000-000000000002'::uuid else gen_random_uuid() end));
commit;
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare u uuid:='eeeeeeee-6900-4000-8000-000000000001';s uuid:=game_private.current_season();begin
 if (select health from public.game_season_players where season_id=s and player_id=u)<>60 then raise exception 'Concurrent uses duplicated healing';end if;
 if (select quantity from public.game_inventory where season_id=s and player_id=u and good_id='bandages')<>0 then raise exception 'Concurrent uses corrupted stock';end if;
 if (select count(*) from game_private.inventory_requests where season_id=s and player_id=u and action='use_bandage')<>1 then raise exception 'More than one bandage use succeeded';end if;
 if (select count(*) from public.game_inventory_ledger where season_id=s and player_id=u and good_id='bandages' and delta=-1)<>1 then raise exception 'Consumption ledger duplicated';end if;
end$$;
select 'PASS: concurrent distinct requests and duplicate retries consume one bandage and heal once';
SQL
