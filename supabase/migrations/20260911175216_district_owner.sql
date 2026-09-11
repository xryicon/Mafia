
create function game_private.district_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; d public.game_districts; p public.game_district_plots; t public.game_plot_templates;
 bt public.game_building_types; z public.game_zoning; st public.game_district_site_templates;
 b uuid; new_id uuid; reason text:=trim(p_payload->>'reason'); payload jsonb:=p_payload-'reason'; j jsonb;
begin
 perform game_private.require_active();
 if not game_private.has_permission('districts.manage') then raise exception 'District management permission required.'; end if;
 if not game_private.rate('district_manage',60) then raise exception 'Too many edits. Try again shortly.'; end if;
 begin
 s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 if reason is null or length(reason) not between 3 and 1000 then raise exception 'Give a reason for the audit record.'; end if;
 perform set_config('game.reason',reason,true);
 case p_action
 when 'district' then
  select * into d from public.game_districts where id=nullif(payload->>'id','')::uuid for update;
  if d.id is null then
   insert into public.game_districts(slug,name) values(payload->>'slug',payload->>'name') returning * into d;
  end if;
  select * into d from jsonb_populate_record(d,payload);
  if length(d.description)>4000 or length(d.tagline)>200 or not(d.image_url ~ '^/art/[a-zA-Z0-9._/-]+$' or d.image_url ~ '^https://') then raise exception 'Check the district text and image URL.'; end if;
  if jsonb_typeof(d.city_polygon)<>'array' or jsonb_array_length(d.city_polygon) not between 3 and 30 then raise exception 'A district needs 3 to 30 map points.'; end if;
  if exists(select 1 from jsonb_array_elements(d.city_polygon) v where jsonb_typeof(v)<>'array' or jsonb_array_length(v)<>2 or (v->>0)::numeric not between 0 and 1200 or (v->>1)::numeric not between 0 and 800) then raise exception 'District map points must stay inside the 1200 by 800 city map.'; end if;
  update public.game_districts set slug=d.slug,name=d.name,description=d.description,tagline=d.tagline,
   district_type=d.district_type,image_url=d.image_url,industries=d.industries,strategic_importance=d.strategic_importance,
   tax_rate=d.tax_rate,police_heat=d.police_heat,property_value_index=d.property_value_index,property_trend=d.property_trend,
   status=d.status,city_polygon=d.city_polygon,map_data=d.map_data,updated_at=now() where id=d.id;
  insert into public.game_district_territory(season_id,district_id,status) values(s,d.id,d.status)
  on conflict(season_id,district_id) do update set status=excluded.status;
  new_id:=d.id;
 when 'archive_district' then
  new_id:=(payload->>'id')::uuid;
  if exists(select 1 from public.game_district_plots where district_id=new_id and season_id=s and owner_type in ('player','gang')) then raise exception 'A district with player or gang property cannot be archived during its season.'; end if;
  update public.game_districts set archived_at=case when coalesce((payload->>'archive')::boolean,true) then now() else null end where id=new_id;
 when 'plot' then
  select * into t from public.game_plot_templates where id=nullif(payload->>'id','')::uuid for update;
  if t.id is null then
   insert into public.game_plot_templates(district_id,code,polygon,size,zoning,base_price)
   values((payload->>'district_id')::uuid,payload->>'code',payload->'polygon',(payload->>'size')::integer,payload->>'zoning',(payload->>'base_price')::bigint) returning * into t;
  end if;
  select * into t from jsonb_populate_record(t,payload);
  if jsonb_typeof(t.polygon)<>'array' or jsonb_array_length(t.polygon)<3 or jsonb_array_length(t.polygon)>30 then raise exception 'A plot needs 3 to 30 map points.'; end if;
  if exists(select 1 from jsonb_array_elements(t.polygon) v where jsonb_typeof(v)<>'array' or jsonb_array_length(v)<>2 or (v->>0)::numeric not between 0 and 1200 or (v->>1)::numeric not between 0 and 800) then raise exception 'Plot points must be inside the 1200 by 800 map.'; end if;
  select * into p from public.game_district_plots where template_id=t.id and season_id=s for update;
  if exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'Settle the plot auction and offers before editing its terms.'; end if;
  
  update public.game_plot_templates set code=t.code,polygon=t.polygon,size=t.size,zoning=t.zoning,status=case when t.entity_id is null and t.status='owned' then 'available' else t.status end,
   base_price=t.base_price,tax_rate=t.tax_rate,utility_level=t.utility_level,infrastructure_level=t.infrastructure_level,
   build_capacity=t.build_capacity,strategic_type=nullif(t.strategic_type,''),description=t.description where id=t.id;
  update public.game_district_plots set code=t.code,polygon=t.polygon,size=t.size,zoning=t.zoning,
   status=case when owner_id is not null and t.status in ('available','owned') then 'owned' else t.status end,asking_price=case when t.status in ('reserved','locked') then null else asking_price end,base_price=t.base_price,tax_rate=t.tax_rate,
   utility_level=t.utility_level,infrastructure_level=t.infrastructure_level,build_capacity=t.build_capacity,
   strategic_type=nullif(t.strategic_type,''),version=version+1 where template_id=t.id and season_id=s;
  perform game_private.ensure_districts(s);
  new_id:=t.id;
 when 'zoning' then
  if exists(select 1 from jsonb_array_elements_text(payload->'allowed_buildings') v where not exists(select 1 from public.game_building_types where id=v)) then raise exception 'Choose existing building types.'; end if;
  insert into public.game_zoning(id,name,allowed_buildings) values(payload->>'id',payload->>'name',array(select jsonb_array_elements_text(payload->'allowed_buildings')))
  on conflict(id) do update set name=excluded.name,allowed_buildings=excluded.allowed_buildings;
 when 'building_type' then
  select * into bt from public.game_building_types where id=payload->>'id';
  if bt.id is null then
   insert into public.game_building_types(id,name,cost,construction_seconds,business_type)
   values(payload->>'id',payload->>'name',(payload->>'cost')::bigint,(payload->>'construction_seconds')::integer,payload->>'business_type') returning * into bt;
  end if;
  select * into bt from jsonb_populate_record(bt,payload);
  update public.game_building_types set name=bt.name,cost=bt.cost,construction_seconds=bt.construction_seconds,
   capacity_required=bt.capacity_required,minimum_utility=bt.minimum_utility,minimum_infrastructure=bt.minimum_infrastructure,
   business_type=bt.business_type,good_id=nullif(bt.good_id,''),batch_size=bt.batch_size,cycle_seconds=bt.cycle_seconds,
   input_good_id=nullif(bt.input_good_id,''),input_quantity=bt.input_quantity,telegram_fee=bt.telegram_fee,active=bt.active where id=bt.id;
 when 'site' then
  select * into st from public.game_district_site_templates where id=nullif(payload->>'id','')::uuid;
  if st.id is null then
   insert into public.game_district_site_templates(district_id,name,kind,resource_type)
   values((payload->>'district_id')::uuid,payload->>'name',payload->>'kind',payload->>'resource_type') returning * into st;
  end if;
  select * into st from jsonb_populate_record(st,payload);
  if st.plot_template_id is not null and not exists(select 1 from public.game_plot_templates where id=st.plot_template_id and district_id=st.district_id) then raise exception 'Choose a plot in this district.'; end if;
  if jsonb_typeof(st.data)<>'object' then raise exception 'Resource measurements must be an object.'; end if;
  update public.game_district_site_templates set name=st.name,plot_template_id=st.plot_template_id,kind=st.kind,resource_type=st.resource_type,data=st.data where id=st.id;
  insert into public.game_district_sites(season_id,template_id,district_id,plot_id,name,kind,resource_type,data)
  values(s,st.id,st.district_id,(select id from public.game_district_plots where template_id=st.plot_template_id and season_id=s),st.name,st.kind,st.resource_type,st.data)
  on conflict(season_id,template_id) do update set name=excluded.name,plot_id=excluded.plot_id,kind=excluded.kind,resource_type=excluded.resource_type,data=excluded.data;
  new_id:=st.id;
 when 'building' then
  select * into p from public.game_district_plots where id=(payload->>'plot_id')::uuid and season_id=s for update;
  if p.id is null or p.owner_id is null then raise exception 'Assign a building to an owned plot.'; end if;
  if exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') or p.asking_price is not null then raise exception 'Withdraw listings and settle offers before changing buildings.'; end if;
  update public.game_district_businesses set archived_at=now(),status='closed' where plot_id=p.id and archived_at is null;
  update public.game_district_buildings set archived_at=now() where plot_id=p.id and archived_at is null;
  if nullif(payload->>'building_type','') is not null then
   select * into strict bt from public.game_building_types where id=payload->>'building_type';
   insert into public.game_district_buildings(season_id,plot_id,building_type,owner_type,owner_id,construction_status,cost,ready_at,built_at)
   values(s,p.id,bt.id,p.owner_type,p.owner_id,'ready',bt.cost,now(),now()) returning id into b;
   insert into public.game_district_businesses(season_id,district_id,plot_id,building_id,owner_type,owner_id,name,business_type,telegram_fee,sells,buys)
   values(s,p.district_id,p.id,b,p.owner_type,p.owner_id,coalesce(nullif(payload->>'name',''),p.code||' '||bt.name),bt.business_type,bt.telegram_fee,
   case when bt.good_id is null then '{}'::text[] else array[bt.good_id] end,case when bt.input_good_id is null then '{}'::text[] else array[bt.input_good_id] end);
  end if;
  perform game_private.district_event(p.district_id,'system','building_assignment','Building assignment changed at '||p.code,p.id);
 when 'control' then
  insert into public.game_district_territory(season_id,district_id,controller_gang_id,neutral_influence,fortification,status)
  values(s,(payload->>'district_id')::uuid,nullif(payload->>'controller_gang_id','')::uuid,(payload->>'neutral_influence')::bigint,(payload->>'fortification')::integer,payload->>'status')
  on conflict(season_id,district_id) do update set controller_gang_id=excluded.controller_gang_id,neutral_influence=excluded.neutral_influence,fortification=excluded.fortification,status=excluded.status;
  perform game_private.district_event((payload->>'district_id')::uuid,'gang','gang_control','District control updated by the city administration',null,null,nullif(payload->>'controller_gang_id','')::uuid);
 when 'influence' then
  insert into public.game_district_gang_control(season_id,district_id,gang_id,influence)
  values(s,(payload->>'district_id')::uuid,(payload->>'gang_id')::uuid,(payload->>'influence')::bigint)
  on conflict(season_id,district_id,gang_id) do update set influence=excluded.influence;
 when 'war' then
  if nullif(payload->>'id','') is null then
   insert into public.game_district_wars(season_id,district_id,name,status,objectives)
   values(s,(payload->>'district_id')::uuid,payload->>'name',payload->>'status',coalesce(payload->'objectives','[]')) returning id into new_id;
  else
   update public.game_district_wars set name=payload->>'name',status=payload->>'status',objectives=coalesce(payload->'objectives','[]'),
   ended_at=case when payload->>'status'='finished' then now() else null end where id=(payload->>'id')::uuid and season_id=s returning id into new_id;
  end if;
 when 'war_party' then
  insert into public.game_district_war_parties(war_id,season_id,gang_id,side,supply,data)
  values((payload->>'war_id')::uuid,s,(payload->>'gang_id')::uuid,payload->>'side',(payload->>'supply')::bigint,coalesce(payload->'data','{}'))
  on conflict(war_id,gang_id) do update set side=excluded.side,supply=excluded.supply,data=excluded.data;
 when 'operation' then
  if not exists(select 1 from public.game_district_wars where id=(payload->>'war_id')::uuid and season_id=s) then raise exception 'Choose a current-season war.'; end if;
  insert into public.game_district_operations(war_id,gang_id,kind,status,description,data)
  values((payload->>'war_id')::uuid,(payload->>'gang_id')::uuid,payload->>'kind',payload->>'status',payload->>'description',coalesce(payload->'data','{}'));
 when 'event' then
  if length(payload->>'description') not between 3 and 1000 then raise exception 'Enter an event description.'; end if;
  perform game_private.district_event((payload->>'district_id')::uuid,'system','administration',payload->>'description');
 when 'event_visibility' then
  insert into public.game_district_event_visibility(event_id,hidden,reason) values((payload->>'event_id')::bigint,(payload->>'hidden')::boolean,reason)
  on conflict(event_id) do update set hidden=excluded.hidden,reason=excluded.reason;
 else raise exception 'Unknown management action.';
 end case;
 insert into public.game_audit(actor_id,action,target,after_data,reason) values(auth.uid(),'district_manage.'||p_action,coalesce(new_id::text,payload->>'district_id','district configuration'),payload,reason);
 return jsonb_build_object('message','Saved. The change is recorded in the audit history.','id',new_id);
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
  raise log 'district management failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','Check the fields. This change was not saved.');
 end;
end $$;
create function public.district_manage(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.district_manage(p_action,p_payload) $$;
revoke all on function game_private.district_manage(text,jsonb),public.district_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.district_manage(text,jsonb),public.district_manage(text,jsonb) to authenticated;
