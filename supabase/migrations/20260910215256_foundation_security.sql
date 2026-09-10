
-- Additive foundation: retain existing players, assets and history.
alter table public.game_players drop constraint game_players_id_fkey;
alter table public.game_players add constraint game_players_id_fkey foreign key(id) references auth.users(id) on delete restrict;
alter table public.game_players add column deleted_at timestamptz, add column sessions_revoked_at timestamptz;
alter table public.game_events drop constraint game_events_player_id_fkey;
alter table public.game_events add constraint game_events_player_id_fkey foreign key(player_id) references public.game_players(id) on delete restrict;
alter table public.game_listings drop constraint game_listings_seller_id_fkey;
alter table public.game_listings add constraint game_listings_seller_id_fkey foreign key(seller_id) references public.game_players(id) on delete restrict;

alter table public.game_players alter column cash drop default;
create table public.game_ledger (
 id bigint generated always as identity primary key, player_id uuid not null references public.game_players(id),
 balance_before bigint not null, delta bigint not null, balance_after bigint not null,
 reason text not null, actor_id uuid, created_at timestamptz not null default now(),
 check(balance_before + delta = balance_after)
);
create index on public.game_ledger(player_id,created_at desc);
insert into public.game_ledger(player_id,balance_before,delta,balance_after,reason)
 select id,0,cash,cash,'Migration opening balance; earlier activity retained in game_events' from public.game_players;
create table public.game_audit (
 id bigint generated always as identity primary key, actor_id uuid, action text not null,
 target text, before_data jsonb, after_data jsonb, reason text,
 created_at timestamptz not null default now()
);
create index on public.game_audit(created_at desc);
create function game_private.immutable() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Historical records cannot be changed or deleted.'; end $$;
create trigger immutable_rows before update or delete on public.game_ledger for each row execute function game_private.immutable();
create trigger immutable_truncate before truncate on public.game_ledger for each statement execute function game_private.immutable();
create trigger immutable_rows before update or delete on public.game_audit for each row execute function game_private.immutable();
create trigger immutable_truncate before truncate on public.game_audit for each statement execute function game_private.immutable();
create trigger immutable_rows before update or delete on public.game_events for each row execute function game_private.immutable();
create trigger immutable_truncate before truncate on public.game_events for each statement execute function game_private.immutable();

create function game_private.wallet_entry() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
 insert into public.game_ledger(player_id,balance_before,delta,balance_after,reason,actor_id)
 values(new.id,0,new.cash,new.cash,coalesce(nullif(current_setting('game.reason',true),''),'Starting balance'),auth.uid());
 elsif new.cash <> old.cash then
 insert into public.game_ledger(player_id,balance_before,delta,balance_after,reason,actor_id)
 values(new.id,old.cash,new.cash-old.cash,new.cash,coalesce(nullif(current_setting('game.reason',true),''),'Database balance adjustment'),auth.uid());
 end if; return new;
end $$;
create trigger wallet_entry after insert or update of cash on public.game_players for each row execute function game_private.wallet_entry();

create table public.game_roles (id text primary key, name text not null, is_owner boolean not null default false);
insert into public.game_roles values('owner','Owner',true),('moderator','Moderator',false),('player','Player',false);
create table public.game_permissions (id text primary key, owner_only boolean not null default false);
insert into public.game_permissions values
 ('players.warn',false),('players.mute',false),('players.kick',false),('players.ban_temporary',false),('players.ban_permanent',false),
 ('reports.review',false),('tickets.manage',false),('chat.delete',false),('evidence.view',false),
 ('economy.manage',true),('money.grant',true),('assets.spawn',true),('seasons.reset',true),('roles.manage',true),('audit.view',true);
create table public.game_role_permissions (
 role_id text references public.game_roles(id), permission_id text references public.game_permissions(id), primary key(role_id,permission_id)
);
insert into public.game_role_permissions select 'moderator',id from public.game_permissions where not owner_only;
create table public.game_user_roles (
 player_id uuid primary key references public.game_players(id), role_id text not null references public.game_roles(id)
);
insert into public.game_user_roles select id,'player' from public.game_players;
create index on public.game_user_roles(role_id);
create function game_private.has_permission(permission text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.game_user_roles u join public.game_roles r on r.id=u.role_id
 where u.player_id=auth.uid() and (r.is_owner or exists(select 1 from public.game_role_permissions rp
 join public.game_permissions p on p.id=rp.permission_id where rp.role_id=r.id and p.id=permission and not p.owner_only)))
