-- Active, replay-safe vehicle dismantling with shared player-owned bays.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce active chop shops',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('chop_shop_cost',5000,0,1000000000),('chop_upgrade_cost',4000,0,1000000000),('chop_city_fee',350,0,1000000),('chop_max_fee',300,0,1000000),('chop_heat_per_part',4,0,100),('chop_idle_seconds',300,60,3600);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots) values
 ('salvaged-wheels','Salvaged wheels','Chop shop',1,1,60,false,'materials','Wheels actively removed from a stolen car. Trade or store them.',1500,'{}'),
 ('salvaged-doors','Salvaged doors','Chop shop',1,1,60,false,'materials','Doors actively removed from a stolen car. Trade or store them.',2000,'{}'),
 ('car-battery','Car battery','Chop shop',1,1,60,false,'materials','A salvaged vehicle battery. Trade or store it.',1000,'{}'),
 ('salvaged-engine','Salvaged engine','Chop shop',1,1,60,false,'materials','An engine lifted from a dismantled car. Trade or store it.',5000,'{}');
insert into public.game_season_valuations(season_id,good_id,unit_value) select s.id,g.id,0 from public.game_seasons s cross join public.game_goods g where g.id in('salvaged-wheels','salvaged-doors','car-battery','salvaged-engine') on conflict do nothing;
alter table game_private.street_vehicles drop constraint street_vehicles_status_check;
alter table game_private.street_vehicles add constraint street_vehicles_status_check check(status in('escaping','stored','sold','seized','abandoned','dismantling','stripped'));
create table game_private.chop_shops(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),owner_id uuid references public.game_players(id),building_id uuid unique references public.game_district_buildings(id),district_id uuid not null references public.game_districts(id),bays integer not null default 2 check(bays in(2,4,6)),fee bigint not null default 100 check(fee>=0),check((owner_id is null)=(building_id is null)));
create unique index chop_city_per_season on game_private.chop_shops(season_id) where owner_id is null;
create table game_private.chop_jobs(id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),shop_id uuid not null references game_private.chop_shops(id),vehicle_id uuid not null unique references game_private.street_vehicles(id),status text not null check(status in('queued','active','paused','done')),fee bigint not null,removed text[] not null default '{}',part text,step integer not null default 0 check(step between 0 and 5),token uuid not null default gen_random_uuid(),next_at timestamptz not null default clock_timestamp(),last_active timestamptz not null default clock_timestamp(),queued_at timestamptz not null default clock_timestamp(),created_at timestamptz not null default clock_timestamp());
create index chop_bay_queue on game_private.chop_jobs(shop_id,status,queued_at,id);
create unique index chop_one_job on game_private.chop_jobs(season_id,player_id) where status<>'done';
create table game_private.chop_requests(season_id uuid not null,player_id uuid not null,request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,primary key(season_id,player_id,request_id));
do $$declare t text;begin foreach t in array array['chop_shops','chop_jobs','chop_requests'] loop execute format('alter table game_private.%I enable row level security',t);execute format('revoke all on game_private.%I from public,anon,authenticated',t);end loop;end$$;
create trigger chop_shop_audit after insert or update on game_private.chop_shops for each row execute function game_private.audit_change();
create trigger chop_job_audit after insert or update on game_private.chop_jobs for each row execute function game_private.audit_change();
create trigger chop_receipt_retain before update or delete or truncate on game_private.chop_requests for each statement execute function game_private.district_immutable();
create function game_private.chop_shop_open(shop game_private.chop_shops) returns boolean language sql stable security definer set search_path='' as $$
 select shop.owner_id is null or exists(select 1 from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where b.id=shop.building_id and b.season_id=shop.season_id and b.owner_type='player' and b.owner_id=shop.owner_id and p.owner_type='player' and p.owner_id=shop.owner_id and b.archived_at is null and p.archived_at is null and b.building_type='garage' and b.construction_status='ready' and b.condition>0 and p.asking_price is null and not exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') and not exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open'));
