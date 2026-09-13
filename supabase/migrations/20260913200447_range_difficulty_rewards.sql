-- Difficulty snapshots, radial scoring, immutable XP awards and shared recovery.
select pg_advisory_xact_lock(4704001);
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Add range difficulties, completion XP and recovery',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('range_beginner_target_percent',100,75,130),('range_advanced_target_percent',65,40,90),
 ('range_beginner_speed_percent',100,50,150),('range_advanced_speed_percent',250,160,400),
 ('range_beginner_completion_xp',50,1,10000),('range_advanced_completion_xp',150,2,30000),
 ('range_completion_round_percent',100,10,100),('range_cooldown_seconds',600,0,86400);
alter table public.game_range_sessions
 add column difficulty text not null default 'legacy' check(difficulty in ('legacy','beginner','advanced')),
 add column cooldown_until timestamptz,
 add column xp_awarded integer not null default 0 check(xp_awarded>=0);
create index range_sessions_recovery on public.game_range_sessions(player_id,season_id,cooldown_until desc);
create table game_private.range_xp_ledger(
 session_id uuid primary key references public.game_range_sessions(id),
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 xp_before bigint not null,delta integer not null check(delta>0),xp_after bigint not null,
 created_at timestamptz not null default clock_timestamp(),check(xp_after=xp_before+delta)
);
create index range_xp_player on game_private.range_xp_ledger(player_id,season_id);
create index range_xp_season on game_private.range_xp_ledger(season_id);
alter table game_private.range_xp_ledger enable row level security;
revoke all on game_private.range_xp_ledger from public,anon,authenticated;
create trigger range_xp_retain before update or delete or truncate on game_private.range_xp_ledger for each statement execute function game_private.district_immutable();

create function game_private.range_mode_config(mode text) returns jsonb language plpgsql stable set search_path='' as $$
declare c jsonb:=game_private.range_config();scale numeric;speed numeric;reward int;
begin
 if mode not in ('beginner','advanced') or mode is null then raise exception 'Choose Beginner or Advanced.';end if;
 scale:=game_private.setting('range_'||mode||'_target_percent')/100.0;
 speed:=game_private.setting('range_'||mode||'_speed_percent')/100.0;
 reward:=game_private.setting('range_'||mode||'_completion_xp');
 return c||jsonb_build_object('radius_x',(c->>'radius_x')::numeric*scale,'radius_y',(c->>'radius_y')::numeric*scale,
 'move_speed',(c->>'move_speed')::numeric*speed,'completion_xp',reward,'scoring_version',2,
 'required_rounds',ceil((c->>'rounds')::int*game_private.setting('range_completion_round_percent')/100.0)::int);
end$$;

create function game_private.range_score(distance_squared numeric,c jsonb) returns integer language sql immutable set search_path='' as $$
 select case when distance_squared is null or distance_squared<0 or distance_squared>1 then 0
 when coalesce((c->>'scoring_version')::int,1)=1 then case when distance_squared<=power((c->>'bullseye_percent')::numeric/100,2) then (c->>'bullseye_points')::int else (c->>'hit_points')::int end
 else round((c->>'hit_points')::numeric+greatest(0,(c->>'bullseye_points')::numeric-(c->>'hit_points')::numeric)*(1-sqrt(distance_squared)))::int end;
$$;

