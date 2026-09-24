begin;
create function pg_temp.verify(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
do $$declare users uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()];u uuid;s uuid;home uuid;city uuid;shop uuid;bid uuid;pid uuid;v uuid;j uuid;req jsonb;r jsonb;first jsonb;cash0 bigint;owner_cash bigint;i integer;k integer;part text;begin
 foreach u in array users loop insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();end loop;
 s:=game_private.current_season();select id into home from public.game_districts where slug='the-waterfront';perform set_config('game.reason','Chop integration test',true);update public.game_players set cash=100000 where id=any(users);
 perform set_config('request.jwt.claim.sub',users[1]::text,true);r:=public.chop_shop_state();select id into city from game_private.chop_shops where season_id=s and owner_id is null;
 -- Own a ready garage and open a two-bay business.
 select b.id,p.id into bid,pid from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where p.season_id=s and p.code='W25';
 -- Earlier integration fixtures can occupy W25. Vacate only this rolled-back test property, preserving the live transfer guards.
 update public.game_property_leases set released_at=clock_timestamp() where plot_id=pid and released_at is null;
 update public.game_property_stations set removed_at=clock_timestamp() where building_id=bid and removed_at is null;
 update public.game_district_plots set owner_type='player',owner_id=users[1],asking_price=null where id=pid;update public.game_district_buildings set owner_type='player',owner_id=users[1] where id=bid;
 req:=jsonb_build_object('season_id',s,'building_id',bid,'request_id',gen_random_uuid());
 set local role authenticated;first:=public.chop_shop_action('open',req);reset role;perform pg_temp.verify(not first?'error','Open failed '||first::text);perform pg_temp.verify(public.chop_shop_action('open',req)=first,'Open replay failed');
 select id into shop from game_private.chop_shops where building_id=bid;perform pg_temp.verify((select bays=2 from game_private.chop_shops where id=shop),'Wrong bay count');
 r:=public.chop_shop_action('fee',jsonb_build_object('season_id',s,'shop_id',shop,'fee',125,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','Fee save failed '||r::text);
 select cash into owner_cash from public.game_players where id=users[1];
 -- Three customers: two work, one queues, fees pay once.
 for i in 2..4 loop
  u:=users[i];perform set_config('request.jwt.claim.sub',u::text,true);perform public.chop_shop_state();
  insert into game_private.street_vehicles(season_id,player_id,district_id,model_id,name,sale_value,status,source_id) values(s,u,home,'coupe','Test coupe',1500,'stored',gen_random_uuid()) returning id into v;
  req:=jsonb_build_object('season_id',s,'shop_id',shop,'vehicle_id',v,'fee',125,'request_id',gen_random_uuid());
  r:=public.chop_shop_action('start',req||'{"fee":0}');perform pg_temp.verify(r?'error','Forged fee allowed');
  set local role authenticated;first:=public.chop_shop_action('start',req);reset role;perform pg_temp.verify(not first?'error','Start failed '||first::text);perform pg_temp.verify(public.chop_shop_action('start',req)=first,'Entry replay failed');
  perform pg_temp.verify((select status='dismantling' from game_private.street_vehicles where id=v),'Car still usable');
 end loop;
 perform pg_temp.verify((select count(*)=2 from game_private.chop_jobs where shop_id=shop and status='active'),'Bay overbooking');perform pg_temp.verify((select count(*)=1 from game_private.chop_jobs where shop_id=shop and status='queued'),'Queue absent');perform pg_temp.verify((select cash=owner_cash+375 from public.game_players where id=users[1]),'Fee transfer wrong');
 -- Customer cannot change business, another job or drive a committed car.
 r:=public.chop_shop_action('upgrade',jsonb_build_object('season_id',s,'shop_id',shop,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Nonowner upgraded');
 select id into j from game_private.chop_jobs where player_id=users[2];
 r:=public.chop_shop_action('pause',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Customer accessed another job');
 r:=public.travel_action('refuel',jsonb_build_object('season_id',s,'vehicle_id',v,'units',1,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Dismantling vehicle refuelled');
 -- Pausing frees the bay to the queued player. Resuming goes to the back.
 perform set_config('request.jwt.claim.sub',users[2]::text,true);r:=public.chop_shop_action('pause',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','Pause failed');perform pg_temp.verify((select status='active' from game_private.chop_jobs where player_id=users[4]),'Queue not promoted');
 r:=public.chop_shop_action('resume',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify((select status='queued' from game_private.chop_jobs where id=j),'Resume bypassed queue');
 update game_private.chop_jobs set last_active=clock_timestamp()-interval '10 minutes' where player_id=users[3];perform public.chop_shop_state();perform pg_temp.verify((select status='active' from game_private.chop_jobs where id=j),'Idle bay not released');
 -- Engine depends on battery; every part must complete all six active steps.
 r:=public.chop_shop_action('select',jsonb_build_object('season_id',s,'job_id',j,'part','engine','request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Engine dependency bypassed');
 foreach part in array array['battery','wheels','doors','engine'] loop
  r:=public.chop_shop_action('select',jsonb_build_object('season_id',s,'job_id',j,'part',part,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','Select failed '||r::text);
  for k in 0..5 loop
   select jsonb_build_object('season_id',s,'job_id',j,'step',step,'token',token,'request_id',gen_random_uuid()) into req from game_private.chop_jobs where id=j;
   if k=0 then r:=public.chop_shop_action('work',req||'{"step":5}');perform pg_temp.verify(r?'error','Skipped fasteners');r:=public.chop_shop_action('work',req);perform pg_temp.verify(r?'error','Tool delay bypassed');end if;
   update game_private.chop_jobs set next_at=clock_timestamp()-interval '1 second' where id=j;
   if part='battery' and k=5 then
    insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,users[2],'scrap-metal',1) on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+1;update public.game_settings set value=1000 where key='inventory_weight_limit_grams';r:=public.chop_shop_action('work',req);perform pg_temp.verify(r?'error','Inventory limit bypassed');perform pg_temp.verify((select cj.step=5 and cj.part='battery' from game_private.chop_jobs cj where cj.id=j),'Failed inventory reward consumed part');update public.game_settings set value=1000000000 where key='inventory_weight_limit_grams';
   end if;
   set local role authenticated;first:=public.chop_shop_action('work',req);reset role;perform pg_temp.verify(not first?'error','Work failed '||first::text);perform pg_temp.verify(public.chop_shop_action('work',req)=first,'Work replay failed');
   r:=public.chop_shop_action('work',req||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Stale token accepted');
  end loop;
 end loop;
 perform pg_temp.verify((select quantity=4 from public.game_inventory where player_id=users[2] and good_id='salvaged-wheels'),'Wrong wheel reward');perform pg_temp.verify((select quantity=1 from public.game_inventory where player_id=users[2] and good_id='salvaged-engine'),'Duplicate engine');perform pg_temp.verify((select heat>15 from game_private.scav_district_heat where player_id=users[2] and district_id=home),'No heat');
 req:=jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid());first:=public.chop_shop_action('finish',req);perform pg_temp.verify(not first?'error','Finish failed '||first::text);perform pg_temp.verify(public.chop_shop_action('finish',req)=first,'Finish replay');perform pg_temp.verify((select status='stripped' from game_private.street_vehicles where id=(select vehicle_id from game_private.chop_jobs where id=j)),'Shell usable');
 -- Owner upgrades and the city offers independent bays.
 perform set_config('request.jwt.claim.sub',users[1]::text,true);for i in 1..2 loop r:=public.chop_shop_action('upgrade',jsonb_build_object('season_id',s,'shop_id',shop,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','Upgrade failed '||r::text);end loop;
 r:=public.chop_shop_action('upgrade',jsonb_build_object('season_id',s,'shop_id',shop,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Exceeded six bays');
 insert into game_private.street_vehicles(season_id,player_id,district_id,model_id,name,sale_value,status,source_id) values(s,users[1],home,'coupe','City test',1500,'stored',gen_random_uuid()) returning id into v;
 r:=public.chop_shop_action('start',jsonb_build_object('season_id',s,'shop_id',city,'vehicle_id',v,'fee',350,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','City start failed '||r::text);perform pg_temp.verify((select status='active' from game_private.chop_jobs where vehicle_id=v),'City bay missing');

 for i in 2..4 loop
  u:=users[i];perform set_config('request.jwt.claim.sub',u::text,true);select id into j from game_private.chop_jobs where player_id=u and status<>'done';
  if j is not null then r:=public.chop_shop_action('finish',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','Early finish failed');end if;
  insert into game_private.street_vehicles(season_id,player_id,district_id,model_id,name,sale_value,status,source_id) values(s,u,home,'coupe','City capacity test',1500,'stored',gen_random_uuid()) returning id into v;
  r:=public.chop_shop_action('start',jsonb_build_object('season_id',s,'shop_id',city,'vehicle_id',v,'fee',350,'request_id',gen_random_uuid()));perform pg_temp.verify(not r?'error','City parallel job failed '||r::text);
 end loop;
 perform pg_temp.verify((select count(*)=4 from game_private.chop_jobs where shop_id=city and status='active'),'City incorrectly shares two bays');
 select id into j from game_private.chop_jobs where player_id=users[4] and status='active';
 update game_private.district_travel set district_id=(select id from public.game_districts where slug='old-town') where player_id=users[4];
 r:=public.chop_shop_action('select',jsonb_build_object('season_id',s,'job_id',j,'part','battery','request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Remote dismantling allowed');
 update game_private.district_travel set district_id=home,destination_id=(select id from public.game_districts where slug='old-town'),arrives_at=clock_timestamp()+interval '1 minute' where player_id=users[4];
 r:=public.chop_shop_action('finish',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Dismantled during travel');
 update public.game_seasons set status='locked',locked_at=clock_timestamp() where id=s;
 r:=public.chop_shop_action('finish',jsonb_build_object('season_id',s,'job_id',j,'request_id',gen_random_uuid()));perform pg_temp.verify(r?'error','Locked season accepted dismantling');
end$$;
rollback;
