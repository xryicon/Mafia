-- Street operations: configured risk/reward, seasonal vehicle records and private event state.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce street operations and high-risk prison island',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_island_cash_multiplier',3,1,10),('scavenging_island_patrol_count',4,1,4),('scavenging_island_patrol_speed',4,2,60),('scavenging_island_patrol_radius',32,5,50),('scavenging_island_sentence_minutes',12,1,10080),
 ('scavenging_theft_seconds',10,1,120),('scavenging_theft_success_percent',55,0,100),('scavenging_theft_xp',60,0,10000),
 ('scavenging_pursuer_seconds_per_block',3,1,10),('scavenging_island_pursuer_speed',2,1,10),('scavenging_pursuer_radius',18,5,50),('scavenging_chase_seconds',50,15,180),('scavenging_chase_grace_seconds',4,1,10),('scavenging_getaway_seconds_per_block',2,1,10),('scavenging_escape_min_seconds',6,1,15),
 ('scavenging_garage_vehicle_slots',2,1,20),('scavenging_event_interval_seconds',600,60,86400),('scavenging_event_chance',65,0,100),('scavenging_event_cash_multiplier',2,1,10),
 ('scavenging_combat_bullets',3,1,100),('scavenging_combat_escape_percent',45,0,100),('scavenging_combat_damage_min',15,1,100),('scavenging_combat_damage_max',45,1,100),('scavenging_combat_seconds',5,1,60);
update public.game_settings set value=greatest(value,3) where key='scavenging_patrol_count';
create table game_private.street_vehicle_models(id text primary key,name text not null,sale_value bigint not null check(sale_value between 1 and 100000000),enabled boolean not null default true,version integer not null default 1);
insert into game_private.street_vehicle_models(id,name,sale_value) values('coupe','Raven Coupe',1500),('sedan','Dockside Sedan',2200),('van','Ironworks Delivery Van',3500);
create trigger street_models_audit after insert or update or delete on game_private.street_vehicle_models for each row execute function game_private.audit_change();
create table game_private.street_vehicles(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),district_id uuid not null references public.game_districts(id),model_id text not null references game_private.street_vehicle_models(id),name text not null,sale_value bigint not null check(sale_value>0),status text not null check(status in('escaping','stored','sold','seized','abandoned')),building_id uuid references public.game_district_buildings(id),source_id uuid not null unique,created_at timestamptz not null default clock_timestamp());
create index street_vehicles_owner on game_private.street_vehicles(season_id,player_id,status);
create index street_vehicles_garage on game_private.street_vehicles(building_id,status);
create table game_private.street_events(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),district_id uuid not null references public.game_districts(id),window_id bigint not null,kind text not null check(kind in('quiet','satchel','cache','sweep')),node integer not null check(node between 1 and 14),expires_at timestamptz not null,started_at timestamptz,unique(season_id,player_id,district_id,window_id));
create table game_private.street_requests(season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),primary key(season_id,player_id,request_id));
create table game_private.street_history(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),kind text not null,details jsonb not null,created_at timestamptz not null default clock_timestamp());
alter table game_private.scav_sessions add column pursuit jsonb;
do $$declare t text;begin foreach t in array array['street_vehicle_models','street_vehicles','street_events','street_requests','street_history'] loop
 execute format('alter table game_private.%I enable row level security',t);
 execute format('revoke all on game_private.%I from public,anon,authenticated',t);
end loop;end$$;
create trigger street_requests_retain before update or delete or truncate on game_private.street_requests for each statement execute function game_private.district_immutable();
create trigger street_history_retain before update or delete or truncate on game_private.street_history for each statement execute function game_private.district_immutable();
create trigger street_vehicles_retain before delete or truncate on game_private.street_vehicles for each statement execute function game_private.district_immutable();
create trigger street_vehicles_audit after insert or update on game_private.street_vehicles for each row execute function game_private.audit_change();
create function game_private.street_garage(s uuid,u uuid,bid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select game_private.property_access(s,u,bid,true) and exists(select 1 from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where b.id=bid and b.building_type='garage' and b.archived_at is null and b.construction_status='ready' and b.condition>0 and p.asking_price is null and not exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') and not exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open'))
 and (select count(*) from game_private.street_vehicles where season_id=s and player_id=u and building_id=bid and status='stored')<game_private.setting('scavenging_garage_vehicle_slots');
