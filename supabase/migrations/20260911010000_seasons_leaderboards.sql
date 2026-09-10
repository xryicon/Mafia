
-- Retain the existing world as the first season; do not reset any live gameplay.
create table public.game_seasons (
 id uuid primary key default gen_random_uuid(), name text not null check(length(name) between 3 and 80),
 status text not null default 'draft' check(status in ('draft','open','locked','finalized','archived')),
 starting_cash bigint not null check(starting_cash between 0 and 100000000),
 starting_crates integer not null check(starting_crates between 0 and 1000),
 starts_at timestamptz, ends_at timestamptz, opened_at timestamptz, locked_at timestamptz,
 finalized_at timestamptz, archived_at timestamptz, reset_at timestamptz,
 hall_of_fame_places integer not null default 3 check(hall_of_fame_places between 0 and 100),
 created_at timestamptz not null default now(), check(ends_at is null or starts_at is null or ends_at>starts_at)
);
create unique index one_open_season on public.game_seasons((true)) where status='open';
insert into public.game_seasons(name,status,starting_cash,starting_crates,opened_at)
values('Blackwater · Founding Season','open',game_private.setting('starting_cash'),game_private.setting('starting_crates'),now());
create table game_private.season_runtime (
 singleton boolean primary key default true check(singleton), season_id uuid not null references public.game_seasons(id)
);
insert into game_private.season_runtime select true,id from public.game_seasons;
create function game_private.current_season() returns uuid language sql stable security definer set search_path='' as $$
 select season_id from game_private.season_runtime where singleton
$$;
create function game_private.season_guard(require_open boolean default true) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.game_seasons;
begin
 perform pg_advisory_xact_lock_shared(4704001);
 select * into strict s from public.game_seasons where id=game_private.current_season();
 if require_open and (s.status<>'open' or (s.ends_at is not null and clock_timestamp()>=s.ends_at)) then raise exception 'This season is closed for gameplay.'; end if;
 return s.id;
end $$;
alter table public.game_players add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
alter table public.game_players add column subscription jsonb not null default '{}'::jsonb;
-- Subscription entitlements belong to the permanent identity, never the season.
alter table public.game_inventory add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
create index on public.game_inventory(season_id);
alter table public.game_businesses add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
create index on public.game_businesses(season_id);
alter table public.game_listings add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
create index on public.game_listings(season_id);
alter table public.game_ledger add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
create index on public.game_ledger(season_id);
alter table public.game_events add column season_id uuid not null default game_private.current_season() references public.game_seasons(id);
create index on public.game_events(season_id);
alter table public.game_inventory drop constraint game_inventory_pkey;
alter table public.game_inventory add primary key(season_id,player_id,good_id);
alter table public.game_businesses drop constraint game_businesses_pkey;
alter table public.game_businesses add primary key(season_id,player_id,good_id);