$$;
create table public.game_settings (
 key text primary key, value integer not null, minimum integer not null, maximum integer not null,
 check(value between minimum and maximum)
);
insert into public.game_settings values
 ('starting_cash',10000,0,100000000),('starting_crates',5,0,1000),('market_fee_percent',5,0,100),
 ('listing_limit',20,1,100),('max_listing_quantity',1000,1,1000),('max_unit_price',1000000,1,1000000),
 ('offline_batches',24,1,1000),('actions_per_minute',60,10,300),
 ('rank_soldier',250,1,1000000),('rank_caporegime',800,1,1000000),('rank_underboss',2000,1,1000000);
create table public.game_jobs (
 id text primary key, name text not null, district text not null, description text not null,
 reward integer not null check(reward between 0 and 100000000),
 xp integer not null check(xp between 0 and 1000000),
 cooldown integer not null check(cooldown between 1 and 86400)
);
insert into public.game_jobs values
 ('docks','Dock errand','THE DOCKS','Build connections along the waterfront.',250,10,60),
 ('warehouse','Warehouse shift','INDUSTRIAL QUARTER','Keep the goods moving.',600,20,180),
 ('courier','Night courier','OLD TOWN','Work the night shift.',1100,40,360);
create function game_private.setting(k text) returns integer language sql stable security definer set search_path='' as $$
 select value from public.game_settings where key=k
$$;
create function game_private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.game_audit(actor_id,action,target,before_data,after_data,reason)
 values(auth.uid(),TG_TABLE_NAME||'.'||lower(TG_OP),TG_TABLE_NAME,case when TG_OP<>'INSERT' then to_jsonb(old) end,
 case when TG_OP<>'DELETE' then to_jsonb(new) end,current_setting('game.reason',true));
 return coalesce(new,old);
end $$;
create table public.game_sanctions (
 id uuid primary key default gen_random_uuid(), player_id uuid not null references public.game_players(id),
 kind text not null check(kind in ('warning','mute','ban')), reason text not null check(length(reason) between 3 and 2000),
 expires_at timestamptz, revoked_at timestamptz, actor_id uuid, created_at timestamptz not null default now()
);
create index on public.game_sanctions(player_id,kind);
create table public.game_chat (
 id uuid primary key default gen_random_uuid(), player_id uuid not null references public.game_players(id),
 body text not null check(length(body) between 1 and 1000), deleted_at timestamptz, created_at timestamptz not null default now()
);
create index on public.game_chat(created_at desc);
create table public.game_cases (
 id uuid primary key default gen_random_uuid(), player_id uuid not null references public.game_players(id),
 kind text not null check(kind in ('report','ticket')), subject text not null check(length(subject) between 3 and 160),
 body text not null check(length(body) between 3 and 4000),
 status text not null default 'open' check(status in ('open','investigating','resolved')),
 response text, deleted_at timestamptz, created_at timestamptz not null default now()
);
create index on public.game_cases(player_id,created_at desc);
create table public.game_evidence (
 id uuid primary key default gen_random_uuid(), case_id uuid not null references public.game_cases(id),
 body text not null check(length(body) between 3 and 4000), actor_id uuid, created_at timestamptz not null default now()
);
create index on public.game_evidence(case_id);
create trigger audit_change after insert or update or delete on public.game_settings for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_jobs for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_goods for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_user_roles for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_role_permissions for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_roles for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_permissions for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_sanctions for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_chat for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_cases for each row execute function game_private.audit_change();
create trigger audit_change after insert or update or delete on public.game_evidence for each row execute function game_private.audit_change();

create function game_private.active() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.game_players p where p.id=auth.uid() and
 (p.deleted_at is not null or (p.sessions_revoked_at is not null and not exists(
 select 1 from auth.sessions s where s.id=nullif(auth.jwt()->>'session_id','')::uuid and s.user_id=p.id and s.created_at>p.sessions_revoked_at))))
 and not exists(select 1 from public.game_sanctions s where s.player_id=auth.uid() and s.kind='ban' and s.revoked_at is null and (s.expires_at is null or s.expires_at>now()))