$$;
create function game_private.street_model(target text) returns jsonb language sql stable security definer set search_path='' as $$
 select to_jsonb(v) from game_private.street_vehicle_models v where enabled order by md5(target||id),id limit 1;
$$;

-- Exact relative-motion collision on each straight segment; polling frequency cannot evade patrols.
create function game_private.street_motion_contact(patrols jsonb,points jsonb,departed timestamptz,arrival timestamptz,started timestamptz,finished timestamptz) returns text language plpgsql immutable set search_path='' as $$
declare p jsonb;route jsonb;knots double precision[];sorted double precision[];lo double precision:=extract(epoch from started);hi double precision:=extract(epoch from finished);ep double precision;speed double precision;period double precision;offset_s double precision;len double precision;total double precision;cycle bigint;i integer;j integer;ta double precision;tb double precision;qa jsonb;qb jsonb;pa jsonb;pb jsonb;dx double precision;dy double precision;vx double precision;vy double precision;f double precision;
begin
 if hi<lo then return null;end if;
 total:=game_private.scav_route_length(points);
 for p in select value from jsonb_array_elements(patrols) loop
  route:=p->'route_points';speed:=(p->>'seconds_per_block')::double precision;period:=game_private.scav_route_length(route)*speed;ep:=(p->>'epoch')::double precision;
  if period<=0 then continue;end if;knots:=array[lo,hi];offset_s:=0;
  if total>0 and arrival>departed then
   for i in 0..jsonb_array_length(points)-1 loop
    if i>0 then offset_s:=offset_s+game_private.scav_route_length(jsonb_build_array(points->(i-1),points->i));end if;
    ta:=extract(epoch from departed)+extract(epoch from arrival-departed)*offset_s/total;
    if ta>lo and ta<hi then knots:=array_append(knots,ta);end if;
   end loop;
  end if;
  for cycle in floor((lo-ep)/period)::bigint..floor((hi-ep)/period)::bigint loop
   offset_s:=0;
   for i in 0..jsonb_array_length(route)-1 loop
    if i>0 then offset_s:=offset_s+game_private.scav_route_length(jsonb_build_array(route->(i-1),route->i))*speed;end if;
    ta:=ep+cycle*period+offset_s;if ta>lo and ta<hi then knots:=array_append(knots,ta);end if;
   end loop;
  end loop;
  select array_agg(x order by x) into sorted from(select distinct unnest(knots) x)q;
  if array_length(sorted,1)=1 then sorted:=array_append(sorted,sorted[1]);end if;
  for j in 2..array_length(sorted,1) loop
   ta:=sorted[j-1];tb:=sorted[j];cycle:=floor(((ta+tb)/2-ep)/period)::bigint;
   pa:=game_private.scav_position(points,departed,arrival,to_timestamp(ta));pb:=game_private.scav_position(points,departed,arrival,to_timestamp(tb));
   qa:=game_private.scav_position(route,to_timestamp(ep+cycle*period),to_timestamp(ep+(cycle+1)*period),to_timestamp(ta));qb:=game_private.scav_position(route,to_timestamp(ep+cycle*period),to_timestamp(ep+(cycle+1)*period),to_timestamp(tb));
   dx:=(pa->>0)::double precision-(qa->>0)::double precision;dy:=(pa->>1)::double precision-(qa->>1)::double precision;
   vx:=(pb->>0)::double precision-(qb->>0)::double precision-dx;vy:=(pb->>1)::double precision-(qb->>1)::double precision-dy;
   f:=case when vx*vx+vy*vy=0 then 0 else greatest(0,least(1,-(dx*vx+dy*vy)/(vx*vx+vy*vy))) end;
   if (dx+f*vx)^2+(dy+f*vy)^2<=((p->>'radius')::double precision)^2 then return p->>'id';end if;
  end loop;
 end loop;return null;