create table public.game_season_players (
 season_id uuid not null references public.game_seasons(id), player_id uuid not null references public.game_players(id),
 cash bigint not null default 0, xp integer not null default 0, level integer not null default 1 check(level>=1),
 skills jsonb not null default '{}'::jsonb check(jsonb_typeof(skills)='object'),
 joined_at timestamptz not null default now(), primary key(season_id,player_id)
);
insert into public.game_season_players(season_id,player_id,cash,xp)
select season_id,id,cash,xp from public.game_players;
create index on public.game_season_players(player_id);
create table public.game_season_assets (
 id uuid primary key default gen_random_uuid(), season_id uuid not null default game_private.current_season() references public.game_seasons(id),
 player_id uuid not null references public.game_players(id), kind text not null check(kind in ('land','building','factory','company')),
 name text not null, quantity bigint not null default 1 check(quantity>0), unit_value bigint not null default 0 check(unit_value>=0),
 data jsonb not null default '{}'
);
create index on public.game_season_assets(season_id,player_id,kind);
create index on public.game_season_assets(player_id);
create table public.game_season_gangs (
 id uuid primary key default gen_random_uuid(), season_id uuid not null default game_private.current_season() references public.game_seasons(id),
 name text not null, data jsonb not null default '{}', unique(season_id,id)
);
create table public.game_season_gang_members (
 season_id uuid not null references public.game_seasons(id), player_id uuid not null references public.game_players(id),
 gang_id uuid not null, contribution bigint not null default 0 check(contribution>=0),
 primary key(season_id,player_id), foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create index on public.game_season_gang_members(gang_id);
create index on public.game_season_gang_members(player_id);
create table public.game_season_loans (
 id uuid primary key default gen_random_uuid(), season_id uuid not null default game_private.current_season() references public.game_seasons(id),
 player_id uuid not null references public.game_players(id), principal bigint not null check(principal>=0),
 outstanding bigint not null check(outstanding>=0), data jsonb not null default '{}'
);
create index on public.game_season_loans(season_id,player_id);
create index on public.game_season_loans(player_id);
create table public.game_season_jobs (
 id uuid primary key default gen_random_uuid(), season_id uuid not null default game_private.current_season() references public.game_seasons(id),
 player_id uuid not null references public.game_players(id), kind text not null check(kind in ('crafting','production','construction')),
 status text not null check(status in ('queued','running','completed','cancelled')), ready_at timestamptz, data jsonb not null default '{}'
);
create index on public.game_season_jobs(season_id,player_id);
create index on public.game_season_jobs(player_id);
create table public.game_season_stats (
 season_id uuid not null default game_private.current_season() references public.game_seasons(id),
 player_id uuid not null references public.game_players(id), metric text not null,
 value bigint not null default 0 check(value>=0), primary key(season_id,player_id,metric)
);
create index on public.game_season_stats(player_id);
create table public.game_metric_catalog (
 id text primary key, label text not null, description text not null, available boolean not null
);
insert into public.game_metric_catalog values
 ('net_worth','Net worth','Cash, valued inventory and escrow, businesses and assets, less outstanding loans.',true),
 ('cash','Cash','Available season cash.',true),
 ('land','Land','Season land units owned.',false),
 ('company_value','Company value','Total server-valued company assets.',false),
 ('factory_value','Factory value','Business acquisition values plus factory assets.',true),
 ('production','Production','Units collected from production this season.',true),
 ('trading','Trading','Gross value of goods sold this season.',true),
 ('crime','Crime','Successful street operations this season.',true),
 ('combat','Combat','Combat victories recorded by the server.',false),
 ('crafting','Crafting','Crafted units recorded by the server.',false),
 ('construction','Construction','Businesses and construction completed this season.',true),
 ('gang_contribution','Gang contribution','Season gang contributions.',false),
 ('respect','Respect','Season experience points.',true);
alter table public.game_season_stats add foreign key(metric) references public.game_metric_catalog(id);
create table public.game_leaderboards (
 season_id uuid not null references public.game_seasons(id), metric text not null references public.game_metric_catalog(id),
 label text not null check(length(label) between 1 and 80), enabled boolean not null default true,
 direction text not null default 'desc' check(direction in ('asc','desc')),
 include_banned boolean not null default false, hall_of_fame boolean not null default true,
 primary key(season_id,metric)
);
insert into public.game_leaderboards(season_id,metric,label,enabled)
select s.id,m.id,m.label,m.available from public.game_seasons s cross join public.game_metric_catalog m;
create table public.game_season_valuations (
 season_id uuid not null references public.game_seasons(id), good_id text not null references public.game_goods(id),
 unit_value bigint not null default 0 check(unit_value between 0 and 100000000),
 primary key(season_id,good_id)
);
insert into public.game_season_valuations select s.id,g.id,100 from public.game_seasons s cross join public.game_goods g;
create table public.game_season_results (
 season_id uuid not null references public.game_seasons(id), metric text not null,
 player_id uuid not null references public.game_players(id), handle text not null,
 label text not null, score numeric not null, rank bigint not null, captured_at timestamptz not null default now(),
 primary key(season_id,metric,player_id)
);
create index on public.game_season_results(player_id,season_id);
create index on public.game_season_results(season_id,metric,rank);
create table public.game_hall_of_fame (
 season_id uuid not null, metric text not null, player_id uuid not null, rank bigint not null, label text not null,
 handle text not null, score numeric not null, awarded_at timestamptz not null default now(),
 primary key(season_id,metric,player_id),
 foreign key(season_id,metric,player_id) references public.game_season_results(season_id,metric,player_id)
);
create index on public.game_hall_of_fame(player_id);
-- Keep the wallet projection synchronized without deleting prior-season balances.
create function game_private.sync_season_player() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if current_setting('game.season_reset',true)='closing' then return new; end if;
 insert into public.game_season_players(season_id,player_id,cash,xp)
 values(new.season_id,new.id,new.cash,new.xp)
 on conflict(season_id,player_id) do update set cash=excluded.cash,xp=excluded.xp;
 return new;
end $$;
create trigger season_player_sync after insert or update of cash,xp,season_id on public.game_players for each row execute function game_private.sync_season_player();

create function game_private.record_metric(player uuid,metric_name text,amount bigint) returns void language plpgsql security definer set search_path='' as $$
declare season uuid;
begin
 season:=game_private.season_guard();
 if amount<0 then raise exception 'Metric increment must not be negative.'; end if;
 insert into public.game_season_stats as s(season_id,player_id,metric,value) values(season,player,metric_name,amount)
 on conflict(season_id,player_id,metric) do update set value=s.value+excluded.value;
end $$;
create or replace function game_private.state()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 p public.game_players;
 season uuid; start_cash bigint; start_crates integer;
begin
 if uid is null then raise exception 'Log in to enter Blackwater.'; end if;
 perform game_private.require_active();
 season:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid) then perform game_private.season_guard(); end if;
 select starting_cash,starting_crates into start_cash,start_crates from public.game_seasons where id=season;
 insert into public.game_players(id, handle, cash) values (uid, 'Rookie-' || left(uid::text, 8), start_cash)
 on conflict (id) do nothing;
 if found then
   insert into public.game_inventory(player_id, good_id, quantity) values (uid, 'whiskey', start_crates);
   insert into public.game_events(player_id, description, cash_delta)
     values (uid, 'Arrived in Blackwater · starting cash and goods', start_cash);
 end if;
 insert into public.game_user_roles values(uid,'player') on conflict do nothing;
 select * into strict p from public.game_players where id = uid;
 return jsonb_build_object(
   'player', to_jsonb(p),
 'season',(select to_jsonb(s) from public.game_seasons s where id=season),
 'jobs',(select jsonb_agg(j order by j.reward) from public.game_jobs j),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings),
 'permissions',(select coalesce(jsonb_agg(id),'[]') from public.game_permissions where game_private.has_permission(id)),
 'ledger',(select coalesce(jsonb_agg(l order by l.id desc),'[]') from (select * from public.game_ledger where player_id=uid and season_id=season order by id desc limit 100) l),
   'goods', (select coalesce(jsonb_agg(g order by g.business_cost), '[]'::jsonb) from public.game_goods g),
   'inventory', (select coalesce(jsonb_agg(i order by i.good_id), '[]'::jsonb) from public.game_inventory i where i.player_id = uid and i.season_id=season),
   'businesses', (select coalesce(jsonb_agg(b order by b.good_id), '[]'::jsonb) from public.game_businesses b where b.player_id = uid and b.season_id=season),
   'market', (select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) from
      (select * from public.game_listings where status = 'active' and season_id=season order by created_at desc, id limit 200) m),
   'my_listings', (select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) from public.game_listings m where m.seller_id = uid and m.status = 'active' and m.season_id=season),
   'events', (select coalesce(jsonb_agg(e order by e.created_at desc), '[]'::jsonb) from
      (select * from public.game_events where player_id = uid and season_id=season order by created_at desc, id limit 30) e),
   'server_time', now()
 );
