-- First-person input leases. The browser sends direction, never a position or travel speed.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce server-authoritative first-person street movement',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_foot_road_half_percent',13,5,20),('scavenging_foot_walk_seconds',10,4,30),('scavenging_foot_sprint_percent',150,100,200),
 ('scavenging_input_lease_ms',500,200,800),('scavenging_input_rate',360,60,1200),('scavenging_interaction_radius_percent',8,3,15);
alter table game_private.scav_sessions add column walk_controller uuid,add column walk_sequence bigint not null default 0;
create function game_private.foot_walkable(p jsonb,width numeric) returns boolean language sql immutable set search_path='' as $$
 select (p->>0)::numeric between 0 and 4 and (p->>1)::numeric between 0 and 2 and (abs((p->>0)::numeric-round((p->>0)::numeric))<=width or abs((p->>1)::numeric-round((p->>1)::numeric))<=width);
$$;
create function game_private.foot_clear(a jsonb,b jsonb,width numeric) returns boolean language plpgsql immutable set search_path='' as $$
declare x integer;y integer;axis integer;lo numeric;hi numeric;miss boolean;minimum numeric;maximum numeric;delta numeric;t0 numeric;t1 numeric;begin
 if not game_private.foot_walkable(a,width) or not game_private.foot_walkable(b,width) then return false;end if;
 for x in 0..3 loop for y in 0..1 loop
  lo:=0;hi:=1;miss:=false;
  for axis in 0..1 loop
   minimum:=(case when axis=0 then x else y end)+width;maximum:=minimum+1-2*width;delta:=(b->>axis)::numeric-(a->>axis)::numeric;
   if abs(delta)<.000000000001 then
    if (a->>axis)::numeric<=minimum or (a->>axis)::numeric>=maximum then miss:=true;exit;end if;
   else t0:=(minimum-(a->>axis)::numeric)/delta;t1:=(maximum-(a->>axis)::numeric)/delta;lo:=greatest(lo,least(t0,t1));hi:=least(hi,greatest(t0,t1));end if;
  end loop;
  if not miss and hi>lo+.000000000001 then return false;end if;
 end loop;end loop;return true;
end$$;
create function game_private.foot_step(origin jsonb,dx double precision,dy double precision,seconds double precision,speed double precision,width numeric) returns jsonb language plpgsql immutable set search_path='' as $$
declare magnitude double precision:=greatest(1,sqrt(dx*dx+dy*dy));distance double precision:=greatest(0,least(.8,seconds))/greatest(1,speed);steps integer;i integer;point jsonb:=origin;x double precision;y double precision;begin
 steps:=greatest(1,ceil(distance/.018));
 for i in 1..steps loop
  x:=greatest(0,least(4,(point->>0)::double precision+dx/magnitude*distance/steps));y:=greatest(0,least(2,(point->>1)::double precision+dy/magnitude*distance/steps));
  if game_private.foot_walkable(jsonb_build_array(x,y),width) then point:=jsonb_build_array(x,y);
  elsif game_private.foot_walkable(jsonb_build_array(x,point->1),width) then point:=jsonb_build_array(x,point->1);
  elsif game_private.foot_walkable(jsonb_build_array(point->0,y),width) then point:=jsonb_build_array(point->0,y);end if;
 end loop;
 if not game_private.foot_clear(origin,point,width) then
  if game_private.foot_clear(origin,jsonb_build_array(point->0,origin->1),width) then point:=jsonb_build_array(point->0,origin->1);else point:=jsonb_build_array(origin->0,point->1);end if;
 end if;return point;
