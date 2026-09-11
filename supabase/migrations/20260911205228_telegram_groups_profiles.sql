-- Extend the existing private Telegram service; no message, receipt or balance is replaced.
alter table game_private.identities add column avatar_url text;
alter table game_private.identities add constraint profile_avatar_url check(avatar_url is null or (length(avatar_url)<=2048 and avatar_url ~ '^https://[^[:space:]<>]+$'));
create function game_private.player_avatar(p_player uuid) returns text language sql stable set search_path='' as $$
 select coalesce(avatar_url,'/art/command-portrait.jpg') from game_private.identities where player_id=p_player
$$;
create function game_private.profile_avatar(p_url text) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not game_private.rate('profile_avatar',10) then raise exception 'Wait before changing your picture again.';end if;
 if nullif(trim(p_url),'') is not null and (length(p_url)>2048 or p_url !~ '^https://[^[:space:]<>]+$') then return jsonb_build_object('error','Use a valid HTTPS image URL.');end if;
 perform set_config('game.reason','Player updated their profile picture',true);
 update game_private.identities set avatar_url=nullif(trim(p_url),'') where player_id=auth.uid();
 return jsonb_build_object('message','Profile picture saved.','avatar_url',game_private.player_avatar(auth.uid()));
end $$;
create function public.profile_avatar(p_url text) returns jsonb language sql security invoker set search_path='' as $$select game_private.profile_avatar(p_url)$$;
alter function game_private.city_status() rename to city_status_before_portraits;
create function game_private.city_status() returns jsonb language plpgsql security definer set search_path='' as $$
begin return game_private.city_status_before_portraits()||jsonb_build_object('avatar_url',game_private.player_avatar(auth.uid()));end $$;
alter function game_private.season_profile(uuid) rename to season_profile_before_portraits;
create function game_private.season_profile(p_player uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin return game_private.season_profile_before_portraits(p_player)||jsonb_build_object('avatar_url',game_private.player_avatar(p_player),'is_self',p_player=auth.uid());end $$;

insert into public.game_settings(key,value,minimum,maximum) values
 ('telegram_group_limit',10,1,100),('telegram_group_members',50,2,200),('telegram_group_name_limit',60,3,100) on conflict do nothing;
alter table game_private.telegram_threads alter column second_player drop not null;
alter table game_private.telegrams alter column recipient_id drop not null;
create table game_private.telegram_rooms(
 thread_id uuid primary key references game_private.telegram_threads(id),
 kind text not null check(kind in ('group','gang')), name text not null check(length(name) between 3 and 100),
 owner_id uuid not null references public.game_players(id), gang_id uuid references public.game_season_gangs(id),
 season_id uuid references public.game_seasons(id), closed_at timestamptz, created_at timestamptz not null default now(),
 check((kind='gang' and gang_id is not null and season_id is not null) or (kind='group' and gang_id is null and season_id is null))
);
create unique index telegram_one_gang_room on game_private.telegram_rooms(gang_id) where kind='gang';
create index telegram_rooms_owner on game_private.telegram_rooms(owner_id);
create table game_private.telegram_members(
 thread_id uuid not null references game_private.telegram_rooms(thread_id),player_id uuid not null references public.game_players(id),
 status text not null check(status in ('invited','active','left','declined','removed')),
 invited_by uuid not null references public.game_players(id),joined_at timestamptz,updated_at timestamptz not null default now(),
 primary key(thread_id,player_id)
);
create index telegram_members_player on game_private.telegram_members(player_id,status,thread_id);
create table game_private.telegram_deliveries(
 message_id uuid not null references game_private.telegrams(id),player_id uuid not null references public.game_players(id),
 primary key(message_id,player_id)
);
create index telegram_deliveries_player on game_private.telegram_deliveries(player_id,message_id);
create table game_private.telegram_room_events(
 id bigint generated always as identity primary key,thread_id uuid not null references game_private.telegram_rooms(thread_id),
 actor_id uuid not null references public.game_players(id),target_id uuid references public.game_players(id),
 action text not null,created_at timestamptz not null default now()
);
create index telegram_room_events_thread on game_private.telegram_room_events(thread_id,created_at desc);
create table game_private.telegram_room_requests(
 player_id uuid not null references public.game_players(id),request_id uuid not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default now(),primary key(player_id,request_id)
);
do $$ declare n text;begin
 foreach n in array array['telegram_rooms','telegram_members','telegram_deliveries','telegram_room_events','telegram_room_requests'] loop
  execute format('alter table game_private.%I enable row level security',n);
  execute format('revoke all on game_private.%I from public,anon,authenticated',n);
  execute format('create trigger retain_rows before %s on game_private.%I for each row execute function game_private.%I()',case when n in ('telegram_rooms','telegram_members') then 'delete' else 'update or delete' end,n,case when n in ('telegram_rooms','telegram_members') then 'no_delete' else 'immutable' end);
  execute format('create trigger retain_table before truncate on game_private.%I for each statement execute function game_private.no_delete()',n);
 end loop;
end $$;

-- Gang membership is read from its authoritative seasonal roster on every access.
create function game_private.telegram_access(p_thread uuid,p_player uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from game_private.telegram_threads t left join game_private.telegram_rooms r on r.thread_id=t.id
 where t.id=p_thread and (p_player in(t.first_player,t.second_player) and r.thread_id is null
 or r.kind='group' and exists(select 1 from game_private.telegram_members m where m.thread_id=t.id and m.player_id=p_player and m.status='active')
 or r.kind='gang' and r.season_id=game_private.current_season() and exists(select 1 from public.game_season_gang_members m where m.gang_id=r.gang_id and m.season_id=r.season_id and m.player_id=p_player)))
$$;
create function game_private.telegram_audience(p_thread uuid,p_sender uuid) returns setof uuid language sql stable set search_path='' as $$
 select p.id from public.game_players p join (
  select m.player_id from game_private.telegram_members m join game_private.telegram_rooms r on r.thread_id=m.thread_id
   where r.thread_id=p_thread and r.kind='group' and m.status='active'
  union all
  select m.player_id from public.game_season_gang_members m join game_private.telegram_rooms r on r.gang_id=m.gang_id and r.season_id=m.season_id
   where r.thread_id=p_thread and r.kind='gang' and r.season_id=game_private.current_season()
 ) a on a.player_id=p.id
 where p.id<>p_sender and p.deleted_at is null
 and not exists(select 1 from public.game_sanctions s where s.player_id=p.id and s.kind='ban' and s.revoked_at is null and (s.expires_at is null or s.expires_at>now()))
 and not exists(select 1 from game_private.telegram_blocks b where (b.player_id=p.id and b.blocked_id=p_sender) or (b.player_id=p_sender and b.blocked_id=p.id))
$$;
create function game_private.telegram_visible(p_message uuid,p_player uuid) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from game_private.telegrams m where m.id=p_message and
 (m.sender_id=p_player or m.recipient_id=p_player or exists(select 1 from game_private.telegram_deliveries d where d.message_id=m.id and d.player_id=p_player)))
