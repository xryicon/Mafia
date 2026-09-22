select pg_advisory_xact_lock(4704020);
-- A responding unit follows the getaway destination, recalculated only after an authoritative move.
create function game_private.street_pursuer(s uuid,u uuid) returns void language plpgsql security definer set search_path='' as $$
declare v game_private.scav_sessions;t timestamptz:=clock_timestamp();patrol jsonb;remaining jsonb;point jsonb;destination jsonb;route jsonb;back jsonb;duration double precision;epoch double precision;cycle bigint;speed numeric;radius numeric;island boolean;
begin
 select * into strict v from game_private.scav_sessions where season_id=s and player_id=u for update;
 if v.pursuit is null or (v.pursuit#>>'{rules,scavenging_patrol_enabled}')::integer=0 then return;end if;
 select x into patrol from jsonb_array_elements(v.pursuit->'patrols')x where x->>'id'='pursuit-unit';
 destination:=v.route_points->-1;
 if patrol is not null then
  duration:=game_private.scav_route_length(patrol->'route_points')*(patrol->>'seconds_per_block')::double precision;epoch:=(patrol->>'epoch')::double precision;
  cycle:=floor((extract(epoch from t)-epoch)/duration);
  point:=game_private.scav_position(patrol->'route_points',to_timestamp(epoch+cycle*duration),to_timestamp(epoch+(cycle+1)*duration),t);
 else point:=jsonb_build_array(case when (destination->>0)::numeric>=2 then 4 else 0 end,case when (destination->>1)::numeric>=1 then 2 else 0 end);end if;
 route:=game_private.scav_route(point,destination);
 if game_private.scav_route_length(route)<0.001 then route:=game_private.scav_route(point,jsonb_build_array(case when (point->>0)::numeric=0 then 1 else 0 end,(point->>1)::numeric));end if;
 select jsonb_agg(x order by n desc) into back from jsonb_array_elements(route) with ordinality a(x,n);
 route:=route||back;
 select coalesce(jsonb_agg(x),'[]') into remaining from jsonb_array_elements(v.pursuit->'patrols')x where x->>'id'<>'pursuit-unit';
 select slug='blackwater-island' into island from public.game_districts where id=v.district_id;
 speed:=(v.pursuit->'rules'->>case when island then 'scavenging_island_pursuer_speed' else 'scavenging_pursuer_seconds_per_block' end)::numeric;
 radius:=(v.pursuit#>>'{rules,scavenging_pursuer_radius}')::numeric/100;
 update game_private.scav_sessions set pursuit=jsonb_set(pursuit,'{patrols}',remaining||jsonb_build_array(jsonb_build_object('id','pursuit-unit','route_points',route,'epoch',extract(epoch from t),'seconds_per_block',speed,'radius',radius))) where season_id=s and player_id=u;
end$$;
revoke all on function game_private.street_pursuer(uuid,uuid) from public,anon,authenticated;

-- Resolve one retained vehicle outcome. A missing/full/expired garage falls back to the agreed cash sale.
create function game_private.street_settle(s uuid,u uuid,outcome text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v game_private.scav_sessions;car game_private.street_vehicles;result jsonb;destination uuid;
begin
 select * into strict v from game_private.scav_sessions where season_id=s and player_id=u for update;
 if v.pursuit is null then raise exception 'No pursuit is active.';end if;
 select * into strict car from game_private.street_vehicles where id=(v.pursuit->>'vehicle_id')::uuid and season_id=s and player_id=u and status='escaping' for update;
 perform set_config('game.reason','Street getaway: '||car.id,true);
 if outcome='escaped' then
  destination:=car.building_id;
  if destination is not null and game_private.street_garage(s,u,destination) then
   update game_private.street_vehicles set status='stored' where id=car.id;
   result:=jsonb_build_object('message','Escaped. '||car.name||' is secured in your garage.','vehicle_id',car.id,'stored',true);
  else
   update game_private.street_vehicles set status='sold',building_id=null where id=car.id;
   perform game_private.district_wallet(u,car.sale_value,'Stolen vehicle sale: '||car.id);
   result:=jsonb_build_object('message','Escaped. No garage space was available; '||car.name||' was sold immediately for $'||car.sale_value||'.','vehicle_id',car.id,'cash',car.sale_value);
  end if;
 else
  update game_private.street_vehicles set status=case when outcome='caught' then 'seized' else 'abandoned' end,building_id=null where id=car.id;
  result:=jsonb_build_object('message',case when outcome='caught' then 'Police intercepted you. The stolen car was seized and you were sent to Blackwater Island.' else 'You abandoned the stolen car and ended the pursuit without a reward.' end,'caught',outcome='caught');
 end if;
 insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,outcome,result);
 insert into public.game_events(player_id,description,cash_delta) values(u,result->>'message',coalesce((result->>'cash')::bigint,0));
 update game_private.scav_sessions set pursuit=null where season_id=s and player_id=u;
 return result;
end$$;
-- Continue sweeping pursuit movement on every street action and prison/status refresh.
alter function game_private.scav_resolve_patrol() rename to scav_resolve_search_patrol;
create function game_private.scav_resolve_patrol() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();v game_private.scav_sessions;t timestamptz;contact text;result jsonb;sentence uuid;deadline timestamptz;
begin
 result:=game_private.scav_resolve_search_patrol();if result is not null then return result;end if;
 s:=game_private.season_guard(false);
 if not exists(select 1 from game_private.scav_sessions where season_id=s and player_id=u and pursuit is not null) then return null;end if;
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 select * into v from game_private.scav_sessions where season_id=s and player_id=u for update;if v.pursuit is null then return null;end if;
 t:=clock_timestamp();deadline:=(v.pursuit->>'deadline')::timestamptz;
 contact:=game_private.street_motion_contact(v.pursuit->'patrols',v.route_points,v.departed_at,v.arrives_at,greatest((v.pursuit->>'checked_at')::timestamptz,(v.pursuit->>'grace_until')::timestamptz),least(t,deadline));
 if contact is not null or t>=deadline then
  select id into sentence from public.game_prison_sentences where season_id=s and player_id=u and released_at is null and release_at>t;
  if sentence is null then sentence:=game_private.imprison(u,(v.pursuit->>'sentence_minutes')::integer,'Caught during a stolen-car pursuit.');end if;
  insert into game_private.scav_arrests(attempt_id,season_id,player_id,district_id,patrol_id,kind,sentence_id) values((v.pursuit->>'id')::uuid,s,u,v.district_id,coalesce(contact,'police-cordon'),'car',sentence) on conflict do nothing;
  return game_private.street_settle(s,u,'caught');
 end if;
 update game_private.scav_sessions set pursuit=jsonb_set(pursuit,'{checked_at}',to_jsonb(t)) where season_id=s and player_id=u;
 return null;
end$$;

create function game_private.street_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid:=game_private.current_season();u uuid:=auth.uid();v game_private.scav_sessions;t timestamptz:=clock_timestamp();interval_s integer;event_window bigint;event_kind text;island boolean;event game_private.street_events;
begin
 perform game_private.require_active();select * into v from game_private.scav_sessions where season_id=s and player_id=u;
 if v.district_id is not null then
  interval_s:=game_private.setting('scavenging_event_interval_seconds');event_window:=floor(extract(epoch from t)/interval_s);
  perform pg_advisory_xact_lock(4704020);
  if not exists(select 1 from game_private.street_events e where e.season_id=s and e.player_id=u and e.district_id=v.district_id and e.window_id=event_window) then
   event_kind:=case when random()*100>=game_private.setting('scavenging_event_chance') then 'quiet' else (array['satchel','cache','sweep'])[1+floor(random()*3)::int] end;
   insert into game_private.street_events(season_id,player_id,district_id,window_id,kind,node,expires_at) values(s,u,v.district_id,event_window,event_kind,1+floor(random()*14)::integer,to_timestamp((event_window+1)*interval_s)) on conflict do nothing;
  end if;
  select * into event from game_private.street_events e where e.season_id=s and e.player_id=u and e.district_id=v.district_id and e.window_id=event_window;
  select slug='blackwater-island' into island from public.game_districts where id=v.district_id;
 end if;
 return jsonb_build_object('pursuit',v.pursuit,'vitals',game_private.vitals_state(),'weapon',game_private.robbery_weapon(s,u),'island',coalesce(island,false),
  'cash_multiplier',case when island then game_private.setting('scavenging_island_cash_multiplier') else 1 end,
  'event',case when event.kind<>'quiet' and event.started_at is null then to_jsonb(event)-'season_id'-'player_id'-'window_id' else null end,
  'garages',(select coalesce(jsonb_agg(x),'[]') from(select b.id,p.code,d.name district_name from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id join public.game_districts d on d.id=p.district_id where b.season_id=s and b.building_type='garage' and game_private.street_garage(s,u,b.id) order by d.name,p.code)x),
  'vehicles',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select c.id,c.name,c.sale_value,c.building_id,p.code,c.created_at,game_private.property_access(s,u,c.building_id,true) garage_active from game_private.street_vehicles c left join public.game_district_plots p on p.id=(select plot_id from public.game_district_buildings where id=c.building_id) where c.season_id=s and c.player_id=u and c.status='stored')x),
  'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select kind,details,created_at from game_private.street_history where season_id=s and player_id=u order by created_at desc limit 12)x),
  'models',(select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]') from game_private.street_vehicle_models m where m.enabled or game_private.has_permission('bin_diving.manage')));
end$$;
create or replace function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;ops jsonb;targets jsonb;
begin
 result:=game_private.bin_state_before_robberies();ops:=game_private.street_state();
 select coalesce(jsonb_agg(case when x->>'kind'='car' then x||jsonb_build_object('vehicle',game_private.street_model(x->>'id')) else x end),'[]') into targets from jsonb_array_elements(result#>'{scavenging,targets}')x;
 return jsonb_set(result,'{scavenging}',(result->'scavenging')||jsonb_build_object('operations',ops,'targets',targets,'patrols',coalesce(result#>'{scavenging,session,pending,patrols}',ops#>'{pursuit,patrols}',game_private.scav_patrols((result#>>'{scavenging,session,district_id}')::uuid))));
end$$;

alter function public.scavenging_action(text,jsonb) set schema game_private;
alter function game_private.scavenging_action(text,jsonb) rename to scav_action_before_operations;
create function public.scavenging_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.street_requests;v game_private.scav_sessions;d public.game_districts;t timestamptz;result jsonb;car jsonb;target jsonb;bid uuid;item game_private.street_vehicles;event game_private.street_events;v_pending jsonb;receipt jsonb;opened boolean;rules jsonb;xp integer;weapon jsonb;shots integer;damage integer;absorbed numeric;hp numeric;vit jsonb;chance numeric;f jsonb;before_arrival timestamptz;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 -- Arrest is resolved outside the action rollback block, including on invalid or interrupted requests.
 result:=game_private.scav_resolve_patrol();if result is not null then return result;end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid street action.';end if;
  nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh the streets before continuing.';end if;
  select * into prior from game_private.street_requests where season_id=s and player_id=u and request_id=nonce;
  if found then if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'Request already used for another action.';end if;return prior.result;end if;
  perform game_private.season_guard();
  select * into v from game_private.scav_sessions where season_id=s and player_id=u for update;t:=clock_timestamp();
  perform set_config('game.reason','Street operation: '||p_action||' / '||nonce,true);perform set_config('game.inventory_request',nonce::text,true);
  if v.pursuit is not null and p_action not in('move','escape','fight','abandon') then raise exception 'Finish your police pursuit before another activity.';end if;
  if p_action in('steal','event','escape','fight','abandon','sell_vehicle','vehicle_model') or (p_action='finish' and v.pending?'mode') then
   if not game_private.rate('street_operations',game_private.setting('actions_per_minute')) then raise exception 'Slow down. Try again in a moment.';end if;
  end if;
  if p_action='vehicle_model' then
   if not game_private.has_permission('bin_diving.manage') then raise exception 'Owner permission required.';end if;
   if length(btrim(coalesce(p_payload->>'reason',''))) not between 5 and 500 then raise exception 'Add an audit reason.';end if;
   perform set_config('game.reason','Vehicle model: '||(p_payload->>'reason'),true);
   update game_private.street_vehicle_models set sale_value=(p_payload->>'sale_value')::bigint,enabled=(p_payload->>'enabled')::boolean,version=version+1 where id=p_payload->>'id' and version=(p_payload->>'version')::integer;
   if not found then raise exception 'The model changed. Refresh before saving.';end if;
   result:=jsonb_build_object('message','Vehicle model saved and audited.');
  elsif p_action='sell_vehicle' then
   select * into item from game_private.street_vehicles where id=(p_payload->>'vehicle_id')::uuid and season_id=s and player_id=u and status='stored' for update;
   if not found then raise exception 'Choose a vehicle you own in storage.';end if;
   update game_private.street_vehicles set status='sold',building_id=null where id=item.id;
   perform game_private.district_wallet(u,item.sale_value,'Stored vehicle sale: '||item.id);
   result:=jsonb_build_object('message',item.name||' sold for $'||item.sale_value||'.','cash',item.sale_value);
   insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,'vehicle_sold',result);
  elsif p_action in('steal','event') then
   if v.player_id is null or v.pending is not null or v.arrives_at>t then raise exception 'Reach the location and finish your current action first.';end if;
   if exists(select 1 from public.game_range_sessions where season_id=s and player_id=u and status='active' and ends_at>t) then raise exception 'Finish your shooting range session first.';end if;
   select * into d from public.game_districts where id=v.district_id and archived_at is null;
   if d.id is null or d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') or not (select enabled from public.game_bin_rules) then raise exception 'This district is closed for scavenging.';end if;
   if exists(select 1 from public.game_bin_dives where season_id=s and player_id=u and ready_at>t) then raise exception 'Wait for your city-wide search cooldown.';end if;
   if p_action='steal' then
    select x into target from game_private.scav_maps m cross join lateral jsonb_array_elements(m.targets)x where m.season_id=s and m.player_id=u and m.district_id=d.id and x->>'id'=p_payload->>'target_id';
    if target->>'kind' is distinct from 'car' then raise exception 'Choose a parked car.';end if;
    car:=game_private.street_model(target->>'id');if car is null then raise exception 'Vehicle theft is currently unavailable.';end if;
    bid:=nullif(p_payload->>'garage_id','')::uuid;
    if bid is not null and not game_private.street_garage(s,u,bid) then raise exception 'Choose a usable garage with an empty vehicle bay.';end if;
    if bid is null then select b.id into bid from public.game_district_buildings b where b.season_id=s and b.building_type='garage' and game_private.street_garage(s,u,b.id) order by b.id limit 1;end if;
    result:=game_private.scav_action_before_operations('search',p_payload);if result?'error' or result?'caught' then return result;end if;
    select ss.pending into v_pending from game_private.scav_sessions ss where season_id=s and player_id=u;
    v_pending:=v_pending||jsonb_build_object('mode','theft','vehicle',car,'garage_id',bid,'ready_at',t+make_interval(secs=>game_private.setting('scavenging_theft_seconds')),'success_percent',game_private.setting('scavenging_theft_success_percent'),'xp',game_private.setting('scavenging_theft_xp'));
    result:=jsonb_build_object('message','Lock bypass underway. One lockpick used. A successful theft starts a police pursuit.');
   else
    select * into event from game_private.street_events where id=(p_payload->>'event_id')::uuid and season_id=s and player_id=u and district_id=d.id and expires_at>t and started_at is null for update;
    if not found or event.kind not in('satchel','cache') then raise exception 'This street opportunity has expired or was already used.';end if;
    if game_private.scav_route_length(jsonb_build_array(v.route_points->-1,jsonb_build_array(event.node%5,event.node/5)))>0.000001 then raise exception 'Walk to the street event first.';end if;
    update game_private.street_events set started_at=t where id=event.id;
    v_pending:=jsonb_build_object('id',nonce,'target_id',event.id,'kind','bin','mode','event','event_kind',event.kind,'cash_multiplier',game_private.setting('scavenging_event_cash_multiplier'),'started_at',t,'ready_at',t+make_interval(secs=>game_private.setting('scavenging_search_seconds')),'patrols',game_private.scav_patrols(d.id),'xp',0);
    result:=jsonb_build_object('message','Investigating the street opportunity. Keep an eye on patrols.');
   end if;
   v_pending:=v_pending||jsonb_build_object('patrol_sentence_minutes',game_private.setting(case when d.slug='blackwater-island' then 'scavenging_island_sentence_minutes' else 'scavenging_patrol_sentence_minutes' end));
   select jsonb_object_agg(key,value) into rules from public.game_settings where key like 'scavenging_%';
   v_pending:=v_pending||jsonb_build_object('operation_rules',rules);
   update game_private.scav_sessions set pending=v_pending where season_id=s and player_id=u;
  elsif p_action='finish' and v.pending?'mode' then
   v_pending:=v.pending;
   if v_pending->>'id' is distinct from p_payload->>'attempt_id' or (v_pending->>'ready_at')::timestamptz>t then raise exception 'This operation is not ready.';end if;
   select * into strict d from public.game_districts where id=v.district_id;
   if v_pending->>'mode'='event' then
    result:=game_private.bin_action('dive',jsonb_build_object('season_id',s,'district_id',d.id,'request_id',v_pending->>'id'));if result?'error' then raise exception '%',result->>'error';end if;
    insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,'street_find',jsonb_build_object('message','Investigated a street opportunity.','receipt',result->'receipt'));
   else
    if d.archived_at is not null or d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') or not (select enabled from public.game_bin_rules) then raise exception 'Scavenging is paused here. Abandon this operation or wait for it to reopen.';end if;
    opened:=random()*100<(v_pending->>'success_percent')::numeric;rules:=v_pending->'operation_rules';xp:=case when opened then (v_pending->>'xp')::integer else 0 end;
    insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at) select s,u,d.id,d.name,'nothing',0,version,t,t+make_interval(secs=>cooldown_seconds) from public.game_bin_rules returning to_jsonb(game_bin_dives.*) into receipt;
    if opened then
     car:=v_pending->'vehicle';bid:=(v_pending->>'garage_id')::uuid;
     insert into game_private.street_vehicles(season_id,player_id,district_id,model_id,name,sale_value,status,building_id,source_id) values(s,u,d.id,car->>'id',car->>'name',(car->>'sale_value')::bigint,'escaping',bid,(v_pending->>'id')::uuid) returning * into item;
     if xp>0 then insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description) values(s,u,'lockpicking',(v_pending->>'id')::uuid,xp,'Stole a parked vehicle');end if;
     update game_private.scav_sessions set pursuit=jsonb_build_object('id',v_pending->>'id','vehicle_id',item.id,'vehicle_name',item.name,'started_at',t,'checked_at',t,'grace_until',t+make_interval(secs=>(rules->>'scavenging_chase_grace_seconds')::int),'deadline',t+make_interval(secs=>(rules->>'scavenging_chase_seconds')::int),'exit_node',0,'patrols',v_pending->'patrols','sentence_minutes',v_pending->'patrol_sentence_minutes','rules',rules,'next_shot_at',t) where season_id=s and player_id=u;
     perform game_private.street_pursuer(s,u);
     result:=jsonb_build_object('message','Engine running. Police alerted! Reach the escape marker or fight back. +'||xp||' Lockpicking XP.','pursuit',true,'xp',xp);
    else result:=jsonb_build_object('message','The ignition refused to turn. Your lockpick broke.','xp',0);end if;
    insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,'vehicle_theft',result);
   end if;
   update game_private.scav_sessions set pending=null where season_id=s and player_id=u;
  elsif p_action in('escape','abandon','fight') then
   if v.pursuit is null then raise exception 'No police pursuit is active.';end if;
   rules:=v.pursuit->'rules';
   if p_action='escape' then
    if v.arrives_at>t or game_private.scav_route_length(jsonb_build_array(v.route_points->-1,'[0,0]'::jsonb))>0.000001 or t<(v.pursuit->>'started_at')::timestamptz+make_interval(secs=>(rules->>'scavenging_escape_min_seconds')::int) then raise exception 'Reach the escape marker and wait for a clear exit.';end if;
    result:=game_private.street_settle(s,u,'escaped');
   elsif p_action='abandon' then result:=game_private.street_settle(s,u,'abandoned');
   else
    if (v.pursuit->>'next_shot_at')::timestamptz>t then raise exception 'Take cover before firing again.';end if;
    weapon:=game_private.robbery_weapon(s,u);shots:=(rules->>'scavenging_combat_bullets')::integer;
    if weapon is null or (weapon->>'ammo')::integer<shots then raise exception 'Equip a working gun and enough compatible ammunition.';end if;
    vit:=game_private.vitals_state();hp:=(vit->>'health')::numeric;if hp<=0 then raise exception 'You are too injured to fight.';end if;
    update public.game_inventory_gear set quantity=quantity-shots,location=case when quantity=shots then 'retired' else location end,equipment_slot=case when quantity=shots then null else equipment_slot end where id=(weapon->>'ammo_id')::uuid and player_id=u and season_id=s and location='equipped' and quantity>=shots;
    if not found then raise exception 'Equipped ammunition changed. Refresh first.';end if;
    update public.game_inventory_gear set condition=greatest(0,(weapon->>'condition')::integer-shots*(weapon->>'wear_per_shot')::integer) where id=(weapon->>'id')::uuid;
    update game_private.range_magazines set loaded=greatest(0,loaded-shots),reload_capacity=null,reload_started_at=null,reload_ready_at=null where season_id=s and player_id=u and ammo_id=(weapon->>'ammo_id')::uuid;
    damage:=(rules->>'scavenging_combat_damage_min')::int+floor(random()*(greatest((rules->>'scavenging_combat_damage_min')::int,(rules->>'scavenging_combat_damage_max')::int)-(rules->>'scavenging_combat_damage_min')::int+1))::int;
    absorbed:=least((vit->>'armour')::numeric,damage);hp:=greatest(0,hp-damage+absorbed);
    update public.game_season_players set health=hp,health_updated_at=t,armour=greatest(0,armour-absorbed) where season_id=s and player_id=u;
    f:=game_private.robbery_factors(s,u);chance:=least(100,greatest(0,(rules->>'scavenging_combat_escape_percent')::numeric+(f->>'level')::numeric-1));
    if hp<=0 then perform game_private.imprison(u,(v.pursuit->>'sentence_minutes')::int,'Injured and arrested after firing at police.');result:=game_private.street_settle(s,u,'caught');
    elsif random()*100<chance then result:=game_private.street_settle(s,u,'escaped');
    else
     update game_private.scav_sessions set pursuit=pursuit||jsonb_build_object('next_shot_at',t+make_interval(secs=>(rules->>'scavenging_combat_seconds')::int)) where season_id=s and player_id=u;
     result:=jsonb_build_object('message','Police returned fire. The pursuit continues. Reach the exit or take cover before firing again.');
    end if;
    result:=result||jsonb_build_object('bullets',shots,'damage',damage-absorbed,'health',hp,'fired',true);
    insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,'police_exchange',result);
    perform game_private.inventory_sync(s,u);
   end if;
  else
   result:=game_private.scav_action_before_operations(p_action,p_payload);if result?'error' or result?'caught' then return result;end if;
   if p_action='move' and v.pursuit is not null then
    update game_private.scav_sessions set arrives_at=departed_at+make_interval(secs=>game_private.scav_route_length(route_points)*(v.pursuit#>>'{rules,scavenging_getaway_seconds_per_block}')::int) where season_id=s and player_id=u;
    perform game_private.street_pursuer(s,u);
   elsif p_action='search' then
    update game_private.scav_sessions set pending=pending||jsonb_build_object('patrol_sentence_minutes',game_private.setting('scavenging_island_sentence_minutes')) where season_id=s and player_id=u and pending is not null and district_id in(select id from public.game_districts where slug='blackwater-island');
   end if;
  end if;
  insert into game_private.street_requests(season_id,player_id,request_id,action,payload,result) values(s,u,nonce,p_action,p_payload,result);
  return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Invalid street operation. Refresh and try again.');when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

revoke all on function game_private.street_garage(uuid,uuid,uuid),game_private.street_model(text),game_private.street_motion_contact(jsonb,jsonb,timestamptz,timestamptz,timestamptz,timestamptz),game_private.street_settle(uuid,uuid,text),game_private.scav_resolve_search_patrol(),game_private.scav_resolve_patrol(),game_private.street_state(),game_private.scav_action_before_operations(text,jsonb),public.scavenging_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.scavenging_action(text,jsonb) to authenticated;
create or replace function game_private.scav_action_before_operations(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;v game_private.scav_sessions;s uuid;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 result:=game_private.scav_resolve_patrol();if result is not null then return result;end if;
 result:=game_private.scav_action_before_patrols(p_action,p_payload);
 if p_action='search' and not(result?'error') then
  select * into v from game_private.scav_sessions where season_id=s and player_id=auth.uid();
  if v.pending is not null and not(v.pending?'patrols') then
   update game_private.scav_sessions set pending=pending||jsonb_build_object('patrols',game_private.scav_patrols(v.district_id),'patrol_sentence_minutes',game_private.setting(case when exists(select 1 from public.game_districts where id=v.district_id and slug='blackwater-island') then 'scavenging_island_sentence_minutes' else 'scavenging_patrol_sentence_minutes' end)) where season_id=s and player_id=auth.uid();
  end if;
  result:=coalesce(game_private.scav_resolve_patrol(),result);
 end if;
 return result;
end$$;

-- Private vehicle collection for property screens; never exposes other players' vehicles.
create function public.street_vehicle_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 return jsonb_build_object('season_id',s,'vehicles',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select c.id,c.name,c.sale_value,c.building_id,p.code,c.created_at,game_private.property_access(s,u,c.building_id,true) garage_active from game_private.street_vehicles c left join public.game_district_plots p on p.id=(select plot_id from public.game_district_buildings where id=c.building_id) where c.season_id=s and c.player_id=u and c.status='stored')x));
end$$;
revoke all on function public.street_vehicle_state() from public,anon,authenticated;
grant execute on function public.street_vehicle_state() to authenticated;
notify pgrst,'reload schema';