end$$;
create or replace function game_private.scav_patrols(d uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare routes jsonb:='[[[0,0],[4,0],[4,2],[0,2],[0,0]],[[1,0],[1,1],[3,1],[3,2],[1,2],[1,0]],[[0,1],[4,1],[4,0],[0,0],[0,1]],[[2,0],[2,2],[4,2],[4,0],[2,0]]]';result jsonb:='[]';i integer;island boolean;patrol_count integer;speed integer;radius integer;
begin
 if game_private.setting('scavenging_patrol_enabled')=0 or d is null then return result;end if;
 select slug='blackwater-island' into island from public.game_districts where id=d;
 patrol_count:=game_private.setting(case when island then 'scavenging_island_patrol_count' else 'scavenging_patrol_count' end);
 speed:=game_private.setting(case when island then 'scavenging_island_patrol_speed' else 'scavenging_patrol_seconds_per_block' end);
 radius:=game_private.setting(case when island then 'scavenging_island_patrol_radius' else 'scavenging_patrol_radius_percent' end);
 if exists(select 1 from game_private.street_events where season_id=game_private.current_season() and player_id=auth.uid() and district_id=d and kind='sweep' and expires_at>now()) then patrol_count:=least(4,patrol_count+1);end if;
 for i in 0..patrol_count-1 loop
  result:=result||jsonb_build_array(jsonb_build_object('id','patrol-'||(i+1),'route_points',routes->i,
   'epoch',1700000000+mod(abs(hashtextextended(d::text,i)::numeric),100000),
   'seconds_per_block',speed,'radius',radius/100.0));
 end loop;
 return result;
end$$;
create or replace function game_private.bin_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 s uuid; uid uuid:=auth.uid(); nonce uuid; prior game_private.bin_requests;
 r public.game_bin_rules; d public.game_districts; receipt public.game_bin_dives;
 stamp timestamptz; ready timestamptz; roll integer; amount integer:=0;bonus numeric:=1; outcome text; result jsonb; reason text;
begin
 perform game_private.require_active(); if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid action details.'; end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh before continuing.'; end if;
  nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null then raise exception 'A request ID is required.'; end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.bin_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This request ID was already used for a different action.'; end if;
   return prior.result;
  end if;
  if p_action='configure' then
   if not game_private.has_permission('bin_diving.manage') then raise exception 'Owner permission required.'; end if;
   reason:=btrim(p_payload->>'reason');
   if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5-500 characters for the audit log.'; end if;
   select * into strict r from public.game_bin_rules for update;
   if (p_payload->>'version')::integer is distinct from r.version then raise exception 'Another edit was saved. Refresh and review the current rules.'; end if;
   perform set_config('game.reason','Bin diving rules: '||reason,true);
   update public.game_bin_rules set enabled=(p_payload->>'enabled')::boolean,
    cooldown_seconds=(p_payload->>'cooldown_seconds')::integer,cash_min=(p_payload->>'cash_min')::integer,cash_max=(p_payload->>'cash_max')::integer,
    cash_chance=(p_payload->>'cash_chance')::numeric,pickaxe_chance=(p_payload->>'pickaxe_chance')::numeric,
    pistol_blueprint_chance=(p_payload->>'pistol_blueprint_chance')::numeric,bullet_blueprint_chance=(p_payload->>'bullet_blueprint_chance')::numeric,
    lockpick_chance=(p_payload->>'lockpick_chance')::numeric,bandages_blueprint_chance=coalesce((p_payload->>'bandages_blueprint_chance')::numeric,r.bandages_blueprint_chance),version=version+1;
   result:=jsonb_build_object('message','Bin diving rules saved. New districts use these rules automatically.');
  else
   perform game_private.season_guard();
   select * into strict r from public.game_bin_rules for share;
   if p_action='dive' then
    if not r.enabled then raise exception 'Bin diving is paused by the city Owner.'; end if;
    select * into d from public.game_districts where id=(p_payload->>'district_id')::uuid and archived_at is null for share;
    if not found then raise exception 'This district is not open.'; end if;
    if d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') then raise exception 'This district is in lockdown.'; end if;
   elsif p_action<>'equip' then raise exception 'Unknown bin diving action.'; end if;
   perform 1 from public.game_players where id=uid and season_id=s for update;
   if not found then raise exception 'Open your dashboard to initialize this season.'; end if;
   perform set_config('game.reason','Bin diving '||p_action||': '||nonce,true);
   if p_action='equip' then
    if exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working') then raise exception 'Finish your mining shift before replacing equipment.'; end if;
    update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=uid and good_id='pickaxe' and quantity>0;
    if not found then raise exception 'Find a pickaxe by bin diving or buy one from another player on the market.'; end if;
    insert into public.game_mining_tools(season_id,player_id,durability) values(s,uid,game_private.setting('mining_pickaxe_durability'))
     on conflict(season_id,player_id) do update set durability=excluded.durability
     where public.game_mining_tools.durability<excluded.durability;
    if not found then raise exception 'Your current pickaxe is already in full condition.'; end if;
    result:=jsonb_build_object('message','Pickaxe equipped. Visit a public mine to put it to work.');
   else
    stamp:=clock_timestamp();
    select max(ready_at) into ready from public.game_bin_dives where season_id=s and player_id=uid;
    if ready>stamp then raise exception 'Give the streets a moment. Your cooldown applies across every district.'; end if;
    if (r.bandages_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'bandages_blueprint',1)) or (r.pickaxe_chance>0 and not game_private.inventory_fits(s,uid,'pickaxe',1)) or (r.lockpick_chance>0 and not game_private.inventory_fits(s,uid,'lockpick',1)) or (r.pistol_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'pistol_blueprint',1)) or (r.bullet_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'bullet_blueprint',1)) then raise exception 'Free space and weight in Inventory before searching for loot.';end if;
    roll:=floor(random()*10000)::integer;
    outcome:=case when roll<r.cash_chance*100 then 'cash'
     when roll<(r.cash_chance+r.pickaxe_chance)*100 then 'pickaxe'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance)*100 then 'pistol_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance)*100 then 'bullet_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance)*100 then 'lockpick'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance+r.bandages_blueprint_chance)*100 then 'bandages_blueprint' else 'nothing' end;
    if d.slug='blackwater-island' then bonus:=game_private.setting('scavenging_island_cash_multiplier');end if;
    if exists(select 1 from game_private.scav_sessions where season_id=s and player_id=uid and pending->>'mode'='event' and pending->>'id'=nonce::text) then
     bonus:=bonus*coalesce((select (pending->>'cash_multiplier')::numeric from game_private.scav_sessions where season_id=s and player_id=uid),1);
    end if;
    if outcome='cash' then amount:=floor((r.cash_min+floor(random()*(r.cash_max-r.cash_min+1))::integer)*bonus)::integer;end if;
    insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at)
     values(s,uid,d.id,d.name,outcome,amount,r.version,stamp,stamp+make_interval(secs=>r.cooldown_seconds)) returning * into receipt;
    if outcome='cash' then perform game_private.district_wallet(uid,amount,'Bin diving: '||receipt.id);
    elsif outcome<>'nothing' then
     insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,outcome,1)
      on conflict(season_id,player_id,good_id) do update set quantity=public.game_inventory.quantity+1;
    end if;
    result:=jsonb_build_object('message',case when outcome='nothing' then 'Nothing useful this time. The next bin tells another story.' else 'You found something worth keeping.' end,'receipt',to_jsonb(receipt));
   end if;
  end if;
  insert into game_private.bin_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception
  when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the values: chances must total at most 100%, cash must be a valid range, and cooldown must be 1-86,400 seconds.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;

revoke all on function game_private.street_garage(uuid,uuid,uuid),game_private.street_model(text),game_private.street_motion_contact(jsonb,jsonb,timestamptz,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