end $$;

create or replace function game_private.act(p_action text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 p public.game_players;
 season uuid:=game_private.current_season();
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
   select * into listing from public.game_listings where id = (p_payload->>'listing_id')::uuid and season_id=season for update;
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
   select j.reward,j.xp,j.cooldown,j.name into reward,xp_reward,cooldown,label from public.game_jobs j where j.id=p_payload->>'job';
   if not found then raise exception 'Unknown operation.'; end if;
   update public.game_players set cash = cash + reward, xp = xp + xp_reward,
     job_ready_at = now() + make_interval(secs => cooldown) where id = uid;
   insert into public.game_events(player_id,description,cash_delta) values (uid,label || ' completed',reward);
   result_message := label || ' complete. +$' || reward || ' and +' || xp_reward || ' respect.';
 when 'business' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   if exists(select 1 from public.game_businesses where player_id = uid and good_id = good.id and season_id=season) then raise exception 'You already own that business.'; end if;
   if p.cash < good.business_cost then raise exception 'Not enough cash for this business.'; end if;
   update public.game_players set cash = cash - good.business_cost where id = uid;
   insert into public.game_businesses(player_id,good_id) values (uid,good.id);
   insert into public.game_events(player_id,description,cash_delta) values (uid,'Opened ' || good.business_name,-good.business_cost);
   result_message := good.business_name || ' acquired. Production has started.';
 when 'collect' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   select * into biz from public.game_businesses where player_id = uid and good_id = good.id and season_id=season for update;
   if not found then raise exception 'You do not own this business.'; end if;
   batches := least(game_private.setting('offline_batches'), floor(extract(epoch from (now()-biz.collected_at))/good.cycle_seconds)::integer);
   if batches < 1 then raise exception 'Production is not ready yet.'; end if;
   qty := batches * good.batch_size;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values (uid,good.id,qty)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_businesses set collected_at = case
     when extract(epoch from (now()-biz.collected_at)) >= game_private.setting('offline_batches') * good.cycle_seconds then now()
     else biz.collected_at + make_interval(secs => batches * good.cycle_seconds) end
     where player_id = uid and good_id = good.id and season_id=season;
   insert into public.game_events(player_id,description) values (uid,'Collected ' || qty || ' ' || lower(good.name));
   result_message := qty || ' ' || lower(good.name) || ' added to your inventory.';
 when 'list' then
   qty := (p_payload->>'quantity')::integer; price := (p_payload->>'unit_price')::integer;
   if qty is null or price is null or qty < 1 or qty > game_private.setting('max_listing_quantity') or price < 1 or price > game_private.setting('max_unit_price') then raise exception 'Use a quantity of 1–1,000 and a unit price of $1–$1,000,000.'; end if;
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown goods.'; end if;
   if (select count(*) from public.game_listings where seller_id = uid and status = 'active' and season_id=season) >= game_private.setting('listing_limit') then raise exception 'Your active offer limit has been reached.'; end if;
   update public.game_inventory set quantity = quantity - qty
     where player_id = uid and good_id = good.id and season_id=season and quantity >= qty;
   if not found then raise exception 'You do not have enough goods. Listed stock is already reserved.'; end if;
   insert into public.game_listings(seller_id,seller_handle,good_id,quantity,unit_price) values(uid,p.handle,good.id,qty,price);
   insert into public.game_events(player_id,description) values (uid,'Listed ' || qty || ' ' || lower(good.name) || ' at $' || price || ' each');
   result_message := 'Offer posted. Your goods are reserved until sold or cancelled.';
 when 'buy' then
   total := listing.quantity::bigint * listing.unit_price;
   fee := (total * game_private.setting('market_fee_percent') + 99) / 100;
   if p.cash < total then raise exception 'Not enough cash to buy this lot.'; end if;
   update public.game_players set cash = cash - total where id = uid;
   update public.game_players set cash = cash + total - fee where id = listing.seller_id;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'sold' where id = listing.id;
   insert into public.game_events(player_id,description,cash_delta) values
     (uid,'Bought ' || listing.quantity || ' ' || listing.good_id || ' from ' || listing.seller_handle,-total),
     (listing.seller_id,'Sold ' || listing.quantity || ' ' || listing.good_id || ' · $' || fee || ' market fee',total-fee);
   result_message := 'Deal closed. Goods delivered to your inventory.';
 when 'cancel' then
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'cancelled' where id = listing.id;
   insert into public.game_events(player_id,description) values (uid,'Cancelled an offer · ' || listing.quantity || ' ' || listing.good_id || ' returned');
   result_message := 'Offer withdrawn. Reserved stock returned.';
 else raise exception 'Unknown game action.';
 end case;
 return jsonb_build_object('message',result_message);
end $$;


create function game_private.staff_action_foundation(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare target_id uuid; required text; reason text:=trim(payload->>'reason'); duration_minutes integer; v_case public.game_cases; v_role text; v_permission text;
begin
 perform game_private.require_active();
 if not game_private.rate('staff',30) then return jsonb_build_object('error','Too many requests. Wait a minute.'); end if;
 begin
 if length(coalesce(reason,'')) not between 3 and 2000 then raise exception 'Provide a reason of 3–2000 characters.'; end if;
 perform set_config('game.reason',reason,true);
 required:=case action when 'warn' then 'players.warn' when 'mute' then 'players.mute' when 'kick' then 'players.kick'
 when 'ban_temporary' then 'players.ban_temporary' when 'ban_permanent' then 'players.ban_permanent'
 when 'setting' then 'economy.manage' when 'job' then 'economy.manage' when 'good' then 'economy.manage'
 when 'role' then 'roles.manage' when 'permission' then 'roles.manage' when 'delete_chat' then 'chat.delete'
 when 'evidence' then 'evidence.view' when 'grant_money' then 'money.grant' when 'spawn_asset' then 'assets.spawn'
 when 'revoke_sanction' then 'players.ban_permanent' end;
 if action='case' then
 select * into strict v_case from public.game_cases where id=(payload->>'id')::uuid for update;
 required:=case when v_case.kind='report' then 'reports.review' else 'tickets.manage' end;
 end if;
 if required is null or not game_private.has_permission(required) then raise exception 'Permission denied.'; end if;
 if action in ('warn','mute','kick','ban_temporary','ban_permanent','role','grant_money','spawn_asset') then
 target_id:=(payload->>'player_id')::uuid;
 perform id from public.game_players where id=target_id for update;
 if not found then raise exception 'Player not found.'; end if;
 if exists(select 1 from public.game_user_roles u join public.game_roles r on r.id=u.role_id where u.player_id=target_id and r.is_owner)
 and not game_private.has_permission('roles.manage') then raise exception 'Moderators cannot act on Owners.'; end if;
 end if;
 case action
 when 'warn','mute','ban_temporary','ban_permanent' then
 if action in ('mute','ban_temporary') then
 duration_minutes:=(payload->>'minutes')::integer;
 if duration_minutes is null or duration_minutes not between 1 and 525600 then raise exception 'Duration must be 1–525600 minutes.'; end if;
 end if;
 insert into public.game_sanctions(player_id,kind,reason,expires_at,actor_id)
 values(target_id,case when action='warn' then 'warning' when action='mute' then 'mute' else 'ban' end,reason,
 case when duration_minutes is not null then now()+make_interval(mins=>duration_minutes) end,auth.uid());
 when 'kick' then
 update public.game_players set sessions_revoked_at=clock_timestamp() where id=target_id;
 insert into public.game_audit(actor_id,action,target,reason) values(auth.uid(),'players.kick',target_id::text,reason);
 when 'revoke_sanction' then
 if exists(select 1 from public.game_sanctions s join public.game_user_roles u on u.player_id=s.player_id join public.game_roles r on r.id=u.role_id
 where s.id=(payload->>'id')::uuid and r.is_owner) and not game_private.has_permission('roles.manage') then raise exception 'Permission denied.'; end if;
 update public.game_sanctions set revoked_at=now() where id=(payload->>'id')::uuid;
 when 'setting' then
 update public.game_settings set value=(payload->>'value')::integer where key=payload->>'key';
 if not found then raise exception 'Unknown setting.'; end if;
 if game_private.setting('rank_soldier')>=game_private.setting('rank_caporegime') or game_private.setting('rank_caporegime')>=game_private.setting('rank_underboss') then raise exception 'Rank thresholds must remain in ascending order.'; end if;
 when 'job' then
 update public.game_jobs set reward=(payload->>'reward')::integer,xp=(payload->>'xp')::integer,cooldown=(payload->>'cooldown')::integer where id=payload->>'id';
 when 'good' then
 if (payload->>'batch_size')::integer not between 1 and 1000 or (payload->>'cycle_seconds')::integer not between 1 and 86400
 or (payload->>'business_cost')::integer not between 1 and 100000000 then raise exception 'Business values outside allowed range.'; end if;
 update public.game_goods set business_cost=(payload->>'business_cost')::integer,batch_size=(payload->>'batch_size')::integer,cycle_seconds=(payload->>'cycle_seconds')::integer where id=payload->>'id';
 when 'permission' then
 v_role:=payload->>'role_id'; v_permission:=payload->>'permission_id';
 if v_role<>'moderator' then raise exception 'Only Moderator permissions can be configured here.'; end if;
 if exists(select 1 from public.game_permissions where id=v_permission and owner_only) then raise exception 'This permission is reserved for Owner.'; end if;
 if (payload->>'enabled')::boolean then insert into public.game_role_permissions values(v_role,v_permission) on conflict do nothing;
 else delete from public.game_role_permissions where role_id=v_role and permission_id=v_permission; end if;
 when 'role' then
 -- Serialize role changes to prevent concurrent removal of the last Owner.
 perform pg_advisory_xact_lock(7192026);
 v_role:=payload->>'role_id';
 if v_role<>'owner' and exists(select 1 from public.game_user_roles where player_id=target_id and role_id='owner')
 and (select count(*) from public.game_user_roles where role_id='owner')<=1 then raise exception 'The last Owner cannot be removed.'; end if;
 insert into public.game_user_roles values(target_id,v_role) on conflict(player_id) do update set role_id=excluded.role_id;
 when 'grant_money' then
 if (payload->>'amount')::bigint not between 1 and 100000000 then raise exception 'Amount must be 1–100000000.'; end if;
 update public.game_players set cash=cash+(payload->>'amount')::bigint where id=target_id;
 insert into public.game_audit(actor_id,action,target,after_data,reason) values(auth.uid(),action,target_id::text,payload-'reason',reason);
 when 'spawn_asset' then
 if (payload->>'quantity')::integer not between 1 and 1000 then raise exception 'Quantity must be 1–1000.'; end if;
 insert into public.game_inventory as i(player_id,good_id,quantity) values(target_id,payload->>'good_id',(payload->>'quantity')::integer)
 on conflict(season_id,player_id,good_id) do update set quantity=i.quantity+excluded.quantity;
 insert into public.game_audit(actor_id,action,target,after_data,reason) values(auth.uid(),action,target_id::text,payload-'reason',reason);
 when 'delete_chat' then update public.game_chat set deleted_at=now() where id=(payload->>'id')::uuid and deleted_at is null;
 when 'case' then update public.game_cases set status=payload->>'status',response=left(payload->>'response',4000) where id=v_case.id;
 when 'evidence' then
 if not exists(select 1 from public.game_cases c where c.id=(payload->>'case_id')::uuid and game_private.has_permission(case c.kind when 'report' then 'reports.review' else 'tickets.manage' end)) then raise exception 'Permission denied.'; end if;
 insert into public.game_evidence(case_id,body,actor_id) values((payload->>'case_id')::uuid,payload->>'body',auth.uid());
 end case;
 return jsonb_build_object('message','Saved. The action has been audited.');
 exception when others then
 if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
 raise log 'staff_action failed code=% action=%',SQLSTATE,required;
 return jsonb_build_object('error','Invalid request. Check the identifiers and allowed values.');
 end;
end $$;


create or replace function game_private.dispatch(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare season uuid; before_qty bigint; after_qty bigint; seller uuid; trade_value bigint; result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
 season:=game_private.season_guard();
 if p_payload ? 'season_id' and (p_payload->>'season_id')::uuid<>season then raise exception 'Season changed. Refresh before trying again.'; end if;
 -- The shared season lock makes snapshot/reset mutually exclusive with gameplay.
 if p_action='collect' then
 perform id from public.game_players where id=auth.uid() for update;
 select coalesce(sum(quantity),0) into before_qty from public.game_inventory where player_id=auth.uid() and season_id=season;
 elsif p_action='buy' then
 select seller_id,quantity::bigint*unit_price into seller,trade_value from public.game_listings where id=(p_payload->>'listing_id')::uuid and season_id=season;
 end if;
 perform set_config('game.reason',p_action,true);
 result:=game_private.act(p_action,p_payload);
 if p_action='job' then perform game_private.record_metric(auth.uid(),'crime',1);
 elsif p_action='business' then perform game_private.record_metric(auth.uid(),'construction',1);
 elsif p_action='collect' then
 select coalesce(sum(quantity),0) into after_qty from public.game_inventory where player_id=auth.uid() and season_id=season;
 perform game_private.record_metric(auth.uid(),'production',after_qty-before_qty);
 elsif p_action='buy' then perform game_private.record_metric(seller,'trading',trade_value);
 end if;
 return result;
 exception when others then
 if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
 raise log 'season gameplay failure code=%',SQLSTATE;
 return jsonb_build_object('error','This action could not be completed. Refresh and check your values.');
 end;
end $$;
create or replace function game_private.staff_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if action in ('setting','job','good','grant_money','spawn_asset') then
 perform game_private.require_active();
 begin perform game_private.season_guard(); exception when raise_exception then return jsonb_build_object('error',SQLERRM); end;
 end if;
 return game_private.staff_action_foundation(action,payload);
end $$;

insert into public.game_permissions values('seasons.manage',true),('leaderboards.manage',true);

create function game_private.season_scores(p_season uuid,p_metric text)
returns table(player_id uuid,handle text,score numeric) language sql stable security definer set search_path='' as $$
with base as (
 select sp.player_id,p.handle,sp.cash,sp.xp,
 coalesce((select sum(i.quantity::numeric*v.unit_value) from public.game_inventory i join public.game_season_valuations v on v.season_id=i.season_id and v.good_id=i.good_id where i.season_id=p_season and i.player_id=sp.player_id),0)
 +coalesce((select sum(l.quantity::numeric*v.unit_value) from public.game_listings l join public.game_season_valuations v on v.season_id=l.season_id and v.good_id=l.good_id where l.season_id=p_season and l.seller_id=sp.player_id and l.status='active'),0) as stock_value,
 coalesce((select sum(g.business_cost::numeric) from public.game_businesses b join public.game_goods g on g.id=b.good_id where b.season_id=p_season and b.player_id=sp.player_id),0) as business_value,
 coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=sp.player_id),0) as asset_value,
 coalesce((select sum(l.outstanding::numeric) from public.game_season_loans l where l.season_id=p_season and l.player_id=sp.player_id),0) as debt
 from public.game_season_players sp join public.game_players p on p.id=sp.player_id
 join public.game_leaderboards board on board.season_id=sp.season_id and board.metric=p_metric
 where sp.season_id=p_season and p.deleted_at is null and (board.include_banned or not exists(
 select 1 from public.game_sanctions s where s.player_id=p.id and s.kind='ban' and s.revoked_at is null and (s.expires_at is null or s.expires_at>now())))
)
select b.player_id,b.handle,case p_metric
 when 'cash' then b.cash::numeric when 'respect' then b.xp::numeric
 when 'net_worth' then b.cash+b.stock_value+b.business_value+b.asset_value-b.debt
 when 'land' then coalesce((select sum(a.quantity::numeric) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='land'),0)
 when 'company_value' then coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='company'),0)
 when 'factory_value' then b.business_value+coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='factory'),0)
 when 'gang_contribution' then coalesce((select sum(m.contribution::numeric) from public.game_season_gang_members m where m.season_id=p_season and m.player_id=b.player_id),0)
 else coalesce((select s.value::numeric from public.game_season_stats s where s.season_id=p_season and s.player_id=b.player_id and s.metric=p_metric),0) end
