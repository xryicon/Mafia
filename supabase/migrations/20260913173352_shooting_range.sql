-- Shooting practice consumes equipped ammunition and preserves weapon wear.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce the Blackwater shooting range',true);
insert into public.game_permissions(id,owner_only) values('range.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('range_enabled',1,0,1),('range_rounds',10,1,30),('range_round_seconds',5,2,60),('range_targets_per_round',3,1,3),('range_move_vertical',8,0,15),('range_bullseye_percent',42,10,80),
 ('range_move_amplitude',10,0,12),('range_move_speed',100,10,300),('range_radius_x',4,2,7),('range_radius_y',8,4,12),
 ('range_hit_points',50,1,10000),('range_bullseye_points',100,1,10000),
 ('range_fire_interval_ms',500,200,5000),('range_lag_tolerance_ms',1000,100,2000),('range_actions_per_minute',180,10,600);
create table public.game_range_weapons(
 good_id text primary key references public.game_goods(id),ammo_good_id text not null references public.game_goods(id),
 condition_max integer not null check(condition_max between 1 and 10000),wear_per_shot integer not null check(wear_per_shot between 1 and 10000),
 enabled boolean not null default true,version integer not null default 1
);
insert into public.game_range_weapons(good_id,ammo_good_id,condition_max,wear_per_shot) values('homemade-pistol','homemade-bullets',100,1);
create index range_weapon_ammo on public.game_range_weapons(ammo_good_id);
create table public.game_range_sessions(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 weapon_id uuid not null references public.game_inventory_gear(id),weapon_good_id text not null references public.game_goods(id),equipment_slot text not null check(equipment_slot in ('primary','secondary')),
 seed integer not null,config jsonb not null,weapon_rule jsonb not null,
 started_at timestamptz not null,ends_at timestamptz not null,finished_at timestamptz,
 status text not null default 'active' check(status in ('active','finished','stopped')),
 shots integer not null default 0 check(shots>=0),hits integer not null default 0 check(hits between 0 and shots),score integer not null default 0 check(score>=0),
 streak integer not null default 0,best_streak integer not null default 0,last_shot_at timestamptz,last_elapsed_ms integer not null default -1
);
create index range_sessions_player on public.game_range_sessions(player_id,season_id,started_at desc);
create index range_sessions_scores on public.game_range_sessions(season_id,score desc) where status<>'active';
create unique index range_one_active_session on public.game_range_sessions(season_id,player_id) where status='active';
create index range_sessions_weapon on public.game_range_sessions(weapon_id);
create index range_sessions_good on public.game_range_sessions(weapon_good_id);
create table public.game_range_shots(
 id uuid primary key default gen_random_uuid(),session_id uuid not null references public.game_range_sessions(id),season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),request_id uuid not null,weapon_id uuid not null references public.game_inventory_gear(id),ammo_id uuid not null references public.game_inventory_gear(id),
 elapsed_ms integer not null,x numeric not null,y numeric not null,round integer not null,lane integer,hit boolean not null,points integer not null,
 condition_before integer not null,condition_after integer not null,ammo_before integer not null,ammo_after integer not null,
 created_at timestamptz not null default clock_timestamp(),unique(season_id,player_id,request_id),
 check(condition_after>=0 and condition_after<condition_before),check(ammo_after=ammo_before-1 and ammo_after>=0)
);
create index range_shots_session on public.game_range_shots(session_id,created_at desc);
create index range_shots_player on public.game_range_shots(player_id,season_id);
create index range_shots_weapon on public.game_range_shots(weapon_id);
create index range_shots_ammo on public.game_range_shots(ammo_id);
create table game_private.range_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),request_id uuid not null,
 action text not null,payload jsonb not null,result jsonb not null,primary key(season_id,player_id,request_id)
);
create index range_requests_player on game_private.range_requests(player_id);
alter table public.game_range_weapons enable row level security;
alter table public.game_range_sessions enable row level security;
alter table public.game_range_shots enable row level security;
alter table game_private.range_requests enable row level security;
revoke all on public.game_range_weapons,public.game_range_sessions,public.game_range_shots,game_private.range_requests from public,anon,authenticated;
create trigger range_rules_audit after insert or update or delete on public.game_range_weapons for each row execute function game_private.audit_change();
create trigger range_sessions_retain before delete or truncate on public.game_range_sessions for each statement execute function game_private.district_immutable();
create trigger range_shots_retain before update or delete or truncate on public.game_range_shots for each statement execute function game_private.district_immutable();
create trigger range_requests_retain before update or delete or truncate on game_private.range_requests for each statement execute function game_private.district_immutable();

