
create schema if not exists game_private;
revoke all on schema game_private from public, anon;
grant usage on schema game_private to authenticated;

create table public.game_players (
 id uuid primary key references auth.users(id) on delete cascade,
 handle text not null,
 cash bigint not null default 10000 check (cash between 0 and 9000000000000),
 xp integer not null default 0 check (xp >= 0),
 job_ready_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create table public.game_goods (
 id text primary key, name text not null, business_name text not null,
 business_cost integer not null check (business_cost > 0),
 batch_size integer not null check (batch_size > 0),
 cycle_seconds integer not null default 300 check (cycle_seconds > 0)
);
insert into public.game_goods values
 ('whiskey','Whiskey crates','Backroom distillery',3000,3,300),
 ('silk','Silk bolts','Textile workshop',5000,2,300),
 ('steel','Steel bundles','Dockside foundry',8000,2,300);
create table public.game_inventory (
 player_id uuid not null references public.game_players(id) on delete cascade,
 good_id text not null references public.game_goods(id),
 quantity integer not null default 0 check (quantity between 0 and 1000000),
 primary key (player_id, good_id)
);
create index game_inventory_good_idx on public.game_inventory(good_id);
create table public.game_businesses (
 player_id uuid not null references public.game_players(id) on delete cascade,
 good_id text not null references public.game_goods(id),
 collected_at timestamptz not null default now(),
 primary key (player_id, good_id)
);
create index game_businesses_good_idx on public.game_businesses(good_id);
create table public.game_listings (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.game_players(id) on delete cascade,
 seller_handle text not null,
 good_id text not null references public.game_goods(id),
 quantity integer not null check (quantity between 1 and 1000),
 unit_price integer not null check (unit_price between 1 and 1000000),
 status text not null default 'active' check (status in ('active','sold','cancelled')),
 created_at timestamptz not null default now()
);
create index game_listings_market_idx on public.game_listings(created_at desc) where status = 'active';
create index game_listings_seller_idx on public.game_listings(seller_id, status);
create index game_listings_good_idx on public.game_listings(good_id);
create table public.game_events (
 id uuid primary key default gen_random_uuid(),
 player_id uuid not null references public.game_players(id) on delete cascade,
 description text not null, cash_delta bigint not null default 0,
 created_at timestamptz not null default now()
);
create index game_events_player_idx on public.game_events(player_id, created_at desc);

alter table public.game_players enable row level security;
alter table public.game_goods enable row level security;
alter table public.game_inventory enable row level security;
alter table public.game_businesses enable row level security;
alter table public.game_listings enable row level security;
alter table public.game_events enable row level security;

revoke all on public.game_players, public.game_goods, public.game_inventory,
 public.game_businesses, public.game_listings, public.game_events from anon, authenticated;
grant select on public.game_players, public.game_goods, public.game_inventory,
 public.game_businesses, public.game_listings, public.game_events to authenticated;
create policy game_players_self on public.game_players for select to authenticated using (id = (select auth.uid()));
create policy game_goods_read on public.game_goods for select to authenticated using (true);
create policy game_inventory_self on public.game_inventory for select to authenticated using (player_id = (select auth.uid()));
create policy game_businesses_self on public.game_businesses for select to authenticated using (player_id = (select auth.uid()));
create policy game_listings_read on public.game_listings for select to authenticated using (status = 'active' or seller_id = (select auth.uid()));
create policy game_events_self on public.game_events for select to authenticated using (player_id = (select auth.uid()));

create function game_private.state()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 p public.game_players;
begin
 if uid is null then raise exception 'Log in to enter Blackwater.'; end if;
 insert into public.game_players(id, handle) values (uid, 'Rookie-' || left(uid::text, 8))
 on conflict (id) do nothing;
 if found then
   insert into public.game_inventory(player_id, good_id, quantity) values (uid, 'whiskey', 5);
   insert into public.game_events(player_id, description, cash_delta)
     values (uid, 'Arrived in Blackwater · starting cash and 5 whiskey crates', 10000);
 end if;
 select * into strict p from public.game_players where id = uid;
 return jsonb_build_object(
   'player', to_jsonb(p),
   'goods', (select coalesce(jsonb_agg(g order by g.business_cost), '[]'::jsonb) from public.game_goods g),
   'inventory', (select coalesce(jsonb_agg(i order by i.good_id), '[]'::jsonb) from public.game_inventory i where i.player_id = uid),
   'businesses', (select coalesce(jsonb_agg(b order by b.good_id), '[]'::jsonb) from public.game_businesses b where b.player_id = uid),
   'market', (select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) from
      (select * from public.game_listings where status = 'active' order by created_at desc, id limit 200) m),
   'my_listings', (select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) from public.game_listings m where m.seller_id = uid and m.status = 'active'),
   'events', (select coalesce(jsonb_agg(e order by e.created_at desc), '[]'::jsonb) from
      (select * from public.game_events where player_id = uid order by created_at desc, id limit 30) e),
   'server_time', now()
 );