end$$;
alter function game_private.scav_route(jsonb,jsonb) rename to scav_center_route;
create function game_private.scav_route(a jsonb,b jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare width numeric:=game_private.setting('scavenging_foot_road_half_percent')/100.0;pa jsonb;pb jsonb;begin
 if ((a->>0)::numeric=round((a->>0)::numeric) or (a->>1)::numeric=round((a->>1)::numeric)) and ((b->>0)::numeric=round((b->>0)::numeric) or (b->>1)::numeric=round((b->>1)::numeric)) then return game_private.scav_center_route(a,b);end if;
 if game_private.foot_clear(a,b,width) then return jsonb_build_array(a,b);end if;
 pa:=case when abs((a->>0)::numeric-round((a->>0)::numeric))<abs((a->>1)::numeric-round((a->>1)::numeric)) then jsonb_build_array(round((a->>0)::numeric),a->1) else jsonb_build_array(a->0,round((a->>1)::numeric)) end;
 pb:=case when abs((b->>0)::numeric-round((b->>0)::numeric))<abs((b->>1)::numeric-round((b->>1)::numeric)) then jsonb_build_array(round((b->>0)::numeric),b->1) else jsonb_build_array(b->0,round((b->>1)::numeric)) end;
 return jsonb_build_array(a)||game_private.scav_center_route(pa,pb)||jsonb_build_array(b);
end$$;
create function game_private.foot_snapshot(s uuid,u uuid) returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('server_time',clock_timestamp(),'session',to_jsonb(v)-'season_id'-'player_id','patrols',coalesce(v.pursuit->'patrols',game_private.scav_patrols(v.district_id))) from game_private.scav_sessions v where season_id=s and player_id=u;
$$;
create function public.street_motion(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();v game_private.scav_sessions;stamp timestamptz;controller uuid;seq bigint;dx double precision;dy double precision;speed double precision;lease double precision;origin jsonb;goal jsonb;result jsonb;width numeric;begin
 perform game_private.require_active();s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 result:=game_private.scav_resolve_patrol();if result is not null then return case when coalesce((result->>'caught')::boolean,false) then result else game_private.foot_snapshot(s,u)||result end;end if;
 begin
  perform game_private.season_guard();
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh the street controls.';end if;
  if not game_private.rate('street_motion',game_private.setting('scavenging_input_rate')) then raise exception 'Movement updates arrived too quickly.';end if;
  select * into v from game_private.scav_sessions where season_id=s and player_id=u for update;stamp:=clock_timestamp();controller:=(p_payload->>'controller')::uuid;
  if v.player_id is null or controller is null or v.district_id is distinct from (p_payload->>'district_id')::uuid then raise exception 'Enter this district before walking.';end if;
  if not (select enabled from public.game_bin_rules) or exists(select 1 from public.game_districts where id=v.district_id and (archived_at is not null or status='lockdown')) or exists(select 1 from public.game_district_territory where season_id=s and district_id=v.district_id and status='lockdown') then raise exception 'Street exploration is closed here.';end if;
  origin:=game_private.scav_position(v.route_points,v.departed_at,v.arrives_at,stamp);
  if p_action='begin' then
   if v.walk_controller is distinct from controller then
    update game_private.scav_sessions set walk_controller=controller,walk_sequence=0,route_points=jsonb_build_array(origin),departed_at=stamp,arrives_at=stamp where season_id=s and player_id=u;
   end if;
  elsif p_action='step' then
   if v.walk_controller is distinct from controller then raise exception 'Movement control changed in another tab. Re-enter street view.';end if;
   if jsonb_typeof(p_payload->'sequence') is distinct from 'number' or (p_payload->>'sequence')::numeric<>trunc((p_payload->>'sequence')::numeric) then raise exception 'Invalid movement sequence.';end if;
   seq:=(p_payload->>'sequence')::bigint;if seq<=v.walk_sequence then return game_private.foot_snapshot(s,u);end if;
   if jsonb_typeof(p_payload->'dx') is distinct from 'number' or jsonb_typeof(p_payload->'dy') is distinct from 'number' or jsonb_typeof(coalesce(p_payload->'sprint','false')) is distinct from 'boolean' then raise exception 'Invalid walking direction.';end if;
   dx:=(p_payload->>'dx')::double precision;dy:=(p_payload->>'dy')::double precision;
   if not(dx between -1 and 1 and dy between -1 and 1) then raise exception 'Invalid walking direction.';end if;
   if v.pending is not null and (dx<>0 or dy<>0) then
    -- Walking away abandons the unfinished search; already-spent lockpicks remain spent.
    update game_private.scav_sessions set pending=null where season_id=s and player_id=u;
   end if;
   speed:=game_private.setting('scavenging_foot_walk_seconds');
   if coalesce((p_payload->>'sprint')::boolean,false) then speed:=speed*100/game_private.setting('scavenging_foot_sprint_percent');end if;
   if v.pursuit->>'vehicle_id' is not null then speed:=(v.pursuit#>>'{rules,scavenging_getaway_seconds_per_block}')::double precision;end if;
   lease:=game_private.setting('scavenging_input_lease_ms')/1000.0;width:=game_private.setting('scavenging_foot_road_half_percent')/100.0;
   goal:=game_private.foot_step(origin,dx,dy,lease,speed,width);
   update game_private.scav_sessions set walk_sequence=seq,node=round((goal->>1)::numeric)::int*5+round((goal->>0)::numeric)::int,path=jsonb_build_array(round((goal->>1)::numeric)::int*5+round((goal->>0)::numeric)::int),route_points=jsonb_build_array(origin,goal),departed_at=stamp,arrives_at=case when goal=origin then stamp else stamp+make_interval(secs=>lease) end where season_id=s and player_id=u;
   if v.pursuit is not null then perform game_private.street_pursuer(s,u);end if;
  else raise exception 'Unknown street control.';end if;
  return game_private.foot_snapshot(s,u);
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return jsonb_build_object('error','Invalid street control. Refresh and try again.');when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
revoke all on function game_private.foot_walkable(jsonb,numeric),game_private.foot_clear(jsonb,jsonb,numeric),game_private.foot_step(jsonb,double precision,double precision,double precision,double precision,numeric),game_private.scav_center_route(jsonb,jsonb),game_private.scav_route(jsonb,jsonb),game_private.foot_snapshot(uuid,uuid),public.street_motion(text,jsonb) from public,anon,authenticated;
grant execute on function public.street_motion(text,jsonb) to authenticated;
notify pgrst,'reload schema';
