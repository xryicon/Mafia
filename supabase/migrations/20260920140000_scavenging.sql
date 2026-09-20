-- Street exploration uses server-timed movement, private search sites and the existing loot ledger.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce district scavenging and car lockpicking',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_walk_seconds',3,1,30),('scavenging_search_seconds',4,1,120),
 ('scavenging_lock_seconds',8,1,120),('scavenging_restock_seconds',600,1,86400),
 ('scavenging_car_success_percent',65,0,100),('scavenging_lock_xp',25,1,10000);
create table game_private.scav_maps(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),targets jsonb not null,
 primary key(season_id,player_id,district_id)
);
create table game_private.scav_sessions(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),node integer not null default 0 check(node between 0 and 14),
 path jsonb not null default '[0]',departed_at timestamptz not null default clock_timestamp(),arrives_at timestamptz not null default clock_timestamp(),
 pending jsonb,primary key(season_id,player_id)
);
create table game_private.scav_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(season_id,player_id,request_id)
);
create table game_private.scav_results(
 id uuid primary key,season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),target_id text not null,kind text not null,opened boolean not null,
 xp integer not null,receipt_id uuid references public.game_bin_dives(id),created_at timestamptz not null default clock_timestamp()
);
alter table game_private.scav_maps enable row level security;
alter table game_private.scav_sessions enable row level security;
alter table game_private.scav_requests enable row level security;
alter table game_private.scav_results enable row level security;
revoke all on game_private.scav_maps,game_private.scav_sessions,game_private.scav_requests,game_private.scav_results from public,anon,authenticated;
create trigger scav_requests_retain before update or delete or truncate on game_private.scav_requests for each statement execute function game_private.district_immutable();
create trigger scav_results_retain before update or delete or truncate on game_private.scav_results for each statement execute function game_private.district_immutable();

alter function game_private.bin_state() rename to bin_loot_state;
create function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare data jsonb; s uuid; u uuid:=auth.uid(); session game_private.scav_sessions; streets jsonb;
begin
 data:=game_private.bin_loot_state();s:=(data->'season'->>'id')::uuid;
 select * into session from game_private.scav_sessions where season_id=s and player_id=u;
 select coalesce(jsonb_agg(name order by sort_order,name),'[]') into streets from
  (select name,sort_order from public.game_district_streets where district_id=session.district_id and archived_at is null order by sort_order,name limit 3)x;
 return data||jsonb_build_object('scavenging',jsonb_build_object(
  'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'scavenging_%'),
  'session',case when session.player_id is null then null else to_jsonb(session)-'player_id'-'season_id' end,
  'streets',streets,
  'targets',coalesce((select targets from game_private.scav_maps where season_id=s and player_id=u and district_id=session.district_id),'[]'),
  'recent',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select kind,opened,xp,created_at from game_private.scav_results where season_id=s and player_id=u order by created_at desc limit 10)x)
 ));
end$$;

create function public.scavenging_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.scav_requests;session game_private.scav_sessions;
 d public.game_districts;stamp timestamptz;destination integer;cursor_node integer;route jsonb;v_targets jsonb;target jsonb;
 result jsonb;receipt jsonb;v_pending jsonb;opened boolean;xp integer:=0;ready timestamptz;steps integer;