$$;
create or replace function game_private.telegram_signal() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.recipient_id is null then
  insert into game_private.telegram_deliveries(message_id,player_id) select new.id,p from game_private.telegram_audience(new.thread_id,new.sender_id) p;
 end if;
 insert into public.game_telegram_signals as signal(player_id)
 select new.sender_id union select new.recipient_id where new.recipient_id is not null
 union select player_id from game_private.telegram_deliveries where message_id=new.id
 on conflict(player_id) do update set revision=signal.revision+1;
 return new;
end $$;

-- Room metadata never appears in public audit records; membership history stays private.
create function game_private.telegram_room_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare r game_private.telegram_rooms; g public.game_season_gangs; t uuid; target uuid; request uuid; result jsonb; saved game_private.telegram_room_requests; title text; s uuid;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_room',30) then return jsonb_build_object('error','Too many group changes. Try again shortly.');end if;
 begin
 s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 request:=(p_payload->>'request_id')::uuid;
 if request is null then raise exception 'Refresh and retry this group action.';end if;
 select * into saved from game_private.telegram_room_requests where player_id=auth.uid() and request_id=request;
 if found then
  if saved.payload is distinct from jsonb_build_object('action',p_action,'payload',p_payload) then raise exception 'This request was already used for another action.';end if;
  return saved.result;
 end if;
 if p_action in ('create','gang') then
  if exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'You are muted.';end if;
  if p_action='gang' then
   select g0.* into g from public.game_season_gangs g0 join public.game_season_gang_members m on m.gang_id=g0.id and m.season_id=g0.season_id where m.player_id=auth.uid() and m.season_id=s;
   if g.id is null then raise exception 'Join a gang to open its conversation.';end if;
   select * into r from game_private.telegram_rooms where gang_id=g.id;
   if r.thread_id is null then
    insert into game_private.telegram_threads(first_player,subject) values(auth.uid(),g.name) returning id into t;
    insert into game_private.telegram_rooms(thread_id,kind,name,owner_id,gang_id,season_id) values(t,'gang',g.name,auth.uid(),g.id,s) returning * into r;
   end if;
  else
   title:=trim(coalesce(p_payload->>'name',''));
   if length(title) not between 3 and game_private.setting('telegram_group_name_limit') then raise exception 'Check the group name length.';end if;
   if (select count(*) from game_private.telegram_rooms where owner_id=auth.uid() and kind='group' and closed_at is null)>=game_private.setting('telegram_group_limit') then raise exception 'Your group ownership limit has been reached.';end if;
   insert into game_private.telegram_threads(first_player,subject) values(auth.uid(),title) returning id into t;
   insert into game_private.telegram_rooms(thread_id,kind,name,owner_id) values(t,'group',title,auth.uid()) returning * into r;
   insert into game_private.telegram_members(thread_id,player_id,status,invited_by,joined_at) values(t,auth.uid(),'active',auth.uid(),clock_timestamp());
  end if;
 else
  select * into r from game_private.telegram_rooms where thread_id=(p_payload->>'thread_id')::uuid for update;
  if r.thread_id is null or r.kind<>'group' then raise exception 'Group unavailable. Gang chat follows the gang roster.';end if;
  if r.closed_at is not null then raise exception 'This group is closed. Its history is retained.';end if;
  if p_action in ('accept','decline') then
   if not exists(select 1 from game_private.telegram_members where thread_id=r.thread_id and player_id=auth.uid() and status='invited') then raise exception 'Invitation unavailable.';end if;
   update game_private.telegram_members set status=case when p_action='accept' then 'active' else 'declined' end,joined_at=case when p_action='accept' then clock_timestamp() else null end,updated_at=clock_timestamp() where thread_id=r.thread_id and player_id=auth.uid();
  else
   if not game_private.telegram_access(r.thread_id,auth.uid()) then raise exception 'Group unavailable.';end if;
   if p_action='leave' then
    if r.owner_id=auth.uid() then raise exception 'Transfer group ownership before leaving.';end if;
    update game_private.telegram_members set status='left',updated_at=clock_timestamp() where thread_id=r.thread_id and player_id=auth.uid();
   else
    if r.owner_id<>auth.uid() then raise exception 'Only the group owner can manage members.';end if;
    if p_action='invite' then
     if exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'You are muted.';end if;
     select i.player_id into target from game_private.identities i join public.game_players p on p.id=i.player_id where lower(i.username)=lower(trim(p_payload->>'username')) and p.deleted_at is null;
     if target is null or target=auth.uid() or exists(select 1 from game_private.telegram_blocks where (player_id=target and blocked_id=auth.uid()) or (player_id=auth.uid() and blocked_id=target))
      or exists(select 1 from public.game_sanctions where player_id=target and kind='ban' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'This player is unavailable for invitations.';end if;
     if exists(select 1 from game_private.telegram_members where thread_id=r.thread_id and player_id=target and status in ('invited','active')) then raise exception 'This player is already a member or invited.';end if;
     if (select count(*) from game_private.telegram_members where thread_id=r.thread_id and status in ('invited','active'))>=game_private.setting('telegram_group_members') then raise exception 'This group has reached its member limit.';end if;
     insert into game_private.telegram_members(thread_id,player_id,status,invited_by) values(r.thread_id,target,'invited',auth.uid())
     on conflict(thread_id,player_id) do update set status='invited',invited_by=auth.uid(),joined_at=null,updated_at=clock_timestamp();
    elsif p_action in ('remove','transfer') then
     target:=(p_payload->>'player_id')::uuid;
     if target is null or target=auth.uid() or not exists(select 1 from game_private.telegram_members where thread_id=r.thread_id and player_id=target and status in ('active','invited')) then raise exception 'Choose another group member.';end if;
     if p_action='transfer' then
      if not exists(select 1 from game_private.telegram_members where thread_id=r.thread_id and player_id=target and status='active') then raise exception 'Ownership requires an active member.';end if;
      if (select count(*) from game_private.telegram_rooms where owner_id=target and kind='group' and closed_at is null)>=game_private.setting('telegram_group_limit') then raise exception 'This player has reached their group ownership limit.';end if;
      update game_private.telegram_rooms set owner_id=target where thread_id=r.thread_id;
     else update game_private.telegram_members set status='removed',updated_at=clock_timestamp() where thread_id=r.thread_id and player_id=target;end if;
    elsif p_action='close' then
     update game_private.telegram_rooms set closed_at=clock_timestamp() where thread_id=r.thread_id;
    elsif p_action='rename' then
     title:=trim(coalesce(p_payload->>'name',''));
     if length(title) not between 3 and game_private.setting('telegram_group_name_limit') then raise exception 'Check the group name length.';end if;
     update game_private.telegram_rooms set name=title where thread_id=r.thread_id;
    else raise exception 'Unknown group action.';end if;
   end if;
  end if;
 end if;
 insert into game_private.telegram_room_events(thread_id,actor_id,target_id,action) values(r.thread_id,auth.uid(),target,p_action);
 insert into public.game_telegram_signals as sig(player_id)
 select auth.uid() union select target where target is not null union select player_id from game_private.telegram_members where thread_id=r.thread_id and status in ('active','invited')
 on conflict(player_id) do update set revision=sig.revision+1;
 result:=jsonb_build_object('message',case p_action when 'create' then 'Group created. Invite your players.' when 'gang' then 'Gang conversation opened.' when 'invite' then 'Invitation sent.' when 'accept' then 'You joined the group.' when 'leave' then 'You left the group.' when 'close' then 'Group closed. Your conversation history is retained.' else 'Group updated.' end,'thread_id',r.thread_id);
 insert into game_private.telegram_room_requests values(auth.uid(),request,jsonb_build_object('action',p_action,'payload',p_payload),result,now());
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'telegram room failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The group change could not be saved.');
 end;
