
create function game_private.district_owner_name(kind text, owner uuid) returns text language sql stable security definer set search_path='' as $$
 select case when kind='player' then coalesce((select username from game_private.identities where player_id=owner),'Player')
 when kind='gang' then coalesce((select name from public.game_season_gangs where id=owner),'Gang')
 else coalesce((select name from public.game_district_entities where id=owner),'Unclaimed') end
$$;
create function game_private.district_event(d uuid, category text, event_type text, description text, plot uuid default null, business uuid default null, gang uuid default null, metadata jsonb default '{}') returns void language sql security definer set search_path='' as $$
 insert into public.game_district_events(season_id,district_id,category,event_type,description,actor_id,plot_id,business_id,gang_id,metadata)
 values(game_private.current_season(),d,category,event_type,description,auth.uid(),plot,business,gang,metadata)
$$;
create function game_private.ensure_districts(s uuid) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare p public.game_district_plots; t public.game_plot_templates; b uuid; d public.game_districts;
begin
 -- Serialize first access only when catalog content has not been instantiated.
 if not exists(select 1 from public.game_plot_templates t join public.game_districts d on d.id=t.district_id
 where t.archived_at is null and d.archived_at is null and not exists(select 1 from public.game_district_plots p where p.season_id=s and p.template_id=t.id)) then return; end if;
 perform pg_advisory_xact_lock(4704020);
 perform set_config('game.reason','Initialize district catalog for season',true);
 for d in select * from public.game_districts where archived_at is null loop
  insert into public.game_district_territory(season_id,district_id,status) values(s,d.id,d.status) on conflict do nothing;
 end loop;
 for t in select t.* from public.game_plot_templates t join public.game_districts d on d.id=t.district_id where t.archived_at is null and d.archived_at is null loop
  insert into public.game_district_plots(season_id,template_id,district_id,code,polygon,size,zoning,status,owner_type,owner_id,base_price,tax_rate,utility_level,infrastructure_level,build_capacity,strategic_type)
  values(s,t.id,t.district_id,t.code,t.polygon,t.size,t.zoning,t.status,
   coalesce((select entity_type from public.game_district_entities where id=t.entity_id),'none'),t.entity_id,
   t.base_price,t.tax_rate,t.utility_level,t.infrastructure_level,t.build_capacity,t.strategic_type)
  on conflict(season_id,template_id) do nothing returning * into p;
  if p.id is null then continue; end if;
  if t.building_type is not null and p.owner_id is not null then
   insert into public.game_district_buildings(season_id,plot_id,building_type,owner_type,owner_id,construction_status,cost,ready_at,built_at)
   select s,p.id,bt.id,p.owner_type,p.owner_id,'ready',bt.cost,now(),now() from public.game_building_types bt where bt.id=t.building_type returning id into b;
   insert into public.game_district_businesses(season_id,district_id,plot_id,building_id,owner_type,owner_id,name,business_type,description,sells,buys,telegram_fee)
   select s,t.district_id,p.id,b,p.owner_type,p.owner_id,coalesce(t.business_name,bt.name),bt.business_type,t.description,
    case when bt.good_id is null then '{}'::text[] else array[bt.good_id] end,
    case when bt.input_good_id is null then '{}'::text[] else array[bt.input_good_id] end,bt.telegram_fee
   from public.game_building_types bt where bt.id=t.building_type;
   insert into public.game_district_events(season_id,district_id,category,event_type,description,plot_id,business_id)
   select s,t.district_id,'business','business_opening',name||' registered at '||p.code,p.id,id
   from public.game_district_businesses where plot_id=p.id;
  end if;
 end loop;
 insert into public.game_district_sites(season_id,template_id,district_id,plot_id,name,kind,resource_type,data)
 select s,t.id,t.district_id,p.id,t.name,t.kind,t.resource_type,t.data
 from public.game_district_site_templates t join public.game_districts d on d.id=t.district_id
 left join public.game_district_plots p on p.template_id=t.plot_template_id and p.season_id=s
 where t.archived_at is null and d.archived_at is null on conflict(season_id,template_id) do nothing;
end $$;