from base b
$$;
create function game_private.season_ranking(p_season uuid,p_metric text)
returns table(player_id uuid,handle text,score numeric,rank bigint) language sql stable security definer set search_path='' as $$
 select s.player_id,s.handle,s.score,rank() over(order by
 case when b.direction='desc' then s.score end desc,
 case when b.direction='asc' then s.score end asc)
 from game_private.season_scores(p_season,p_metric) s
 join public.game_leaderboards b on b.season_id=p_season and b.metric=p_metric
$$;

create function game_private.season_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.game_seasons; current_s public.game_seasons; target uuid; reason text:=trim(payload->>'reason'); board_config public.game_leaderboards;
begin
 perform game_private.require_active();
 if not game_private.has_permission(case when action in ('reset','launch_next') then 'seasons.reset'
 when action in ('leaderboard','valuation') then 'leaderboards.manage' else 'seasons.manage' end) then return jsonb_build_object('error','Permission denied.'); end if;
 if not game_private.rate('season_admin',20) then return jsonb_build_object('error','Too many requests. Wait a minute.'); end if;
 begin
 perform pg_advisory_xact_lock(4704001);
 if length(coalesce(reason,'')) not between 3 and 2000 then raise exception 'Provide an audit reason of 3–2000 characters.'; end if;
 perform set_config('game.reason',reason,true);
 select * into strict current_s from public.game_seasons where id=game_private.current_season() for update;
 if action='create' then
 insert into public.game_seasons(name,starting_cash,starting_crates)
 values(trim(payload->>'name'),game_private.setting('starting_cash'),game_private.setting('starting_crates')) returning id into target;
 insert into public.game_leaderboards(season_id,metric,label,enabled,direction,include_banned,hall_of_fame)
 select target,metric,label,enabled,direction,include_banned,hall_of_fame from public.game_leaderboards where season_id=current_s.id;
 insert into public.game_season_valuations select target,good_id,unit_value from public.game_season_valuations where season_id=current_s.id;
 else
 target:=(payload->>'season_id')::uuid;
 select * into strict s from public.game_seasons where id=target for update;
 case action
 when 'configure' then
 if s.status not in ('draft','open','locked') then raise exception 'Finalized season configuration is immutable.'; end if;
 if s.id=current_s.id and s.status='draft' then raise exception 'Reset is already prepared. Launch this season before editing it.'; end if;
 update public.game_seasons set name=trim(payload->>'name'),
 starting_cash=case when s.status='draft' then (payload->>'starting_cash')::bigint else starting_cash end,
 starting_crates=case when s.status='draft' then (payload->>'starting_crates')::integer else starting_crates end,
 starts_at=nullif(payload->>'starts_at','')::timestamptz,ends_at=nullif(payload->>'ends_at','')::timestamptz,
 hall_of_fame_places=(payload->>'hall_of_fame_places')::integer where id=target;
 when 'leaderboard' then
 if s.status in ('finalized','archived') then raise exception 'Finalized leaderboards are immutable.'; end if;
 update public.game_leaderboards set label=trim(payload->>'label'),enabled=(payload->>'enabled')::boolean,
 direction=payload->>'direction',include_banned=(payload->>'include_banned')::boolean,hall_of_fame=(payload->>'hall_of_fame')::boolean
 where season_id=target and metric=payload->>'metric';
 if not found then raise exception 'Unknown ranking category.'; end if;
 when 'valuation' then
 if s.status in ('finalized','archived') then raise exception 'Finalized valuations are immutable.'; end if;
 update public.game_season_valuations set unit_value=(payload->>'unit_value')::bigint where season_id=target and good_id=payload->>'good_id';
 if not found then raise exception 'Unknown commodity.'; end if;
 when 'lock' then
 if target<>current_s.id or s.status<>'open' then raise exception 'Only the current open season can be locked.'; end if;
 update public.game_seasons set status='locked',locked_at=least(clock_timestamp(),coalesce(ends_at,clock_timestamp())) where id=target;
 when 'open','launch' then
 if target<>current_s.id or s.status not in ('draft','locked') then raise exception 'Prepare a reset before opening a new season.'; end if;
 if s.starts_at is not null and clock_timestamp()<s.starts_at then raise exception 'The configured start time has not arrived.'; end if;
 if s.ends_at is not null and clock_timestamp()>=s.ends_at then raise exception 'Change the season end time before reopening.'; end if;
 if s.status='locked' then
 update public.game_businesses set collected_at=collected_at+(clock_timestamp()-s.locked_at) where season_id=target;
 update public.game_players set job_ready_at=greatest(job_ready_at,s.locked_at)+(clock_timestamp()-s.locked_at) where season_id=target;
 end if;
 update public.game_seasons set status='open',opened_at=coalesce(opened_at,clock_timestamp()),locked_at=null where id=target;
 when 'snapshot' then
 if target<>current_s.id or s.status<>'locked' then raise exception 'Lock the current season before capturing final results.'; end if;
 for board_config in select * from public.game_leaderboards where season_id=target and enabled loop
 insert into public.game_season_results(season_id,metric,player_id,handle,label,score,rank)
 select target,board_config.metric,r.player_id,r.handle,board_config.label,r.score,r.rank from game_private.season_ranking(target,board_config.metric) r;
 end loop;
 update public.game_seasons set status='finalized',finalized_at=clock_timestamp() where id=target;
 when 'archive' then
 if s.status<>'finalized' then raise exception 'Capture final results before archiving.'; end if;
 insert into public.game_hall_of_fame(season_id,metric,player_id,rank,label,handle,score)
 select r.season_id,r.metric,r.player_id,r.rank,r.label,r.handle,r.score from public.game_season_results r
 join public.game_leaderboards b on b.season_id=r.season_id and b.metric=r.metric
 where r.season_id=target and b.hall_of_fame and r.rank<=s.hall_of_fame_places;
 update public.game_seasons set status='archived',archived_at=clock_timestamp() where id=target;
 when 'reset','launch_next' then
 if current_s.status<>'archived' or current_s.reset_at is not null or s.status<>'draft' or target=current_s.id then raise exception 'Archive the current season and select a fresh draft season first.'; end if;
 if payload->>'confirmation' is distinct from ('RESET '||current_s.name) or (payload->>'expected_current_season')::uuid is distinct from current_s.id then raise exception 'Reset confirmation does not match the current season.'; end if;
 if action='launch_next' and ((s.starts_at is not null and clock_timestamp()<s.starts_at) or (s.ends_at is not null and clock_timestamp()>=s.ends_at)) then raise exception 'The next season is outside its configured launch window.'; end if;
 -- Close each old wallet in its old ledger, preserving the final season-player record.
 perform set_config('game.season_reset','closing',true);
 perform set_config('game.reason','Season close: '||current_s.name||' / '||reason,true);
 update public.game_players set cash=0 where season_id=current_s.id;
 update public.game_seasons set reset_at=clock_timestamp() where id=current_s.id;
 update game_private.season_runtime set season_id=target where singleton;
 perform set_config('game.season_reset','opening',true);
 perform set_config('game.reason','Season opening: '||s.name||' / '||reason,true);
 update public.game_players set season_id=target,cash=s.starting_cash,xp=0,job_ready_at=clock_timestamp();
 insert into public.game_inventory(season_id,player_id,good_id,quantity)
 select target,id,'whiskey',s.starting_crates from public.game_players;
 -- New season keys mean empty skills, levels=1, assets, gangs, loans, queues, stats and market.
 -- No historical gameplay, financial records, subscriptions or moderation data is deleted.
 if action='launch_next' then update public.game_seasons set status='open',opened_at=clock_timestamp() where id=target; end if;
 perform set_config('game.season_reset','',true);
 else raise exception 'Unknown season action.';
 end case;
 end if;
 insert into public.game_audit(actor_id,action,target,reason,after_data)
 values(auth.uid(),'season.'||action,target::text,reason,jsonb_build_object('previous_current',current_s.id,'current',game_private.current_season()));
 return jsonb_build_object('message','Season action completed.','season_id',target);
 exception when others then
 if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
 raise log 'season admin failure code=%',SQLSTATE;
 return jsonb_build_object('error','Invalid season request. Check the fields and current season status.');
 end;