$$;
create function game_private.require_active() returns void language plpgsql security definer set search_path='' as $$
begin if not game_private.active() then raise exception 'Access suspended or session revoked. Sign in again; contact support if access remains suspended.'; end if; end $$;
create table game_private.rate_buckets (
 player_id uuid not null, scope text not null, window_start timestamptz not null, hits integer not null, primary key(player_id,scope)
);
create function game_private.rate(scope_name text, max_hits integer) returns boolean language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into game_private.rate_buckets as b values(auth.uid(),scope_name,date_trunc('minute',clock_timestamp()),1)
 on conflict(player_id,scope) do update set
 hits=case when b.window_start=date_trunc('minute',clock_timestamp()) then b.hits+1 else 1 end,
 window_start=date_trunc('minute',clock_timestamp()) returning hits into n;
 return n<=max_hits;
end $$;
create or replace function game_private.state()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid();
 p public.game_players;
begin
 if uid is null then raise exception 'Log in to enter Blackwater.'; end if;
 perform game_private.require_active();
 insert into public.game_players(id, handle, cash) values (uid, 'Rookie-' || left(uid::text, 8), game_private.setting('starting_cash'))
 on conflict (id) do nothing;
 if found then
   insert into public.game_inventory(player_id, good_id, quantity) values (uid, 'whiskey', game_private.setting('starting_crates'));
   insert into public.game_events(player_id, description, cash_delta)
     values (uid, 'Arrived in Blackwater · starting cash and goods', game_private.setting('starting_cash'));
 end if;
 insert into public.game_user_roles values(uid,'player') on conflict do nothing;
 select * into strict p from public.game_players where id = uid;
 return jsonb_build_object(
   'player', to_jsonb(p),
 'jobs',(select jsonb_agg(j order by j.reward) from public.game_jobs j),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings),
 'permissions',(select coalesce(jsonb_agg(id),'[]') from public.game_permissions where game_private.has_permission(id)),
 'ledger',(select coalesce(jsonb_agg(l order by l.id desc),'[]') from (select * from public.game_ledger where player_id=uid order by id desc limit 100) l),
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