create function game_private.district_state(p_slug text default null,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; d public.game_districts; result jsonb; manage boolean;
begin
 perform game_private.require_active();
 if not game_private.rate('district_read',120) then raise exception 'Wait a moment before refreshing.'; end if;
 s:=game_private.season_guard(false);
 perform game_private.ensure_districts(s);
 manage:=game_private.has_permission('districts.manage');
 if p_slug is not null then
  select * into d from public.game_districts where (slug=p_slug or id::text=p_slug) and (archived_at is null or manage);
  if d.id is null then raise exception 'District not found'; end if;
 end if;
 select jsonb_build_object(
 'districts',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object(
  'controller',game_private.district_owner_name('gang',t.controller_gang_id),
  'runtime_status',coalesce(t.status,x.status),
  'available_plots',(select count(*) from public.game_district_plots p where p.season_id=s and p.district_id=x.id and p.status='available' and p.archived_at is null),
  'active_businesses',(select count(*) from public.game_district_businesses b where b.season_id=s and b.district_id=x.id and b.status='open' and b.archived_at is null)) order by x.name)
  from public.game_districts x left join public.game_district_territory t on t.district_id=x.id and t.season_id=s where x.archived_at is null),'[]'::jsonb),
 'district',to_jsonb(d),'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),
 'player_id',auth.uid(),'cash',(select cash from public.game_players where id=auth.uid()),
 'gang_id',(select gang_id from public.game_season_gang_members where season_id=s and player_id=auth.uid()),
 'can_manage',manage,'server_time',now(),
 'plots',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
  'owner_name',game_private.district_owner_name(p.owner_type,p.owner_id),
  'price',coalesce(p.asking_price,ceil(p.base_price*d.property_value_index/100)),
  'tax',coalesce(p.tax_rate,d.tax_rate),
  'watched',exists(select 1 from public.game_plot_watchlists w where w.plot_id=p.id and w.player_id=auth.uid())) order by p.code)
 from public.game_district_plots p where p.district_id=d.id and p.season_id=s and p.archived_at is null),'[]'::jsonb),
 'buildings',coalesce((select jsonb_agg(b) from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where p.district_id=d.id and b.season_id=s and b.archived_at is null),'[]'::jsonb),
 'businesses',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('owner_name',game_private.district_owner_name(b.owner_type,b.owner_id)) order by b.name) from public.game_district_businesses b where b.district_id=d.id and b.season_id=s and b.archived_at is null),'[]'::jsonb),
 'sites',coalesce((select jsonb_agg(x order by x.name) from public.game_district_sites x where x.district_id=d.id and x.season_id=s and x.archived_at is null),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(e order by e.id desc) from (
  select e.*,game_private.district_owner_name('player',e.actor_id) as actor_name from public.game_district_events e
  left join public.game_district_event_visibility v on v.event_id=e.id
  where e.season_id=s and (d.id is null or e.district_id=d.id) and (p_before is null or e.id<p_before) and (not coalesce(v.hidden,false) or manage)
  order by e.id desc limit 100) e),'[]'::jsonb),
 'territory',coalesce((select to_jsonb(t)||jsonb_build_object('controller_name',case when t.controller_gang_id is null then 'Neutral' else game_private.district_owner_name('gang',t.controller_gang_id) end)
 from public.game_district_territory t where t.season_id=s and t.district_id=d.id),'{}'::jsonb),
 'influence',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('name',g.name) order by c.influence desc) from public.game_district_gang_control c join public.game_season_gangs g on g.id=c.gang_id where c.season_id=s and c.district_id=d.id),'[]'::jsonb),
 'wars',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object(
 'parties',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('name',g.name)) from public.game_district_war_parties p join public.game_season_gangs g on g.id=p.gang_id where p.war_id=w.id),'[]'::jsonb),
 'operations',coalesce((select jsonb_agg(o order by o.created_at desc) from public.game_district_operations o where o.war_id=w.id),'[]'::jsonb))) from public.game_district_wars w where w.season_id=s and w.district_id=d.id and w.status<>'finished'),'[]'::jsonb),
 'auctions',coalesce((select jsonb_agg(a) from public.game_plot_auctions a join public.game_district_plots p on p.id=a.plot_id where p.district_id=d.id and p.season_id=s and a.status='open'),'[]'::jsonb),
 'offers',coalesce((select jsonb_agg(o) from public.game_plot_offers o join public.game_district_plots p on p.id=o.plot_id where p.district_id=d.id and p.season_id=s and o.status='open' and (o.buyer_id=auth.uid() or o.seller_id=auth.uid())),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(x order by x.created_at desc) from (select ps.* from public.game_property_sales ps join public.game_district_plots p on p.id=ps.plot_id where p.district_id=d.id and ps.season_id=s order by ps.created_at desc limit 50) x),'[]'::jsonb),
 'market',coalesce((select jsonb_agg(l order by l.created_at desc) from public.game_listings l where l.district_id=d.id and l.season_id=s and l.status='active'),'[]'::jsonb),
 'trades',coalesce((select jsonb_agg(x order by x.created_at desc) from (select * from public.game_district_trades where district_id=d.id and season_id=s order by created_at desc limit 100) x),'[]'::jsonb),
 'market_volume',coalesce((select sum(quantity*unit_price) from public.game_district_trades where district_id=d.id and season_id=s),0),
 'building_types',(select coalesce(jsonb_agg(b order by b.cost),'[]'::jsonb) from public.game_building_types b where b.active),
 'zoning',(select coalesce(jsonb_agg(z),'[]'::jsonb) from public.game_zoning z),
 'goods',(select jsonb_agg(g) from public.game_goods g),
 'jobs',coalesce((select jsonb_agg(j) from public.game_jobs j join public.game_district_jobs dj on dj.job_id=j.id where dj.district_id=d.id),'[]'::jsonb),
 'job_ready_at',(select job_ready_at from public.game_players where id=auth.uid()),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'district_%'),
 'management',case when manage then jsonb_build_object(
  'districts',(select coalesce(jsonb_agg(x order by name),'[]'::jsonb) from public.game_districts x),
  'templates',(select coalesce(jsonb_agg(x order by code),'[]'::jsonb) from public.game_plot_templates x where d.id is null or x.district_id=d.id),
  'site_templates',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.game_district_site_templates x where d.id is null or x.district_id=d.id),
  'entities',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.game_district_entities x),
  'gangs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]'::jsonb) from public.game_season_gangs where season_id=s)) else null end
 ) into result;
 return result;
end $$;
create function public.district_state(p_slug text default null,p_before bigint default null) returns jsonb language sql security invoker set search_path='' as $$ select game_private.district_state(p_slug,p_before) $$;
revoke all on function game_private.district_immutable(),game_private.district_owner_name(text,uuid),game_private.district_event(uuid,text,text,text,uuid,uuid,uuid,jsonb),game_private.ensure_districts(uuid),game_private.district_state(text,bigint),public.district_state(text,bigint) from public,anon,authenticated;
grant execute on function game_private.district_state(text,bigint),public.district_state(text,bigint) to authenticated;
