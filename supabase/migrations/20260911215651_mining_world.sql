-- Register the districts pictured on the existing dashboard. No invented player holdings or revenue.
select set_config('game.reason','Open dashboard districts and Mines & Quarries',true);
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('mines-and-quarries','Mines & Quarries','mining','Raw materials build Blackwater.','Iron, stone, coal and copper run beneath these hills. Work a public claim or own the extraction rights that supply the city.','/art/mining/map.webp',array['Iron mining','Quarrying','Coal','Copper'],'Iron, stone, coal and copper run beneath these hills. Work a public claim or own the extraction rights that supply the city.','[[12,143],[75,54],[202,31],[313,117],[334,199],[256,221],[160,239],[45,203]]'::jsonb,'{"atlas_key":"mines-and-quarries","transport":"Rail + road"}'::jsonb) on conflict(slug) do nothing;
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('old-town','Old Town','urban','Every street has a story.','Old workshops and narrow streets form Blackwater’s oldest neighborhood. Explore its registry, trade locally and build gang influence.','/art/command-city.jpg',array['Workshops','Local trade'],'Old workshops and narrow streets form Blackwater’s oldest neighborhood. Explore its registry, trade locally and build gang influence.','[[40,300],[138,224],[283,216],[386,274],[470,343],[457,397],[380,416],[252,409],[132,399],[37,361]]'::jsonb,'{"atlas_key":"old-town","transport":"City roads"}'::jsonb) on conflict(slug) do nothing;
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('downtown','Downtown','commercial','Ambition has an address.','Blackwater’s commercial heart connects players, property and commerce. Shape the next deal in the city registry.','/art/command-city.jpg',array['Commerce','Player trade'],'Blackwater’s commercial heart connects players, property and commerce. Shape the next deal in the city registry.','[[515,241],[581,201],[650,226],[711,289],[787,316],[791,394],[731,450],[637,454],[559,404],[497,363]]'::jsonb,'{"atlas_key":"downtown","transport":"City roads"}'::jsonb) on conflict(slug) do nothing;
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('industrial-quarter','Industrial Quarter','industrial','Supply makes the city move.','Factories and rail yards connect industry to the harbor. Find local market orders and establish your influence.','/art/command-city.jpg',array['Manufacturing','Production','Freight'],'Factories and rail yards connect industry to the harbor. Find local market orders and establish your influence.','[[858,226],[965,180],[1070,243],[1177,264],[1196,377],[1130,451],[980,500],[862,479],[822,394],[790,309]]'::jsonb,'{"atlas_key":"industrial-quarter","transport":"City roads"}'::jsonb) on conflict(slug) do nothing;
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('blackwater-island','Blackwater Island','island','Across the water. Above the noise.','The island holds a strategic position in Blackwater harbor. Follow its territory and local economy as the city grows.','/art/command-city.jpg',array['Strategic land','Harbor services'],'The island holds a strategic position in Blackwater harbor. Follow its territory and local economy as the city grows.','[[558,73],[641,39],[753,50],[820,117],[756,181],[641,166],[565,137]]'::jsonb,'{"atlas_key":"blackwater-island","transport":"City roads"}'::jsonb) on conflict(slug) do nothing;
insert into public.game_districts(slug,name,district_type,tagline,description,image_url,industries,strategic_importance,city_polygon,map_data) values ('drilling-shore','Drilling Shore','energy','Fortunes beneath the surface.','An exposed stretch of Blackwater’s coast marked for the energy trade. Explore its registry, local market and territory.','/art/command-city.jpg',array['Energy','Export routes'],'An exposed stretch of Blackwater’s coast marked for the energy trade. Explore its registry, local market and territory.','[[948,603],[1030,520],[1147,566],[1169,684],[1090,750],[954,710]]'::jsonb,'{"atlas_key":"drilling-shore","transport":"City roads"}'::jsonb) on conflict(slug) do nothing;

insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available) values
 ('iron-ore','Iron ore','Mine extraction',1,1,60,false),
 ('stone','Stone','Quarry extraction',1,1,60,false),
 ('copper-ore','Copper ore','Mine extraction',1,1,60,false),
 ('coal','Coal','Mine extraction',1,1,60,false),
 ('limestone','Limestone','Quarry extraction',1,1,60,false)
 on conflict(id) do nothing;