create or replace function game_private.act(p_action text, p_payload jsonb default '{}'::jsonb)
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
   select j.reward,j.xp,j.cooldown,j.name into reward,xp_reward,cooldown,label from public.game_jobs j where j.id=p_payload->>'job';
   if not found then raise exception 'Unknown operation.'; end if;
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
   result_message := good.business_name || ' acquired. Production has started.';
 when 'collect' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   select * into biz from public.game_businesses where player_id = uid and good_id = good.id for update;
   if not found then raise exception 'You do not own this business.'; end if;
   batches := least(game_private.setting('offline_batches'), floor(extract(epoch from (now()-biz.collected_at))/good.cycle_seconds)::integer);
   if batches < 1 then raise exception 'Production is not ready yet.'; end if;
   qty := batches * good.batch_size;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values (uid,good.id,qty)
     on conflict(player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_businesses set collected_at = case
     when extract(epoch from (now()-biz.collected_at)) >= game_private.setting('offline_batches') * good.cycle_seconds then now()
     else biz.collected_at + make_interval(secs => batches * good.cycle_seconds) end
     where player_id = uid and good_id = good.id;
   insert into public.game_events(player_id,description) values (uid,'Collected ' || qty || ' ' || lower(good.name));
   result_message := qty || ' ' || lower(good.name) || ' added to your inventory.';
 when 'list' then
   qty := (p_payload->>'quantity')::integer; price := (p_payload->>'unit_price')::integer;
   if qty is null or price is null or qty < 1 or qty > game_private.setting('max_listing_quantity') or price < 1 or price > game_private.setting('max_unit_price') then raise exception 'Use a quantity of 1–1,000 and a unit price of $1–$1,000,000.'; end if;
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown goods.'; end if;
   if (select count(*) from public.game_listings where seller_id = uid and status = 'active') >= game_private.setting('listing_limit') then raise exception 'Your active offer limit has been reached.'; end if;
   update public.game_inventory set quantity = quantity - qty
     where player_id = uid and good_id = good.id and quantity >= qty;
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


-- Only the guarded dispatchers can invoke economic internals.
revoke all on function game_private.act(text,jsonb),game_private.state() from public,anon,authenticated;
create function game_private.dispatch(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
 perform set_config('game.reason',p_action,true);
 return game_private.act(p_action,p_payload);
 exception when others then
 if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
 raise log 'game_action failed code=% action=%',SQLSTATE,case when p_action in ('job','business','collect','list','buy','cancel') then p_action else 'unknown' end;
 return jsonb_build_object('error','This action could not be completed. Refresh and check your values.');
 end;
end $$;
create function game_private.read_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin perform game_private.require_active(); return game_private.state(); end $$;
create or replace function public.game_action(p_action text,p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select game_private.dispatch(p_action,p_payload); $$;
create or replace function public.game_state() returns jsonb language sql security invoker set search_path='' as $$ select game_private.read_state(); $$;

create function game_private.staff_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
 insert into public.game_inventory as i values(target_id,payload->>'good_id',(payload->>'quantity')::integer)
 on conflict(player_id,good_id) do update set quantity=i.quantity+excluded.quantity;
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

create function game_private.community_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not game_private.rate('community',10) then return jsonb_build_object('error','Too many messages. Wait a minute.'); end if;
 begin
 perform game_private.state();
 if action='chat' then
 if exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'You are muted.'; end if;
 insert into public.game_chat(player_id,body) values(auth.uid(),trim(payload->>'body'));
 elsif action in ('report','ticket') then
 insert into public.game_cases(player_id,kind,subject,body) values(auth.uid(),action,trim(payload->>'subject'),trim(payload->>'body'));
 elsif action='delete_own_chat' then update public.game_chat set deleted_at=now() where id=(payload->>'id')::uuid and player_id=auth.uid();
 elsif action='delete_own_case' then update public.game_cases set deleted_at=now() where id=(payload->>'id')::uuid and player_id=auth.uid();
 else raise exception 'Unknown action.'; end if;
 return jsonb_build_object('message','Saved.');
 exception when others then
 if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
 return jsonb_build_object('error','Check your message length and try again.');
 end;
end $$;
create function game_private.community_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 return jsonb_build_object(
 'chat',(select coalesce(jsonb_agg(c order by c.created_at desc),'[]') from
 (select c.*,p.handle from public.game_chat c join public.game_players p on p.id=c.player_id where c.deleted_at is null order by c.created_at desc limit 100) c),
 'cases',(select coalesce(jsonb_agg(c order by c.created_at desc),'[]') from public.game_cases c where player_id=auth.uid() and deleted_at is null),
 'sanctions',(select coalesce(jsonb_agg(s order by s.created_at desc),'[]') from public.game_sanctions s where player_id=auth.uid())
 );
end $$;
create function game_private.staff_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not exists(select 1 from public.game_permissions where game_private.has_permission(id)) then raise exception 'Permission denied.'; end if;
 return jsonb_build_object(
 'permissions',(select coalesce(jsonb_agg(id),'[]') from public.game_permissions where game_private.has_permission(id)),
 'players',(select coalesce(jsonb_agg(p),'[]') from (select p.id,p.handle,coalesce(u.role_id,'player') as role_id from public.game_players p left join public.game_user_roles u on u.player_id=p.id order by p.created_at desc limit 500) p),
 'sanctions',case when game_private.has_permission('evidence.view') then (select coalesce(jsonb_agg(s),'[]') from (select * from public.game_sanctions order by created_at desc limit 200) s) else '[]'::jsonb end,
 'cases',(select coalesce(jsonb_agg(c),'[]') from (select * from public.game_cases where (deleted_at is null or game_private.has_permission('evidence.view')) and game_private.has_permission(case kind when 'report' then 'reports.review' else 'tickets.manage' end) order by created_at desc limit 200) c),
 'evidence',(select coalesce(jsonb_agg(e),'[]') from (select e.* from public.game_evidence e join public.game_cases c on c.id=e.case_id where game_private.has_permission('evidence.view') and game_private.has_permission(case c.kind when 'report' then 'reports.review' else 'tickets.manage' end) order by e.created_at desc limit 200) e),
 'chat',(select coalesce(jsonb_agg(c),'[]') from (select * from public.game_chat where (deleted_at is null and game_private.has_permission('chat.delete')) or game_private.has_permission('evidence.view') order by created_at desc limit 100) c),
 'settings',case when game_private.has_permission('economy.manage') then (select jsonb_agg(s order by key) from public.game_settings s) else '[]'::jsonb end,
 'jobs',case when game_private.has_permission('economy.manage') then (select jsonb_agg(j) from public.game_jobs j) else '[]'::jsonb end,
 'goods',case when game_private.has_permission('economy.manage') then (select jsonb_agg(g) from public.game_goods g) else '[]'::jsonb end,
 'moderator_permissions',case when game_private.has_permission('roles.manage') then (select coalesce(jsonb_agg(permission_id),'[]') from public.game_role_permissions where role_id='moderator') else '[]'::jsonb end,
 'permission_catalog',case when game_private.has_permission('roles.manage') then (select jsonb_agg(p) from public.game_permissions p) else '[]'::jsonb end,
 'audit',case when game_private.has_permission('audit.view') then (select coalesce(jsonb_agg(a),'[]') from (select * from public.game_audit order by id desc limit 200) a) else '[]'::jsonb end
 );
end $$;
create function public.staff_state() returns jsonb language sql security invoker set search_path='' as $$ select game_private.staff_state(); $$;
create function public.staff_action(action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.staff_action(action,payload); $$;
create function public.community_state() returns jsonb language sql security invoker set search_path='' as $$ select game_private.community_state(); $$;
create function public.community_action(action text,payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.community_action(action,payload); $$;
alter table public.game_ledger enable row level security;
revoke all on public.game_ledger from public,anon,authenticated;
alter table public.game_audit enable row level security;
revoke all on public.game_audit from public,anon,authenticated;
alter table public.game_roles enable row level security;
revoke all on public.game_roles from public,anon,authenticated;
alter table public.game_permissions enable row level security;
revoke all on public.game_permissions from public,anon,authenticated;
alter table public.game_role_permissions enable row level security;
revoke all on public.game_role_permissions from public,anon,authenticated;
alter table public.game_user_roles enable row level security;
revoke all on public.game_user_roles from public,anon,authenticated;
alter table public.game_settings enable row level security;
revoke all on public.game_settings from public,anon,authenticated;
alter table public.game_jobs enable row level security;
revoke all on public.game_jobs from public,anon,authenticated;
alter table public.game_sanctions enable row level security;
revoke all on public.game_sanctions from public,anon,authenticated;
alter table public.game_chat enable row level security;
revoke all on public.game_chat from public,anon,authenticated;
alter table public.game_cases enable row level security;
revoke all on public.game_cases from public,anon,authenticated;
alter table public.game_evidence enable row level security;
revoke all on public.game_evidence from public,anon,authenticated;

-- Active-session checks also cover direct REST reads, beyond the UI/RPC boundary.
create policy active_session on public.game_players as restrictive for select to authenticated using ((select game_private.active()));
create policy active_session on public.game_goods as restrictive for select to authenticated using ((select game_private.active()));
create policy active_session on public.game_inventory as restrictive for select to authenticated using ((select game_private.active()));
create policy active_session on public.game_businesses as restrictive for select to authenticated using ((select game_private.active()));
create policy active_session on public.game_listings as restrictive for select to authenticated using ((select game_private.active()));
create policy active_session on public.game_events as restrictive for select to authenticated using ((select game_private.active()));

revoke all on all functions in schema game_private from public,anon,authenticated;
grant execute on function game_private.active(),game_private.dispatch(text,jsonb),game_private.read_state(),
 game_private.staff_state(),game_private.staff_action(text,jsonb),game_private.community_state(),game_private.community_action(text,jsonb) to authenticated;
revoke all on function public.staff_state(),public.staff_action(text,jsonb),public.community_state(),public.community_action(text,jsonb) from public,anon;
grant execute on function public.staff_state(),public.staff_action(text,jsonb),public.community_state(),public.community_action(text,jsonb) to authenticated;
-- Retain moderated content and evidence even when privileged maintenance is performed.
create function game_private.no_delete() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Use soft deletion or revocation; history must be retained.'; end $$;
create trigger retain_history before delete on public.game_chat for each row execute function game_private.no_delete();
create trigger retain_truncate before truncate on public.game_chat for each statement execute function game_private.no_delete();
create trigger retain_history before delete on public.game_cases for each row execute function game_private.no_delete();
create trigger retain_truncate before truncate on public.game_cases for each statement execute function game_private.no_delete();
create trigger retain_history before delete on public.game_evidence for each row execute function game_private.no_delete();
create trigger retain_truncate before truncate on public.game_evidence for each statement execute function game_private.no_delete();
create trigger retain_history before delete on public.game_sanctions for each row execute function game_private.no_delete();
create trigger retain_truncate before truncate on public.game_sanctions for each statement execute function game_private.no_delete();