-- A status transition pays at most once, including expiry during refresh/start.
-- The existing player XP trigger keeps seasonal respect and profile ranks in sync.
create function game_private.range_complete_session() returns trigger language plpgsql security definer set search_path='' as $$
declare before_xp bigint;award int;
begin
 if old.status<>'active' or new.status='active' or old.difficulty='legacy' then return new;end if;
 new.finished_at:=case when new.status='finished' then old.ends_at else least(clock_timestamp(),old.ends_at) end;
 new.cooldown_until:=new.finished_at+make_interval(secs=>(old.config->>'cooldown_seconds')::int);
 if new.status='finished' and clock_timestamp()>=old.ends_at
 and exists(select 1 from public.game_seasons where id=old.season_id and status='open' and (ends_at is null or old.ends_at<=ends_at))
 and (select count(distinct round) from public.game_range_shots where session_id=old.id)>=(old.config->>'required_rounds')::int then
  select xp into before_xp from public.game_players where id=old.player_id and season_id=old.season_id and deleted_at is null for update;
  if found then
   award:=(old.config->>'completion_xp')::int;
   insert into game_private.range_xp_ledger(session_id,season_id,player_id,xp_before,delta,xp_after)
    values(old.id,old.season_id,old.player_id,before_xp,award,before_xp+award) on conflict(session_id) do nothing;
   if found then
    perform set_config('game.reason','Shooting range completion: '||old.id,true);
    update public.game_players set xp=xp+award where id=old.player_id and season_id=old.season_id;
    new.xp_awarded:=award;
    insert into public.game_events(season_id,player_id,description,cash_delta) values(old.season_id,old.player_id,initcap(old.difficulty)||' range completed · +'||award||' XP',0);
   end if;
  end if;
 end if;
 return new;
end$$;
create trigger range_complete_session before update of status on public.game_range_sessions for each row execute function game_private.range_complete_session();

-- Settle completed attempts before season locking/snapshots; stop unfinished ones.
create function game_private.range_close_season() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status='open' and new.status<>'open' then
  perform pg_advisory_xact_lock(4704020);
  update public.game_range_sessions set status=case when ends_at<=clock_timestamp() then 'finished' else 'stopped' end
   where season_id=old.id and status='active';
 end if;
 return new;
end$$;
create trigger range_close_season before update of status on public.game_seasons for each row execute function game_private.range_close_season();
revoke all on function game_private.range_mode_config(text),game_private.range_score(numeric,jsonb),game_private.range_complete_session(),game_private.range_close_season() from public,anon,authenticated;

