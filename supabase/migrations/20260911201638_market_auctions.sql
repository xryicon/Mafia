-- Goods auctions are season scoped; existing fixed-price listings are unchanged.
insert into public.game_settings(key,value,minimum,maximum) values
 ('auction_min_minutes',5,1,1440),('auction_max_minutes',10080,1440,43200),
 ('auction_default_minutes',1440,1,43200),('auction_min_increment',10,1,1000000),
 ('auction_max_bid',1000000000,1,2000000000),('auction_extension_seconds',60,0,600),
 ('auction_listing_limit',20,1,100);

create table public.game_market_auctions (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 seller_id uuid not null references public.game_players(id), good_id text not null references public.game_goods(id),
 district_id uuid references public.game_districts(id), quantity integer not null check(quantity>0),
 starting_bid bigint not null check(starting_bid>0), current_bid bigint not null default 0 check(current_bid>=0),
 bidder_id uuid references public.game_players(id), escrow bigint not null default 0 check(escrow>=0),
 bid_count integer not null default 0 check(bid_count>=0), increment integer not null check(increment>0),
 fee_percent integer not null check(fee_percent between 0 and 100), extension_seconds integer not null check(extension_seconds between 0 and 600),
 status text not null default 'open' check(status in ('open','sold','unsold','cancelled')),
 created_at timestamptz not null default now(), ends_at timestamptz not null, completed_at timestamptz,
 fee_paid bigint not null default 0, check(bidder_id is null or bidder_id<>seller_id),
 check((bidder_id is null and current_bid=0) or (bidder_id is not null and current_bid>=starting_bid)),
 check((status='open' and escrow=current_bid) or (status<>'open' and escrow=0))
);
create index market_auction_deadlines on public.game_market_auctions(season_id,ends_at,id) where status='open';
create index market_auction_seller on public.game_market_auctions(season_id,seller_id,created_at desc);
create index market_auction_bidder on public.game_market_auctions(season_id,bidder_id) where bidder_id is not null;
create index market_auction_good on public.game_market_auctions(good_id);
create index market_auction_district on public.game_market_auctions(district_id);
create table public.game_market_bids (
 id uuid primary key default gen_random_uuid(), auction_id uuid not null references public.game_market_auctions(id),
 bidder_id uuid not null references public.game_players(id), amount bigint not null check(amount>0),
 created_at timestamptz not null default now()
);
create index market_bid_history on public.game_market_bids(auction_id,created_at desc);
create index market_bid_player on public.game_market_bids(bidder_id,auction_id);
create table game_private.market_requests (
 player_id uuid not null references public.game_players(id),season_id uuid not null references public.game_seasons(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default now(),primary key(player_id,season_id,request_id)
);
alter table public.game_market_auctions enable row level security;
alter table public.game_market_bids enable row level security;
alter table game_private.market_requests enable row level security;
revoke all on public.game_market_auctions,public.game_market_bids,game_private.market_requests from public,anon,authenticated;
create trigger retain_market_auctions before delete on public.game_market_auctions for each row execute function game_private.district_immutable();
create trigger retain_market_auctions_table before truncate on public.game_market_auctions for each statement execute function game_private.district_immutable();
create trigger retain_market_bids before update or delete on public.game_market_bids for each row execute function game_private.district_immutable();
create trigger retain_market_bids_table before truncate on public.game_market_bids for each statement execute function game_private.district_immutable();
create trigger retain_market_requests before update or delete on game_private.market_requests for each row execute function game_private.district_immutable();
create trigger audit_market_auctions after insert or update on public.game_market_auctions for each row execute function game_private.audit_change();

-- Callers hold season -> auction coordinator -> auction rows -> all affected wallets in UUID order.
create function game_private.market_finish(a public.game_market_auctions, cancel_sale boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare fee bigint; recipient uuid;
begin
 if a.status<>'open' then return;end if;
 if cancel_sale or a.bidder_id is null then
  recipient:=a.seller_id;
  if a.escrow>0 then perform game_private.district_wallet(a.bidder_id,a.escrow,'Auction refund: '||a.id);end if;
  update public.game_market_auctions set status=case when cancel_sale then 'cancelled' else 'unsold' end,escrow=0,completed_at=clock_timestamp() where id=a.id;
 else
  recipient:=a.bidder_id;fee:=ceil(a.current_bid*a.fee_percent::numeric/100);
  perform game_private.district_wallet(a.seller_id,a.current_bid-fee,'Auction sale: '||a.id);
  perform game_private.record_metric(a.seller_id,'trading',a.current_bid);
  update public.game_market_auctions set status='sold',escrow=0,fee_paid=fee,completed_at=clock_timestamp() where id=a.id;
  insert into public.game_events(season_id,player_id,description,cash_delta) values
   (a.season_id,a.seller_id,'Auction sold: '||a.quantity||' '||a.good_id||' · $'||fee||' fee',a.current_bid-fee),
   (a.season_id,a.bidder_id,'Auction won: '||a.quantity||' '||a.good_id||' · paid from reserved bid',0);
 end if;
 insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(a.season_id,recipient,a.good_id,a.quantity)
 on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
 if cancel_sale or a.bidder_id is null then
  insert into public.game_events(season_id,player_id,description) values(a.season_id,a.seller_id,'Auction closed: '||a.quantity||' '||a.good_id||' returned to inventory');
 end if;
 if a.district_id is not null then
  perform game_private.district_event(a.district_id,'economy','market_auction','Goods auction '||case when cancel_sale then 'cancelled' when a.bidder_id is null then 'ended without bids' else 'sold for $'||a.current_bid end,null,null,null,jsonb_build_object('auction_id',a.id,'good_id',a.good_id,'quantity',a.quantity));
 end if;
end $$;

create function game_private.market_close_due(cancel_season boolean default false) returns integer
language plpgsql security definer set search_path='' as $$
declare s uuid; ids uuid[]; a public.game_market_auctions; count_closed integer:=0;
begin
 s:=game_private.season_guard(false);
 if not cancel_season and not exists(select 1 from public.game_seasons where id=s and status='open' and (ends_at is null or ends_at>clock_timestamp())) then return 0;end if;
 perform pg_advisory_xact_lock(4704040);
 select array_agg(id) into ids from (select id from public.game_market_auctions where season_id=s and status='open' and (cancel_season or ends_at<=clock_timestamp()) order by ends_at,id limit case when cancel_season then null else 50 end for update) q;
 if ids is null then return 0;end if;
 perform id from public.game_players where id in(select seller_id from public.game_market_auctions where id=any(ids) union select bidder_id from public.game_market_auctions where id=any(ids)) order by id for update;
 for a in select * from public.game_market_auctions where id=any(ids) order by id loop
  perform game_private.market_finish(a,cancel_season);count_closed:=count_closed+1;
 end loop;
 return count_closed;
end $$;

create function game_private.market_auction_action(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid; uid uuid:=auth.uid(); nonce uuid; saved game_private.market_requests;
 a public.game_market_auctions; qty integer; amount bigint; minutes integer; d uuid; result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again shortly.');end if;
 begin
 s:=game_private.season_guard();
 if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the market.';end if;
 nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'Missing request reference. Refresh the market.';end if;
 perform pg_advisory_xact_lock(4704040);
 select * into saved from game_private.market_requests where player_id=uid and season_id=s and request_id=nonce;
 if found then
  if saved.action<>p_action or saved.payload<>p_payload then raise exception 'This request reference was already used.';end if;
  return saved.result;
 end if;
 if p_action<>'create' then
  select * into a from public.game_market_auctions where id=(p_payload->>'auction_id')::uuid and season_id=s for update;
  if not found then raise exception 'Auction unavailable.';end if;
 end if;
 perform id from public.game_players where id in(uid,a.seller_id,a.bidder_id) order by id for update;
 if not exists(select 1 from public.game_players where id=uid and season_id=s) then raise exception 'Reload to enter the season.';end if;
 case p_action
 when 'create' then
  qty:=(p_payload->>'quantity')::integer;amount:=(p_payload->>'starting_bid')::bigint;minutes:=(p_payload->>'duration_minutes')::integer;d:=nullif(p_payload->>'district_id','')::uuid;
  if qty is null or qty not between 1 and game_private.setting('max_listing_quantity') or amount is null or amount not between 1 and game_private.setting('auction_max_bid') or minutes is null or minutes not between game_private.setting('auction_min_minutes') and game_private.setting('auction_max_minutes') then raise exception 'Check the quantity, starting bid and duration limits.';end if;
  if not exists(select 1 from public.game_goods where id=p_payload->>'good_id') then raise exception 'Unknown goods.';end if;
  if d is not null and not exists(select 1 from public.game_districts where id=d and archived_at is null and status<>'lockdown' and not exists(select 1 from public.game_district_territory where season_id=s and district_id=d and status='lockdown')) then raise exception 'This district market is unavailable.';end if;
  if exists(select 1 from public.game_seasons where id=s and ends_at is not null and clock_timestamp()+make_interval(mins=>minutes)>ends_at) then raise exception 'Choose a duration that ends before the season closes.';end if;
  if (select count(*) from public.game_market_auctions where season_id=s and seller_id=uid and status='open')>=game_private.setting('auction_listing_limit') then raise exception 'Your open auction limit has been reached.';end if;
  update public.game_inventory set quantity=quantity-qty where season_id=s and player_id=uid and good_id=p_payload->>'good_id' and quantity>=qty;
  if not found then raise exception 'Not enough available goods. Listed stock is already reserved.';end if;
  insert into public.game_market_auctions(season_id,seller_id,good_id,district_id,quantity,starting_bid,ends_at,increment,fee_percent,extension_seconds)
  values(s,uid,p_payload->>'good_id',d,qty,amount,clock_timestamp()+make_interval(mins=>minutes),game_private.setting('auction_min_increment'),game_private.setting('market_fee_percent'),game_private.setting('auction_extension_seconds')) returning * into a;
  insert into public.game_events(season_id,player_id,description) values(s,uid,'Opened auction: '||qty||' '||a.good_id);
  result:=jsonb_build_object('message','Auction opened. Your goods are reserved.','auction_id',a.id);
 when 'bid' then
  if a.status<>'open' or a.ends_at<=clock_timestamp() then raise exception 'This auction has ended. Refresh the market.';end if;
  if a.seller_id=uid then raise exception 'You cannot bid on your own auction.';end if;
  amount:=(p_payload->>'amount')::bigint;
  if amount is null or amount<case when a.bidder_id is null then a.starting_bid else a.current_bid+a.increment end or amount>game_private.setting('auction_max_bid') then raise exception 'Your bid is below the next bid or above the limit. Refresh the auction.';end if;
  -- Keep the previous leading bid in reserve until the replacement is funded.
  perform game_private.district_wallet(uid,-(amount-case when a.bidder_id=uid then a.escrow else 0 end),'Reserve auction bid: '||a.id);
  if a.bidder_id is not null and a.bidder_id<>uid then
   perform game_private.district_wallet(a.bidder_id,a.escrow,'Outbid refund: '||a.id);
   insert into public.game_events(season_id,player_id,description,cash_delta) values(s,a.bidder_id,'Outbid on '||a.good_id||' · reserved cash returned',a.escrow);
  end if;
  insert into public.game_market_bids(auction_id,bidder_id,amount) values(a.id,uid,amount);
  update public.game_market_auctions set current_bid=amount,bidder_id=uid,escrow=amount,bid_count=bid_count+1,
   ends_at=least(greatest(ends_at,clock_timestamp()+make_interval(secs=>extension_seconds)),coalesce((select ends_at from public.game_seasons where id=s),'infinity'::timestamptz))
   where id=a.id;
  result:=jsonb_build_object('message','Bid placed. The full bid is held until you win or are outbid.','auction_id',a.id);
 when 'cancel' then
  if a.seller_id<>uid then raise exception 'This is not your auction.';end if;
  if a.status<>'open' or a.ends_at<=clock_timestamp() or a.bid_count>0 then raise exception 'Only an open auction without bids can be withdrawn.';end if;
  perform game_private.market_finish(a,true);
  result:=jsonb_build_object('message','Auction withdrawn. Goods returned.','auction_id',a.id);
 when 'settle' then
  if a.status='open' and a.ends_at>clock_timestamp() then raise exception 'This auction is still running.';end if;
  if a.status='open' then perform game_private.market_finish(a);end if;
  result:=jsonb_build_object('message','Auction settled. Cash and goods have been delivered.','auction_id',a.id);
 else raise exception 'Unknown auction action.';end case;
 insert into game_private.market_requests(player_id,season_id,request_id,action,payload,result) values(uid,s,nonce,p_action,p_payload,result);
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'market auction failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The auction action was not saved. Check your values and refresh.');
 end;
end $$;


create function game_private.market_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; state jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('market_reads',120) then raise exception 'Too many market reads. Try again shortly.';end if;
 perform game_private.market_close_due();
 s:=game_private.season_guard(false);state:=game_private.read_state();
 return jsonb_build_object('game',state,
 'auctions',(select coalesce(jsonb_agg(q order by q.created_at desc),'[]') from (
  select a.*,game_private.district_owner_name('player',a.seller_id) as seller_name,
   case when a.bidder_id is not null then game_private.district_owner_name('player',a.bidder_id) end as bidder_name,
   exists(select 1 from public.game_market_bids b where b.auction_id=a.id and b.bidder_id=auth.uid()) as has_bid
  from public.game_market_auctions a where a.id in (
   select id from public.game_market_auctions where season_id=s and status='open'
   union select id from (select id from public.game_market_auctions where season_id=s and (seller_id=auth.uid() or bidder_id=auth.uid() or exists(select 1 from public.game_market_bids b where b.auction_id=game_market_auctions.id and b.bidder_id=auth.uid())) order by created_at desc limit 100) mine
  ) order by (a.status='open') desc,a.ends_at,a.id limit 300
 ) q),
 'reserved_cash',(select coalesce(sum(escrow),0) from public.game_market_auctions where season_id=s and bidder_id=auth.uid() and status='open'),
 'reserved_stock',(select coalesce(sum(quantity),0) from public.game_market_auctions where season_id=s and seller_id=auth.uid() and status='open'),
 'districts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.game_districts where archived_at is null),
 'server_time',clock_timestamp());
end $$;
create function public.market_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.market_state()$$;
create function public.market_auction_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.market_auction_action(p_action,p_payload)$$;
revoke all on function game_private.market_finish(public.game_market_auctions,boolean),game_private.market_close_due(boolean),game_private.market_state(),game_private.market_auction_action(text,jsonb),public.market_state(),public.market_auction_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.market_state(),game_private.market_auction_action(text,jsonb),public.market_state(),public.market_auction_action(text,jsonb) to authenticated;

-- Extend the current score calculation, preserving all district and buy-order valuation terms.
do $$
declare definition text;
begin
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as stock_value,' in definition)=0 or position(' as asset_value,' in definition)=0 then raise exception 'Unexpected season score definition';end if;
 definition:=replace(definition,' as stock_value,',
 ' +coalesce((select sum(a.quantity::numeric*v.unit_value) from public.game_market_auctions a join public.game_season_valuations v on v.season_id=a.season_id and v.good_id=a.good_id where a.season_id=p_season and a.seller_id=sp.player_id and a.status=''open''),0) as stock_value,');
 definition:=replace(definition,' as asset_value,',
 ' +coalesce((select sum(a.escrow::numeric) from public.game_market_auctions a where a.season_id=p_season and a.bidder_id=sp.player_id and a.status=''open''),0) as asset_value,');
 execute definition;
 -- Snapshot returns outstanding reserves before capturing immutable cash/rankings.
 select pg_get_functiondef('game_private.season_action(text,jsonb)'::regprocedure) into definition;
 if position('for board_config in select * from public.game_leaderboards' in definition)=0 then raise exception 'Unexpected season snapshot definition';end if;
 definition:=replace(definition,'for board_config in select * from public.game_leaderboards','perform game_private.market_close_due(true);' || chr(10) || ' for board_config in select * from public.game_leaderboards');
 execute definition;
end $$;
create function game_private.market_season_reopen() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status='locked' and new.status='open' and old.locked_at is not null then
  update public.game_market_auctions set ends_at=least(ends_at+(clock_timestamp()-old.locked_at),coalesce(new.ends_at,'infinity'::timestamptz)) where season_id=new.id and status='open';
 end if;
 return new;
end $$;
create trigger market_season_clock after update of status on public.game_seasons for each row execute function game_private.market_season_reopen();
revoke all on function game_private.market_season_reopen() from public,anon,authenticated;
-- Supabase runs settlement even when no player has a browser open.
-- The plain PostgreSQL CI service has no pg_cron; it exercises the same function directly.
do $$
begin
 if exists(select 1 from pg_available_extensions where name='pg_cron') then
  create extension if not exists pg_cron;
  perform cron.schedule('blackwater-market-auctions','* * * * *','select game_private.market_close_due();');
 end if;
end $$;

