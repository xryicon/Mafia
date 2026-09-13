#!/usr/bin/env bash
set -euo pipefail
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('cccccccc-6000-4000-8000-000000000001'),('cccccccc-6000-4000-8000-000000000002'),('cccccccc-6000-4000-8000-000000000003');
select set_config('request.jwt.claim.sub','cccccccc-6000-4000-8000-000000000001',false);select public.game_state();
select public.gang_action('create',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid(),'name','Concurrent Family A'));
select public.gang_action('deposit',jsonb_build_object('season_id',game_private.current_season(),'gang_id',(select gang_id from public.game_season_gang_members where player_id=auth.uid() and season_id=game_private.current_season()),'request_id',gen_random_uuid(),'amount',2000));
select set_config('request.jwt.claim.sub','cccccccc-6000-4000-8000-000000000002',false);select public.game_state();
select public.gang_action('create',jsonb_build_object('season_id',game_private.current_season(),'request_id',gen_random_uuid(),'name','Concurrent Family B'));
select set_config('request.jwt.claim.sub','cccccccc-6000-4000-8000-000000000003',false);select public.game_state();
select public.gang_action('request_join',jsonb_build_object('season_id',game_private.current_season(),'gang_id',id,'request_id',gen_random_uuid())) from public.game_season_gangs where name in('Concurrent Family A','Concurrent Family B');
SQL
# Duplicate withdrawal requests must create one credit and one statement entry.
pids=()
for n in 1 2; do
 psql -v ON_ERROR_STOP=1 >"/tmp/gang-retry-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','cccccccc-6000-4000-8000-000000000001',true);
select set_config('test.gang',gang_id::text,true) from public.game_season_gang_members where player_id=auth.uid() and season_id=game_private.current_season();
select set_config('test.season',game_private.current_season()::text,true);
set local role authenticated;
select public.gang_action('withdraw',jsonb_build_object('season_id',current_setting('test.season'),'gang_id',current_setting('test.gang'),'request_id','cccccccc-6000-4000-8000-000000000004','amount',1000));
commit;
SQL
 pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
# Two different deposits must not spend the same wallet twice.
pids=()
for n in 5 6; do
 psql -v ON_ERROR_STOP=1 -v "nonce=cccccccc-6000-4000-8000-00000000000$n" >"/tmp/gang-spend-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','cccccccc-6000-4000-8000-000000000001',true);
select set_config('test.gang',gang_id::text,true) from public.game_season_gang_members where player_id=auth.uid() and season_id=game_private.current_season();
select set_config('test.season',game_private.current_season()::text,true);
set local role authenticated;
select public.gang_action('deposit',jsonb_build_object('season_id',current_setting('test.season'),'gang_id',current_setting('test.gang'),'request_id',:'nonce','amount',7000));
commit;
SQL
 pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
# Two gang leaders race to accept the same applicant.
pids=()
for n in 1 2; do
 psql -v ON_ERROR_STOP=1 -v "actor=cccccccc-6000-4000-8000-00000000000$n" >"/tmp/gang-accept-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub',:'actor',true);
select set_config('test.gang',gang_id::text,true) from public.game_season_gang_members where player_id=auth.uid() and season_id=game_private.current_season();
select set_config('test.application',id::text,true) from game_private.gang_join_requests where gang_id=current_setting('test.gang')::uuid and player_id='cccccccc-6000-4000-8000-000000000003';
select set_config('test.season',game_private.current_season()::text,true);
set local role authenticated;
select public.gang_action('accept',jsonb_build_object('season_id',current_setting('test.season'),'gang_id',current_setting('test.gang'),'request_id',gen_random_uuid(),'application_id',current_setting('test.application')));
commit;
SQL
 pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$declare g uuid;begin
select id into g from public.game_season_gangs where name='Concurrent Family A';
if(select cash from public.game_players where id='cccccccc-6000-4000-8000-000000000001')<>1000 then raise exception 'Concurrent gang wallet mismatch';end if;
if(select balance from game_private.gang_accounts where gang_id=g)<>8000 then raise exception 'Concurrent gang bank mismatch';end if;
if(select count(*) from game_private.gang_ledger where gang_id=g)<>3 then raise exception 'Concurrent ledger duplicate';end if;
if(select count(*) from public.game_ledger where player_id='cccccccc-6000-4000-8000-000000000001' and reason like 'Gang bank %')<>3 then raise exception 'Wallet entries missing';end if;
if(select count(*) from public.game_season_gang_members where player_id='cccccccc-6000-4000-8000-000000000003')<>1 then raise exception 'Applicant joined two gangs';end if;
if(select count(*) from game_private.gang_join_requests where player_id='cccccccc-6000-4000-8000-000000000003' and status='accepted')<>1 then raise exception 'Duplicate acceptance';end if;
end$$;
select 'PASS: concurrent gang withdrawal retries, competing deposits and competing join approvals';
SQL