create or replace function game_private.range_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();t timestamptz:=clock_timestamp();v public.game_range_sessions;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 update public.game_range_sessions set status='finished',finished_at=ends_at where season_id=s and player_id=u and status='active' and ends_at+make_interval(secs=>(config->>'lag_tolerance_ms')::numeric/1000)<t;
 select * into v from public.game_range_sessions where season_id=s and player_id=u order by started_at desc,id limit 1;
 if v.status='active' then
  insert into game_private.range_magazines(weapon_id,season_id,player_id,ammo_id,loaded)
   select v.weapon_id,s,u,a.id,0 from public.game_inventory_gear a where a.season_id=s and a.player_id=u and a.location='equipped' and a.equipment_slot='ammo' and a.good_id=v.weapon_rule->>'ammo_good_id' and a.quantity>0 on conflict(weapon_id) do nothing;
 end if;
 return jsonb_build_object('season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),'server_time',clock_timestamp(),
 'config',game_private.range_config(),
 'difficulties',jsonb_build_array(jsonb_build_object('id','beginner','name','Beginner','config',game_private.range_mode_config('beginner')),jsonb_build_object('id','advanced','name','Advanced','config',game_private.range_mode_config('advanced'))),
 'cooldown_until',(select max(cooldown_until) from public.game_range_sessions where player_id=u and season_id=s),'can_manage',game_private.has_permission('range.manage'),
 'weapons',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'good_id',g.good_id,'name',i.name,'slot',g.equipment_slot,'raw_condition',g.condition,'condition',least(w.condition_max,coalesce(g.condition,w.condition_max)),'condition_max',w.condition_max,'wear_per_shot',w.wear_per_shot,'enabled',coalesce(w.enabled,false),'ammo_good_id',w.ammo_good_id,'ammo_name',a.name,'magazine',game_private.range_magazine_state(g.id,case when v.status='active' and v.weapon_id=g.id then v.weapon_rule else to_jsonb(w) end)) order by g.equipment_slot),'[]') from public.game_inventory_gear g join public.game_goods i on i.id=g.good_id left join public.game_range_weapons w on w.good_id=g.good_id left join public.game_goods a on a.id=w.ammo_good_id where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot in ('primary','secondary') and g.quantity=1),
 'ammo',(select jsonb_build_object('id',g.id,'good_id',g.good_id,'name',i.name,'quantity',g.quantity) from public.game_inventory_gear g join public.game_goods i on i.id=g.good_id where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot='ammo' and g.quantity>0),
 'session',case when v.id is null then null else to_jsonb(v)||jsonb_build_object('participated_rounds',(select count(distinct round) from public.game_range_shots where session_id=v.id),'hit_targets',(select coalesce(jsonb_agg(round::text||':'||lane),'[]') from public.game_range_shots where session_id=v.id and hit),'last_shot',(select jsonb_build_object('id',shot_row.id,'hit',shot_row.hit,'points',shot_row.points,'round',shot_row.round,'lane',shot_row.lane,'x',shot_row.x,'y',shot_row.y,'elapsed_ms',shot_row.elapsed_ms,'created_at',shot_row.created_at) from public.game_range_shots shot_row where shot_row.session_id=v.id order by shot_row.created_at desc,shot_row.id desc limit 1)) end,
 'stats',(select jsonb_build_object('xp_earned',coalesce(sum(xp_awarded),0),'sessions',count(*),'best_score',coalesce(max(score),0),'shots',coalesce(sum(shots),0),'hits',coalesce(sum(hits),0),'best_accuracy',coalesce(max(round(hits*100.0/nullif(shots,0))),0)) from public.game_range_sessions where season_id=s and player_id=u and status<>'active'),
 'recent',(select coalesce(jsonb_agg(x order by x.started_at desc),'[]') from (select id,score,hits,shots,status,started_at,difficulty,xp_awarded from public.game_range_sessions where season_id=s and player_id=u and status<>'active' order by started_at desc limit 5) x),
 'leaders',(select coalesce(jsonb_agg(x order by x.score desc,x.player_id),'[]') from (select p.id as player_id,p.handle as username,game_private.player_avatar(p.id) as avatar_url,max(r.score) as score from public.game_range_sessions r join public.game_players p on p.id=r.player_id where r.season_id=s and p.deleted_at is null and r.shots>0 and (r.status<>'active' or r.ends_at+make_interval(secs=>(r.config->>'lag_tolerance_ms')::numeric/1000)<t) group by p.id order by max(r.score) desc,p.id limit 5) x),
 'management',case when game_private.has_permission('range.manage') then jsonb_build_object('weapons',(select coalesce(jsonb_agg(w order by w.good_id),'[]') from public.game_range_weapons w),'goods',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'equipment_slots',equipment_slots) order by name) from public.game_goods where equipment_slots&&array['primary','secondary','ammo']),'settings',(select jsonb_agg(g order by key) from public.game_settings g where key like 'range\_%' escape '\')) else null end);
end$$;

create or replace function game_private.range_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.range_requests;v public.game_range_sessions;w public.game_range_weapons;gun public.game_inventory_gear;ammo public.game_inventory_gear;c jsonb;t timestamptz;result jsonb;elapsed integer;server_elapsed integer;r integer;l integer;hit_lane integer;x numeric;y numeric;target jsonb;distance numeric;best numeric:=1000000;points integer:=0;hp integer;wear integer;mag game_private.range_magazines;mag_state jsonb;mode text;
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
   insert into game_private.range_magazines(weapon_id,season_id,player_id,ammo_id,loaded) values(gun.id,s,u,ammo.id,least(w.magazine_capacity,ammo.quantity)) on conflict(weapon_id) do nothing;
   mode:=coalesce(p_payload->>'difficulty','beginner');
   if mode not in ('beginner','advanced') then raise exception 'Choose Beginner or Advanced.';end if;
   if exists(select 1 from public.game_range_sessions where player_id=u and season_id=s and cooldown_until>t) then raise exception 'Range cooldown active. Rest before starting either difficulty.';end if;
   c:=game_private.range_mode_config(mode);
   if exists(select 1 from public.game_seasons where id=s and ends_at is not null and t+make_interval(secs=>(c->>'rounds')::int*(c->>'round_seconds')::int)>ends_at) then raise exception 'There is not enough time to complete a session before the season ends.';end if;
   insert into public.game_range_sessions(season_id,player_id,weapon_id,weapon_good_id,equipment_slot,seed,config,weapon_rule,started_at,ends_at,difficulty,cooldown_until)
    values(s,u,gun.id,gun.good_id,gun.equipment_slot,floor(random()*1000000)::int,c,to_jsonb(w),t,t+make_interval(secs=>(c->>'rounds')::int*(c->>'round_seconds')::int),mode,t+make_interval(secs=>(c->>'rounds')::int*(c->>'round_seconds')::int+(c->>'cooldown_seconds')::int)) returning * into v;
   result:=jsonb_build_object('message','Range session started. Every shot uses one bullet.','session_id',v.id);
  elsif p_action in ('fire','finish','reload') then
   select * into v from public.game_range_sessions where id=(p_payload->>'session_id')::uuid and player_id=u and season_id=s for update;
   if not found then raise exception 'This range session is not yours.';end if;
   if p_action='finish' then
    if v.status='active' then update public.game_range_sessions set status=case when t>=ends_at then 'finished' else 'stopped' end,finished_at=least(t,ends_at) where id=v.id;end if;
    select * into v from public.game_range_sessions where id=v.id;
    result:=jsonb_build_object('message',case when v.xp_awarded>0 then 'Session complete. +'||v.xp_awarded||' XP.' when v.status='stopped' then 'Session ended early. No completion XP.' else 'Session recorded. Complete the required rounds to earn XP.' end,'session_id',v.id,'xp_awarded',v.xp_awarded);
   elsif p_action='reload' then
    if game_private.setting('range_enabled')=0 or v.status<>'active' or t>=v.ends_at then raise exception 'Reload during an active range session.';end if;
    select * into gun from public.game_inventory_gear where id=v.weapon_id and player_id=u and season_id=s and location='equipped' and equipment_slot=v.equipment_slot and quantity=1 for update;
    if not found then raise exception 'Your equipped weapon changed. Start a new session.';end if;
    if not exists(select 1 from public.game_range_weapons where good_id=gun.good_id and enabled) or coalesce(gun.condition,(v.weapon_rule->>'condition_max')::int)<=0 then raise exception 'This weapon cannot reload.';end if;
    select * into ammo from public.game_inventory_gear where player_id=u and season_id=s and location='equipped' and equipment_slot='ammo' and good_id=v.weapon_rule->>'ammo_good_id' and quantity>0 for update;
    if not found then raise exception 'Equip compatible ammunition before reloading.';end if;
    insert into game_private.range_magazines(weapon_id,season_id,player_id,ammo_id,loaded) values(gun.id,s,u,ammo.id,0) on conflict(weapon_id) do nothing;
    mag_state:=game_private.range_magazine_state(gun.id,v.weapon_rule);
    select * into mag from game_private.range_magazines where weapon_id=gun.id for update;
    if mag.reload_ready_at>t then raise exception 'Your weapon is already reloading.';end if;
    if (mag_state->>'loaded')::int>=least(ammo.quantity,(v.weapon_rule->>'magazine_capacity')::int) then raise exception 'Your magazine is already full. Equip more bullets if needed.';end if;
    update game_private.range_magazines set ammo_id=ammo.id,loaded=0,reload_capacity=(v.weapon_rule->>'magazine_capacity')::int,reload_started_at=t,reload_ready_at=t+make_interval(secs=>(v.weapon_rule->>'reload_ms')::numeric/1000) where weapon_id=gun.id returning * into mag;
    result:=jsonb_build_object('message','Reloading. Hold your fire.','reload_started_at',mag.reload_started_at,'reload_ready_at',mag.reload_ready_at,'weapon_id',gun.id);
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
    insert into game_private.range_magazines(weapon_id,season_id,player_id,ammo_id,loaded) values(gun.id,s,u,ammo.id,0) on conflict(weapon_id) do nothing;
    mag_state:=game_private.range_magazine_state(gun.id,v.weapon_rule);
    select * into mag from game_private.range_magazines where weapon_id=gun.id for update;
    if mag.reload_ready_at>t then raise exception 'Reloading. Wait for your weapon to be ready.';end if;
    if mag.ammo_id is distinct from ammo.id or coalesce((mag_state->>'loaded')::int,0)<=0 then raise exception 'Magazine empty. Reload your weapon.';end if;
    if mag.fire_ready_at is not null and v.started_at+make_interval(secs=>elapsed::numeric/1000)<mag.fire_ready_at then raise exception 'The shot was aimed before reloading finished.';end if;
    update game_private.range_magazines set loaded=(mag_state->>'loaded')::int-1 where weapon_id=gun.id;
    r:=elapsed/((c->>'round_seconds')::int*1000);
    for l in 0..((c->>'targets_per_round')::int-1) loop
     if exists(select 1 from public.game_range_shots where session_id=v.id and round=r and lane=l and hit) then continue;end if;
     target:=game_private.range_target(v.seed,r,l,elapsed,c);
     distance:=power((x-(target->>'x')::numeric)/(target->>'rx')::numeric,2)+power((y-(target->>'y')::numeric)/(target->>'ry')::numeric,2);
     if distance<=1 and distance<best then best:=distance;hit_lane:=l;end if;
    end loop;
    if hit_lane is not null then points:=game_private.range_score(best,c);end if;
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


create or replace function game_private.range_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
  insert into public.game_range_weapons(good_id,ammo_good_id,condition_max,wear_per_shot,enabled,magazine_capacity,reload_ms)
   values(p_payload->>'good_id',p_payload->>'ammo_good_id',(p_payload->>'condition_max')::int,(p_payload->>'wear_per_shot')::int,(p_payload->>'enabled')::boolean,coalesce((p_payload->>'magazine_capacity')::int,w.magazine_capacity,10),coalesce((p_payload->>'reload_ms')::int,w.reload_ms,1800))
   on conflict(good_id) do update set ammo_good_id=excluded.ammo_good_id,condition_max=excluded.condition_max,wear_per_shot=excluded.wear_per_shot,enabled=excluded.enabled,magazine_capacity=excluded.magazine_capacity,reload_ms=excluded.reload_ms,version=game_range_weapons.version+1;
 elsif p_action='settings' then
  if jsonb_typeof(p_payload->'settings') is distinct from 'object' then raise exception 'Choose range settings.';end if;
  for entry in select * from jsonb_each_text(p_payload->'settings') loop
   k:=entry.key;n:=entry.value::integer;
   if k not like 'range\_%' escape '\' or not exists(select 1 from public.game_settings where key=k and n between minimum and maximum) then raise exception 'Range setting is outside its allowed limits.';end if;
   update public.game_settings set value=n where key=k;
  end loop;
  if game_private.setting('range_bullseye_points')<=game_private.setting('range_hit_points') then raise exception 'Bullseye points must exceed outer hit points.';end if;
  if game_private.setting('range_advanced_target_percent')>=game_private.setting('range_beginner_target_percent') or game_private.setting('range_advanced_completion_xp')<=game_private.setting('range_beginner_completion_xp') then raise exception 'Advanced needs smaller targets and more completion XP than Beginner.';end if;
 else raise exception 'Unknown range control.';end if;
 return jsonb_build_object('message','Range controls saved and audited. Active sessions retain their starting settings.','state',game_private.range_state());
end$$;

notify pgrst,'reload schema';