$$;
create function game_private.chop_tick(s uuid) returns void language plpgsql security definer set search_path='' as $$
declare shop game_private.chop_shops;slots integer;begin
 update game_private.chop_jobs set status='paused' where season_id=s and status in('active','queued') and last_active<clock_timestamp()-make_interval(secs=>game_private.setting('chop_idle_seconds'));
 for shop in select * from game_private.chop_shops where season_id=s loop
  if not game_private.chop_shop_open(shop) then update game_private.chop_jobs set status='paused' where shop_id=shop.id and status in('active','queued');continue;end if;
  slots:=case when shop.owner_id is null then 1000000 else shop.bays-(select count(*) from game_private.chop_jobs where shop_id=shop.id and status='active') end;
  update game_private.chop_jobs set status='active',last_active=clock_timestamp() where id in(select id from game_private.chop_jobs where shop_id=shop.id and status='queued' order by queued_at,id limit greatest(0,slots));
 end loop;
end$$;
create function public.chop_shop_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();loc jsonb;begin
 perform game_private.require_active();perform pg_advisory_xact_lock(4704020);s:=game_private.season_guard(false);loc:=game_private.travel_state();
 insert into game_private.chop_shops(season_id,district_id) select s,id from public.game_districts where slug='the-waterfront' on conflict do nothing;
 perform game_private.chop_tick(s);
 -- Queue presence does not count as dismantling activity in an occupied bay.
 update game_private.chop_jobs set last_active=clock_timestamp() where season_id=s and player_id=u and status='queued';
 return jsonb_build_object('season_id',s,'player_id',u,'location',loc,'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'chop_%'),
 'shops',(select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select c.*,coalesce(p.code,'City chop shop') name,d.name district_name,d.slug district_slug,game_private.chop_shop_open(c) available,(select count(*) from game_private.chop_jobs where shop_id=c.id and status='active') occupied,(select count(*) from game_private.chop_jobs where shop_id=c.id and status='queued') queued from game_private.chop_shops c join public.game_districts d on d.id=c.district_id left join public.game_district_buildings b on b.id=c.building_id left join public.game_district_plots p on p.id=b.plot_id where c.season_id=s)x),
 'garages',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'name',p.code)),'[]') from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where b.season_id=s and b.owner_type='player' and b.owner_id=u and b.building_type='garage' and b.archived_at is null and b.construction_status='ready' and game_private.property_access(s,u,b.id,true) and not exists(select 1 from game_private.chop_shops where building_id=b.id)),
 'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'sale_value',sale_value)),'[]') from game_private.street_vehicles where season_id=s and player_id=u and status='stored'),
 'job',(select to_jsonb(j)||jsonb_build_object('vehicle_name',v.name,'queue_position',(select count(*) from game_private.chop_jobs q where q.shop_id=j.shop_id and q.status='queued' and (q.queued_at,q.id)<=(j.queued_at,j.id))) from game_private.chop_jobs j join game_private.street_vehicles v on v.id=j.vehicle_id where j.season_id=s and j.player_id=u and j.status<>'done'));
