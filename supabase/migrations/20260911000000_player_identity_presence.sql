-- Public names are reserved atomically at signup and stay separate from editable Auth metadata.
create table game_private.identities (
 player_id uuid primary key references auth.users(id) on delete cascade,
 username text not null check(length(username) between 3 and 48),
 claimed boolean not null default false,
 created_at timestamptz not null default now()
);
create unique index identities_username_unique on game_private.identities(lower(username));
insert into game_private.identities(player_id,username)
 select u.id,coalesce(p.handle,'Player-'||replace(u.id::text,'-',''))
 from auth.users u left join public.game_players p on p.id=u.id;

create function game_private.valid_username(candidate text) returns boolean language sql immutable set search_path='' as $$
 select coalesce(candidate ~ '^[A-Za-z][A-Za-z0-9_-]{2,23}$'
 and lower(candidate) not in ('owner','admin','administrator','moderator','blackwater','system','support')
 and candidate !~* '^(Rookie|Player)-',false)
$$;
create function game_private.register_identity() returns trigger language plpgsql security definer set search_path='' as $$
declare candidate text:=nullif(btrim(new.raw_user_meta_data->>'username'),'');
begin
 if candidate is null then
  insert into game_private.identities(player_id,username) values(new.id,'Player-'||replace(new.id::text,'-',''));
 else
  if not game_private.valid_username(candidate) then raise exception 'Choose a valid, unreserved username.'; end if;
  insert into game_private.identities(player_id,username,claimed) values(new.id,candidate,true);
 end if;
 return new;
end $$;
create trigger register_game_identity after insert on auth.users for each row execute function game_private.register_identity();
create trigger audit_identity after update on game_private.identities for each row execute function game_private.audit_change();

