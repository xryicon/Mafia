
insert into public.game_zoning(id,name,allowed_buildings) values
 ('industrial','Industrial',array['warehouse','workshop','foundry','distillery']),
 ('commercial','Commercial',array['warehouse','logistics','workshop']),
 ('civic','Civic',array['telegram','harbor']),
 ('waterfront','Waterfront',array['warehouse','logistics','harbor']);
insert into public.game_building_types(id,name,cost,construction_seconds,business_type,good_id,batch_size,cycle_seconds,telegram_fee) values
 ('warehouse','Warehouse',3000,300,'Storage',null,0,3600,null),
 ('workshop','Textile Workshop',5000,600,'Manufacturing','silk',2,300,null),
 ('foundry','Ironworks',8000,900,'Industrial Factory','steel',2,300,null),
 ('distillery','Distillery',4000,600,'Distillery','whiskey',3,300,null),
 ('logistics','Logistics Office',3500,300,'Logistics',null,0,3600,null),
 ('telegram','Telegram Office',6000,600,'Communications',null,0,3600,25),
 ('harbor','Harbor Terminal',12000,1800,'Shipping',null,0,3600,null);
do $$
declare d uuid; city uuid; company uuid; p uuid; n integer; col integer; rownum integer; x integer; y integer; s uuid;
begin
 perform set_config('game.reason','Founding Waterfront district catalog',true);
 insert into public.game_district_entities(name,entity_type) values('Blackwater Port Authority','city') returning id into city;
 insert into public.game_district_entities(name,entity_type) values('Waterfront Trading Company','company') returning id into company;
 insert into public.game_districts(slug,name,description,tagline,district_type,industries,strategic_importance,tax_rate,city_polygon,map_data)
 values('the-waterfront','The Waterfront','Cargo arrives under cover of darkness. Own the warehouses, supply the workshops, and decide what the city pays.',
 'Trade fuels influence.','waterfront',array['Shipping','Warehousing','Logistics','Manufacturing'],
 'The harbour connects Blackwater to the outside world. Land, production and player trade build lasting influence.',3,
 '[[104,343],[240,326],[425,400],[518,490],[430,548],[230,523],[95,440]]',
 '{"water_label":"BLACKWATER HARBOR","street_labels":["WHARF ROAD","COPPER QUAY","DOCK STREET"],"accent":"#83b5c8"}') returning id into d;
 for n in 1..24 loop
  col:=(n-1)%6;rownum:=(n-1)/6;x:=90+col*140+rownum*25;y:=120+rownum*130;
  insert into public.game_plot_templates(district_id,code,polygon,size,zoning,status,base_price,utility_level,infrastructure_level,build_capacity,strategic_type,entity_id,building_type,business_name,description)
  values(d,'W'||lpad(n::text,2,'0'),jsonb_build_array(jsonb_build_array(x,y),jsonb_build_array(x+116,y),jsonb_build_array(x+138,y+94),jsonb_build_array(x+22,y+94)),
  800+n*100,case when n in (6,23) then 'civic' when n%3=0 then 'commercial' when n>=19 then 'waterfront' else 'industrial' end,
  case when n<=6 then 'owned' when n in (21,23) then 'reserved' when n=24 then 'locked' else 'available' end,
  3000+n*500,case when n<=12 then 80 else 60 end,70,3,
  case when n=23 then 'Harbor terminal' when n=6 then 'Telegram office' end,
  case when n<=3 or n=6 then city when n<=6 then company end,
  case n when 1 then 'warehouse' when 2 then 'logistics' when 3 then 'foundry' when 4 then 'workshop' when 5 then 'distillery' when 6 then 'telegram' end,
  case n when 1 then 'Copper Quay Warehouses' when 2 then 'Waterfront Freight Office' when 3 then 'Dockside Ironworks' when 4 then 'Salt & Silk Workshop' when 5 then 'Lantern Row Distillery' when 6 then 'Waterfront Telegram Office' end,
  case n when 6 then 'The district communications exchange. Current office fees are published here.' when 1 then 'Secure storage near the quayside.' else 'A registered Waterfront enterprise.' end) returning id into p;
  if n=23 then
   insert into public.game_district_site_templates(district_id,plot_template_id,name,kind,resource_type,data)
   values(d,p,'Harbor Terminal','strategic','harbor','{"capacity":120,"unit":"cargo lots / day","survey_status":"Established","description":"The deep-water entrance to Blackwater. A key route for freight and district influence."}');
  elsif n=1 then
   insert into public.game_district_site_templates(district_id,plot_template_id,name,kind,resource_type,data)
   values(d,p,'Copper Quay Storage','resource','warehouse','{"capacity":50000,"unit":"goods","survey_status":"Surveyed","description":"Warehouse capacity available in the district."}');
  end if;
 end loop;
 insert into public.game_district_site_templates(district_id,name,kind,resource_type,data) values
 (d,'Deep-water Berths','resource','dock','{"capacity":12,"unit":"berths","survey_status":"Surveyed","description":"Commercial docking infrastructure."}'),
 (d,'North Bridge Checkpoint','strategic','checkpoint','{"description":"Road connection between the Waterfront and central Blackwater.","fortification":0}');
 insert into public.game_district_jobs(district_id,job_id) values(d,'docks'),(d,'warehouse');
 s:=game_private.current_season();
 perform game_private.ensure_districts(s);
 insert into public.game_district_events(season_id,district_id,category,event_type,description)
 values(s,d,'system','district_opening','The Waterfront land registry opened. Plots and businesses are available to inspect.');
end $$;