insert into public.game_district_entities(name,entity_type) values('Blackwater Mining Authority','city') on conflict(name) do nothing;
insert into public.game_zoning(id,name,allowed_buildings) values('extraction','Mineral extraction','{}') on conflict(id) do nothing;
do $$
declare d uuid; city uuid; p uuid; v record;
begin
 select id into strict d from public.game_districts where slug='mines-and-quarries';
 select id into strict city from public.game_district_entities where name='Blackwater Mining Authority';
 for v in select * from (values
 ('MQ-01','North Ridge Iron Mine','iron-ore','open','public',2000000,4,60,40,300,200,125,125000,'mine'),
 ('MQ-02','Crown Stone Quarry','stone','open','public',2400000,6,60,60,300,515,150,100000,'quarry'),
 ('MQ-03','Copperhead Mine','copper-ore','closed','private',1300000,3,90,30,300,970,140,160000,'mine'),
 ('MQ-04','East Quarry','limestone','open','private',1600000,5,60,50,300,1040,300,115000,'quarry'),
 ('MQ-05','Blackrock Coal Mine','coal','open','public',1800000,5,60,50,300,615,290,130000,'mine'),
 ('MQ-06','Westbank Limestone','limestone','closed','private',1200000,5,60,50,300,170,285,110000,'quarry'),
 ('MQ-07','Southern Claim','iron-ore','reserved','private',900000,3,90,30,300,365,398,175000,'mine'),
 ('MQ-08','Deep Rock Claim','stone','reserved','private',1500000,4,90,40,300,660,476,180000,'quarry'),
 ('MQ-09','High Ridge Claim','copper-ore','closed','private',1000000,3,90,30,300,960,442,155000,'mine'),
 ('MQ-10','Riverbed Quarry','stone','open','public',800000,6,60,60,300,800,555,90000,'quarry')
 ) as v(code,name,good,status,access,reserve,hand_yield,hand_seconds,op_yield,op_seconds,x,y,price,art) loop
  insert into public.game_plot_templates(district_id,code,polygon,size,zoning,status,base_price,utility_level,infrastructure_level,build_capacity,strategic_type,entity_id,description)
  values(d,v.code,jsonb_build_array(jsonb_build_array(v.x-65,v.y-40),jsonb_build_array(v.x+65,v.y-40),jsonb_build_array(v.x+65,v.y+30),jsonb_build_array(v.x-65,v.y+30)),3200,'extraction','owned',v.price,60,70,1,'Mining claim',city,v.name)
  on conflict(district_id,code) do nothing;
  select id into strict p from public.game_plot_templates where district_id=d and code=v.code;
  insert into public.game_mine_definitions(plot_template_id,name,description,good_id,image_url,map_x,map_y,initial_status,initial_access,initial_reserve,hand_yield,hand_seconds,operation_yield,operation_seconds,survey_status)
  values(p,v.name,'A registered extraction site in the Blackwater hills. Gather raw materials and supply the player economy.',v.good,'/art/mining/'||v.art||'.webp',v.x,v.y,v.status,v.access,v.reserve,v.hand_yield,v.hand_seconds,v.op_yield,v.op_seconds,case when v.status='reserved' then 'Reserved for future release' else 'Surveyed' end)
  on conflict(plot_template_id) do nothing;
 end loop;
 insert into public.game_district_site_templates(district_id,name,kind,resource_type,data)
 values(d,'Rail Loading Terminal','strategic','rail','{"transport":"Rail + road","description":"City-owned freight infrastructure connecting the mines to Blackwater."}')
 on conflict do nothing;
end $$;
select game_private.ensure_districts(game_private.current_season());
insert into public.game_district_events(season_id,district_id,category,event_type,description,plot_id,metadata)
select m.season_id,p.district_id,'resources','mine_registered',def.name||' registered · '||m.status||' · '||m.access_mode||' access',p.id,jsonb_build_object('mine_id',m.id)
from public.game_mines m join public.game_mine_definitions def on def.id=m.definition_id join public.game_district_plots p on p.id=m.plot_id
where m.season_id=game_private.current_season() and not exists(select 1 from public.game_district_events e where e.plot_id=p.id and e.event_type='mine_registered');

insert into public.game_season_valuations(season_id,good_id,unit_value)
select s.id,v.good_id,v.unit_value from public.game_seasons s cross join (values ('iron-ore',30),('stone',15),('copper-ore',45),('coal',25),('limestone',12)) v(good_id,unit_value)
where s.status in ('draft','open','locked') on conflict do nothing;
