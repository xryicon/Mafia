-- Street-level properties, city leases and installed workstations.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce city property leases and crafting stations',true);
insert into public.game_permissions(id,owner_only) values('property.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('property_station_cost',500,0,1000000000),('property_station_space',20,1,1000000);
create table public.game_district_streets(
 id uuid primary key default gen_random_uuid(),district_id uuid not null references public.game_districts(id),
 name text not null check(length(name) between 2 and 80),description text not null default '' check(length(description)<=600),
 sort_order integer not null default 0,archived_at timestamptz,unique(district_id,name)
);
alter table public.game_plot_templates add column street_id uuid references public.game_district_streets(id);
alter table public.game_plot_templates add column image_url text not null default '';
create index plot_template_street on public.game_plot_templates(street_id) where street_id is not null;
create table public.game_property_lease_terms(
 template_id uuid primary key references public.game_plot_templates(id),rent bigint not null check(rent between 1 and 1000000000),
 term_hours integer not null check(term_hours between 1 and 8760),enabled boolean not null default false,version integer not null default 1
);
create table public.game_property_leases(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 plot_id uuid not null references public.game_district_plots(id),building_id uuid not null references public.game_district_buildings(id),
 player_id uuid not null references public.game_players(id),rent bigint not null check(rent>0),
 starts_at timestamptz not null default clock_timestamp(),ends_at timestamptz not null,released_at timestamptz,
 check(ends_at>starts_at)
);
create unique index one_property_tenant on public.game_property_leases(building_id) where released_at is null;
create index property_lease_player on public.game_property_leases(player_id,season_id,building_id);
create index property_lease_plot on public.game_property_leases(plot_id);
create index property_lease_season on public.game_property_leases(season_id);
create table public.game_property_stations(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 building_id uuid not null references public.game_district_buildings(id),player_id uuid not null references public.game_players(id),
 cost bigint not null check(cost>=0),space integer not null check(space>0),installed_at timestamptz not null default clock_timestamp(),removed_at timestamptz
);
create unique index one_player_station on public.game_property_stations(building_id,player_id) where removed_at is null;
create index station_player on public.game_property_stations(player_id,season_id);
create index station_season on public.game_property_stations(season_id);
create table game_private.property_requests(
 season_id uuid not null,player_id uuid not null,request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 primary key(season_id,player_id,request_id)
);
alter table public.game_district_streets enable row level security;
alter table public.game_property_lease_terms enable row level security;
alter table public.game_property_leases enable row level security;
alter table public.game_property_stations enable row level security;
alter table game_private.property_requests enable row level security;
revoke all on public.game_district_streets,public.game_property_lease_terms,public.game_property_leases,public.game_property_stations,game_private.property_requests from public,anon,authenticated;
create trigger street_audit after insert or update or delete on public.game_district_streets for each row execute function game_private.audit_change();
create trigger lease_terms_audit after insert or update or delete on public.game_property_lease_terms for each row execute function game_private.audit_change();
create trigger lease_audit after insert or update on public.game_property_leases for each row execute function game_private.audit_change();
create trigger station_audit after insert or update on public.game_property_stations for each row execute function game_private.audit_change();
create trigger lease_retain before delete or truncate on public.game_property_leases for each statement execute function game_private.district_immutable();
create trigger station_retain before delete or truncate on public.game_property_stations for each statement execute function game_private.district_immutable();
create trigger property_request_retain before update or delete or truncate on game_private.property_requests for each statement execute function game_private.district_immutable();

-- Historical tenants may collect their own goods; only the current occupant can deposit.
create function game_private.property_access(s uuid,u uuid,bid uuid,deposit boolean) returns boolean language sql stable security definer set search_path='' as $$
 select u is not null and exists(
 select 1 from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id
 where b.id=bid and b.season_id=s and p.season_id=s and b.archived_at is null and p.archived_at is null
 and ((b.owner_type='player' and b.owner_id=u and p.owner_type='player' and p.owner_id=u)
 or (b.owner_type='city' and p.owner_type='city' and b.owner_id=p.owner_id and exists(
 select 1 from public.game_property_leases l where l.building_id=b.id and l.season_id=s and l.player_id=u
 and ((l.released_at is null and l.ends_at>statement_timestamp()) or (not deposit and (
 exists(select 1 from public.game_storage_inventory i where i.season_id=s and i.building_id=bid and i.player_id=u and i.quantity>0)
 or exists(select 1 from public.game_inventory_gear g where g.season_id=s and g.building_id=bid and g.player_id=u and g.location='storage'))))))))
$$;
create function game_private.property_station_space(s uuid,bid uuid,u uuid) returns bigint language sql stable security definer set search_path='' as $$
 select coalesce((select sum(space) from public.game_property_stations where season_id=s and building_id=bid and player_id=u and removed_at is null
 and game_private.property_access(s,u,bid,true)),0)
$$;
create function game_private.property_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;previous game_private.property_requests;p public.game_district_plots;b public.game_district_buildings;
 terms public.game_property_lease_terms;l public.game_property_leases;r public.game_storage_rules;result jsonb;cost bigint;space bigint;used bigint;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid property request.';end if;
  s:=game_private.season_guard(false);nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh this season before continuing.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into previous from game_private.property_requests where season_id=s and player_id=u and request_id=nonce;
  if found then
   if previous.action is distinct from p_action or previous.payload is distinct from p_payload then raise exception 'This request reference has already been used.';end if;
   return previous.result;
  end if;
  perform game_private.season_guard();
  select * into p from public.game_district_plots where id=(p_payload->>'plot_id')::uuid and season_id=s and archived_at is null for update;
  if not found then raise exception 'Choose a current property.';end if;
  select * into b from public.game_district_buildings where plot_id=p.id and season_id=s and archived_at is null for update;
  if not found or b.construction_status<>'ready' or b.condition<=0 then raise exception 'A completed, usable storage building is required.';end if;
  select * into r from public.game_storage_rules where building_type=b.building_type for share;
  if not found then raise exception 'Only storage buildings support this action.';end if;
  if p.status in ('locked','reserved') or not exists(select 1 from public.game_districts where id=p.district_id and archived_at is null and status<>'lockdown')
   or exists(select 1 from public.game_district_territory where district_id=p.district_id and season_id=s and status='lockdown') then raise exception 'This property is closed during district lockdown.';end if;
  perform 1 from public.game_players where id=u and season_id=s for update;
  if not found then raise exception 'Open your dashboard to enter this season.';end if;
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason','Property action: '||coalesce(p_action,'')||' at '||p.code,true);
  select * into l from public.game_property_leases where building_id=b.id and released_at is null for update;
  if p_action in ('rent','renew') then
   if p.owner_type<>'city' or b.owner_type<>'city' or b.owner_id<>p.owner_id then raise exception 'Only city-owned buildings can be leased.';end if;
   if p.asking_price is not null or exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'This property is listed for transfer.';end if;
   select * into terms from public.game_property_lease_terms where template_id=p.template_id for share;
   if not found or not terms.enabled or not r.enabled then raise exception 'This property is not accepting leases.';end if;
   if (p_payload->>'version')::int is distinct from terms.version or (p_payload->>'rent')::bigint is distinct from terms.rent then raise exception 'Lease terms changed. Refresh and review the new quote.';end if;
   if p_action='renew' then
    if l.id is null or l.player_id<>u or l.ends_at<=clock_timestamp() then raise exception 'This lease has expired. Review the available property to rent again.';end if;
    if l.ends_at>clock_timestamp()+make_interval(hours=>terms.term_hours) then raise exception 'Renew when one rental period or less remains.';end if;
   elsif l.id is not null and l.ends_at>clock_timestamp() then raise exception 'Another lease already occupies this building.';
   end if;
   perform game_private.district_wallet(u,-terms.rent,'City property rent: '||p.code);
   if p_action='renew' then
    update public.game_property_leases set ends_at=ends_at+make_interval(hours=>terms.term_hours) where id=l.id;
   else
    update public.game_property_leases set released_at=clock_timestamp() where building_id=b.id and released_at is null and ends_at<=clock_timestamp();
    -- Expired tenants retain private collection access, but their fittings are retired.
    update public.game_property_stations set removed_at=clock_timestamp() where building_id=b.id and removed_at is null;
    insert into public.game_property_leases(season_id,plot_id,building_id,player_id,rent,ends_at)
     values(s,p.id,b.id,u,terms.rent,clock_timestamp()+make_interval(hours=>terms.term_hours));
   end if;
   perform game_private.district_event(p.district_id,'property','property_lease',case when p_action='renew' then 'City lease renewed at ' else 'City property leased at ' end||p.code,p.id);
   result:=jsonb_build_object('message',case when p_action='renew' then 'Lease extended. Rent paid in full.' else 'The keys are yours. Your city lease is active.' end);
  elsif p_action='vacate' then
   if l.id is null or l.player_id<>u then raise exception 'This is not your current lease.';end if;
   if exists(select 1 from public.game_storage_inventory where building_id=b.id and player_id=u and quantity>0)
    or exists(select 1 from public.game_inventory_gear where building_id=b.id and player_id=u and location='storage') then raise exception 'Collect your stored items before returning the keys.';end if;
   update public.game_property_leases set released_at=clock_timestamp() where id=l.id;
   update public.game_property_stations set removed_at=clock_timestamp() where building_id=b.id and player_id=u and removed_at is null;
   perform game_private.district_event(p.district_id,'property','property_lease_end','City property returned at '||p.code,p.id);
   result:=jsonb_build_object('message','Keys returned. Prepaid rent and installation fees are not refunded.');
  elsif p_action in ('install_station','remove_station') then
   if not game_private.property_access(s,u,b.id,true) then raise exception 'Own this building or hold its active city lease to change its fittings.';end if;
   if p.asking_price is not null or exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'Unlist the property before changing its fittings.';end if;
   if p_action='install_station' then
    if exists(select 1 from public.game_property_stations where building_id=b.id and player_id=u and removed_at is null) then raise exception 'A crafting station is already installed.';end if;
    cost:=game_private.setting('property_station_cost');space:=game_private.setting('property_station_space');
    if (p_payload->>'cost')::bigint is distinct from cost or (p_payload->>'space')::bigint is distinct from space then raise exception 'Installation terms changed. Review the current quote.';end if;
    select coalesce((select sum(quantity) from public.game_storage_inventory where season_id=s and building_id=b.id and player_id=u),0)
     +coalesce((select sum(quantity) from public.game_inventory_gear where season_id=s and building_id=b.id and player_id=u and location='storage'),0) into used;
    if not r.enabled or used+space>r.capacity then raise exception 'Free up enough storage space before installing a station.';end if;
    perform game_private.district_wallet(u,-cost,'Crafting station installed at '||p.code);
    insert into public.game_property_stations(season_id,building_id,player_id,cost,space) values(s,b.id,u,cost,space);
    result:=jsonb_build_object('message','Crafting station installed. Its floor space is reserved inside this building.');
   else
    update public.game_property_stations set removed_at=clock_timestamp() where building_id=b.id and player_id=u and removed_at is null;
    if not found then raise exception 'There is no installed station to remove.';end if;
    result:=jsonb_build_object('message','Crafting station removed. Its storage space is available again.');
   end if;
   perform game_private.district_event(p.district_id,'property','property_fitting',case when p_action='install_station' then 'Crafting station installed at ' else 'Crafting station removed at ' end||p.code,p.id);
  else raise exception 'Choose a supported property action.';end if;
  insert into game_private.property_requests values(s,u,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the property details and refresh.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

-- Catalog controls are explicitly Owner-only; moderators gain no economy editing.
create function game_private.property_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare reason text;t public.game_plot_templates;sid uuid;d uuid;
begin
 perform game_private.require_active();
 if not game_private.has_permission('property.manage') then raise exception 'Owner property permission required.';end if;
 if not game_private.rate('property_manage',60) then return jsonb_build_object('error','Too many property edits.');end if;
 begin
  perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid property edit.';end if;
  reason:=btrim(p_payload->>'reason');if reason is null or length(reason) not between 5 and 500 then raise exception 'Add an audit reason of 5–500 characters.';end if;
  perform set_config('game.reason','Property planning: '||reason,true);
  if p_action='street' then
   d:=(p_payload->>'district_id')::uuid;
   if not exists(select 1 from public.game_districts where id=d and archived_at is null) then raise exception 'Choose an open district.';end if;
   sid:=nullif(p_payload->>'id','')::uuid;
   if sid is null then
    insert into public.game_district_streets(district_id,name,description,sort_order) values(d,btrim(p_payload->>'name'),coalesce(p_payload->>'description',''),coalesce((p_payload->>'sort_order')::int,0));
   else
    update public.game_district_streets set name=btrim(p_payload->>'name'),description=coalesce(p_payload->>'description',''),sort_order=coalesce((p_payload->>'sort_order')::int,0),
     archived_at=case when coalesce((p_payload->>'archived')::boolean,false) then now() else null end where id=sid and district_id=d;
    if not found then raise exception 'Street not found in this district.';end if;
   end if;
  elsif p_action='property' then
   select * into t from public.game_plot_templates where id=(p_payload->>'template_id')::uuid and archived_at is null for update;
   if not found then raise exception 'Property template not found.';end if;
   sid:=nullif(p_payload->>'street_id','')::uuid;
   if sid is not null and not exists(select 1 from public.game_district_streets where id=sid and district_id=t.district_id and archived_at is null) then raise exception 'Choose a street in this district.';end if;
   if coalesce(p_payload->>'image_url','')<>'' and not (p_payload->>'image_url' ~ '^(https://|/art/)[^[:space:]]+$') then raise exception 'Use an artwork path or HTTPS image URL.';end if;
   update public.game_plot_templates set street_id=sid,image_url=coalesce(p_payload->>'image_url','') where id=t.id;
   if coalesce((p_payload->>'lease_enabled')::boolean,false) and (not exists(select 1 from public.game_district_entities where id=t.entity_id and entity_type='city')
     or not exists(select 1 from public.game_storage_rules where building_type=t.building_type)) then raise exception 'Leases require a city-owned garage or warehouse template.';end if;
   if coalesce((p_payload->>'lease_enabled')::boolean,false) or p_payload->>'rent' is not null or exists(select 1 from public.game_property_lease_terms where template_id=t.id) then
   insert into public.game_property_lease_terms(template_id,rent,term_hours,enabled)
    values(t.id,coalesce((p_payload->>'rent')::bigint,(select rent from public.game_property_lease_terms where template_id=t.id)),coalesce((p_payload->>'term_hours')::int,(select term_hours from public.game_property_lease_terms where template_id=t.id)),coalesce((p_payload->>'lease_enabled')::boolean,false))
    on conflict(template_id) do update set rent=excluded.rent,term_hours=excluded.term_hours,enabled=excluded.enabled,version=game_property_lease_terms.version+1;end if;
  else raise exception 'Choose street or property settings.';end if;
  return jsonb_build_object('message','Property registry updated. Existing lease end dates are preserved.');
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation or unique_violation then return jsonb_build_object('error','Check the property settings and try again.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

alter function game_private.district_state(text,bigint) rename to district_state_before_properties;
create function game_private.district_state(p_slug text default null,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb;s uuid;did uuid;u uuid:=auth.uid();
begin
 v:=game_private.district_state_before_properties(p_slug,p_before);s:=(v->'season'->>'id')::uuid;did:=(v->'district'->>'id')::uuid;
 return v||jsonb_build_object(
 'streets',(select coalesce(jsonb_agg(x order by x.sort_order,x.name),'[]') from public.game_district_streets x where district_id=did and (archived_at is null or game_private.has_permission('property.manage'))),
 'plots',(select coalesce(jsonb_agg(x||jsonb_build_object('street_id',t.street_id,'image_url',t.image_url) order by x->>'code'),'[]') from jsonb_array_elements(v->'plots') x join public.game_plot_templates t on t.id=(x->>'template_id')::uuid),
 'lease_terms',(select coalesce(jsonb_agg(t),'[]') from public.game_property_lease_terms t join public.game_plot_templates p on p.id=t.template_id where p.district_id=did),
 'leases',(select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'plot_id',l.plot_id,'building_id',l.building_id,'player_id',l.player_id,'player_name',game_private.district_owner_name('player',l.player_id),'ends_at',l.ends_at,'active',l.released_at is null and l.ends_at>clock_timestamp())),'[]') from public.game_property_leases l join public.game_district_plots p on p.id=l.plot_id where l.season_id=s and p.district_id=did and ((l.released_at is null and l.ends_at>clock_timestamp()) or l.player_id=u)),
 'property_storage',(select coalesce(jsonb_agg(jsonb_build_object('building_id',b.id,'plot_id',b.plot_id,'capacity',r.capacity,'enabled',r.enabled,
 'can_access',game_private.property_access(s,u,b.id,false),'can_store',game_private.property_access(s,u,b.id,true),
 'station', (select jsonb_build_object('id',f.id,'space',f.space,'installed_at',f.installed_at) from public.game_property_stations f where f.building_id=b.id and f.player_id=u and f.removed_at is null and game_private.property_access(s,u,b.id,true)))),'[]')
 from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id join public.game_storage_rules r on r.building_type=b.building_type where b.season_id=s and p.district_id=did and b.archived_at is null),
 'property_settings',jsonb_build_object('station_cost',game_private.setting('property_station_cost'),'station_space',game_private.setting('property_station_space')),
 'can_manage_properties',game_private.has_permission('property.manage'));
end$$;
create function public.property_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.property_action(p_action,p_payload)$$;
create function public.property_manage(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.property_manage(p_action,p_payload)$$;
revoke all on function game_private.property_access(uuid,uuid,uuid,boolean),game_private.property_station_space(uuid,uuid,uuid),game_private.property_action(text,jsonb),game_private.property_manage(text,jsonb),game_private.district_state(text,bigint),game_private.district_state_before_properties(text,bigint),public.property_action(text,jsonb),public.property_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.property_action(text,jsonb),game_private.property_manage(text,jsonb),game_private.district_state(text,bigint),public.property_action(text,jsonb),public.property_manage(text,jsonb) to authenticated;

-- Add two new city rental properties without changing any existing ownership.
insert into public.game_district_streets(district_id,name,description,sort_order)
 select d.id,x.name,x.description,x.n from public.game_districts d cross join (values
 (1,'Harbor Road','The main artery of the docks. Warehouses, freight and the city’s trade.'),
 (2,'Warehouse Row','Secure your stock. Build the supply behind your empire.'),
 (3,'Dockside Avenue','Workshops and businesses along the waterfront.'),
 (4,'Pier District','Deep-water access and the strategic edge of the city.')) x(n,name,description) where d.slug='the-waterfront';
update public.game_plot_templates t set street_id=st.id from public.game_district_streets st where st.district_id=t.district_id and st.sort_order=case when t.code~'^W[0-9]+$' then least(4,((substring(t.code from 2)::int-1)/6)+1) else 3 end;
insert into public.game_plot_templates(district_id,code,polygon,size,zoning,status,base_price,utility_level,infrastructure_level,build_capacity,entity_id,building_type,business_name,description,street_id,image_url)
 select d.id,x.code,x.polygon::jsonb,x.size,'waterfront','owned',x.price,80,80,2,e.id,x.kind,x.name,x.description,st.id,x.image
 from public.game_districts d join public.game_district_entities e on e.name='Blackwater Port Authority'
 join public.game_district_streets st on st.district_id=d.id and st.name='Warehouse Row'
 cross join (values
 ('W25','[[960,110],[1120,110],[1120,225],[960,225]]',120,3000,'garage','Quayside Small Garage','City keys. A private place for your stock and workbench.','/art/exchange-small.webp',300),
 ('W26','[[965,280],[1135,280],[1135,450],[965,450]]',1000,15000,'warehouse','Harbor Reserve Warehouse','Room for a larger stockpile. Available on a prepaid city lease.','/art/harbor-small.webp',1500)
 )x(code,polygon,size,price,kind,name,description,image,rent) where d.slug='the-waterfront';
insert into public.game_property_lease_terms(template_id,rent,term_hours,enabled)
 select t.id,case when t.building_type='garage' then 300 else 1500 end,168,true from public.game_plot_templates t join public.game_districts d on d.id=t.district_id where d.slug='the-waterfront' and t.code in ('W25','W26');
select game_private.ensure_districts(game_private.current_season());
create index property_lease_building on public.game_property_leases(building_id);
create index property_station_building on public.game_property_stations(building_id);
notify pgrst,'reload schema';
