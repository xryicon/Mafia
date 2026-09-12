-- National Bank: additive, seasonal accounts. No existing money is moved.
insert into public.game_settings(key,value,minimum,maximum) values
 ('bank_deposits_enabled',1,0,1),('bank_max_transfer',1000000000,1,2000000000);

create table public.game_bank_accounts(
 season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),
 balance bigint not null default 0 check(balance between 0 and 9007199254740991),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(season_id,player_id)
);
create index bank_account_player on public.game_bank_accounts(player_id);
create table public.game_bank_ledger(
 id uuid primary key default gen_random_uuid(),
 season_id uuid not null,player_id uuid not null,request_id uuid not null,
 delta bigint not null check(delta<>0),balance_before bigint not null,balance_after bigint not null,
 cash_after bigint not null,created_at timestamptz not null default clock_timestamp(),
 foreign key(season_id,player_id) references public.game_bank_accounts(season_id,player_id),
 check(balance_before+delta=balance_after and balance_after>=0 and cash_after>=0),
 unique(season_id,player_id,request_id)
);
create index bank_ledger_player_time on public.game_bank_ledger(player_id,season_id,created_at desc,id);
create table game_private.bank_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(season_id,player_id,request_id)
);
create index bank_request_player on game_private.bank_requests(player_id);
alter table public.game_bank_accounts enable row level security;
alter table public.game_bank_ledger enable row level security;
alter table game_private.bank_requests enable row level security;
revoke all on public.game_bank_accounts,public.game_bank_ledger,game_private.bank_requests from public,anon,authenticated;
create trigger bank_accounts_retain before delete or truncate on public.game_bank_accounts for each statement execute function game_private.district_immutable();
create trigger bank_ledger_immutable before update or delete or truncate on public.game_bank_ledger for each statement execute function game_private.district_immutable();
create trigger bank_requests_immutable before update or delete or truncate on game_private.bank_requests for each statement execute function game_private.district_immutable();

-- Every deposit balance change automatically creates its matching immutable entry.
create function game_private.bank_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare nonce uuid;
begin
 if TG_OP='INSERT' then
  if new.balance<>0 then raise exception 'Bank accounts must open empty.';end if;return new;
 end if;
 if new.season_id<>old.season_id or new.player_id<>old.player_id then raise exception 'Bank account identity cannot change.';end if;
 if new.balance<>old.balance then
  nonce:=nullif(current_setting('game.bank_request_id',true),'')::uuid;
  if nonce is null then raise exception 'A bank transfer reference is required.';end if;
  insert into public.game_bank_ledger(season_id,player_id,request_id,delta,balance_before,balance_after,cash_after)
   select new.season_id,new.player_id,nonce,new.balance-old.balance,old.balance,new.balance,cash from public.game_players where id=new.player_id;
 end if;
 return new;
end $$;
create trigger bank_entry after insert or update on public.game_bank_accounts for each row execute function game_private.bank_entry();

create function game_private.bank_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();v_offset integer:=greatest(0,least(coalesce(p_offset,0),1000000));
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid) then perform game_private.state();end if;
 return jsonb_build_object(
  'season',(select to_jsonb(x) from public.game_seasons x where id=s),'server_time',clock_timestamp(),
  'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
  'player',(select jsonb_build_object('id',id,'handle',handle,'cash',cash) from public.game_players where id=uid),
  'balance',coalesce((select balance from public.game_bank_accounts where season_id=s and player_id=uid),0),
  'opened_at',(select created_at from public.game_bank_accounts where season_id=s and player_id=uid),
  'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'bank_%'),
  'can_manage',game_private.has_permission('economy.manage'),
  'offset',v_offset,'page_size',10,
  'total',(select count(*) from public.game_bank_ledger where player_id=uid and season_id=s),
  'history',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]') from
   (select id,delta,balance_after,cash_after,created_at from public.game_bank_ledger where player_id=uid and season_id=s order by created_at desc,id desc limit 10 offset v_offset) x),
  'totals',(select jsonb_build_object('deposited',coalesce(sum(delta) filter(where delta>0),0),'withdrawn',coalesce(-sum(delta) filter(where delta<0),0),'transfers',count(*)) from public.game_bank_ledger where player_id=uid and season_id=s),
  'flow',(select jsonb_agg(x order by x.day) from (
   select to_char(d.day,'YYYY-MM-DD') day,coalesce(sum(l.delta) filter(where l.delta>0),0) deposits,coalesce(-sum(l.delta) filter(where l.delta<0),0) withdrawals
   from (select (clock_timestamp() at time zone 'UTC')::date-6+n day from generate_series(0,6) n) d
   left join public.game_bank_ledger l on l.player_id=uid and l.season_id=s and l.created_at>=(d.day::timestamp at time zone 'UTC') and l.created_at<((d.day+1)::timestamp at time zone 'UTC')
   group by d.day) x)
 );