begin
 perform game_private.require_active();
 if not game_private.rate('scavenging',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Slow down. Try again in a moment.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid street action.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the streets.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'Request ID required.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.scav_requests where season_id=s and player_id=u and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'Request already used for another action.';end if;
   return prior.result;
  end if;
  perform game_private.season_guard();
  perform 1 from public.game_players where id=u and season_id=s for update;
  if not found then raise exception 'Open the dashboard to initialize this season.';end if;
  stamp:=clock_timestamp();
  select * into session from game_private.scav_sessions where season_id=s and player_id=u for update;
  if p_action='cancel' then
   if session.pending is null then raise exception 'No search is active.';end if;
   update game_private.scav_sessions set pending=null where season_id=s and player_id=u;
   result:=jsonb_build_object('message','Search abandoned. Used lockpicks are not refunded.');
  else
   if not (select enabled from public.game_bin_rules) then raise exception 'The Owner has paused scavenging.';end if;
   select * into d from public.game_districts where id=case when p_action='enter' then (p_payload->>'district_id')::uuid else session.district_id end and archived_at is null for share;
   if not found then raise exception 'Choose an open district.';end if;
   if d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') then raise exception 'This district is in lockdown.';end if;
   if p_action='enter' then
    if session.pending is not null or session.arrives_at>stamp then raise exception 'Finish your current action before changing districts.';end if;
    if session.district_id is distinct from d.id then
     select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'node',n,'kind',case when n%3=0 then 'car' else 'bin' end,'ready_at',null) order by n)
      into v_targets from((select n from generate_series(1,14)n where n%3<>0 order by random() limit 7) union all (select n from generate_series(1,14)n where n%3=0 order by random() limit 3))x;
     insert into game_private.scav_maps values(s,u,d.id,v_targets) on conflict do nothing;
     insert into game_private.scav_sessions(season_id,player_id,district_id) values(s,u,d.id)
      on conflict(season_id,player_id) do update set district_id=d.id,node=0,path='[0]',departed_at=stamp,arrives_at=stamp;
    end if;
    result:=jsonb_build_object('message','Entered '||d.name||'. Click a street or search location to walk.');
   elsif p_action='move' then
    if session.pending is not null then raise exception 'Finish or cancel your search first.';end if;
    if session.arrives_at>stamp then raise exception 'You are still walking.';end if;
    destination:=(p_payload->>'node')::integer;
    if destination is null or destination not between 0 and 14 then raise exception 'Choose a street on the map.';end if;
    cursor_node:=session.node;route:=jsonb_build_array(cursor_node);
    while cursor_node/5<>destination/5 loop
     cursor_node:=cursor_node+case when cursor_node<destination then 5 else -5 end;route:=route||jsonb_build_array(cursor_node);
    end loop;
    while cursor_node<>destination loop
     cursor_node:=cursor_node+case when cursor_node<destination then 1 else -1 end;route:=route||jsonb_build_array(cursor_node);
    end loop;
    steps:=jsonb_array_length(route)-1;
    update game_private.scav_sessions set node=destination,path=route,departed_at=stamp,arrives_at=stamp+make_interval(secs=>steps*game_private.setting('scavenging_walk_seconds')) where season_id=s and player_id=u;
    result:=jsonb_build_object('message',case when steps=0 then 'You are here.' else 'Walking to the selected street.' end);
   elsif p_action='search' then
    if session.pending is not null then raise exception 'A search is already in progress.';end if;
    if session.arrives_at>stamp then raise exception 'Reach the location before searching.';end if;
    select m.targets into v_targets from game_private.scav_maps m where season_id=s and player_id=u and district_id=d.id for update;
    select x into target from jsonb_array_elements(v_targets)x where x->>'id'=p_payload->>'target_id';
    if target is null or (target->>'node')::integer<>session.node then raise exception 'Walk to this location first.';end if;
    if (target->>'ready_at')::timestamptz>stamp then raise exception 'This location has already been searched. Return later.';end if;
    select max(ready_at) into ready from public.game_bin_dives where season_id=s and player_id=u;
    if ready>stamp then raise exception 'Catch your breath. The search cooldown applies across the city.';end if;
    perform set_config('game.reason','Scavenging lockpick: '||nonce,true);perform set_config('game.inventory_request',nonce::text,true);
    if target->>'kind'='car' then
     update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=u and good_id='lockpick' and quantity>0;
     if not found then raise exception 'Carry a lockpick in your inventory to open a car.';end if;
    end if;
    v_pending:=jsonb_build_object('id',nonce,'target_id',target->>'id','kind',target->>'kind','started_at',stamp,
     'ready_at',stamp+make_interval(secs=>game_private.setting(case when target->>'kind'='car' then 'scavenging_lock_seconds' else 'scavenging_search_seconds' end)),
     'success_percent',game_private.setting('scavenging_car_success_percent'),'xp',game_private.setting('scavenging_lock_xp'));
    update game_private.scav_sessions set pending=v_pending where season_id=s and player_id=u;
    update game_private.scav_maps set targets=(select jsonb_agg(case when x->>'id'=target->>'id' then x||jsonb_build_object('ready_at',stamp+make_interval(secs=>game_private.setting('scavenging_restock_seconds'))) else x end) from jsonb_array_elements(v_targets)x)
     where season_id=s and player_id=u and district_id=d.id;
    result:=jsonb_build_object('message',case when target->>'kind'='car' then 'Working the lock. One lockpick used.' else 'Searching the bin…' end);
   elsif p_action='finish' then
    v_pending:=session.pending;
    if v_pending is null or v_pending->>'id' is distinct from p_payload->>'attempt_id' then raise exception 'This search is no longer active.';end if;
    if (v_pending->>'ready_at')::timestamptz>stamp then raise exception 'The search is not finished yet.';end if;
    opened:=v_pending->>'kind'='bin' or random()*100<(v_pending->>'success_percent')::numeric;
    if opened then
     result:=game_private.bin_action('dive',jsonb_build_object('season_id',s,'district_id',d.id,'request_id',(v_pending->>'id')::uuid));
     if result?'error' then raise exception '%',result->>'error';end if;
     receipt:=result->'receipt';
     if v_pending->>'kind'='car' then
      xp:=(v_pending->>'xp')::integer;
      insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description)
       values(s,u,'lockpicking',(v_pending->>'id')::uuid,xp,'Opened a parked car in '||d.name);
     end if;
    else
     insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at)
      select s,u,d.id,d.name,'nothing',0,version,stamp,stamp+make_interval(secs=>cooldown_seconds) from public.game_bin_rules returning to_jsonb(game_bin_dives.*) into receipt;
    end if;
    insert into game_private.scav_results(id,season_id,player_id,district_id,target_id,kind,opened,xp,receipt_id)
     values((v_pending->>'id')::uuid,s,u,d.id,v_pending->>'target_id',v_pending->>'kind',opened,xp,(receipt->>'id')::uuid);
    update game_private.scav_sessions set pending=null where season_id=s and player_id=u;
    result:=jsonb_build_object('receipt',receipt,'xp',xp,'message',case when not opened then 'The lock held. Your lockpick broke.' when xp>0 then 'Car opened. +'||xp||' Lockpicking XP.' else result->>'message' end);
   else raise exception 'Unknown street action.';end if;
  end if;
  insert into game_private.scav_requests values(s,u,nonce,p_action,p_payload,result,stamp);
  return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Invalid street action. Refresh and try again.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end$$;
-- Old bookmarks remain valid, but direct reward calls cannot skip the street interaction.
create or replace function public.bin_diving_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_action='dive' then return jsonb_build_object('error','Enter Scavenging and walk to a bin to search it.');end if;
 return game_private.bin_action(p_action,p_payload);
end$$;
revoke all on function public.scavenging_action(text,jsonb) from public,anon;
grant execute on function public.scavenging_action(text,jsonb) to authenticated;
revoke all on function game_private.bin_state(),game_private.bin_loot_state() from public,anon,authenticated;
update public.game_skill_definitions set description='Earn XP by opening car locks while scavenging and freeing players from prison.',version=version+1 where id='lockpicking';