end $$;

create function game_private.act(p_action text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 p public.game_players;
 good public.game_goods;
 listing public.game_listings;
 biz public.game_businesses;
 qty integer; price integer; total bigint; fee bigint; reward integer; xp_reward integer; cooldown integer;
 batches integer; label text; result_message text;
begin
 if uid is null then raise exception 'Log in to play.'; end if;
 if not exists(select 1 from public.game_players where id = uid) then raise exception 'Reload the game to create your character.'; end if;

 -- Lock a listing before locking wallets. All wallet pairs lock in UUID order.
 -- Inventory operations also hold the owner wallet lock, serializing mutations.
 if p_action in ('buy', 'cancel') then
   select * into listing from public.game_listings where id = (p_payload->>'listing_id')::uuid for update;
   if not found or listing.status <> 'active' then raise exception 'That offer is no longer available. Refresh the market.'; end if;
   if p_action = 'buy' and listing.seller_id = uid then raise exception 'You cannot buy your own offer.'; end if;
   if p_action = 'cancel' and listing.seller_id <> uid then raise exception 'This is not your offer.'; end if;
   perform id from public.game_players where id in (uid, listing.seller_id) order by id for update;
 else
   perform id from public.game_players where id = uid for update;
 end if;
 select * into strict p from public.game_players where id = uid;

 case p_action
 when 'job' then
   if p.job_ready_at > now() then raise exception 'Your crew is still recovering. Wait for the cooldown.'; end if;
   case p_payload->>'job'
    when 'docks' then reward := 250; xp_reward := 10; cooldown := 60; label := 'Dock errand';
    when 'warehouse' then reward := 600; xp_reward := 20; cooldown := 180; label := 'Warehouse shift';
    when 'courier' then reward := 1100; xp_reward := 40; cooldown := 360; label := 'Night courier';
    else raise exception 'Unknown operation.';
   end case;
   update public.game_players set cash = cash + reward, xp = xp + xp_reward,
     job_ready_at = now() + make_interval(secs => cooldown) where id = uid;
   insert into public.game_events(player_id,description,cash_delta) values (uid,label || ' completed',reward);
   result_message := label || ' complete. +$' || reward || ' and +' || xp_reward || ' respect.';
 when 'business' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   if exists(select 1 from public.game_businesses where player_id = uid and good_id = good.id) then raise exception 'You already own that business.'; end if;
   if p.cash < good.business_cost then raise exception 'Not enough cash for this business.'; end if;
   update public.game_players set cash = cash - good.business_cost where id = uid;
   insert into public.game_businesses(player_id,good_id) values (uid,good.id);
   insert into public.game_events(player_id,description,cash_delta) values (uid,'Opened ' || good.business_name,-good.business_cost);
   result_message := good.business_name || ' acquired. First batch ready in 5 minutes.';
 when 'collect' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   select * into biz from public.game_businesses where player_id = uid and good_id = good.id for update;
   if not found then raise exception 'You do not own this business.'; end if;
   batches := least(24, floor(extract(epoch from (now()-biz.collected_at))/good.cycle_seconds)::integer);
   if batches < 1 then raise exception 'Production is not ready yet.'; end if;
   qty := batches * good.batch_size;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values (uid,good.id,qty)
     on conflict(player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_businesses set collected_at = case
     when extract(epoch from (now()-biz.collected_at)) >= 24 * good.cycle_seconds then now()
     else biz.collected_at + make_interval(secs => batches * good.cycle_seconds) end
     where player_id = uid and good_id = good.id;
   insert into public.game_events(player_id,description) values (uid,'Collected ' || qty || ' ' || lower(good.name));
   result_message := qty || ' ' || lower(good.name) || ' added to your inventory.';
 when 'list' then
   qty := (p_payload->>'quantity')::integer; price := (p_payload->>'unit_price')::integer;
   if qty is null or price is null or qty < 1 or qty > 1000 or price < 1 or price > 1000000 then raise exception 'Use a quantity of 1–1,000 and a unit price of $1–$1,000,000.'; end if;
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown goods.'; end if;
   if (select count(*) from public.game_listings where seller_id = uid and status = 'active') >= 20 then raise exception 'You can have up to 20 active offers.'; end if;
   update public.game_inventory set quantity = quantity - qty
     where player_id = uid and good_id = good.id and quantity >= qty;
   if not found then raise exception 'You do not have enough goods. Listed stock is already reserved.'; end if;
   insert into public.game_listings(seller_id,seller_handle,good_id,quantity,unit_price) values(uid,p.handle,good.id,qty,price);
   insert into public.game_events(player_id,description) values (uid,'Listed ' || qty || ' ' || lower(good.name) || ' at $' || price || ' each');
   result_message := 'Offer posted. Your goods are reserved until sold or cancelled.';
 when 'buy' then
   total := listing.quantity::bigint * listing.unit_price;
   fee := greatest(1, (total * 5 + 99) / 100);
   if p.cash < total then raise exception 'Not enough cash to buy this lot.'; end if;
   update public.game_players set cash = cash - total where id = uid;
   update public.game_players set cash = cash + total - fee where id = listing.seller_id;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'sold' where id = listing.id;
   insert into public.game_events(player_id,description,cash_delta) values
     (uid,'Bought ' || listing.quantity || ' ' || listing.good_id || ' from ' || listing.seller_handle,-total),
     (listing.seller_id,'Sold ' || listing.quantity || ' ' || listing.good_id || ' · $' || fee || ' market fee',total-fee);
   result_message := 'Deal closed. Goods delivered to your inventory.';
 when 'cancel' then
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'cancelled' where id = listing.id;
   insert into public.game_events(player_id,description) values (uid,'Cancelled an offer · ' || listing.quantity || ' ' || listing.good_id || ' returned');
   result_message := 'Offer withdrawn. Reserved stock returned.';
 else raise exception 'Unknown game action.';
 end case;
 return jsonb_build_object('message',result_message);
end $$;

revoke all on function game_private.state() from public, anon;
revoke all on function game_private.act(text,jsonb) from public, anon;
grant execute on function game_private.state(), game_private.act(text,jsonb) to authenticated;

create function public.game_state() returns jsonb
 language sql security invoker set search_path = '' as $$ select game_private.state(); $$;
create function public.game_action(p_action text, p_payload jsonb default '{}'::jsonb) returns jsonb
 language sql security invoker set search_path = '' as $$ select game_private.act(p_action,p_payload); $$;
revoke all on function public.game_state(), public.game_action(text,jsonb) from public, anon;
grant execute on function public.game_state(), public.game_action(text,jsonb) to authenticated;
