-- Gang headquarters extends the existing seasonal roster and Telegram service.
select set_config('game.reason','Introduce gang headquarters',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('gang_member_limit',50,2,200),('gang_bank_max_transfer',1000000000,1,2000000000),
 ('gang_bank_deposits_enabled',1,0,1),('gang_request_cooldown_hours',24,1,168);
create table game_private.gang_ranks(
 id text primary key,label text not null,priority integer not null unique,
 manage_members boolean not null default false,review_requests boolean not null default false
);
insert into game_private.gang_ranks values
 ('underboss','Underboss',80,true,true),('capo','Capo',60,false,false),
 ('soldier','Soldier',40,false,false),('associate','Associate',20,false,false);
alter table public.game_season_gang_members add column rank_id text not null default 'associate' references game_private.gang_ranks(id);
alter table public.game_season_gang_members add column version integer not null default 1;
alter table public.game_season_gang_members add column joined_at timestamptz not null default now();
alter table public.game_season_gangs add column description text not null default '' check(length(description)<=300);
alter table public.game_season_gangs add column version integer not null default 1;
alter table public.game_season_gangs add column created_at timestamptz not null default now();

create table game_private.gang_join_requests(
 id uuid primary key default gen_random_uuid(),season_id uuid not null,gang_id uuid not null,
 player_id uuid not null references public.game_players(id),
 status text not null default 'pending' check(status in('pending','accepted','declined','cancelled','superseded')),
 telegram_id uuid references game_private.telegrams(id),reviewed_by uuid references public.game_players(id),
 created_at timestamptz not null default clock_timestamp(),reviewed_at timestamptz,
 foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create unique index gang_request_pending on game_private.gang_join_requests(season_id,gang_id,player_id) where status='pending';
create index gang_request_gang on game_private.gang_join_requests(gang_id,status,created_at desc);
create index gang_request_player on game_private.gang_join_requests(player_id,season_id,created_at desc);
create index gang_request_message on game_private.gang_join_requests(telegram_id);
create index gang_request_reviewer on game_private.gang_join_requests(reviewed_by);
create table game_private.gang_accounts(
 season_id uuid not null,gang_id uuid not null,balance bigint not null default 0 check(balance between 0 and 9007199254740991),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(season_id,gang_id),foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create index gang_account_gang on game_private.gang_accounts(gang_id);
create table game_private.gang_ledger(
 id uuid primary key default gen_random_uuid(),season_id uuid not null,gang_id uuid not null,
 actor_id uuid not null references public.game_players(id),request_id uuid not null,
 delta bigint not null check(delta<>0),balance_before bigint not null,balance_after bigint not null,
 cash_after bigint not null check(cash_after>=0),created_at timestamptz not null default clock_timestamp(),
 foreign key(season_id,gang_id) references game_private.gang_accounts(season_id,gang_id),
 check(balance_before+delta=balance_after and balance_before>=0 and balance_after>=0),
 unique(season_id,actor_id,request_id)
);
create index gang_ledger_gang on game_private.gang_ledger(gang_id,created_at desc,id desc);
create index gang_ledger_actor on game_private.gang_ledger(actor_id,season_id);
create table game_private.gang_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default clock_timestamp(),primary key(season_id,player_id,request_id)
);
create index gang_requests_player on game_private.gang_requests(player_id);
create table game_private.gang_events(
 id bigint generated always as identity primary key,season_id uuid not null,gang_id uuid not null,
 actor_id uuid not null references public.game_players(id),target_id uuid references public.game_players(id),
 kind text not null,description text not null,created_at timestamptz not null default clock_timestamp(),
 foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create index gang_events_gang on game_private.gang_events(gang_id,created_at desc,id desc);
create index gang_events_actor on game_private.gang_events(actor_id);
create index gang_events_target on game_private.gang_events(target_id);
do $$declare t text;begin
 foreach t in array array['gang_ranks','gang_join_requests','gang_accounts','gang_ledger','gang_requests','gang_events'] loop
  execute format('alter table game_private.%I enable row level security',t);
  execute format('revoke all on game_private.%I from public,anon,authenticated',t);
  execute format('create trigger retain_gang_records before %s on game_private.%I for each statement execute function game_private.district_immutable()',case when t in('gang_ledger','gang_requests','gang_events') then 'update or delete or truncate' else 'delete or truncate' end,t);
 end loop;
 foreach t in array array['game_season_gangs','game_season_gang_members'] loop
  execute format('create trigger audit_gang_change after insert or update or delete on public.%I for each row execute function game_private.audit_change()',t);
 end loop;
end$$;
create trigger audit_gang_requests after insert or update on game_private.gang_join_requests for each row execute function game_private.audit_change();
create trigger audit_gang_ranks after insert or update on game_private.gang_ranks for each row execute function game_private.audit_change();

create function game_private.gang_bank_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare nonce uuid;actor uuid;
begin
 if TG_OP='INSERT' then if new.balance<>0 then raise exception 'Gang accounts must open empty.';end if;return new;end if;
 if new.season_id<>old.season_id or new.gang_id<>old.gang_id then raise exception 'Account identity cannot change.';end if;
 if new.balance<>old.balance then
  nonce:=nullif(current_setting('game.gang_request_id',true),'')::uuid;actor:=auth.uid();
  if nonce is null or actor is null then raise exception 'A gang transfer reference and actor are required.';end if;
  insert into game_private.gang_ledger(season_id,gang_id,actor_id,request_id,delta,balance_before,balance_after,cash_after)
  select new.season_id,new.gang_id,actor,nonce,new.balance-old.balance,old.balance,new.balance,cash from public.game_players where id=actor;
 end if;return new;
end$$;
create trigger gang_bank_entry after insert or update on game_private.gang_accounts for each row execute function game_private.gang_bank_entry();

-- Private, fixed-text service notice. It cannot send arbitrary free messages.
create function game_private.gang_request_telegram(p_request uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare q game_private.gang_join_requests;g public.game_season_gangs;recipient uuid;t uuid;mid uuid;
begin
 select * into strict q from game_private.gang_join_requests where id=p_request;
 select * into strict g from public.game_season_gangs where id=q.gang_id;
 recipient:=(g.data->>'owner_id')::uuid;
 if q.player_id is distinct from auth.uid() or q.status<>'pending' or q.telegram_id is not null then raise exception 'Invalid recruitment notification.';end if;
 if recipient is null or not game_private.visible_player(recipient) or exists(select 1 from game_private.telegram_blocks where (player_id=recipient and blocked_id=auth.uid()) or (player_id=auth.uid() and blocked_id=recipient)) then raise exception 'This gang is not accepting requests from this account.';end if;
 insert into game_private.telegram_threads(first_player,second_player,subject) values(q.player_id,recipient,'Join request · '||g.name) returning id into t;
 insert into game_private.telegrams(thread_id,sender_id,recipient_id,body,season_id,request_id)
 values(t,q.player_id,recipient,'GANG RECRUITMENT NOTICE'||E'\n\n'||game_private.district_owner_name('player',q.player_id)||' has requested to join '||g.name||'. Review this application in your gang headquarters. This automatic notice has no delivery charge.',q.season_id,gen_random_uuid()) returning id into mid;
 insert into game_private.telegram_folders(player_id,thread_id,read_at) values(q.player_id,t,clock_timestamp()),(recipient,t,null);
 return mid;
end$$;

create function game_private.gang_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();nonce uuid;gid uuid;g public.game_season_gangs;me public.game_season_gang_members;target public.game_season_gang_members;
 rankrow game_private.gang_ranks;myrank game_private.gang_ranks;boss boolean;prior game_private.gang_requests;q game_private.gang_join_requests;
 result jsonb;amount numeric;delta bigint;title text;body text;target_id uuid;mid uuid;note text;v integer;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid gang action.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the gang panel.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'An action reference is required.';end if;
  -- Same coordinator as district roster and Telegram membership; always before wallet locks.
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.gang_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This action reference was already used.';end if;
   return prior.result;
  end if;
  perform game_private.season_guard();
  select * into me from public.game_season_gang_members where season_id=s and player_id=uid;
  gid:=(p_payload->>'gang_id')::uuid;
  if p_action='create' then
   if me.player_id is not null then raise exception 'You already belong to a gang.';end if;
   title:=btrim(coalesce(p_payload->>'name',''));
   if length(title) not between 3 and 60 or title ~ '[[:cntrl:]]' then raise exception 'Choose a gang name of 3 to 60 characters.';end if;
   if exists(select 1 from public.game_season_gangs where season_id=s and lower(name)=lower(title)) then raise exception 'That gang name is already in use.';end if;
   perform game_private.district_wallet(uid,-game_private.setting('district_gang_creation_cost'),'Establish seasonal gang');
   insert into public.game_season_gangs(season_id,name,data) values(s,title,jsonb_build_object('owner_id',uid,'recruitment','open')) returning * into g;gid:=g.id;
   perform set_config('game.reason','Gang founded',true);
   insert into public.game_season_gang_members(season_id,player_id,gang_id) values(s,uid,gid);
   update game_private.gang_join_requests set status='superseded',reviewed_at=clock_timestamp() where season_id=s and player_id=uid and status='pending';
   note:='Founded '||title||'.';
  else
   select * into g from public.game_season_gangs where id=gid and season_id=s for update;
   if g.id is null then raise exception 'Gang not found in the current season.';end if;
   boss:=coalesce(g.data->>'owner_id'=uid::text and me.gang_id=gid,false);
   select * into myrank from game_private.gang_ranks where id=me.rank_id and me.gang_id=gid;
   perform set_config('game.reason','Gang action: '||p_action,true);
   if p_action='request_join' then
    if me.player_id is not null then raise exception 'You already belong to a gang.';end if;
    if g.data->>'recruitment' is distinct from 'open' then raise exception 'This gang is not recruiting.';end if;
    select * into q from game_private.gang_join_requests where season_id=s and gang_id=gid and player_id=uid and status='pending';
    if q.id is null then
     if exists(select 1 from game_private.gang_join_requests where season_id=s and gang_id=gid and player_id=uid and created_at>clock_timestamp()-make_interval(hours=>game_private.setting('gang_request_cooldown_hours'))) then raise exception 'Wait before applying to this gang again.';end if;
     insert into game_private.gang_join_requests(season_id,gang_id,player_id) values(s,gid,uid) returning * into q;
     mid:=game_private.gang_request_telegram(q.id);
     update game_private.gang_join_requests set telegram_id=mid where id=q.id;
    end if;
    result:=jsonb_build_object('message','Join request sent. The gang leader has been notified by Telegram.','application_id',q.id,'gang_id',gid);
   elsif p_action='cancel_request' then
    update game_private.gang_join_requests set status='cancelled',reviewed_at=clock_timestamp() where id=(p_payload->>'application_id')::uuid and gang_id=gid and player_id=uid and status='pending';
    if not found then raise exception 'This request is no longer pending.';end if;
    result:=jsonb_build_object('message','Join request cancelled.','gang_id',gid);
   else
    if me.gang_id is distinct from gid then raise exception 'Only current gang members can use this panel.';end if;
    if p_action in('accept','decline') then
     if not(coalesce(boss,false) or myrank.review_requests) then raise exception 'Your rank cannot review join requests.';end if;
     select * into q from game_private.gang_join_requests where id=(p_payload->>'application_id')::uuid and gang_id=gid and season_id=s and status='pending' for update;
     if q.id is null then raise exception 'This request is no longer pending.';end if;target_id:=q.player_id;
     if p_action='accept' then
      if not game_private.visible_player(target_id) then raise exception 'This applicant is unavailable.';end if;
      if exists(select 1 from public.game_season_gang_members where season_id=s and player_id=target_id) then raise exception 'This player has already joined a gang.';end if;
      if (select count(*) from public.game_season_gang_members where gang_id=gid)>=game_private.setting('gang_member_limit') then raise exception 'The gang has reached its member limit.';end if;
      insert into public.game_season_gang_members(season_id,player_id,gang_id) values(s,target_id,gid);
      update game_private.gang_join_requests set status='superseded',reviewed_at=clock_timestamp() where season_id=s and player_id=target_id and status='pending' and id<>q.id;
     end if;
     update game_private.gang_join_requests set status=case when p_action='accept' then 'accepted' else 'declined' end,reviewed_by=uid,reviewed_at=clock_timestamp() where id=q.id;
     note:=game_private.district_owner_name('player',target_id)||case when p_action='accept' then ' was welcomed into the gang.' else ' had their join request declined.' end;
    elsif p_action in('rank','remove','leave') then
     target_id:=case when p_action='leave' then uid else (p_payload->>'player_id')::uuid end;
     select * into target from public.game_season_gang_members where season_id=s and gang_id=gid and player_id=target_id for update;
     if target.player_id is null then raise exception 'This player is no longer in your gang.';end if;
     if g.data->>'owner_id'=target_id::text then raise exception 'The gang leader cannot be removed or assigned another rank.';end if;
     if p_action<>'leave' then
      if target_id=uid or not(coalesce(boss,false) or myrank.manage_members) then raise exception 'Your rank cannot manage this member.';end if;
      if not boss and (select priority from game_private.gang_ranks where id=target.rank_id)>=myrank.priority then raise exception 'You can only manage members below your rank.';end if;
      if (p_payload->>'version')::integer is distinct from target.version then raise exception 'This member changed. Refresh before trying again.';end if;
     end if;
     if p_action='rank' then
      select * into rankrow from game_private.gang_ranks where id=p_payload->>'rank_id';
      if rankrow.id is null or not boss and rankrow.priority>=myrank.priority then raise exception 'You cannot assign this rank.';end if;
      update public.game_season_gang_members set rank_id=rankrow.id,version=version+1 where season_id=s and player_id=target_id;
      note:=game_private.district_owner_name('player',target_id)||' was assigned the rank of '||rankrow.label||'.';
     else
      delete from public.game_season_gang_members where season_id=s and player_id=target_id;
      note:=game_private.district_owner_name('player',target_id)||case when p_action='leave' then ' left the gang.' else ' was removed from the gang.' end;
     end if;
    elsif p_action='settings' then
     if not coalesce(boss,false) then raise exception 'Only the gang leader can edit gang settings.';end if;
     if (p_payload->>'version')::integer is distinct from g.version then raise exception 'Gang settings changed. Refresh before saving.';end if;
     body:=btrim(coalesce(p_payload->>'description',''));
     if length(body)>300 or p_payload->>'recruitment' not in('open','closed') or p_payload->>'recruitment' is null then raise exception 'Check the description and recruitment setting.';end if;
     update public.game_season_gangs set description=body,data=data||jsonb_build_object('recruitment',p_payload->>'recruitment'),version=version+1 where id=gid;
     note:='Gang description and recruitment settings updated.';
    elsif p_action in('deposit','withdraw') then
     if p_action='withdraw' and not coalesce(boss,false) then raise exception 'Only the gang leader can withdraw gang funds.';end if;
     if p_action='deposit' and game_private.setting('gang_bank_deposits_enabled')<>1 then raise exception 'Gang deposits are currently paused.';end if;
     if jsonb_typeof(p_payload->'amount') is distinct from 'number' then raise exception 'Enter a whole-dollar amount.';end if;
     amount:=(p_payload->>'amount')::numeric;
     if amount<>trunc(amount) or amount<1 or amount>game_private.setting('gang_bank_max_transfer') then raise exception 'Amount is outside the gang bank transfer limit.';end if;
     perform 1 from public.game_players where id=uid and season_id=s for update;
     if not found then raise exception 'Open your dashboard to initialize this season.';end if;
     insert into game_private.gang_accounts(season_id,gang_id) values(s,gid) on conflict do nothing;
     perform 1 from game_private.gang_accounts where season_id=s and gang_id=gid for update;
     delta:=case when p_action='deposit' then amount::bigint else -amount::bigint end;
     if (select balance from game_private.gang_accounts where season_id=s and gang_id=gid)+delta<0 then raise exception 'Not enough money in the gang bank.';end if;
     perform set_config('game.gang_request_id',nonce::text,true);
     perform game_private.district_wallet(uid,-delta,'Gang bank '||p_action||': '||gid||' / '||nonce);
     update game_private.gang_accounts set balance=balance+delta,updated_at=clock_timestamp() where season_id=s and gang_id=gid;
     note:=game_private.district_owner_name('player',uid)||case when delta>0 then ' deposited $' else ' withdrew $' end||amount||case when delta>0 then ' into the gang bank.' else ' from the gang bank.' end;
    else raise exception 'Unknown gang action.';
    end if;
   end if;
  end if;
  if note is not null then
   insert into game_private.gang_events(season_id,gang_id,actor_id,target_id,kind,description) values(s,gid,uid,target_id,p_action,note);
   result:=jsonb_build_object('message',note,'gang_id',gid);
  end if;
  insert into game_private.gang_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation or unique_violation then
  return jsonb_build_object('error','Check your details and refresh the gang panel.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end$$;

create function game_private.gang_workspace(p_gang uuid default null,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();mine uuid;gid uuid;g public.game_season_gangs;me public.game_season_gang_members;r game_private.gang_ranks;
 boss boolean:=false;member boolean:=false;review boolean:=false;manage boolean:=false;off integer:=greatest(0,least(coalesce(p_offset,0),1000000));directory jsonb;selected jsonb;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not game_private.rate('gang_workspace',90) then raise exception 'Wait a moment before refreshing.';end if;
 select * into me from public.game_season_gang_members where season_id=s and player_id=uid;mine:=me.gang_id;gid:=coalesce(p_gang,mine);
 directory:=game_private.gang_directory();
 select * into g from public.game_season_gangs where season_id=s and id=gid;
 if g.id is not null then
  member:=coalesce(mine=gid,false);boss:=member and coalesce(g.data->>'owner_id'=uid::text,false);
  select * into r from game_private.gang_ranks where id=me.rank_id and member;
  review:=boss or coalesce(r.review_requests,false);manage:=boss or coalesce(r.manage_members,false);
  selected:=jsonb_build_object(
   'id',g.id,'name',g.name,'description',g.description,'version',g.version,'created_at',g.created_at,'recruiting',g.data->>'recruitment'='open',
   'leader',jsonb_build_object('id',g.data->>'owner_id','name',game_private.district_owner_name('player',(g.data->>'owner_id')::uuid),'avatar_url',game_private.player_avatar((g.data->>'owner_id')::uuid)),
   'is_member',member,'is_owner',boss,'can_review',review,'can_manage',manage,'my_rank',case when boss then 'Don / Gang leader' else r.label end,
   'member_count',(select count(*) from public.game_season_gang_members where gang_id=gid),
   'respect',(select coalesce(sum(sp.xp),0) from public.game_season_gang_members m join public.game_season_players sp on sp.season_id=m.season_id and sp.player_id=m.player_id where m.gang_id=gid and game_private.visible_player(m.player_id)),
   'application',(select jsonb_build_object('id',id,'status',status,'created_at',created_at) from game_private.gang_join_requests where gang_id=gid and player_id=uid order by created_at desc,id desc limit 1),
   'members',case when member then (select coalesce(jsonb_agg(x order by x.is_owner desc,x.priority desc,x.name),'[]') from (
    select m.player_id as id,game_private.district_owner_name('player',m.player_id) as name,game_private.player_avatar(m.player_id) as avatar_url,
    coalesce(sp.xp,0) as respect,m.contribution,m.rank_id,m.version,m.joined_at,
    m.player_id::text=g.data->>'owner_id' as is_owner,
    case when m.player_id::text=g.data->>'owner_id' then 'Don / Gang leader' else ranks.label end as rank_label,ranks.priority,
    exists(select 1 from game_private.online_players() o where o.player_id=m.player_id) as online,
    manage and m.player_id<>uid and m.player_id::text<>g.data->>'owner_id' and (boss or ranks.priority<r.priority) as can_edit
    from public.game_season_gang_members m join game_private.gang_ranks ranks on ranks.id=m.rank_id left join public.game_season_players sp on sp.season_id=m.season_id and sp.player_id=m.player_id where m.gang_id=gid
   ) x) else '[]'::jsonb end,
   'requests',case when review then (select coalesce(jsonb_agg(x order by x.created_at),'[]') from (
    select q.id,q.player_id,game_private.district_owner_name('player',q.player_id) as name,game_private.player_avatar(q.player_id) as avatar_url,q.created_at,
    coalesce(sp.xp,0) as respect
    from game_private.gang_join_requests q left join public.game_season_players sp on sp.season_id=q.season_id and sp.player_id=q.player_id where q.gang_id=gid and q.status='pending' order by q.created_at limit 100
   ) x) else '[]'::jsonb end,
   'bank',case when member then jsonb_build_object(
    'balance',coalesce((select balance from game_private.gang_accounts where season_id=s and gang_id=gid),0),'can_withdraw',boss,
    'offset',off,'page_size',10,'total',(select count(*) from game_private.gang_ledger where gang_id=gid),
    'history',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id desc),'[]') from (
     select id,actor_id,game_private.district_owner_name('player',actor_id) as name,delta,balance_after,created_at from game_private.gang_ledger where gang_id=gid order by created_at desc,id desc limit 10 offset off
    ) x),
    'my_deposits',(select coalesce(sum(delta),0) from game_private.gang_ledger where gang_id=gid and actor_id=uid and delta>0)
   ) else null end,
   'events',case when member then (select coalesce(jsonb_agg(x order by x.id desc),'[]') from (select id,actor_id,target_id,kind,description,created_at from game_private.gang_events where gang_id=gid order by id desc limit 50)x) else '[]'::jsonb end,
   'territories',(select coalesce(jsonb_agg(x order by x.name),'[]') from (select d.name,d.slug,t.status from public.game_district_territory t join public.game_districts d on d.id=t.district_id where t.season_id=s and t.controller_gang_id=gid and d.archived_at is null)x)
  );
 end if;
 return jsonb_build_object('season',directory->'season','playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
 'player',(select jsonb_build_object('id',id,'name',handle,'cash',cash) from public.game_players where id=uid),
 'directory',(select coalesce(jsonb_agg(x||jsonb_build_object('description',listed.description,'recruiting',listed.data->>'recruitment'='open') order by (x->>'rank')::int,listed.id),'[]') from jsonb_array_elements(directory->'gangs') x join public.game_season_gangs listed on listed.id=(x->>'id')::uuid),
 'total',directory->'total','my_gang_id',mine,'selected',selected,
 'ranks',(select jsonb_agg(to_jsonb(x)||jsonb_build_object('assignable',boss or manage and x.priority<r.priority) order by x.priority desc) from game_private.gang_ranks x),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'gang_%' or key='district_gang_creation_cost'),
 'server_time',clock_timestamp());
end$$;
create function public.gang_workspace(p_gang uuid default null,p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select game_private.gang_workspace(p_gang,p_offset)$$;
create function public.gang_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.gang_action(p_action,p_payload)$$;
revoke all on function game_private.gang_bank_entry(),game_private.gang_request_telegram(uuid),game_private.gang_action(text,jsonb),game_private.gang_workspace(uuid,integer),public.gang_action(text,jsonb),public.gang_workspace(uuid,integer) from public,anon,authenticated;
grant execute on function game_private.gang_action(text,jsonb),game_private.gang_workspace(uuid,integer),public.gang_action(text,jsonb),public.gang_workspace(uuid,integer) to authenticated;

-- Legacy district entry points also use approval-based recruitment and the same hierarchy.
alter function game_private.district_action(text,jsonb) rename to district_action_before_headquarters;
create function game_private.district_action(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare payload jsonb:=p_payload;
begin
 if p_action in('gang_create','gang_join','gang_leave') then
  if p_action='gang_leave' then payload:=payload||jsonb_build_object('gang_id',(select gang_id from public.game_season_gang_members where season_id=game_private.current_season() and player_id=auth.uid()));end if;
  payload:=payload||jsonb_build_object('request_id',coalesce(nullif(payload->>'request_id','')::uuid,gen_random_uuid()));
  return game_private.gang_action(case p_action when 'gang_create' then 'create' when 'gang_join' then 'request_join' else 'leave' end,payload);
 end if;
 return game_private.district_action_before_headquarters(p_action,p_payload);
end$$;
revoke all on function game_private.district_action_before_headquarters(text,jsonb),game_private.district_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.district_action(text,jsonb) to authenticated;

-- A genuine server-generated request carries a link back to the review panel.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.telegram_state(uuid,text,integer,uuid)'::regprocedure) into definition;
 if position('m.body,m.created_at,' in definition)=0 then raise exception 'Review recruitment Telegram integration';end if;
 execute replace(definition,'m.body,m.created_at,','m.body,m.created_at,(select q.gang_id from game_private.gang_join_requests q where q.telegram_id=m.id) as recruitment_gang_id,');
end$$;
notify pgrst,'reload schema';
