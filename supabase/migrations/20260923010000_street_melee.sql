-- Street melee never accepts client damage, position, armour or cooldown values.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Add close-range street melee and presence',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_melee_enabled',1,0,1),('scavenging_melee_range_percent',5,2,10),
 ('scavenging_melee_seconds',2,1,60),('scavenging_melee_damage_min',4,1,50),('scavenging_melee_damage_max',9,1,50),
 ('scavenging_melee_victim_seconds',3,1,300),('scavenging_melee_presence_seconds',15,5,60),
 ('scavenging_melee_police_health',40,1,1000),('scavenging_melee_police_damage',12,0,100);
alter table game_private.scav_sessions add column street_seen_at timestamptz,add column melee_ready_at timestamptz,add column melee_protected_until timestamptz,add column melee_police jsonb not null default '{}';
create function public.street_combat_state(p_season uuid,p_district uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();v game_private.scav_sessions;t timestamptz:=clock_timestamp();begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if s is distinct from p_season or not game_private.rate('street_contacts',30) then raise exception 'Refresh street contacts.';end if;
 select * into v from game_private.scav_sessions where season_id=s and player_id=u;
 if v.player_id is null or v.district_id is distinct from p_district then raise exception 'Enter this district first.';end if;
 if not game_private.robbery_available(s,u,v.district_id,t) then return jsonb_build_object('players','[]'::jsonb);end if;
 update game_private.scav_sessions set street_seen_at=t where season_id=s and player_id=u;
 return jsonb_build_object('ready_at',v.melee_ready_at,'players',coalesce((select jsonb_agg(q) from (
 select p.id,p.handle,game_private.scav_position(x.route_points,x.departed_at,x.arrives_at,t) position
 from game_private.scav_sessions x join public.game_players p on p.id=x.player_id and p.season_id=s
 where x.season_id=s and x.district_id=v.district_id and x.player_id<>u and x.street_seen_at>t-make_interval(secs=>game_private.setting('scavenging_melee_presence_seconds'))
 and game_private.robbery_available(s,x.player_id,v.district_id,t)
 and game_private.scav_route_length(jsonb_build_array(game_private.scav_position(v.route_points,v.departed_at,v.arrives_at,t),game_private.scav_position(x.route_points,x.departed_at,x.arrives_at,t)))<1
 order by p.id limit 40)q),'[]'::jsonb));
end$$;
alter function public.scavenging_action(text,jsonb) rename to scavenging_action_before_melee;
create function public.scavenging_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.street_requests;v game_private.scav_sessions;victim game_private.scav_sessions;
 t timestamptz;point jsonb;other jsonb;target uuid;patrol jsonb;pid text;rules jsonb;result jsonb;damage integer;absorbed numeric;hp numeric;vit jsonb;police_hp integer;units jsonb;begin
 if p_action is distinct from 'punch' then return public.scavenging_action_before_melee(p_action,p_payload);end if;
 perform game_private.require_active();s:=game_private.season_guard(false);
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 result:=game_private.scav_resolve_patrol();if result is not null then return result;end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh the street.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'Request reference required.';end if;
  select * into prior from game_private.street_requests where season_id=s and player_id=u and request_id=nonce;
  if found then if prior.action<>'punch' or prior.payload is distinct from p_payload then raise exception 'Request reference already used.';end if;return prior.result;end if;
  perform game_private.season_guard();
  if game_private.setting('scavenging_melee_enabled')=0 or not game_private.rate('street_melee',30) then raise exception 'Street fighting is unavailable. Try later.';end if;
  select * into v from game_private.scav_sessions where season_id=s and player_id=u for update;t:=clock_timestamp();
  if v.player_id is null or v.street_seen_at is null or v.street_seen_at<t-make_interval(secs=>game_private.setting('scavenging_melee_presence_seconds')) or not game_private.robbery_available(s,u,v.district_id,t) then raise exception 'Enter the streets before fighting.';end if;
  if exists(select 1 from public.game_districts where id=v.district_id and (archived_at is not null or status='lockdown')) or exists(select 1 from public.game_district_territory where season_id=s and district_id=v.district_id and status='lockdown') or not (select enabled from public.game_bin_rules) then raise exception 'Street actions are closed here.';end if;
  if v.melee_ready_at>t or v.arrives_at>t or v.pursuit->>'vehicle_id' is not null then raise exception 'Stop and recover before punching.';end if;
  vit:=game_private.vitals_state();if (vit->>'health')::numeric<=1 then raise exception 'You are too injured to fight.';end if;
  point:=game_private.scav_position(v.route_points,v.departed_at,v.arrives_at,t);
  if p_payload->>'kind'='player' then
   target:=(p_payload->>'target_id')::uuid;
   select * into victim from game_private.scav_sessions where season_id=s and player_id=target for update;
   if target is null or target=u or victim.player_id is null or victim.district_id<>v.district_id or victim.street_seen_at is null or victim.street_seen_at<t-make_interval(secs=>game_private.setting('scavenging_melee_presence_seconds')) or not game_private.robbery_available(s,target,v.district_id,t) or victim.melee_protected_until>t or victim.pursuit->>'vehicle_id' is not null then raise exception 'That player cannot be punched now.';end if;
   other:=game_private.scav_position(victim.route_points,victim.departed_at,victim.arrives_at,t);
  elsif p_payload->>'kind'='police' then
   pid:=p_payload->>'target_id';units:=coalesce(v.pursuit->'patrols',game_private.scav_patrols(v.district_id));
   select x into patrol from jsonb_array_elements(units)x where x->>'id'=pid;
   if patrol is null then raise exception 'That officer is no longer here.';end if;
   police_hp:=coalesce((v.melee_police->>pid)::integer,game_private.setting('scavenging_melee_police_health'));
   if police_hp<=0 then raise exception 'That officer is already down.';end if;
   other:=game_private.street_patrol_position(patrol,t);
  else raise exception 'Choose a nearby player or officer.';end if;
  if game_private.scav_route_length(jsonb_build_array(point,other))>game_private.setting('scavenging_melee_range_percent')/100.0 or not game_private.foot_clear(point,other,game_private.setting('scavenging_foot_road_half_percent')/100.0) then raise exception 'Move within punching range with a clear path.';end if;
  perform set_config('game.reason','Street punch / '||nonce,true);
  damage:=game_private.setting('scavenging_melee_damage_min')+floor(random()*(greatest(game_private.setting('scavenging_melee_damage_min'),game_private.setting('scavenging_melee_damage_max'))-game_private.setting('scavenging_melee_damage_min')+1));
  if target is not null then
   select health,least(armour,damage) into hp,absorbed from public.game_season_players where season_id=s and player_id=target for update;
   if hp is null or hp<=1 then raise exception 'That player is too injured to fight.';end if;
   -- Nonlethal melee: never deletes an account, takes money, or creates a death state.
   update public.game_season_players set health=greatest(1,health-damage+absorbed),armour=greatest(0,armour-absorbed),health_updated_at=t where season_id=s and player_id=target;
   update game_private.scav_sessions set melee_protected_until=t+make_interval(secs=>game_private.setting('scavenging_melee_victim_seconds')),pending=null where season_id=s and player_id=target;
   result:=jsonb_build_object('message','Punch landed.','hit',true,'damage',least(hp-1,damage-absorbed));
   insert into public.game_events(player_id,description) values(target,'You were punched in the streets by '||(select handle from public.game_players where id=u)||'.');
   insert into game_private.street_history(season_id,player_id,kind,details) values(s,target,'punched',jsonb_build_object('attacker_id',u,'damage',result->'damage'));
  else
   update game_private.scav_sessions set melee_police=jsonb_set(melee_police,array[pid],to_jsonb(greatest(0,police_hp-damage))) where season_id=s and player_id=u;
   select jsonb_object_agg(key,value) into rules from public.game_settings where key like 'scavenging_%';
   if v.pursuit is null then
    update game_private.scav_sessions set pursuit=jsonb_build_object('id',nonce,'kind','foot','search_kind','bin','vehicle_id',null,'vehicle_name','On foot','started_at',t,'checked_at',t,'grace_until',t+make_interval(secs=>(rules->>'scavenging_chase_grace_seconds')::int),'deadline',t+make_interval(secs=>(rules->>'scavenging_chase_seconds')::int),'exit_node',0,'patrols',units,'sentence_minutes',case when exists(select 1 from public.game_districts where id=v.district_id and slug='blackwater-island') then (rules->>'scavenging_island_sentence_minutes')::int else (rules->>'scavenging_patrol_sentence_minutes')::int end,'rules',rules,'next_shot_at',t,'last_seen_point',point,'tracking','chasing') where season_id=s and player_id=u;
   end if;
   absorbed:=least((vit->>'armour')::numeric,game_private.setting('scavenging_melee_police_damage'));hp:=greatest(0,(vit->>'health')::numeric-game_private.setting('scavenging_melee_police_damage')+absorbed);
   update public.game_season_players set health=hp,health_updated_at=t,armour=greatest(0,armour-absorbed) where season_id=s and player_id=u;
   result:=jsonb_build_object('message','Punch landed. Police retaliated and are pursuing you.','hit',true,'damage',least(police_hp,damage),'pursuit',true);
   if hp<=0 then result:=game_private.street_settle(s,u,'caught')||result||jsonb_build_object('caught',true);else perform game_private.street_pursuer(s,u);end if;
  end if;
  update game_private.scav_sessions set pending=null,melee_ready_at=t+make_interval(secs=>game_private.setting('scavenging_melee_seconds')) where season_id=s and player_id=u;
  insert into game_private.street_history(season_id,player_id,kind,details) values(s,u,'punch',result||jsonb_build_object('target',p_payload->>'target_id','target_kind',p_payload->>'kind'));
  insert into game_private.street_requests(season_id,player_id,request_id,action,payload,result) values(s,u,nonce,'punch',p_payload,result);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return jsonb_build_object('error','Invalid punch request.');when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
revoke all on function public.scavenging_action_before_melee(text,jsonb),public.scavenging_action(text,jsonb),public.street_combat_state(uuid,uuid) from public,anon,authenticated;
grant execute on function public.scavenging_action(text,jsonb),public.street_combat_state(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