end $$;
create function public.telegram_room_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.telegram_room_action(p_action,p_payload)$$;


create or replace function game_private.telegram_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; o public.game_telegram_office; b public.game_district_businesses; t game_private.telegram_threads; m game_private.telegrams;
 recipient uuid; payee uuid; new_id uuid; draft uuid; amount bigint; old_balance bigint; subject text; body text; request uuid;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_action',game_private.setting('telegram_send_rate')) then return jsonb_build_object('error','Too many telegram actions. Try again shortly.'); end if;
 begin
 s:=game_private.season_guard(p_action='send');perform pg_advisory_xact_lock(4704020);perform game_private.ensure_districts(s);
 if p_action='send' then
  request:=(p_payload->>'request_id')::uuid;
  if request is null then raise exception 'Refresh the composer before sending.'; end if;
  select * into m from game_private.telegrams where sender_id=auth.uid() and request_id=request;
  if m.id is not null then return jsonb_build_object('message','Telegram already delivered.','thread_id',m.thread_id); end if;
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Review the current delivery fee.'; end if;
  if exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'You are muted.'; end if;
  if nullif(p_payload->>'thread_id','') is not null then
   select * into t from game_private.telegram_threads where id=(p_payload->>'thread_id')::uuid and game_private.telegram_access(id,auth.uid());
   if t.id is null then raise exception 'Conversation unavailable.'; end if;
   recipient:=case when t.second_player is null then null when t.first_player=auth.uid() then t.second_player else t.first_player end;
  else
   select i.player_id into recipient from game_private.identities i join public.game_players p on p.id=i.player_id where lower(i.username)=lower(trim(p_payload->>'recipient')) and p.deleted_at is null;
  end if;
  if (t.id is null or t.second_player is not null) and (recipient is null or recipient=auth.uid() or not exists(select 1 from public.game_players where id=recipient and deleted_at is null)
   or exists(select 1 from public.game_sanctions where player_id=recipient and kind='ban' and revoked_at is null and (expires_at is null or expires_at>now()))
   or exists(select 1 from game_private.telegram_blocks where (player_id=recipient and blocked_id=auth.uid()) or (player_id=auth.uid() and blocked_id=recipient))) then raise exception 'This recipient is unavailable for telegrams.'; end if;
  if exists(select 1 from game_private.telegram_rooms where thread_id=t.id and closed_at is not null) then raise exception 'This group is closed. Its history is retained.';end if;
  if t.id is not null and t.second_player is null and not exists(select 1 from game_private.telegram_audience(t.id,auth.uid())) then raise exception 'No available recipients. Invite a player and wait for them to join.';end if;
  subject:=trim(coalesce(p_payload->>'subject',''));body:=trim(coalesce(p_payload->>'body',''));
  if length(body) not between 1 and game_private.setting('telegram_body_limit') or (t.id is null and length(subject) not between 1 and game_private.setting('telegram_subject_limit')) then raise exception 'Check the subject and message length.'; end if;
  select * into strict o from public.game_telegram_office for update;
  select * into strict b from public.game_district_businesses where id=o.business_id for update;
  if not o.available or b.status<>'open' or b.archived_at is not null or exists(select 1 from public.game_district_plots p join public.game_districts d on d.id=p.district_id where p.id=o.plot_id and (p.status='locked' or d.archived_at is not null)) then raise exception 'Telegram service is currently unavailable.'; end if;
  amount:=b.telegram_fee;
  if (p_payload->>'fee')::bigint is distinct from amount then raise exception 'The delivery fee changed. Review the new fee before sending.'; end if;
  payee:=case when b.owner_type='player' then b.owner_id else (select payout_player_id from public.game_district_entities where id=b.owner_id) end;
  perform id from public.game_players where id in(auth.uid(),payee) order by id for update;
  if (select cash from public.game_players where id=auth.uid())<amount then raise exception 'Not enough cash for this telegram.'; end if;
  if t.id is null then insert into game_private.telegram_threads(first_player,second_player,subject) values(auth.uid(),recipient,subject) returning * into t; end if;
  insert into game_private.telegrams(thread_id,sender_id,recipient_id,body,season_id,request_id)
   values(t.id,auth.uid(),recipient,body,s,request) returning id into new_id;
  if amount>0 then
   perform game_private.district_wallet(auth.uid(),-amount,'Telegram delivery fee');
   if payee is not null then perform game_private.district_wallet(payee,amount,'Telegram Office revenue'); end if;
  end if;
  if payee is null then
   insert into game_private.telegram_accounts(season_id,owner_type,owner_id) values(s,b.owner_type,b.owner_id) on conflict do nothing;
   select balance into old_balance from game_private.telegram_accounts where season_id=s and owner_type=b.owner_type and owner_id=b.owner_id for update;
   update game_private.telegram_accounts set balance=balance+amount where season_id=s and owner_type=b.owner_type and owner_id=b.owner_id;
   insert into game_private.telegram_account_ledger(season_id,owner_type,owner_id,message_id,delta,balance_before,balance_after,reason)
    values(s,b.owner_type,b.owner_id,new_id,amount,old_balance,old_balance+amount,'Telegram Office revenue');
  end if;
  insert into game_private.telegram_receipts(message_id,season_id,business_id,owner_type,owner_id,payout_player_id,fee) values(new_id,s,b.id,b.owner_type,b.owner_id,payee,amount);
  insert into game_private.telegram_folders(player_id,thread_id,archived,read_at) values(auth.uid(),t.id,false,now())
   on conflict(player_id,thread_id) do update set archived=false,read_at=now();
  insert into game_private.telegram_folders(player_id,thread_id,archived)
   select recipient,t.id,false where recipient is not null
   union all select player_id,t.id,false from game_private.telegram_deliveries where message_id=new_id
   on conflict(player_id,thread_id) do update set archived=false;
  if nullif(p_payload->>'draft_id','') is not null then update game_private.telegram_drafts set deleted_at=now() where id=(p_payload->>'draft_id')::uuid and player_id=auth.uid(); end if;
  return jsonb_build_object('message','Telegram delivered instantly.','thread_id',t.id,'fee',amount);
 elsif p_action in ('archive','star') then
  select * into t from game_private.telegram_threads where id=(p_payload->>'thread_id')::uuid and game_private.telegram_access(id,auth.uid());
  if t.id is null then raise exception 'Conversation unavailable.'; end if;
  insert into game_private.telegram_folders(player_id,thread_id) values(auth.uid(),t.id) on conflict do nothing;
  if p_action='archive' then update game_private.telegram_folders set archived=not archived where thread_id=t.id and player_id=auth.uid();
  else update game_private.telegram_folders set starred=not starred where thread_id=t.id and player_id=auth.uid();end if;
 elsif p_action in ('draft','delete_draft') then
  draft:=nullif(p_payload->>'id','')::uuid;
  if draft is not null and not exists(select 1 from game_private.telegram_drafts where id=draft and player_id=auth.uid() and deleted_at is null) then raise exception 'Draft unavailable.'; end if;
  if p_action='delete_draft' then update game_private.telegram_drafts set deleted_at=now() where id=draft and player_id=auth.uid();
  elsif draft is null then insert into game_private.telegram_drafts(player_id,recipient,subject,body) values(auth.uid(),left(coalesce(p_payload->>'recipient',''),80),coalesce(p_payload->>'subject',''),coalesce(p_payload->>'body','')) returning id into draft;
  else update game_private.telegram_drafts set recipient=left(coalesce(p_payload->>'recipient',''),80),subject=coalesce(p_payload->>'subject',''),body=coalesce(p_payload->>'body',''),updated_at=now() where id=draft and player_id=auth.uid();end if;
  return jsonb_build_object('message','Draft saved.','draft_id',draft);
 elsif p_action in ('block','unblock') then
  recipient:=(p_payload->>'player_id')::uuid;
  if recipient=auth.uid() or recipient is null then raise exception 'Choose another player.'; end if;
  if p_action='block' then insert into game_private.telegram_blocks(player_id,blocked_id) values(auth.uid(),recipient) on conflict do nothing;
  else delete from game_private.telegram_blocks where player_id=auth.uid() and blocked_id=recipient;end if;
 elsif p_action='report' then
  select * into m from game_private.telegrams where id=(p_payload->>'message_id')::uuid and sender_id<>auth.uid() and game_private.telegram_access(thread_id,auth.uid()) and game_private.telegram_visible(id,auth.uid());
  if m.id is null then raise exception 'You can report only a telegram sent to you.'; end if;
  body:=trim(coalesce(p_payload->>'reason',''));
  if length(body) not between 3 and 2000 then raise exception 'Explain the report in 3 to 2000 characters.';end if;
  if exists(select 1 from game_private.telegram_reports where message_id=m.id and reporter_id=auth.uid()) then raise exception 'This telegram has already been reported.'; end if;
  insert into public.game_cases(player_id,kind,subject,body) values(auth.uid(),'report','Reported telegram',body) returning id into new_id;
  insert into game_private.telegram_reports(case_id,message_id,reporter_id) values(new_id,m.id,auth.uid());
  return jsonb_build_object('message','Report submitted. Only this telegram can be inspected as evidence.');
 else raise exception 'Unknown telegram action.';end if;
 return jsonb_build_object('message','Saved.');
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'telegram action failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The telegram action could not be completed. No payment was taken.');
 end;
