#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
select set_config('game.reason','CI simultaneous robbery fixture',false);
update game_private.robbery_rules set bullet_min=3,bullet_max=3,min_chance=100,max_chance=100,version=1;
do $$declare u uuid;d uuid;s uuid:=game_private.current_season();i integer;begin
 select id into d from public.game_districts where slug='the-waterfront';
 for i in 1..3 loop
  u:=('eeeeeeee-7000-4000-8000-00000000000'||i)::uuid;
  insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
  insert into public.game_inventory_gear(season_id,player_id,good_id,quantity,location,equipment_slot) values(s,u,'homemade-pistol',1,'equipped','secondary'),(s,u,'homemade-bullets',100,'equipped','ammo');
  perform public.scavenging_action('enter',jsonb_build_object('season_id',s,'district_id',d,'request_id',gen_random_uuid()));perform public.bin_diving_state();
 end loop;
end$$;
SQL
pids=()
for attempt in 1 2 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "attempt=$attempt" >"/tmp/robbery-race-$attempt.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',case when :'attempt' in('1','2') then 'eeeeeeee-7000-4000-8000-000000000001' else 'eeeeeeee-7000-4000-8000-000000000002' end,true);
select set_config('robbery.test_season',game_private.current_season()::text,true);
select set_config('robbery.test_weapon',game_private.robbery_weapon(game_private.current_season(),auth.uid())->>'id',true);
set local role authenticated;
select public.robbery_action('attempt',jsonb_build_object('season_id',current_setting('robbery.test_season'),'weapon_id',current_setting('robbery.test_weapon'),'rules_version',1,'target_id','eeeeeeee-7000-4000-8000-000000000003','request_id',case when :'attempt' in('1','2') then 'eeeeeeee-7000-4000-8000-000000000009'::uuid else gen_random_uuid() end));
commit;
SQL
 pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid"; done
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare victim uuid:='eeeeeeee-7000-4000-8000-000000000003';begin
 if (select count(*) from game_private.robbery_attempts where victim_id=victim)<>1 then raise exception 'Concurrent attackers bypassed shared victim protection';end if;
 if (select sum(quantity) from public.game_inventory_gear where player_id in('eeeeeeee-7000-4000-8000-000000000001','eeeeeeee-7000-4000-8000-000000000002') and good_id='homemade-bullets')<>197 then raise exception 'Race consumed wrong ammunition';end if;
 if (select sum(cash) from public.game_players where id in('eeeeeeee-7000-4000-8000-000000000001','eeeeeeee-7000-4000-8000-000000000002',victim))<>(select starting_cash*3 from public.game_seasons where id=game_private.current_season()) then raise exception 'Robbery created or destroyed cash';end if;
end$$;
select set_config('game.reason','Restore normal robbery rules after CI race',false);
update game_private.robbery_rules set bullet_min=0,bullet_max=100,min_chance=5,max_chance=95;
select 'PASS: simultaneous attackers and duplicate retries resolve one robbery without creating money or over-consuming ammo';
SQL