-- The same deterministic movement is rendered in the client; hit scoring is performed here.
create function game_private.range_target(seed integer,r integer,l integer,elapsed_ms integer,c jsonb) returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('x',50+(l-((c->>'targets_per_round')::int-1)/2.0)*case when (c->>'targets_per_round')::int=2 then 40 else 30 end+(c->>'move_amplitude')::numeric*sin((elapsed_ms%((c->>'round_seconds')::int*1000))/1000.0*(c->>'move_speed')::numeric/100+((seed+r*53+l*137)%628)/100.0),
 'y',45+(c->>'move_vertical')::numeric*sin((elapsed_ms%((c->>'round_seconds')::int*1000))/1000.0*(c->>'move_speed')::numeric/100*0.7+((seed+r*53+l*137)%628)/100.0),
 'rx',(c->>'radius_x')::numeric,'ry',(c->>'radius_y')::numeric);
$$;
create function game_private.range_config() returns jsonb language sql stable set search_path='' as $$
 select jsonb_object_agg(substring(key from 7),value) from public.game_settings where key like 'range\_%' escape '\';
$$;

create function game_private.range_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();t timestamptz:=clock_timestamp();v public.game_range_sessions;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 update public.game_range_sessions set status='finished',finished_at=ends_at where season_id=s and player_id=u and status='active' and ends_at+make_interval(secs=>(config->>'lag_tolerance_ms')::numeric/1000)<t;
 select * into v from public.game_range_sessions where season_id=s and player_id=u order by started_at desc,id limit 1;
 return jsonb_build_object('season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),'server_time',clock_timestamp(),
 'config',game_private.range_config(),'can_manage',game_private.has_permission('range.manage'),
 'weapons',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'good_id',g.good_id,'name',i.name,'slot',g.equipment_slot,'raw_condition',g.condition,'condition',least(w.condition_max,coalesce(g.condition,w.condition_max)),'condition_max',w.condition_max,'wear_per_shot',w.wear_per_shot,'enabled',coalesce(w.enabled,false),'ammo_good_id',w.ammo_good_id,'ammo_name',a.name) order by g.equipment_slot),'[]') from public.game_inventory_gear g join public.game_goods i on i.id=g.good_id left join public.game_range_weapons w on w.good_id=g.good_id left join public.game_goods a on a.id=w.ammo_good_id where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot in ('primary','secondary') and g.quantity=1),
 'ammo',(select jsonb_build_object('id',g.id,'good_id',g.good_id,'name',i.name,'quantity',g.quantity) from public.game_inventory_gear g join public.game_goods i on i.id=g.good_id where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot='ammo' and g.quantity>0),
 'session',case when v.id is null then null else to_jsonb(v)||jsonb_build_object('hit_targets',(select coalesce(jsonb_agg(round::text||':'||lane),'[]') from public.game_range_shots where session_id=v.id and hit),'last_shot',(select to_jsonb(x) from public.game_range_shots x where session_id=v.id order by created_at desc,id limit 1)) end,
 'stats',(select jsonb_build_object('sessions',count(*),'best_score',coalesce(max(score),0),'shots',coalesce(sum(shots),0),'hits',coalesce(sum(hits),0),'best_accuracy',coalesce(max(round(hits*100.0/nullif(shots,0))),0)) from public.game_range_sessions where season_id=s and player_id=u and status<>'active'),
 'recent',(select coalesce(jsonb_agg(x order by x.started_at desc),'[]') from (select id,score,hits,shots,status,started_at from public.game_range_sessions where season_id=s and player_id=u and status<>'active' order by started_at desc limit 5) x),
 'leaders',(select coalesce(jsonb_agg(x order by x.score desc,x.player_id),'[]') from (select p.id as player_id,p.handle as username,game_private.player_avatar(p.id) as avatar_url,max(r.score) as score from public.game_range_sessions r join public.game_players p on p.id=r.player_id where r.season_id=s and p.deleted_at is null and r.shots>0 and (r.status<>'active' or r.ends_at+make_interval(secs=>(r.config->>'lag_tolerance_ms')::numeric/1000)<t) group by p.id order by max(r.score) desc,p.id limit 5) x),
 'management',case when game_private.has_permission('range.manage') then jsonb_build_object('weapons',(select coalesce(jsonb_agg(w order by w.good_id),'[]') from public.game_range_weapons w),'goods',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'equipment_slots',equipment_slots) order by name) from public.game_goods where equipment_slots&&array['primary','secondary','ammo']),'settings',(select jsonb_agg(g order by key) from public.game_settings g where key like 'range\_%' escape '\')) else null end);
end$$;

create function game_private.range_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.range_requests;v public.game_range_sessions;w public.game_range_weapons;gun public.game_inventory_gear;ammo public.game_inventory_gear;c jsonb;t timestamptz;result jsonb;elapsed integer;server_elapsed integer;r integer;l integer;hit_lane integer;x numeric;y numeric;target jsonb;distance numeric;best numeric:=1000000;points integer:=0;hp integer;wear integer;
begin
 perform game_private.require_active();
 if not game_private.rate('shooting_range',game_private.setting('range_actions_per_minute')) then return jsonb_build_object('error','The range is busy. Try again shortly.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid range request.';end if;
  s:=game_private.season_guard(false);if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the range.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A shot reference is required.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.range_requests where season_id=s and player_id=u and request_id=nonce;
  if found then if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This reference was already used.';end if;return prior.result||jsonb_build_object('state',game_private.range_state());end if;
  if p_action<>'finish' then perform game_private.season_guard();end if;
  perform 1 from public.game_players where id=u and season_id=s for update;if not found then raise exception 'Open your dashboard to initialize this season.';end if;
  t:=clock_timestamp();
  perform set_config('game.inventory_request',nonce::text,true);perform set_config('game.reason','Shooting range: '||p_action,true);
  if p_action='start' then
   if game_private.setting('range_enabled')=0 then raise exception 'The shooting range is closed.';end if;
   update public.game_range_sessions set status='finished',finished_at=ends_at where player_id=u and season_id=s and status='active' and ends_at<=t;
   if exists(select 1 from public.game_range_sessions where player_id=u and season_id=s and status='active') then raise exception 'Finish your current range session first.';end if;
   select * into gun from public.game_inventory_gear where player_id=u and season_id=s and location='equipped' and equipment_slot=p_payload->>'equipment_slot' and equipment_slot in ('primary','secondary') and quantity=1 for update;
   if not found then raise exception 'Equip a weapon in Inventory first.';end if;
   select * into w from public.game_range_weapons where good_id=gun.good_id and enabled;
   if not found then raise exception 'This weapon is not available for range practice.';end if;
   if coalesce(gun.condition,w.condition_max)<=0 then raise exception 'Your weapon is broken. Equip another weapon.';end if;
   select * into ammo from public.game_inventory_gear where player_id=u and season_id=s and location='equipped' and equipment_slot='ammo' and good_id=w.ammo_good_id and quantity>0 for update;
   if not found then raise exception 'Equip compatible bullets in Inventory first.';end if;
   c:=game_private.range_config();
   insert into public.game_range_sessions(season_id,player_id,weapon_id,weapon_good_id,equipment_slot,seed,config,weapon_rule,started_at,ends_at)
    values(s,u,gun.id,gun.good_id,gun.equipment_slot,floor(random()*1000000)::int,c,to_jsonb(w),t,t+make_interval(secs=>(c->>'rounds')::int*(c->>'round_seconds')::int)) returning * into v;
   result:=jsonb_build_object('message','Range session started. Every shot uses one bullet.','session_id',v.id);
  elsif p_action in ('fire','finish') then
   select * into v from public.game_range_sessions where id=(p_payload->>'session_id')::uuid and player_id=u and season_id=s for update;
   if not found then raise exception 'This range session is not yours.';end if;
   if p_action='finish' then
    if v.status='active' then update public.game_range_sessions set status=case when t>=ends_at then 'finished' else 'stopped' end,finished_at=least(t,ends_at) where id=v.id;end if;
    result:=jsonb_build_object('message','Session recorded.','session_id',v.id);
   else
    if game_private.setting('range_enabled')=0 or v.status<>'active' then raise exception 'This range session is no longer active.';end if;
    c:=v.config;server_elapsed:=floor(extract(epoch from(t-v.started_at))*1000)::int;
    elapsed:=(p_payload->>'elapsed_ms')::int;x:=(p_payload->>'x')::numeric;y:=(p_payload->>'y')::numeric;
    if jsonb_typeof(p_payload->'elapsed_ms') is distinct from 'number' or (p_payload->>'elapsed_ms')::numeric is distinct from elapsed::numeric or elapsed is null or elapsed<0 or elapsed<server_elapsed-(c->>'lag_tolerance_ms')::int or elapsed>server_elapsed+100 or elapsed<=v.last_elapsed_ms or elapsed>=(c->>'rounds')::int*(c->>'round_seconds')::int*1000 then raise exception 'Shot timing expired. Refresh the range clock and try again.';end if;
    if jsonb_typeof(p_payload->'x') is distinct from 'number' or jsonb_typeof(p_payload->'y') is distinct from 'number' or x is null or y is null or x not between 0 and 100 or y not between 0 and 100 then raise exception 'Aim inside the shooting lane.';end if;
    if v.last_shot_at is not null and extract(epoch from(t-v.last_shot_at))*1000<(c->>'fire_interval_ms')::int then raise exception 'Let your weapon settle before firing again.';end if;
    select * into gun from public.game_inventory_gear where id=v.weapon_id and player_id=u and season_id=s and location='equipped' and equipment_slot=v.equipment_slot and quantity=1 for update;
    if not found then raise exception 'Your equipped weapon changed. End this session and start again.';end if;
    if not exists(select 1 from public.game_range_weapons where good_id=gun.good_id and enabled) then raise exception 'This weapon has been disabled for range practice.';end if;
    hp:=least((v.weapon_rule->>'condition_max')::int,coalesce(gun.condition,(v.weapon_rule->>'condition_max')::int));wear:=(v.weapon_rule->>'wear_per_shot')::int;
    if hp<=0 then raise exception 'Your weapon is broken. End the session and equip another weapon.';end if;
    select * into ammo from public.game_inventory_gear where player_id=u and season_id=s and location='equipped' and equipment_slot='ammo' and good_id=v.weapon_rule->>'ammo_good_id' and quantity>0 for update;
    if not found then raise exception 'No compatible bullets equipped. End the session and equip ammunition.';end if;
    r:=elapsed/((c->>'round_seconds')::int*1000);
    for l in 0..((c->>'targets_per_round')::int-1) loop
     if exists(select 1 from public.game_range_shots where session_id=v.id and round=r and lane=l and hit) then continue;end if;
     target:=game_private.range_target(v.seed,r,l,elapsed,c);
     distance:=power((x-(target->>'x')::numeric)/(target->>'rx')::numeric,2)+power((y-(target->>'y')::numeric)/(target->>'ry')::numeric,2);
     if distance<=1 and distance<best then best:=distance;hit_lane:=l;end if;
    end loop;
    if hit_lane is not null then points:=case when best<=power((c->>'bullseye_percent')::numeric/100,2) then (c->>'bullseye_points')::int else (c->>'hit_points')::int end;end if;
    update public.game_inventory_gear set condition=greatest(0,hp-wear) where id=gun.id;
    if ammo.quantity=1 then update public.game_inventory_gear set quantity=0,location='retired',equipment_slot=null where id=ammo.id;
    else update public.game_inventory_gear set quantity=quantity-1 where id=ammo.id;end if;
    insert into public.game_range_shots(session_id,season_id,player_id,request_id,weapon_id,ammo_id,elapsed_ms,x,y,round,lane,hit,points,condition_before,condition_after,ammo_before,ammo_after)
     values(v.id,s,u,nonce,gun.id,ammo.id,elapsed,x,y,r,hit_lane,hit_lane is not null,points,hp,greatest(0,hp-wear),ammo.quantity,ammo.quantity-1);
    update public.game_range_sessions set shots=shots+1,hits=hits+case when hit_lane is null then 0 else 1 end,score=score+points,streak=case when hit_lane is null then 0 else streak+1 end,best_streak=greatest(best_streak,case when hit_lane is null then 0 else streak+1 end),last_shot_at=t,last_elapsed_ms=elapsed where id=v.id;
    result:=jsonb_build_object('message',case when hit_lane is null then 'Miss.' when best<=power((c->>'bullseye_percent')::numeric/100,2) then 'Bullseye.' else 'Target hit.' end,'hit',hit_lane is not null,'points',points,'lane',hit_lane,'round',r,'x',x,'y',y);
   end if;
  else raise exception 'Unknown range action.';end if;
  insert into game_private.range_requests values(s,u,nonce,p_action,p_payload,result);return result||jsonb_build_object('state',game_private.range_state());
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check your range selection and try again.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

create function game_private.range_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare w public.game_range_weapons;k text;n integer;entry record;
begin
 perform game_private.require_active();if not game_private.has_permission('range.manage') then raise exception 'Range management permission required.';end if;
 perform pg_advisory_xact_lock(4704020);
 if jsonb_typeof(p_payload) is distinct from 'object' or length(p_payload::text)>8192 or length(trim(coalesce(p_payload->>'reason','')))<5 then raise exception 'Provide an audit reason.';end if;
 perform set_config('game.reason','Shooting range controls: '||left(trim(p_payload->>'reason'),500),true);
 if p_action='weapon' then
  if not exists(select 1 from public.game_goods where id=p_payload->>'good_id' and equipment_slots&&array['primary','secondary']) then raise exception 'Choose a weapon with a primary or secondary slot.';end if;
  if not exists(select 1 from public.game_goods where id=p_payload->>'ammo_good_id' and 'ammo'=any(equipment_slots)) then raise exception 'Choose compatible ammunition.';end if;
  select * into w from public.game_range_weapons where good_id=p_payload->>'good_id' for update;
  if coalesce(w.version,0) is distinct from (p_payload->>'version')::int then raise exception 'Weapon rules changed. Refresh these controls.';end if;
  insert into public.game_range_weapons(good_id,ammo_good_id,condition_max,wear_per_shot,enabled)
   values(p_payload->>'good_id',p_payload->>'ammo_good_id',(p_payload->>'condition_max')::int,(p_payload->>'wear_per_shot')::int,(p_payload->>'enabled')::boolean)
   on conflict(good_id) do update set ammo_good_id=excluded.ammo_good_id,condition_max=excluded.condition_max,wear_per_shot=excluded.wear_per_shot,enabled=excluded.enabled,version=game_range_weapons.version+1;
 elsif p_action='settings' then
  if jsonb_typeof(p_payload->'settings') is distinct from 'object' then raise exception 'Choose range settings.';end if;
  for entry in select * from jsonb_each_text(p_payload->'settings') loop
   k:=entry.key;n:=entry.value::integer;
   if k not like 'range\_%' escape '\' or not exists(select 1 from public.game_settings where key=k and n between minimum and maximum) then raise exception 'Range setting is outside its allowed limits.';end if;
   update public.game_settings set value=n where key=k;
  end loop;
 else raise exception 'Unknown range control.';end if;
 return jsonb_build_object('message','Range controls saved and audited. Active sessions retain their starting settings.','state',game_private.range_state());
end$$;
create function public.range_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.range_state()$$;
create function public.range_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.range_action(p_action,p_payload)$$;
create function public.range_manage(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.range_manage(p_action,p_payload)$$;
revoke all on function game_private.range_target(integer,integer,integer,integer,jsonb),game_private.range_config(),game_private.range_state(),game_private.range_action(text,jsonb),game_private.range_manage(text,jsonb),public.range_state(),public.range_action(text,jsonb),public.range_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.range_state(),game_private.range_action(text,jsonb),game_private.range_manage(text,jsonb),public.range_state(),public.range_action(text,jsonb),public.range_manage(text,jsonb) to authenticated;
notify pgrst,'reload schema';