end $$;

create function game_private.season_state(p_season uuid,p_metric text,p_offset integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_season,game_private.current_season()); selected public.game_seasons; rows jsonb; total bigint; my_rank jsonb;
begin
 perform game_private.require_active(); perform game_private.season_guard(false);
 if p_offset is null or p_offset<0 or p_offset>1000000 then raise exception 'Invalid page.'; end if;
 select * into strict selected from public.game_seasons where id=target;
 if exists(select 1 from public.game_leaderboards where season_id=target and metric=p_metric and enabled) then
 if selected.status in ('finalized','archived') then
 select count(*) into total from public.game_season_results where season_id=target and metric=p_metric;
 select coalesce(jsonb_agg(r order by r.rank,r.player_id),'[]') into rows from
 (select player_id,handle,score,rank from public.game_season_results where season_id=target and metric=p_metric order by rank,player_id limit 100 offset p_offset) r;
 select to_jsonb(r) into my_rank from (select player_id,handle,score,rank from public.game_season_results where season_id=target and metric=p_metric and player_id=auth.uid()) r;
 else
 select count(*) into total from game_private.season_ranking(target,p_metric);
 select coalesce(jsonb_agg(r order by r.rank,r.player_id),'[]') into rows from
 (select * from game_private.season_ranking(target,p_metric) order by rank,player_id limit 100 offset p_offset) r;
 select to_jsonb(r) into my_rank from game_private.season_ranking(target,p_metric) r where player_id=auth.uid();
 end if;
 end if;
 return jsonb_build_object(
 'current_season_id',game_private.current_season(),'season',to_jsonb(selected),
 'seasons',(select jsonb_agg(s order by s.created_at desc) from public.game_seasons s),
 'boards',(select jsonb_agg(b order by b.metric) from
 (select b.*,c.available,c.description from public.game_leaderboards b join public.game_metric_catalog c on c.id=b.metric where b.season_id=target) b),
 'valuations',(select jsonb_agg(v) from public.game_season_valuations v where v.season_id=target),
 'rankings',coalesce(rows,'[]'),'total',coalesce(total,0),'offset',p_offset,'metric',p_metric,'my_rank',my_rank,
 'hall_of_fame',(select coalesce(jsonb_agg(h order by h.awarded_at desc,h.rank,h.player_id),'[]') from
 (select h.*,s.name as season_name from public.game_hall_of_fame h join public.game_seasons s on s.id=h.season_id order by h.awarded_at desc,h.rank,h.player_id limit 100 offset p_offset) h),
 'hall_total',(select count(*) from public.game_hall_of_fame),
 'can_manage',game_private.has_permission('seasons.manage'),
 'can_reset',game_private.has_permission('seasons.reset'),
 'server_time',clock_timestamp()
 );
