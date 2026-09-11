#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
# Reuse the disposable players created by district_races.sh. Never run on production.
quote=$(psql -At -v ON_ERROR_STOP=1 -c "select jsonb_build_object('recipient',(select username from game_private.identities where player_id='eeeeeeee-0000-4000-8000-000000000002'),'subject','Concurrent delivery','body','One telegram, one charge','fee',b.telegram_fee,'season_id',o.season_id,'request_id','ffffffff-1111-4111-8111-111111111111') from public.game_telegram_office o join public.game_district_businesses b on b.id=o.business_id")
before=$(psql -At -v ON_ERROR_STOP=1 -c "select cash from public.game_players where id='eeeeeeee-0000-4000-8000-000000000001'")
for connection in 1 2; do
 psql -At -v ON_ERROR_STOP=1 -v "quote=$quote" >"/tmp/telegram-race-$connection.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.telegram_action('send',:'quote'::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 -v "before=$before" <<'SQL'
select set_config('test.telegram_before',:'before',false);
do $$
declare fee bigint;
begin
 select telegram_fee into fee from public.game_district_businesses where id=(select business_id from public.game_telegram_office);
 if (select count(*) from game_private.telegrams where request_id='ffffffff-1111-4111-8111-111111111111')<>1 then raise exception 'Concurrent retry created duplicate telegrams';end if;
 if (select cash from public.game_players where id='eeeeeeee-0000-4000-8000-000000000001')<>current_setting('test.telegram_before')::bigint-fee then raise exception 'Concurrent delivery double charged sender';end if;
 if (select count(*) from game_private.telegram_receipts r join game_private.telegrams m on m.id=r.message_id where m.request_id='ffffffff-1111-4111-8111-111111111111')<>1 then raise exception 'Concurrent receipt mismatch';end if;
end $$;
select 'PASS: two connections retry one telegram; one message, receipt and charge' as result;
SQL


# Group delivery must preserve the existing exactly-once payment behavior.
psql -v ON_ERROR_STOP=1 <<'SQL'
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000001',true);
do $$
declare r jsonb;t uuid;
begin
 r:=public.telegram_room_action('create','{"request_id":"ffffffff-2222-4222-8222-111111111111","name":"Concurrent group"}');
 if r?'error' then raise exception '%',r;end if;t:=(r->>'thread_id')::uuid;
 r:=public.telegram_room_action('invite',jsonb_build_object('request_id','ffffffff-2222-4222-8222-222222222222','thread_id',t,'username',(select username from game_private.identities where player_id='eeeeeeee-0000-4000-8000-000000000002')));
 if r?'error' then raise exception '%',r;end if;
 perform set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000002',true);
 r:=public.telegram_room_action('accept',jsonb_build_object('request_id','ffffffff-2222-4222-8222-333333333333','thread_id',t));
 if r?'error' then raise exception '%',r;end if;
end $$;
commit;
SQL
quote=$(psql -At -v ON_ERROR_STOP=1 -c "select jsonb_build_object('thread_id',(select thread_id from game_private.telegram_rooms where name='Concurrent group'),'body','Concurrent group delivery','fee',b.telegram_fee,'season_id',o.season_id,'request_id','ffffffff-3333-4333-8333-111111111111') from public.game_telegram_office o join public.game_district_businesses b on b.id=o.business_id")
before=$(psql -At -v ON_ERROR_STOP=1 -c "select cash from public.game_players where id='eeeeeeee-0000-4000-8000-000000000001'")
for connection in 1 2; do
 psql -At -v ON_ERROR_STOP=1 -v "quote=$quote" >"/tmp/telegram-group-race-$connection.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','eeeeeeee-0000-4000-8000-000000000001',true);
set local role authenticated;
select public.telegram_action('send',:'quote'::jsonb);
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 -v "before=$before" <<'SQL'
select set_config('test.telegram_before',:'before',false);
do $$
declare fee bigint;
begin
 select telegram_fee into fee from public.game_district_businesses where id=(select business_id from public.game_telegram_office);
 if (select count(*) from game_private.telegrams where request_id='ffffffff-3333-4333-8333-111111111111')<>1 then raise exception 'Concurrent group retry duplicated telegram';end if;
 if (select cash from public.game_players where id='eeeeeeee-0000-4000-8000-000000000001')<>current_setting('test.telegram_before')::bigint-fee then raise exception 'Concurrent group retry double charged';end if;
 if (select count(*) from game_private.telegram_deliveries d join game_private.telegrams m on m.id=d.message_id where m.request_id='ffffffff-3333-4333-8333-111111111111')<>1 then raise exception 'Group delivery receipt mismatch';end if;
end $$;
select 'PASS: concurrent group retries create one message, charge and delivery' as result;
SQL

