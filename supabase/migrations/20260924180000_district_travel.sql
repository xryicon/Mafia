-- Persistent district location, timed travel and per-vehicle fuel.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce district travel and personal dashboard heat',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('travel_enabled',1,0,1),('travel_walk_seconds',120,1,86400),('travel_train_seconds',45,1,86400),('travel_drive_seconds',20,1,86400),
 ('travel_train_fare',50,0,1000000),('travel_drive_fuel',5,1,100),('travel_fuel_price',10,1,1000000);
alter table game_private.street_vehicles add column fuel integer not null default 0 check(fuel between 0 and 100);
create table game_private.district_travel(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),destination_id uuid references public.game_districts(id),
 method text check(method in('walk','train','drive')),vehicle_id uuid references game_private.street_vehicles(id),departed_at timestamptz,arrives_at timestamptz,
 primary key(season_id,player_id),check((destination_id is null)=(arrives_at is null)));
create table game_private.travel_requests(season_id uuid not null,player_id uuid not null,request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,primary key(season_id,player_id,request_id));
alter table game_private.district_travel enable row level security;alter table game_private.travel_requests enable row level security;
revoke all on game_private.district_travel,game_private.travel_requests from public,anon,authenticated;
create trigger district_travel_audit after insert or update on game_private.district_travel for each row execute function game_private.audit_change();
create trigger travel_requests_retain before update or delete or truncate on game_private.travel_requests for each statement execute function game_private.district_immutable();
create function game_private.travel_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();loc game_private.district_travel;d uuid;jailed boolean;
begin
 perform game_private.require_active();perform pg_advisory_xact_lock(4704020);s:=game_private.season_guard(false);
 perform 1 from public.game_players where id=u for update;
 select district_id into d from game_private.scav_sessions where season_id=s and player_id=u;
 if d is null then select id into d from public.game_districts where slug='the-waterfront';end if;
 insert into game_private.district_travel(season_id,player_id,district_id) values(s,u,d) on conflict do nothing;
 select * into loc from game_private.district_travel where season_id=s and player_id=u for update;
 jailed:=coalesce((game_private.prison_state()->>'jailed')::boolean,false);
 if jailed then
  select id into d from public.game_districts where slug='blackwater-island';
  update game_private.district_travel set district_id=d,destination_id=null,arrives_at=null where season_id=s and player_id=u returning * into loc;
 elsif loc.arrives_at<=clock_timestamp() then
  update game_private.district_travel set district_id=destination_id,destination_id=null,arrives_at=null where season_id=s and player_id=u returning * into loc;
 end if;
 return jsonb_build_object('season_id',s,'enabled',game_private.setting('travel_enabled')=1,'jailed',jailed,'server_time',clock_timestamp(),
 'current',(select jsonb_build_object('id',id,'slug',slug,'name',name) from public.game_districts where id=loc.district_id),
 'heat',game_private.scav_risk(s,u,loc.district_id)->'heat',
 'journey',case when loc.destination_id is not null then (select jsonb_build_object('id',id,'slug',slug,'name',name,'method',loc.method,'arrives_at',loc.arrives_at,'departed_at',loc.departed_at) from public.game_districts where id=loc.destination_id) end,
 'districts',(select jsonb_agg(jsonb_build_object('id',id,'slug',slug,'name',name,'status',status) order by name) from public.game_districts where archived_at is null),
 'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'fuel',fuel) order by created_at),'[]') from game_private.street_vehicles where season_id=s and player_id=u and status='stored'),
 'options',jsonb_build_object('walk_seconds',game_private.setting('travel_walk_seconds'),'train_seconds',game_private.setting('travel_train_seconds'),'drive_seconds',game_private.setting('travel_drive_seconds'),'train_fare',game_private.setting('travel_train_fare'),'drive_fuel',game_private.setting('travel_drive_fuel'),'fuel_price',game_private.setting('travel_fuel_price')));