end $$;

create function game_private.bank_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();s uuid;nonce uuid;prior game_private.bank_requests;amount numeric;delta bigint;entry public.game_bank_ledger;result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid transfer details.';end if;
  if p_action not in ('deposit','withdraw') or p_action is null then raise exception 'Choose deposit or withdrawal.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the bank.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A transfer reference is required.';end if;
  -- Same wallet lock as other economic actions, then account; serializes retries and competing spends.
  perform 1 from public.game_players where id=uid and season_id=s for update;
  if not found then raise exception 'Open your dashboard to initialize this season.';end if;
  select * into prior from game_private.bank_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This transfer reference was already used.';end if;
   return prior.result;
  end if;
  perform game_private.season_guard();
  if p_action='deposit' and game_private.setting('bank_deposits_enabled')<>1 then raise exception 'New deposits are paused. Withdrawals remain available.';end if;
  if jsonb_typeof(p_payload->'amount') is distinct from 'number' then raise exception 'Enter a whole-dollar amount.';end if;
  amount:=(p_payload->>'amount')::numeric;
  if amount<>trunc(amount) or amount<1 or amount>game_private.setting('bank_max_transfer') then raise exception 'Amount is outside the bank transfer limit.';end if;
  insert into public.game_bank_accounts(season_id,player_id) values(s,uid) on conflict do nothing;
  perform 1 from public.game_bank_accounts where season_id=s and player_id=uid for update;
  delta:=case when p_action='deposit' then amount::bigint else -amount::bigint end;
  if delta<0 and (select balance from public.game_bank_accounts where season_id=s and player_id=uid)<amount then raise exception 'Not enough money in your bank account.';end if;
  perform set_config('game.bank_request_id',nonce::text,true);
  perform game_private.district_wallet(uid,-delta,'National Bank '||p_action||': '||nonce);
  update public.game_bank_accounts set balance=balance+delta,updated_at=clock_timestamp() where season_id=s and player_id=uid;
  select * into strict entry from public.game_bank_ledger where season_id=s and player_id=uid and request_id=nonce;
  result:=jsonb_build_object('message',case when delta>0 then 'Deposit complete. Your money is in the bank.' else 'Withdrawal complete. Your money is in your wallet.' end,'receipt',to_jsonb(entry));
  insert into game_private.bank_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then
  return jsonb_build_object('error','Check the transfer amount and refresh your balances.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;
create function public.bank_state(p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select game_private.bank_state(p_offset)$$;
create function public.bank_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.bank_action(p_action,p_payload)$$;
revoke all on function game_private.bank_entry(),game_private.bank_state(integer),game_private.bank_action(text,jsonb),public.bank_state(integer),public.bank_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.bank_state(integer),game_private.bank_action(text,jsonb),public.bank_state(integer),public.bank_action(text,jsonb) to authenticated;

-- Stored money remains part of net worth; cash rankings continue to show wallet cash.
-- Previous-season accounts remain intact and a new season naturally starts at zero.
do $$ declare definition text;begin
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as asset_value,' in definition)=0 then raise exception 'Review bank net-worth integration';end if;
 execute replace(definition,' as asset_value,',
 ' +coalesce((select ba.balance::numeric from public.game_bank_accounts ba where ba.season_id=p_season and ba.player_id=sp.player_id),0) as asset_value,');
end $$;
notify pgrst,'reload schema';