create function public.username_available(candidate text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('available',game_private.valid_username(btrim(candidate)) and
 not exists(select 1 from game_private.identities where lower(username)=lower(btrim(candidate))))
$$;

create function game_private.rename_identity(target uuid,candidate text) returns void language plpgsql security definer set search_path='' as $$
declare chosen text:=btrim(candidate);
begin
 if not game_private.valid_username(chosen) then raise exception 'Use an unreserved name of 3–24 letters, numbers, underscores or hyphens, starting with a letter.'; end if;
 update game_private.identities set username=chosen,claimed=true where player_id=target;
 if not found then raise exception 'Player not found.'; end if;
 update public.game_players set handle=chosen where id=target;
 update public.game_listings set seller_handle=chosen where seller_id=target and status='active';
end $$;

create function public.claim_username(candidate text) returns jsonb language plpgsql security definer set search_path='' as $$
declare identity game_private.identities;
begin
 perform game_private.require_active();
 if not game_private.rate('username',10) then return jsonb_build_object('error','Too many attempts. Wait a minute.'); end if;
 begin
  select * into strict identity from game_private.identities where player_id=auth.uid() for update;
  if identity.claimed then raise exception 'Your username is already set. Contact Support to change it.'; end if;
  perform set_config('game.reason','Player claimed their username',true);
  perform game_private.rename_identity(auth.uid(),candidate);
  return jsonb_build_object('message','Username saved. Welcome to Blackwater.','username',btrim(candidate));
 exception when unique_violation then return jsonb_build_object('error','That username is taken. Choose another name.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;

insert into public.game_permissions(id,owner_only) values('players.rename',true);
create or replace function game_private.staff_action(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare reason text:=btrim(payload->>'reason');
begin
 perform game_private.require_active(); perform game_private.season_guard(false);
 if action='username' then
  if not game_private.has_permission('players.rename') then return jsonb_build_object('error','Permission denied.'); end if;
  if not game_private.rate('staff',30) then return jsonb_build_object('error','Too many requests. Wait a minute.'); end if;
  begin
   if length(coalesce(reason,'')) not between 3 and 2000 then raise exception 'Provide a reason of 3–2000 characters.'; end if;
   perform set_config('game.reason',reason,true);
   perform game_private.rename_identity((payload->>'player_id')::uuid,payload->>'username');
   return jsonb_build_object('message','Username changed. The action has been audited.');
  exception when unique_violation then return jsonb_build_object('error','That username is taken.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
  when invalid_text_representation then return jsonb_build_object('error','Invalid player.');
  end;
 end if;
 if action in ('setting','job','good','grant_money','spawn_asset') then
  begin perform game_private.season_guard(); exception when raise_exception then return jsonb_build_object('error',SQLERRM); end;
 end if;
 return game_private.staff_action_foundation(action,payload);
end $$;

-- Presence is per authenticated session; multiple tabs/devices still count as one player.
create table game_private.player_presence (
 player_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 last_seen_at timestamptz not null default now(),
 primary key(player_id,session_id)
);
create index presence_recent on game_private.player_presence(last_seen_at desc);
create index season_respect_directory on public.game_season_players(season_id,xp desc,player_id);
insert into public.game_settings(key,value,minimum,maximum) values
 ('presence_window_seconds',90,60,600),('chat_poll_seconds',5,3,30);

create function game_private.visible_player(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.game_players p where p.id=target and p.deleted_at is null)
 and not exists(select 1 from public.game_sanctions s where s.player_id=target and s.kind='ban'
 and s.revoked_at is null and (s.expires_at is null or s.expires_at>now()))
$$;
create function game_private.online_players() returns table(player_id uuid) language sql stable security definer set search_path='' as $$
 select distinct presence.player_id from game_private.player_presence presence
 join auth.sessions s on s.id=presence.session_id and s.user_id=presence.player_id
 join public.game_players p on p.id=presence.player_id
 where presence.last_seen_at>now()-make_interval(secs=>game_private.setting('presence_window_seconds'))
 and (p.sessions_revoked_at is null or s.created_at>p.sessions_revoked_at)
 and game_private.visible_player(p.id)
$$;

create function public.social_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare session uuid:=nullif(auth.jwt()->>'session_id','')::uuid; identity game_private.identities;
begin
 perform game_private.require_active();
 if not game_private.rate('social_read',120) then raise exception 'Too many requests. Wait a minute.'; end if;
 if session is null or not exists(select 1 from auth.sessions s where s.id=session and s.user_id=auth.uid())
 then raise exception 'Sign in again to reconnect to the city.'; end if;
 if not exists(select 1 from public.game_players where id=auth.uid()) then perform game_private.state(); end if;
 select * into strict identity from game_private.identities where player_id=auth.uid();
 insert into game_private.player_presence as p(player_id,session_id,last_seen_at) values(auth.uid(),session,clock_timestamp())
 on conflict(player_id,session_id) do update set last_seen_at=excluded.last_seen_at
 where p.last_seen_at<clock_timestamp()-interval '20 seconds';
 return jsonb_build_object(
  'player_id',auth.uid(),'username',identity.username,'username_claimed',identity.claimed,
  'online_count',(select count(*) from game_private.online_players()),
  'window_seconds',game_private.setting('presence_window_seconds'),'poll_seconds',game_private.setting('chat_poll_seconds'),
  'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=game_private.current_season()),
  'permissions',(select coalesce(jsonb_agg(id),'[]'::jsonb) from public.game_permissions where game_private.has_permission(id)),
  'muted',exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())),
  'chat',(select coalesce(jsonb_agg(c order by c.created_at,c.id),'[]'::jsonb) from (
   select m.id,m.player_id,p.handle as username,m.body,m.created_at,coalesce(r.role_id,'player') as role
   from public.game_chat m join public.game_players p on p.id=m.player_id
   left join public.game_user_roles r on r.player_id=p.id
   where m.deleted_at is null and p.deleted_at is null order by m.created_at desc,m.id desc limit 60
  ) c),'server_time',clock_timestamp()
 );
end $$;

create function public.presence_leave() returns void language sql security definer set search_path='' as $$
 delete from game_private.player_presence where player_id=auth.uid() and session_id=nullif(auth.jwt()->>'session_id','')::uuid
$$;

create function public.player_directory(p_search text default '',p_online boolean default false,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare season uuid; result jsonb;
begin
 perform game_private.require_active(); season:=game_private.season_guard(false);
 if not game_private.rate('directory',60) then raise exception 'Too many requests. Wait a minute.'; end if;
 if p_offset is null or p_offset not between 0 and 1000000 or length(coalesce(p_search,''))>64 then raise exception 'Invalid search.'; end if;
 with online as materialized (select * from game_private.online_players()),
 ranked as materialized (
  select p.id,p.handle as username,sp.xp as respect,rank() over(order by sp.xp desc) as rank,
  exists(select 1 from online o where o.player_id=p.id) as online,coalesce(r.role_id,'player') as role
  from public.game_season_players sp join public.game_players p on p.id=sp.player_id
  left join public.game_user_roles r on r.player_id=p.id
  where sp.season_id=season and game_private.visible_player(p.id)
 ), filtered as (
  select * from ranked where strpos(lower(username),lower(btrim(coalesce(p_search,''))))>0 and (not coalesce(p_online,false) or online)
 )
 select jsonb_build_object(
  'players',(select coalesce(jsonb_agg(p order by p.rank,p.id),'[]'::jsonb) from (select * from filtered order by rank,id limit 50 offset p_offset) p),
  'total',(select count(*) from filtered),'offset',p_offset,'page_size',50,
  'my_rank',(select rank from ranked where id=auth.uid()),'online_count',(select count(*) from online),
  'season',(select jsonb_build_object('id',s.id,'name',s.name,'status',s.status) from public.game_seasons s where s.id=season),
  'server_time',clock_timestamp()
 ) into result;
 return result;
end $$;

create function public.support_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not game_private.rate('support_read',60) then raise exception 'Too many requests. Wait a minute.'; end if;
 return jsonb_build_object(
  'cases',(select coalesce(jsonb_agg(c order by c.created_at desc),'[]'::jsonb) from public.game_cases c where c.player_id=auth.uid() and c.deleted_at is null),
  'sanctions',(select coalesce(jsonb_agg(s order by s.created_at desc),'[]'::jsonb) from public.game_sanctions s where s.player_id=auth.uid())
 );
end $$;

alter table game_private.identities enable row level security;
alter table game_private.player_presence enable row level security;
revoke all on game_private.identities,game_private.player_presence from public,anon,authenticated;
revoke all on function game_private.valid_username(text),game_private.register_identity(),game_private.rename_identity(uuid,text),
 game_private.visible_player(uuid),game_private.online_players() from public,anon,authenticated;
revoke all on function public.username_available(text),public.claim_username(text),public.social_state(),
 public.presence_leave(),public.player_directory(text,boolean,integer),public.support_state() from public,anon,authenticated;
grant execute on function public.username_available(text) to anon,authenticated;
grant execute on function public.claim_username(text),public.social_state(),public.presence_leave(),
 public.player_directory(text,boolean,integer),public.support_state() to authenticated;

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
 insert into public.game_players(id, handle, cash) values (uid, coalesce((select username from game_private.identities where player_id=uid), 'Rookie-' || left(uid::text, 8)), start_cash)
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
