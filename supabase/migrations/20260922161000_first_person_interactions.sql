select pg_advisory_xact_lock(4704020);
-- Preserve search accounting and allow interaction from arm’s reach.
create or replace function game_private.scav_action_before_patrols(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.scav_requests;session game_private.scav_sessions;
 d public.game_districts;stamp timestamptz;destination integer;cursor_node integer;route jsonb;v_targets jsonb;target jsonb;
 result jsonb;receipt jsonb;v_pending jsonb;opened boolean;xp integer:=0;ready timestamptz;steps integer; origin jsonb; goal jsonb; gx double precision;gy double precision;distance double precision;
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
      on conflict(season_id,player_id) do update set district_id=d.id,node=0,path='[0]',route_points='[[0,0]]',departed_at=stamp,arrives_at=stamp;
    end if;
    result:=jsonb_build_object('message','Entered '||d.name||'. Click a street or search location to walk.');
   elsif p_action='move' then
    if session.pending is not null then raise exception 'Finish or cancel your search first.';end if;
    if p_payload?'x' or p_payload?'y' then
     if jsonb_typeof(p_payload->'x') is distinct from 'number' or jsonb_typeof(p_payload->'y') is distinct from 'number' then raise exception 'Choose a street on the map.';end if;
     gx:=(p_payload->>'x')::double precision;gy:=(p_payload->>'y')::double precision;
    else
     destination:=(p_payload->>'node')::integer;
     if destination is null or destination not between 0 and 14 then raise exception 'Choose a street on the map.';end if;
     gx:=destination%5;gy:=destination/5;
    end if;
    if gx is null or gy is null or not(gx between 0 and 4 and gy between 0 and 2) or (gx<>trunc(gx) and gy<>trunc(gy)) then raise exception 'Choose a walkable street.';end if;
    goal:=jsonb_build_array(gx,gy);
    origin:=game_private.scav_position(session.route_points,session.departed_at,session.arrives_at,stamp);
    route:=game_private.scav_route(origin,goal);distance:=game_private.scav_route_length(route);
    destination:=round(gy)::int*5+round(gx)::int;
    update game_private.scav_sessions set walk_controller=null,node=destination,path=jsonb_build_array(destination),route_points=route,departed_at=stamp,arrives_at=stamp+make_interval(secs=>distance*game_private.setting('scavenging_walk_seconds')) where season_id=s and player_id=u;
    result:=jsonb_build_object('message',case when distance=0 then 'You are here.' else 'Walking to the selected street.' end);
   elsif p_action='search' then
    if session.pending is not null then raise exception 'A search is already in progress.';end if;
    if session.arrives_at>stamp then raise exception 'Reach the location before searching.';end if;
    select m.targets into v_targets from game_private.scav_maps m where season_id=s and player_id=u and district_id=d.id for update;
    select x into target from jsonb_array_elements(v_targets)x where x->>'id'=p_payload->>'target_id';
    if target is null or game_private.scav_route_length(jsonb_build_array(session.route_points->(jsonb_array_length(session.route_points)-1),jsonb_build_array((target->>'node')::int%5,(target->>'node')::int/5)))>game_private.setting('scavenging_interaction_radius_percent')/100 then raise exception 'Walk to this location first.';end if;
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

revoke all on function game_private.scav_action_before_patrols(text,jsonb) from public,anon,authenticated;
