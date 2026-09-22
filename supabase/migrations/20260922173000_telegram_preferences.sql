-- Account-level preferences and private, read-only automatic market receipts.
create table game_private.telegram_preferences(player_id uuid primary key references public.game_players(id),purchases boolean not null default true,sales boolean not null default true);
create table game_private.market_receipt_audience(thread_id uuid primary key references game_private.telegram_threads(id),player_id uuid not null references public.game_players(id));
alter table game_private.telegram_preferences enable row level security;
alter table game_private.market_receipt_audience enable row level security;
revoke all on game_private.telegram_preferences,game_private.market_receipt_audience from public,anon,authenticated;
create function public.telegram_preferences(p_preferences jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform game_private.require_active();
 if p_preferences is not null then
  if jsonb_typeof(p_preferences)<>'object' or jsonb_typeof(p_preferences->'purchases') is distinct from 'boolean' or jsonb_typeof(p_preferences->'sales') is distinct from 'boolean' then raise exception 'Choose purchase and sale alert preferences.';end if;
  insert into game_private.telegram_preferences(player_id,purchases,sales) values(auth.uid(),(p_preferences->>'purchases')::boolean,(p_preferences->>'sales')::boolean)
  on conflict(player_id) do update set purchases=excluded.purchases,sales=excluded.sales;
 end if;
 select jsonb_build_object('purchases',purchases,'sales',sales) into result from game_private.telegram_preferences where player_id=auth.uid();
 return coalesce(result,'{"purchases":true,"sales":true}'::jsonb);
end$$;
revoke all on function public.telegram_preferences(jsonb) from public,anon;
grant execute on function public.telegram_preferences(jsonb) to authenticated;

alter function game_private.telegram_access(uuid,uuid) rename to telegram_access_before_market_preferences;
create function game_private.telegram_access(p_thread uuid,p_player uuid) returns boolean language sql stable set search_path='' as $$
 select game_private.telegram_access_before_market_preferences(p_thread,p_player) and not exists(select 1 from game_private.market_receipt_audience where thread_id=p_thread and player_id<>p_player)
$$;
alter function game_private.telegram_player_threads(uuid) rename to telegram_player_threads_before_market_preferences;
create function game_private.telegram_player_threads(p_player uuid) returns setof uuid language sql stable set search_path='' as $$
 select t from game_private.telegram_player_threads_before_market_preferences(p_player) t where not exists(select 1 from game_private.market_receipt_audience a where a.thread_id=t and a.player_id<>p_player)
$$;
revoke all on function game_private.telegram_access(uuid,uuid),game_private.telegram_access_before_market_preferences(uuid,uuid),game_private.telegram_player_threads(uuid),game_private.telegram_player_threads_before_market_preferences(uuid) from public,anon,authenticated;

create or replace function game_private.market_trade_telegram(p_season uuid,p_buyer uuid,p_seller uuid,p_good text,p_quantity integer,p_total bigint,p_fee bigint,p_remaining integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare t uuid;item text;details text;recipient uuid;sender uuid;enabled boolean;is_purchase boolean;
begin
 select name into item from public.game_goods where id=p_good;
 details:=p_quantity||' '||coalesce(item,p_good)||E'\nTotal: $'||p_total||E'\nSeller fee: $'||p_fee||E'\nSeller receives: $'||(p_total-p_fee)||case when p_remaining is null then '' when p_remaining=0 then E'\nBuy order fulfilled.' else E'\nBuy order remaining: '||p_remaining||' items.' end;
 foreach recipient in array array[p_buyer,p_seller] loop
  is_purchase:=recipient=p_buyer;sender:=case when is_purchase then p_seller else p_buyer end;
  select case when is_purchase then purchases else sales end into enabled from game_private.telegram_preferences where player_id=recipient;
  if coalesce(enabled,true) then
   insert into game_private.telegram_threads(first_player,second_player,subject) values(sender,recipient,case when is_purchase then 'Market purchase completed' else 'Market sale completed' end) returning id into t;
   insert into game_private.market_receipt_audience values(t,recipient);
   insert into game_private.telegrams(thread_id,sender_id,recipient_id,body,season_id,request_id) values(t,sender,recipient,'AUTOMATIC MARKET RECEIPT'||E'\n\n'||case when is_purchase then 'You bought these items from ' else 'You sold these items to ' end||game_private.district_owner_name('player',sender)||E'.\n'||details||E'\n\nThis automatic alert has no delivery charge.',p_season,gen_random_uuid());
   insert into game_private.telegram_folders(player_id,thread_id,read_at) values(recipient,t,null);
  end if;
 end loop;
end$$;
-- Mark system receipts read-only and reject attempts to send messages into them.
alter function game_private.telegram_state(uuid,text,integer,uuid) rename to telegram_state_before_market_preferences;
create function game_private.telegram_state(p_thread uuid default null,p_folder text default 'inbox',p_offset integer default 0,p_before uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 result:=game_private.telegram_state_before_market_preferences(p_thread,p_folder,p_offset,p_before);
 if exists(select 1 from game_private.market_receipt_audience where thread_id=p_thread) and result->'thread'<>'null'::jsonb then result:=jsonb_set(result,'{thread,can_send}','false');end if;
 return result;
end$$;
alter function game_private.telegram_action(text,jsonb) rename to telegram_action_before_market_preferences;
create function game_private.telegram_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_action='send' and exists(select 1 from game_private.market_receipt_audience where thread_id::text=p_payload->>'thread_id') then return jsonb_build_object('error','Automatic market receipts are read-only. Start a new Telegram to contact the player.');end if;
 return game_private.telegram_action_before_market_preferences(p_action,p_payload);
end$$;
revoke all on function game_private.telegram_state_before_market_preferences(uuid,text,integer,uuid),game_private.telegram_action_before_market_preferences(text,jsonb),game_private.telegram_state(uuid,text,integer,uuid),game_private.telegram_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.telegram_state(uuid,text,integer,uuid),game_private.telegram_action(text,jsonb) to authenticated;