end $$;

create function game_private.telegram_thread_data(p_thread uuid) returns jsonb language plpgsql stable set search_path='' as $$
declare t game_private.telegram_threads;r game_private.telegram_rooms;other uuid;member_count integer;
begin
 select * into t from game_private.telegram_threads where id=p_thread;
 select * into r from game_private.telegram_rooms where thread_id=p_thread;
 if r.thread_id is null then
  other:=case when t.first_player=auth.uid() then t.second_player else t.first_player end;
  return jsonb_build_object('kind','direct','other_id',other,'other_name',game_private.district_owner_name('player',other),'other_avatar',game_private.player_avatar(other),'subject',t.subject,'can_manage',false,'member_count',2,'can_send',true);
 end if;
 if r.kind='group' then select count(*) into member_count from game_private.telegram_members where thread_id=p_thread and status='active';
 else select count(*) into member_count from public.game_season_gang_members where gang_id=r.gang_id and season_id=r.season_id;end if;
 return jsonb_build_object('kind',r.kind,'other_id',null,'other_name',coalesce((select name from public.game_season_gangs where id=r.gang_id),r.name),'other_avatar',null,'subject',case when r.kind='gang' then 'Gang correspondence' else 'Private group' end,'owner_id',r.owner_id,'member_count',member_count,'closed',r.closed_at is not null,'can_manage',r.kind='group' and r.owner_id=auth.uid() and r.closed_at is null,'can_send',r.closed_at is null and exists(select 1 from game_private.telegram_audience(p_thread,auth.uid())));
