#!/usr/bin/env bash
set -euo pipefail
test "${CI:-}" = "true" && test "${PGHOST:-}" = "localhost" && test "${PGDATABASE:-}" = "postgres"
psql -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users(id) values('bbbbbbbb-5000-4000-8000-000000000001');
begin;
select set_config('request.jwt.claim.sub','bbbbbbbb-5000-4000-8000-000000000001',true);
select public.game_state();
select set_config('game.reason','CI bank concurrency funding',true);
update public.game_players set cash=10000 where id='bbbbbbbb-5000-4000-8000-000000000001';
commit;
SQL
# Identical concurrent requests must yield one receipt.
for n in 1 2 3; do
 psql -At -v ON_ERROR_STOP=1 >"/tmp/bank-retry-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','bbbbbbbb-5000-4000-8000-000000000001',true);
select set_config('bank.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.bank_action('deposit',jsonb_build_object('season_id',current_setting('bank.test_season'),'request_id','bbbbbbbb-5000-4000-8000-000000000002','amount',8000));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select balance from public.game_bank_accounts where player_id='bbbbbbbb-5000-4000-8000-000000000001')<>8000 then raise exception 'Repeated deposit';end if;
 if(select cash from public.game_players where id='bbbbbbbb-5000-4000-8000-000000000001')<>2000 then raise exception 'Repeated wallet debit';end if;
 if(select count(*) from public.game_bank_ledger where player_id='bbbbbbbb-5000-4000-8000-000000000001')<>1 then raise exception 'Repeated receipt';end if;
end$$;
SQL
# Distinct withdrawals compete for the same final money.
for n in 3 4; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=bbbbbbbb-5000-4000-8000-00000000000$n" >"/tmp/bank-withdraw-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','bbbbbbbb-5000-4000-8000-000000000001',true);
select set_config('bank.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.bank_action('withdraw',jsonb_build_object('season_id',current_setting('bank.test_season'),'request_id',:'nonce','amount',7000));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select balance from public.game_bank_accounts where player_id='bbbbbbbb-5000-4000-8000-000000000001')<>1000 then raise exception 'Concurrent withdrawal overdraft';end if;
 if(select cash from public.game_players where id='bbbbbbbb-5000-4000-8000-000000000001')<>9000 then raise exception 'Concurrent withdrawal duplicated credit';end if;
end$$;
SQL
# Different deposits compete for the same cash.
for n in 5 6; do
 psql -At -v ON_ERROR_STOP=1 -v "nonce=bbbbbbbb-5000-4000-8000-00000000000$n" >"/tmp/bank-deposit-$n.txt" <<'SQL' &
begin;
select set_config('request.jwt.claim.sub','bbbbbbbb-5000-4000-8000-000000000001',true);
select set_config('bank.test_season',game_private.current_season()::text,true);
set local role authenticated;
select public.bank_action('deposit',jsonb_build_object('season_id',current_setting('bank.test_season'),'request_id',:'nonce','amount',8000));
commit;
SQL
done
wait
psql -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if(select balance from public.game_bank_accounts where player_id='bbbbbbbb-5000-4000-8000-000000000001')<>9000 then raise exception 'Concurrent deposit double spend';end if;
 if(select cash from public.game_players where id='bbbbbbbb-5000-4000-8000-000000000001')<>1000 then raise exception 'Wallet overdraft';end if;
 if(select count(*) from public.game_bank_ledger where player_id='bbbbbbbb-5000-4000-8000-000000000001')<>3 then raise exception 'Concurrent bank ledger mismatch';end if;
 if(select count(*) from public.game_ledger where player_id='bbbbbbbb-5000-4000-8000-000000000001' and reason like 'National Bank %')<>3 then raise exception 'Concurrent wallet ledger mismatch';end if;
end$$;
select 'PASS: concurrent bank retries, withdrawals, deposits, paired ledgers and conserved funds';
SQL