end$$;
create function public.travel_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.travel_state()$$;
create function public.travel_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;old game_private.travel_requests;state jsonb;loc game_private.district_travel;d public.game_districts;v game_private.street_vehicles;mode text;seconds integer;cost bigint:=0;units integer;result jsonb;
begin
 perform game_private.require_active();perform pg_advisory_xact_lock(4704020);s:=game_private.season_guard();
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid travel request.';end if;nonce:=(p_payload->>'request_id')::uuid;
 if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh your travel options.';end if;
 select * into old from game_private.travel_requests where season_id=s and player_id=u and request_id=nonce;
 if found then if old.action<>p_action or old.payload<>p_payload then raise exception 'Travel reference already used.';end if;return old.result;end if;
 if not game_private.rate('district_travel',30) then raise exception 'Please wait before another travel request.';end if;
 state:=game_private.travel_state();
 if (state->>'jailed')::boolean then raise exception 'You must be released before travelling.';end if;
 select * into loc from game_private.district_travel where season_id=s and player_id=u for update;
 if loc.destination_id is not null then raise exception 'Finish your current journey first.';end if;
 if exists(select 1 from game_private.scav_sessions where season_id=s and player_id=u and (pending is not null or pursuit is not null or arrives_at>clock_timestamp())) then raise exception 'Finish your street action or escape the police before travelling.';end if;
 if p_action='refuel' then
  units:=(p_payload->>'units')::integer;
  select * into v from game_private.street_vehicles where id=(p_payload->>'vehicle_id')::uuid and season_id=s and player_id=u and status='stored' for update;
  if not found or units is null or units<1 or units>100 or v.fuel+units>100 then raise exception 'Choose an owned car and fuel amount that fits its 100-unit tank.';end if;
  cost:=units*game_private.setting('travel_fuel_price');perform game_private.district_wallet(u,-cost,'Vehicle refuel: '||nonce);
  update game_private.street_vehicles set fuel=fuel+units where id=v.id;
  result:=jsonb_build_object('message','Vehicle refuelled.','cost',cost);
 elsif p_action='start' then
  if game_private.setting('travel_enabled')<>1 then raise exception 'Travel is currently unavailable.';end if;
  select * into d from public.game_districts where id=(p_payload->>'district_id')::uuid and archived_at is null;
  if not found or d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') then raise exception 'Choose an open district.';end if;
  if d.id=loc.district_id then raise exception 'You are already in this district.';end if;
  mode:=p_payload->>'method';
  if mode='walk' then seconds:=game_private.setting('travel_walk_seconds');
  elsif mode='train' then seconds:=game_private.setting('travel_train_seconds');cost:=game_private.setting('travel_train_fare');
  elsif mode='drive' then
   seconds:=game_private.setting('travel_drive_seconds');units:=game_private.setting('travel_drive_fuel');
   select * into v from game_private.street_vehicles where id=(p_payload->>'vehicle_id')::uuid and season_id=s and player_id=u and status='stored' for update;
   if not found or v.fuel<units then raise exception 'Choose your own stored car with enough fuel.';end if;
   update game_private.street_vehicles set fuel=fuel-units where id=v.id;
  else raise exception 'Choose walking, train or driving.';end if;
  if cost>0 then perform game_private.district_wallet(u,-cost,'Train fare: '||nonce);end if;
  update game_private.district_travel set destination_id=d.id,method=mode,vehicle_id=v.id,departed_at=clock_timestamp(),arrives_at=clock_timestamp()+make_interval(secs=>seconds) where season_id=s and player_id=u;
  result:=jsonb_build_object('message','Journey started.','cost',cost,'fuel',case when mode='drive' then units else 0 end);
 else raise exception 'Unknown travel action.';end if;
 insert into game_private.travel_requests values(s,u,nonce,p_action,p_payload,result);return result;
exception when raise_exception then return jsonb_build_object('error',SQLERRM);when invalid_text_representation or numeric_value_out_of_range then return jsonb_build_object('error','Check your travel choices.');
end$$;
-- Scavenging entry is checked on the server, including direct requests.
alter function public.scavenging_action(text,jsonb) rename to scavenging_action_before_travel;
create function public.scavenging_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare state jsonb;target uuid;
begin
 if game_private.setting('travel_enabled')=1 and p_action<>'vehicle_model' then
  perform pg_advisory_xact_lock(4704020);state:=game_private.travel_state();
  if state->'journey'<>'null'::jsonb then return jsonb_build_object('error','You are travelling. Wait until you arrive.');end if;
  if p_action='enter' then target:=(p_payload->>'district_id')::uuid;
  elsif p_action<>'sell_vehicle' then select district_id into target from game_private.scav_sessions where season_id=(state->>'season_id')::uuid and player_id=auth.uid();end if;
  if target is not null and target is distinct from (state#>>'{current,id}')::uuid then return jsonb_build_object('error','Travel to this district before entering the streets.');end if;
 end if;
 return public.scavenging_action_before_travel(p_action,p_payload);
end$$;
revoke all on function game_private.travel_state(),public.travel_state(),public.travel_action(text,jsonb),public.scavenging_action_before_travel(text,jsonb),public.scavenging_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.travel_state(),public.travel_state(),public.travel_action(text,jsonb),public.scavenging_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';

-- A previously open first-person tab cannot move in the old district during travel.
alter function public.street_motion(text,jsonb) rename to street_motion_before_travel;
create function public.street_motion(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare state jsonb;begin
 if game_private.setting('travel_enabled')=1 then
  perform pg_advisory_xact_lock(4704020);state:=game_private.travel_state();
  if state->'journey'<>'null'::jsonb or (p_payload->>'district_id')::uuid is distinct from (state#>>'{current,id}')::uuid then return jsonb_build_object('error','Arrive in this district before moving through its streets.');end if;
 end if;
 return public.street_motion_before_travel(p_action,p_payload);
end$$;
revoke all on function public.street_motion_before_travel(text,jsonb),public.street_motion(text,jsonb) from public,anon,authenticated;
grant execute on function public.street_motion(text,jsonb) to authenticated;