end $$;
create function game_private.telegram_room_members(p_thread uuid) returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',m.player_id,'name',i.username,'avatar_url',game_private.player_avatar(m.player_id),'status',m.status,'owner',m.is_owner) order by m.is_owner desc,i.username),'[]'::jsonb)
 from (
 select m.player_id,m.status,m.player_id=r.owner_id as is_owner from game_private.telegram_members m join game_private.telegram_rooms r on r.thread_id=m.thread_id
  where r.thread_id=p_thread and r.kind='group' and (m.status='active' or m.status='invited' and r.owner_id=auth.uid())
 union all
 select m.player_id,'active',g.data->>'owner_id'=m.player_id::text from public.game_season_gang_members m join game_private.telegram_rooms r on r.gang_id=m.gang_id and r.season_id=m.season_id join public.game_season_gangs g on g.id=m.gang_id where r.thread_id=p_thread and r.kind='gang'
 ) m join game_private.identities i on i.player_id=m.player_id
$$;
-- Acquire the messaging coordinator before the existing economic locks for gang roster changes.
alter function game_private.district_action(text,jsonb) rename to district_action_before_group_roster;
create function game_private.district_action(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_action in ('gang_create','gang_join','gang_leave') then
  perform game_private.require_active();perform game_private.season_guard(true);perform pg_advisory_xact_lock(4704020);
 end if;
 return game_private.district_action_before_group_roster(p_action,p_payload);
end $$;


-- Restrict mailbox scans to indexed participation instead of scanning every city thread.
create function game_private.telegram_player_threads(p_player uuid) returns setof uuid language sql stable set search_path='' as $$
 select id from game_private.telegram_threads where first_player=p_player and second_player is not null
 union select id from game_private.telegram_threads where second_player=p_player
 union select thread_id from game_private.telegram_members where player_id=p_player and status='active'
 union select r.thread_id from game_private.telegram_rooms r join public.game_season_gang_members m on m.gang_id=r.gang_id and m.season_id=r.season_id where m.player_id=p_player and m.season_id=game_private.current_season()
$$;
revoke all on function game_private.telegram_player_threads(uuid) from public,anon,authenticated;

create or replace function game_private.telegram_state(p_thread uuid default null,p_folder text default 'inbox',p_offset integer default 0,p_before uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; t game_private.telegram_threads; result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_read',120) then raise exception 'Wait a moment before refreshing.'; end if;
 if not exists(select 1 from public.game_players where id=auth.uid()) then perform game_private.state(); end if;
 s:=game_private.season_guard(false);perform game_private.ensure_districts(s);
 if p_thread is not null then
  select * into t from game_private.telegram_threads where id=p_thread and game_private.telegram_access(id,auth.uid());
  if t.id is null then raise exception 'Conversation unavailable.'; end if;
  insert into game_private.telegram_folders(player_id,thread_id,read_at) values(auth.uid(),t.id,now())
  on conflict(player_id,thread_id) do update set read_at=now();
 end if;
 select jsonb_build_object('player_id',auth.uid(),'cash',(select cash from public.game_players where id=auth.uid()),
 'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),
 'office',game_private.telegram_office_data(),'server_time',now(),
 'limits',jsonb_build_object('subject',game_private.setting('telegram_subject_limit'),'body',game_private.setting('telegram_body_limit'),'group_name',game_private.setting('telegram_group_name_limit'),'group_members',game_private.setting('telegram_group_members')),
 'unread',(select count(*) from game_private.telegrams m left join game_private.telegram_folders f on f.thread_id=m.thread_id and f.player_id=auth.uid() where m.id in(select id from game_private.telegrams where recipient_id=auth.uid() union select message_id from game_private.telegram_deliveries where player_id=auth.uid()) and m.thread_id in(select game_private.telegram_player_threads(auth.uid())) and m.created_at>coalesce(f.read_at,'-infinity'::timestamptz)),
 'thread',case when t.id is null then null else to_jsonb(t)||game_private.telegram_thread_data(t.id) end,
 'threads',coalesce((select jsonb_agg(to_jsonb(x)||game_private.telegram_thread_data(x.id) order by x.last_at desc,x.id) from (
  select t0.id,t0.subject,case when t0.first_player=auth.uid() then t0.second_player else t0.first_player end as other_id,
  game_private.district_owner_name('player',case when t0.first_player=auth.uid() then t0.second_player else t0.first_player end) as other_name,
  coalesce(m.created_at,t0.created_at) as last_at,coalesce(left(m.body,90),'No telegrams yet') as excerpt,coalesce(f.archived,false) as archived,coalesce(f.starred,false) as starred,
  (select count(*) from game_private.telegrams u where u.thread_id=t0.id and u.sender_id<>auth.uid() and game_private.telegram_visible(u.id,auth.uid()) and u.created_at>coalesce(f.read_at,'-infinity'::timestamptz)) as unread
  from game_private.telegram_threads t0
  left join lateral(select body,created_at from game_private.telegrams where thread_id=t0.id and game_private.telegram_visible(id,auth.uid()) order by created_at desc,id desc limit 1)m on true
  left join game_private.telegram_folders f on f.thread_id=t0.id and f.player_id=auth.uid()
  where t0.id in(select game_private.telegram_player_threads(auth.uid())) and
   case p_folder when 'groups' then not coalesce(f.archived,false) and exists(select 1 from game_private.telegram_rooms r where r.thread_id=t0.id and r.kind='group') when 'gang' then not coalesce(f.archived,false) and exists(select 1 from game_private.telegram_rooms r where r.thread_id=t0.id and r.kind='gang') when 'archive' then coalesce(f.archived,false) when 'starred' then coalesce(f.starred,false)
    when 'sent' then not coalesce(f.archived,false) and exists(select 1 from game_private.telegrams where thread_id=t0.id and sender_id=auth.uid())
    else not coalesce(f.archived,false) end
  order by coalesce(m.created_at,t0.created_at) desc,t0.id limit 50 offset greatest(0,least(coalesce(p_offset,0),100000)))x),'[]'::jsonb),
 'messages',coalesce((select jsonb_agg(x order by x.created_at,x.id) from (
  select m.id,m.thread_id,m.sender_id,m.recipient_id,m.body,m.created_at,game_private.district_owner_name('player',m.sender_id) as sender_name,game_private.player_avatar(m.sender_id) as sender_avatar
  from game_private.telegrams m where m.thread_id=t.id and game_private.telegram_visible(m.id,auth.uid()) and (p_before is null or (m.created_at,m.id)<(select created_at,id from game_private.telegrams where id=p_before and thread_id=t.id))
  order by m.created_at desc,m.id desc limit 50)x),'[]'::jsonb),
 'drafts',coalesce((select jsonb_agg(x order by x.updated_at desc) from(select id,recipient,subject,body,updated_at from game_private.telegram_drafts where player_id=auth.uid() and deleted_at is null order by updated_at desc limit 100)x),'[]'::jsonb),
 'blocks',coalesce((select jsonb_agg(jsonb_build_object('id',blocked_id,'name',game_private.district_owner_name('player',blocked_id))) from game_private.telegram_blocks where player_id=auth.uid()),'[]'::jsonb),
 'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.case_id,'message_id',r.message_id,'status',c.status,'response',c.response,'created_at',r.created_at) order by r.created_at desc) from game_private.telegram_reports r join public.game_cases c on c.id=r.case_id where r.reporter_id=auth.uid()),'[]'::jsonb)
 ) into result;
 return result||jsonb_build_object(
 'player_avatar',game_private.player_avatar(auth.uid()),
 'members',case when t.id is not null then game_private.telegram_room_members(t.id) else '[]'::jsonb end,
 'invitations',coalesce((select jsonb_agg(jsonb_build_object('thread_id',r.thread_id,'name',r.name,'invited_by',game_private.district_owner_name('player',m.invited_by)) order by m.updated_at desc) from game_private.telegram_members m join game_private.telegram_rooms r on r.thread_id=m.thread_id where m.player_id=auth.uid() and m.status='invited' and r.closed_at is null),'[]'::jsonb),
 'gang', (select jsonb_build_object('id',g.id,'name',g.name) from public.game_season_gangs g join public.game_season_gang_members m on m.gang_id=g.id and m.season_id=g.season_id where m.player_id=auth.uid() and m.season_id=s)
 );
end $$;

revoke all on function game_private.player_avatar(uuid),game_private.profile_avatar(text),public.profile_avatar(text),
 game_private.city_status_before_portraits(),game_private.city_status(),game_private.season_profile_before_portraits(uuid),game_private.season_profile(uuid),
 game_private.telegram_access(uuid,uuid),game_private.telegram_audience(uuid,uuid),game_private.telegram_visible(uuid,uuid),
 game_private.telegram_thread_data(uuid),game_private.telegram_room_members(uuid),game_private.telegram_room_action(text,jsonb),public.telegram_room_action(text,jsonb),
 game_private.district_action_before_group_roster(text,jsonb),game_private.district_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.profile_avatar(text),public.profile_avatar(text),game_private.city_status(),game_private.season_profile(uuid),
 game_private.telegram_room_action(text,jsonb),public.telegram_room_action(text,jsonb),game_private.district_action(text,jsonb) to authenticated;

