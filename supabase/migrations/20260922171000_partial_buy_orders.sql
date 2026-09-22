-- Support independently funded partial fills, with safe request replay.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Enable partial player buy orders',true);
alter table public.game_district_buy_orders add column remaining_quantity integer;
update public.game_district_buy_orders set remaining_quantity=case when status='open' then quantity else 0 end;
alter table public.game_district_buy_orders alter column remaining_quantity set not null;
alter table public.game_district_buy_orders add constraint buy_order_remaining check(remaining_quantity between 0 and quantity);
alter table public.game_district_trades drop constraint game_district_trades_buy_order_id_key;
create index district_trade_buy_order on public.game_district_trades(buy_order_id) where buy_order_id is not null;
create table game_private.buy_order_requests(
 player_id uuid not null references public.game_players(id),request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 primary key(player_id,request_id)
);
alter table game_private.buy_order_requests enable row level security;
revoke all on game_private.buy_order_requests from public,anon,authenticated;
create trigger buy_order_requests_retain before update or delete or truncate on game_private.buy_order_requests for each statement execute function game_private.district_immutable();
create or replace function game_private.district_market_order(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; d uuid; o public.game_district_buy_orders; qty integer; price integer; total bigint; fee bigint; nonce uuid; prior game_private.buy_order_requests; result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again shortly.'); end if;
 begin
 s:=game_private.season_guard();
 if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the market.'; end if;
 perform pg_advisory_xact_lock(4704020);
 nonce:=nullif(p_payload->>'request_id','')::uuid;
 if nonce is not null then
  select * into prior from game_private.buy_order_requests where player_id=auth.uid() and request_id=nonce;
  if found then
   if prior.action<>p_action or prior.payload<>p_payload then raise exception 'This request reference was already used.';end if;
   return prior.result;
  end if;
 end if;
 if p_action='fill' and p_payload?'quantity' and nonce is null then raise exception 'A request reference is required for partial sales.';end if;
 if p_action='create' then d:=(p_payload->>'district_id')::uuid;
 else
  select * into o from public.game_district_buy_orders where id=(p_payload->>'order_id')::uuid and season_id=s and status='open' for update;
  if o.id is null then raise exception 'This order is no longer open.'; end if;
  d:=o.district_id;
 end if;
 if p_action<>'cancel' and not exists(select 1 from public.game_districts where id=d and archived_at is null and status<>'lockdown'
 and not exists(select 1 from public.game_district_territory where season_id=s and district_id=d and status='lockdown')) then raise exception 'The district exchange is unavailable.'; end if;
 perform id from public.game_players where id in(auth.uid(),o.buyer_id) order by id for update;
 perform set_config('game.reason','District buy order: '||p_action,true);
 case p_action
 when 'create' then
  qty:=(p_payload->>'quantity')::integer;price:=(p_payload->>'unit_price')::integer;
  if qty is null or qty not between 1 and game_private.setting('max_listing_quantity') or price is null or price not between 1 and game_private.setting('max_unit_price') then raise exception 'Check the quantity and price limits.'; end if;
  if not exists(select 1 from public.game_goods where id=p_payload->>'good_id') then raise exception 'Unknown goods.'; end if;
  if (select count(*) from public.game_district_buy_orders where season_id=s and buyer_id=auth.uid() and status='open')>=game_private.setting('listing_limit') then raise exception 'Your open order limit has been reached.'; end if;
  total:=qty::bigint*price;
  perform game_private.district_wallet(auth.uid(),-total,'Fund district buy order');
  insert into public.game_district_buy_orders(season_id,district_id,buyer_id,good_id,quantity,unit_price,escrow,remaining_quantity)
  values(s,d,auth.uid(),p_payload->>'good_id',qty,price,total,qty);
 when 'fill' then
  if o.buyer_id=auth.uid() then raise exception 'You cannot fill your own buy order.'; end if;
  qty:=coalesce((p_payload->>'quantity')::integer,o.remaining_quantity);
  if qty<1 or qty>o.remaining_quantity then raise exception 'Choose a quantity within the remaining order.';end if;
  total:=qty::bigint*o.unit_price;fee:=ceil(total*game_private.setting('market_fee_percent')::numeric/100);
  if o.escrow<>o.remaining_quantity::bigint*o.unit_price then raise exception 'The order funding is unavailable.'; end if;
  update public.game_inventory set quantity=quantity-qty where season_id=s and player_id=auth.uid() and good_id=o.good_id and quantity>=qty;
  if not found then raise exception 'You do not have enough available goods to fill this order.'; end if;
  insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(s,o.buyer_id,o.good_id,qty)
  on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
  perform game_private.district_wallet(auth.uid(),total-fee,'Supply district buy order');
  update public.game_district_buy_orders set remaining_quantity=remaining_quantity-qty,status=case when remaining_quantity=qty then 'filled' else 'open' end,escrow=escrow-total,completed_at=case when remaining_quantity=qty then now() else null end where id=o.id;
  insert into public.game_district_trades(season_id,district_id,buy_order_id,good_id,quantity,unit_price,buyer_id,seller_id)
  values(s,d,o.id,o.good_id,qty,o.unit_price,o.buyer_id,auth.uid());
  perform game_private.record_metric(auth.uid(),'trading',total);
  perform game_private.district_event(d,'economy','market_transaction',qty||' '||o.good_id||' supplied for $'||total,null,null,null,jsonb_build_object('buy_order_id',o.id,'quantity',qty,'good_id',o.good_id));
 when 'cancel' then
  if o.buyer_id<>auth.uid() then raise exception 'This is not your buy order.'; end if;
  perform game_private.district_wallet(auth.uid(),o.escrow,'Refund district buy order');
  update public.game_district_buy_orders set status='cancelled',escrow=0,completed_at=now() where id=o.id;
 else raise exception 'Unknown market order action.';
 end case;
 result:=jsonb_build_object('message',case p_action when 'create' then 'Buy order funded and posted.' when 'fill' then 'Goods supplied. Payment received.' else 'Buy order cancelled. Funds returned.' end);
 if nonce is not null then insert into game_private.buy_order_requests(player_id,request_id,action,payload,result) values(auth.uid(),nonce,p_action,p_payload,result);end if;
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
  raise log 'district order failure code=%',SQLSTATE;return jsonb_build_object('error','The order could not be completed. Refresh and check your values.');
 end;
end $$;