end$$;
create function public.chop_shop_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;old game_private.chop_requests;shop game_private.chop_shops;j game_private.chop_jobs;v game_private.street_vehicles;b public.game_district_buildings;loc jsonb;result jsonb;fee bigint;item text;qty integer;target uuid;begin
 perform game_private.require_active();perform pg_advisory_xact_lock(4704020);s:=game_private.season_guard();
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid chop shop request.';end if;
 nonce:=(p_payload->>'request_id')::uuid;if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh this season first.';end if;
 select * into old from game_private.chop_requests where season_id=s and player_id=u and request_id=nonce;
 if found then if old.action<>p_action or old.payload<>p_payload then raise exception 'Request reference already used.';end if;return old.result;end if;
 if not game_private.rate('chop_shop',120) then raise exception 'Slow down before continuing.';end if;
 loc:=game_private.travel_state();if (loc->>'jailed')::boolean or loc->'journey'<>'null'::jsonb then raise exception 'Arrive at the shop and be out of prison first.';end if;
 if exists(select 1 from game_private.scav_sessions where season_id=s and player_id=u and (pending is not null or pursuit is not null or arrives_at>clock_timestamp())) then raise exception 'Finish your street action first.';end if;
 perform game_private.chop_tick(s);perform set_config('game.reason','Chop shop: '||p_action||' '||nonce,true);
 if p_action='open' then
  select * into b from public.game_district_buildings where id=(p_payload->>'building_id')::uuid and season_id=s and owner_type='player' and owner_id=u and building_type='garage' and archived_at is null and construction_status='ready';
  if not found or not game_private.property_access(s,u,b.id,true) then raise exception 'Choose your own ready garage.';end if;
  select district_id into target from public.game_district_plots where id=b.plot_id;
  if target is distinct from (loc#>>'{current,id}')::uuid then raise exception 'Travel to your garage district first.';end if;
  if exists(select 1 from game_private.chop_shops where building_id=b.id) then raise exception 'This garage already has a shop.';end if;
  perform game_private.district_wallet(u,-game_private.setting('chop_shop_cost'),'Open chop shop: '||nonce);
  insert into game_private.chop_shops(season_id,owner_id,building_id,district_id) values(s,u,b.id,target) returning * into shop;
  if not game_private.chop_shop_open(shop) then raise exception 'This garage is unavailable or being sold.';end if;
  result:=jsonb_build_object('message','Chop shop opened with two bays.');
 elsif p_action in('fee','upgrade') then
  select * into shop from game_private.chop_shops where id=(p_payload->>'shop_id')::uuid and season_id=s and owner_id=u for update;
  if not found or not game_private.chop_shop_open(shop) then raise exception 'Choose your own available shop.';end if;
  if p_action='fee' then fee:=(p_payload->>'fee')::bigint;if fee is null or fee<0 or fee>game_private.setting('chop_max_fee') then raise exception 'Fee is outside the allowed range.';end if;
   update game_private.chop_shops c set fee=(p_payload->>'fee')::bigint where c.id=shop.id;
  else if shop.bays>=6 then raise exception 'This shop already has six bays.';end if;perform game_private.district_wallet(u,-game_private.setting('chop_upgrade_cost'),'Upgrade chop shop: '||nonce);update game_private.chop_shops set bays=bays+2 where id=shop.id;end if;
  result:=jsonb_build_object('message','Shop updated.');
 elsif p_action='start' then
  select * into shop from game_private.chop_shops where id=(p_payload->>'shop_id')::uuid and season_id=s for update;
  if not found or not game_private.chop_shop_open(shop) then raise exception 'Shop unavailable.';end if;
  if shop.district_id is distinct from (loc#>>'{current,id}')::uuid then raise exception 'Travel to the shop district first.';end if;
  if exists(select 1 from game_private.chop_jobs where season_id=s and player_id=u and status<>'done') then raise exception 'Finish your existing car first.';end if;
  select * into v from game_private.street_vehicles where id=(p_payload->>'vehicle_id')::uuid and season_id=s and player_id=u and status='stored' for update;
  if not found then raise exception 'Choose your own stored car.';end if;
  fee:=case when shop.owner_id=u then 0 when shop.owner_id is null then game_private.setting('chop_city_fee') else shop.fee end;
  if (p_payload->>'fee')::bigint is distinct from fee then raise exception 'The fee changed. Review it before starting.';end if;
  perform game_private.district_wallet(u,-fee,'Chop shop entry: '||nonce);
  if shop.owner_id is not null and shop.owner_id<>u and fee>0 then perform game_private.district_wallet(shop.owner_id,fee,'Chop shop customer: '||nonce);end if;
  update game_private.street_vehicles set status='dismantling',building_id=null where id=v.id;
  insert into game_private.chop_jobs(season_id,player_id,shop_id,vehicle_id,status,fee) values(s,u,shop.id,v.id,'queued',fee) returning * into j;
  perform game_private.chop_tick(s);result:=jsonb_build_object('message','Car committed to dismantling. Your fee is paid once.');
 else
  select * into j from game_private.chop_jobs where id=(p_payload->>'job_id')::uuid and season_id=s and player_id=u and status<>'done' for update;
  if not found then raise exception 'Job unavailable.';end if;
  select * into shop from game_private.chop_shops where id=j.shop_id;
  -- A closed/sold shop cannot trap salvage: the customer may finish its shell.
  if p_action<>'finish' and not game_private.chop_shop_open(shop) then raise exception 'Shop unavailable. You may scrap the remaining shell.';end if;
  if shop.district_id is distinct from (loc#>>'{current,id}')::uuid then raise exception 'Return to the shop district first.';end if;
  if p_action='pause' then update game_private.chop_jobs set status='paused' where id=j.id;result:=jsonb_build_object('message','Progress saved in paused storage. Bay released.');
  elsif p_action='resume' then
   if j.status<>'paused' then raise exception 'Only a paused job can rejoin the queue.';end if;
   update game_private.chop_jobs set status='queued',queued_at=clock_timestamp(),last_active=clock_timestamp() where id=j.id;perform game_private.chop_tick(s);result:=jsonb_build_object('message','Rejoined the queue with your saved progress.');
  elsif p_action='finish' then
   perform set_config('game.inventory_request',nonce::text,true);
   insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'scrap-metal',2) on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
   perform game_private.inventory_sync(s,u);update game_private.chop_jobs set status='done' where id=j.id;update game_private.street_vehicles set status='stripped' where id=j.vehicle_id;
   result:=jsonb_build_object('message','Shell scrapped. Received 2 scrap metal.');
  elsif p_action='select' then
   if j.status<>'active' or j.part is not null then raise exception 'Wait for a bay or finish the current part.';end if;
   item:=p_payload->>'part';if item is null or item not in('wheels','doors','battery','engine') or item=any(j.removed) then raise exception 'Choose an attached part.';end if;
   if item='engine' and not 'battery'=any(j.removed) then raise exception 'Remove the battery before the engine.';end if;
   update game_private.chop_jobs set part=item,step=0,token=gen_random_uuid(),next_at=clock_timestamp()+interval '0.5 seconds',last_active=clock_timestamp() where id=j.id;
   result:=jsonb_build_object('message','Undo the highlighted fasteners, release the fittings, then lift the part.');
  elsif p_action='work' then
   if j.status<>'active' or j.part is null or (p_payload->>'token')::uuid is distinct from j.token or (p_payload->>'step')::integer is distinct from j.step then raise exception 'Refresh the current removal step.';end if;
   if clock_timestamp()<j.next_at then raise exception 'Finish the tool movement before the next step.';end if;
   if j.step=5 then
    item:=case j.part when 'wheels' then 'salvaged-wheels' when 'doors' then 'salvaged-doors' when 'battery' then 'car-battery' when 'engine' then 'salvaged-engine' end;qty:=case j.part when 'wheels' then 4 when 'doors' then 2 else 1 end;
    perform set_config('game.inventory_request',nonce::text,true);
    insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,item,qty) on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
    perform game_private.inventory_sync(s,u);
    insert into game_private.scav_district_heat(season_id,player_id,district_id,heat) values(s,u,shop.district_id,game_private.setting('chop_heat_per_part')) on conflict(season_id,player_id,district_id) do update set heat=least(100,game_private.scav_heat_value(scav_district_heat.heat,scav_district_heat.updated_at,clock_timestamp())+game_private.setting('chop_heat_per_part')),updated_at=clock_timestamp();
    update game_private.chop_jobs set removed=array_append(removed,part),part=null,step=0,token=gen_random_uuid(),last_active=clock_timestamp() where id=j.id;
    result:=jsonb_build_object('message','Part removed and added to inventory. District heat increased.');
   else update game_private.chop_jobs set step=step+1,token=gen_random_uuid(),next_at=clock_timestamp()+interval '0.5 seconds',last_active=clock_timestamp() where id=j.id;result:=jsonb_build_object('message','Fastener released. Continue removing the part.');end if;
  else raise exception 'Unknown shop action.';end if;
  perform game_private.chop_tick(s);
 end if;
 insert into game_private.chop_requests values(s,u,nonce,p_action,p_payload,result);return result;
exception when raise_exception then return jsonb_build_object('error',SQLERRM);when invalid_text_representation or numeric_value_out_of_range or check_violation or unique_violation or not_null_violation then return jsonb_build_object('error','The car or shop changed. Refresh and try again.');end$$;
revoke all on function game_private.chop_shop_open(game_private.chop_shops),game_private.chop_tick(uuid),public.chop_shop_state(),public.chop_shop_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.chop_shop_state(),public.chop_shop_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';