end $$;
create function game_private.season_profile(p_player uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare current_rows jsonb; past_rows jsonb; profile_handle text;
begin
 perform game_private.require_active(); perform game_private.season_guard(false);
 select handle into strict profile_handle from public.game_players where id=p_player and deleted_at is null;
 select coalesce(jsonb_agg(r order by r.metric),'[]') into current_rows from (
 select b.metric,b.label,r.score,r.rank from public.game_leaderboards b
 cross join lateral game_private.season_ranking(b.season_id,b.metric) r
 where b.season_id=game_private.current_season() and b.enabled and r.player_id=p_player
 and (select status from public.game_seasons where id=b.season_id) not in ('finalized','archived')
 union all
 select r.metric,r.label,r.score,r.rank from public.game_season_results r
 where r.season_id=game_private.current_season() and r.player_id=p_player
 ) r;
 select coalesce(jsonb_agg(r order by r.archived_at desc,r.metric),'[]') into past_rows from (
 select r.*,s.name as season_name,s.archived_at from public.game_season_results r join public.game_seasons s on s.id=r.season_id
 where r.player_id=p_player and s.status='archived'
 ) r;
 return jsonb_build_object('player_id',p_player,'handle',profile_handle,'current',current_rows,'previous',past_rows,
 'current_season',(select name from public.game_seasons where id=game_private.current_season()),
 'hall_of_fame',(select coalesce(jsonb_agg(h),'[]') from public.game_hall_of_fame h where player_id=p_player));
end $$;
create function public.season_action(action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.season_action(action,payload); $$;
create function public.season_state(p_season uuid default null,p_metric text default 'net_worth',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$ select game_private.season_state(p_season,p_metric,p_offset); $$;
create function public.season_profile(p_player uuid) returns jsonb language sql security invoker set search_path='' as $$ select game_private.season_profile(p_player); $$;
alter table public.game_seasons enable row level security;
revoke all on public.game_seasons from public,anon,authenticated;
alter table public.game_season_players enable row level security;
revoke all on public.game_season_players from public,anon,authenticated;
alter table public.game_season_assets enable row level security;
revoke all on public.game_season_assets from public,anon,authenticated;
alter table public.game_season_gangs enable row level security;
revoke all on public.game_season_gangs from public,anon,authenticated;
alter table public.game_season_gang_members enable row level security;
revoke all on public.game_season_gang_members from public,anon,authenticated;
alter table public.game_season_loans enable row level security;
revoke all on public.game_season_loans from public,anon,authenticated;
alter table public.game_season_jobs enable row level security;
revoke all on public.game_season_jobs from public,anon,authenticated;
alter table public.game_season_stats enable row level security;
revoke all on public.game_season_stats from public,anon,authenticated;
alter table public.game_metric_catalog enable row level security;
revoke all on public.game_metric_catalog from public,anon,authenticated;
alter table public.game_leaderboards enable row level security;
revoke all on public.game_leaderboards from public,anon,authenticated;
alter table public.game_season_valuations enable row level security;
revoke all on public.game_season_valuations from public,anon,authenticated;
alter table public.game_season_results enable row level security;
revoke all on public.game_season_results from public,anon,authenticated;
alter table public.game_hall_of_fame enable row level security;
revoke all on public.game_hall_of_fame from public,anon,authenticated;
create trigger immutable_rows before update or delete on public.game_season_results for each row execute function game_private.immutable();
create trigger immutable_truncate before truncate on public.game_season_results for each statement execute function game_private.immutable();
create trigger immutable_rows before update or delete on public.game_hall_of_fame for each row execute function game_private.immutable();
create trigger immutable_truncate before truncate on public.game_hall_of_fame for each statement execute function game_private.immutable();
create trigger audit_changes after insert or update or delete on public.game_seasons for each row execute function game_private.audit_change();
create trigger audit_changes after insert or update or delete on public.game_leaderboards for each row execute function game_private.audit_change();
create trigger audit_changes after insert or update or delete on public.game_season_valuations for each row execute function game_private.audit_change();
create trigger audit_changes after insert or update or delete on public.game_season_loans for each row execute function game_private.audit_change();
create policy current_season_only on public.game_inventory as restrictive for select to authenticated using (season_id=(select game_private.current_season()));
create policy current_season_only on public.game_businesses as restrictive for select to authenticated using (season_id=(select game_private.current_season()));
create policy current_season_only on public.game_listings as restrictive for select to authenticated using (season_id=(select game_private.current_season()));
create policy current_season_only on public.game_ledger as restrictive for select to authenticated using (season_id=(select game_private.current_season()));
create policy current_season_only on public.game_events as restrictive for select to authenticated using (season_id=(select game_private.current_season()));

-- Season APIs use guarded dispatchers; none of the internal score or reset helpers is exposed.
revoke all on all functions in schema game_private from public,anon,authenticated;
grant execute on function game_private.active(),game_private.current_season(),game_private.dispatch(text,jsonb),game_private.read_state(),
game_private.staff_state(),game_private.staff_action(text,jsonb),game_private.community_state(),game_private.community_action(text,jsonb),
game_private.season_state(uuid,text,integer),game_private.season_action(text,jsonb),game_private.season_profile(uuid) to authenticated;
revoke all on function public.season_state(uuid,text,integer),public.season_action(text,jsonb),public.season_profile(uuid) from public,anon;
grant execute on function public.season_state(uuid,text,integer),public.season_action(text,jsonb),public.season_profile(uuid) to authenticated;
