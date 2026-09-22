begin;
create function pg_temp.street_check(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
create function pg_temp.street_player(gun boolean default false) returns jsonb language plpgsql as $$
declare u uuid:=gen_random_uuid();s uuid:=game_private.current_season();d uuid;r jsonb;site jsonb;begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 select id into d from public.game_districts where slug='the-waterfront';
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'lockpick',5);
 if gun then
  insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-pistol',1),(s,u,'homemade-bullets',20);
  r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'item_key','good:homemade-pistol','equipment_slot','secondary','request_id',gen_random_uuid()));perform pg_temp.street_check(not r?'error','Equip gun failed '||r::text);
  r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',20,'request_id',gen_random_uuid()));perform pg_temp.street_check(not r?'error','Equip ammo failed '||r::text);
 end if;
 r:=public.scavenging_action('enter',jsonb_build_object('season_id',s,'district_id',d,'request_id',gen_random_uuid()));perform pg_temp.street_check(not r?'error','Entry failed '||r::text);
 select x into site from jsonb_array_elements(public.bin_diving_state()#>'{scavenging,targets}')x where x->>'kind'='car' limit 1;
 return jsonb_build_object('u',u,'s',s,'d',d,'site',site);
end$$;
create function pg_temp.street_steal(f jsonb,bid uuid default null) returns jsonb language plpgsql as $$
declare s uuid:=(f->>'s')::uuid;u uuid:=(f->>'u')::uuid;site jsonb:=f->'site';q jsonb;r jsonb;begin
 update game_private.scav_sessions set node=(site->>'node')::int,route_points=jsonb_build_array(jsonb_build_array((site->>'node')::int%5,(site->>'node')::int/5)),departed_at=clock_timestamp()-interval '2 seconds',arrives_at=clock_timestamp()-interval '1 second' where season_id=s and player_id=u;
 q:=jsonb_build_object('season_id',s,'target_id',site->>'id','request_id',gen_random_uuid(),'garage_id',bid,'sale_value',99999999,'success_percent',100,'xp',999999);
 r:=public.scavenging_action('steal',q);perform pg_temp.street_check(not r?'error','Theft start failed '||r::text);
 perform pg_temp.street_check(public.scavenging_action('steal',q)=r,'Theft start replay changed outcome');
 perform pg_temp.street_check((select quantity from public.game_inventory where player_id=u and good_id='lockpick')=4,'Repeated theft consumed extra tools');
 r:=public.scavenging_action('finish',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'attempt_id',q->>'request_id'));perform pg_temp.street_check(r?'error','Theft finished early');
 update game_private.scav_sessions set pending=jsonb_set(pending,'{ready_at}',to_jsonb(clock_timestamp()-interval '1 second')) where season_id=s and player_id=u;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'attempt_id',q->>'request_id');r:=public.scavenging_action('finish',q);
 perform pg_temp.street_check(not r?'error' and (r->>'pursuit')::boolean,'Theft failed '||r::text);perform pg_temp.street_check(public.scavenging_action('finish',q)=r,'Collection replay changed outcome');
 perform pg_temp.street_check((select count(*) from game_private.street_vehicles where player_id=u)=1,'Theft created duplicate vehicles');
 perform pg_temp.street_check((select sum(delta) from game_private.skill_xp_ledger where player_id=u and skill_id='lockpicking')=60,'Forged or missing theft XP');
 return r;
end$$;
select set_config('game.reason','CI street operations fixtures',true);
update public.game_settings set value=300 where key='actions_per_minute';
update public.game_settings set value=0 where key='scavenging_patrol_enabled';
update public.game_settings set value=100 where key in('scavenging_theft_success_percent','scavenging_combat_escape_percent');
update public.game_settings set value=30 where key in('scavenging_combat_damage_min','scavenging_combat_damage_max');
do $$
declare f jsonb;u uuid;s uuid;d uuid;q jsonb;r jsonb;first jsonb;cash0 bigint;car game_private.street_vehicles;bid uuid;other uuid;denied boolean;weapon jsonb;receipt jsonb;island uuid;event_id uuid;begin
 f:=pg_temp.street_player();u:=(f->>'u')::uuid;s:=(f->>'s')::uuid;d:=(f->>'d')::uuid;
 -- Without a gun the fighting action is unavailable; normal walking has no arrest risk.
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'target_id',f#>>'{site,id}');
 r:=public.scavenging_action('steal',q);perform pg_temp.street_check(r?'error','Theft allowed from another street');
 perform pg_temp.street_steal(f);
 select * into car from game_private.street_vehicles where player_id=u;
 perform pg_temp.street_check(car.sale_value=(f#>>'{site,vehicle,sale_value}')::bigint,'Client controlled vehicle price');
 r:=public.scavenging_action('fight',jsonb_build_object('season_id',s,'request_id',gen_random_uuid()));perform pg_temp.street_check(r?'error','Unarmed fight accepted');
 r:=public.scavenging_action('enter',jsonb_build_object('season_id',s,'district_id',d,'request_id',gen_random_uuid()));perform pg_temp.street_check(r?'error','District switching escaped a pursuit');
 r:=public.scavenging_action('escape',jsonb_build_object('season_id',s,'request_id',gen_random_uuid()));perform pg_temp.street_check(r?'error','Remote escape accepted');
 select cash into cash0 from public.game_players where id=u;
 update game_private.scav_sessions set route_points='[[0,0]]',arrives_at=clock_timestamp()-interval '1 second',pursuit=jsonb_set(pursuit,'{started_at}',to_jsonb(clock_timestamp()-interval '10 seconds')) where player_id=u;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid());first:=public.scavenging_action('escape',q);perform pg_temp.street_check(not first?'error' and (first->>'cash')::bigint=car.sale_value,'Automatic sale failed '||first::text);
 perform pg_temp.street_check(public.scavenging_action('escape',q)=first,'Sale replay failed');
 perform pg_temp.street_check((select cash from public.game_players where id=u)=cash0+car.sale_value,'Sale credit incorrect');
 perform pg_temp.street_check((select count(*) from public.game_ledger where player_id=u and reason like 'Stolen vehicle sale:%')=1,'Sale ledger missing or duplicated');
 perform pg_temp.street_check((select status from game_private.street_vehicles where id=car.id)='sold','Sold car retained');
 -- A valid city lease stores a vehicle; only that player can sell it.
 f:=pg_temp.street_player();u:=(f->>'u')::uuid;
 select b.id into bid from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where p.season_id=s and p.code='W25';
 q:=jsonb_build_object('season_id',s,'plot_id',(select plot_id from public.game_district_buildings where id=bid),'request_id',gen_random_uuid(),'version',1,'rent',300);
 r:=public.property_action('rent',q);perform pg_temp.street_check(not r?'error','Garage lease fixture failed '||r::text);
 perform pg_temp.street_check(game_private.street_garage(s,u,bid),'Leased garage not usable');perform pg_temp.street_steal(f,bid);
 update game_private.scav_sessions set route_points='[[0,0]]',arrives_at=clock_timestamp()-interval '1 second',pursuit=jsonb_set(pursuit,'{started_at}',to_jsonb(clock_timestamp()-interval '10 seconds')) where player_id=u;
 r:=public.scavenging_action('escape',jsonb_build_object('season_id',s,'request_id',gen_random_uuid()));perform pg_temp.street_check((r->>'stored')::boolean,'Car was not stored '||r::text);
 select * into car from game_private.street_vehicles where player_id=u;
 perform pg_temp.street_check(jsonb_array_length(public.street_vehicle_state()->'vehicles')=1,'Garage vehicle missing');
 f:=pg_temp.street_player();other:=(f->>'u')::uuid;
 perform pg_temp.street_check(jsonb_array_length(public.street_vehicle_state()->'vehicles')=0,'Other player vehicle leaked');
 r:=public.scavenging_action('sell_vehicle',jsonb_build_object('season_id',s,'vehicle_id',car.id,'request_id',gen_random_uuid()));perform pg_temp.street_check(r?'error','Other player sold car');
 perform set_config('request.jwt.claim.sub',u::text,true);select cash into cash0 from public.game_players where id=u;
 q:=jsonb_build_object('season_id',s,'vehicle_id',car.id,'request_id',gen_random_uuid());first:=public.scavenging_action('sell_vehicle',q);perform pg_temp.street_check(not first?'error','Stored sale failed');perform pg_temp.street_check(public.scavenging_action('sell_vehicle',q)=first,'Stored sale duplicated');perform pg_temp.street_check((select cash from public.game_players where id=u)=cash0+car.sale_value,'Stored sale credit wrong');
 -- Return fire consumes compatible equipped ammunition, gun condition and armour before health.
 f:=pg_temp.street_player(true);u:=(f->>'u')::uuid;perform pg_temp.street_steal(f);weapon:=game_private.robbery_weapon(s,u);
 update public.game_season_players set armour=10 where player_id=u and season_id=s;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'bullets',0,'damage',0,'health',100);first:=public.scavenging_action('fight',q);perform pg_temp.street_check(not first?'error' and (first->>'fired')::boolean,'Fight failed '||first::text);
 perform pg_temp.street_check(public.scavenging_action('fight',q)=first,'Fight replay altered result');
 perform pg_temp.street_check((select quantity from public.game_inventory_gear where id=(weapon->>'ammo_id')::uuid)=17,'Wrong equipped ammo consumed');
 perform pg_temp.street_check((select condition from public.game_inventory_gear where id=(weapon->>'id')::uuid)=97,'Weapon wear incorrect');
 perform pg_temp.street_check((select health=80 and armour=0 from public.game_season_players where player_id=u and season_id=s),'Damage ignored armour or trusted client');
 -- Incapacitation seizes the car, gives no sale, and creates a prison sentence.
 f:=pg_temp.street_player(true);u:=(f->>'u')::uuid;perform pg_temp.street_steal(f);update public.game_season_players set health=5 where player_id=u and season_id=s;
 r:=public.scavenging_action('fight',jsonb_build_object('season_id',s,'request_id',gen_random_uuid()));perform pg_temp.street_check((r->>'caught')::boolean,'Injured player escaped');
 perform pg_temp.street_check((select status='seized' from game_private.street_vehicles where player_id=u),'Caught car not seized');perform pg_temp.street_check((public.prison_state()->>'jailed')::boolean,'Prison sentence missing');
 -- Refreshing late still resolves an expired getaway.
 f:=pg_temp.street_player();u:=(f->>'u')::uuid;perform pg_temp.street_steal(f);
 update game_private.scav_sessions set pursuit=jsonb_set(pursuit,'{deadline}',to_jsonb(clock_timestamp()-interval '1 second')) where player_id=u;
 r:=public.prison_state();perform pg_temp.street_check((r->>'jailed')::boolean,'Expired pursuit evaded custody by navigation');
 perform pg_temp.street_check((select status='seized' from game_private.street_vehicles where player_id=u),'Expired pursuit retained car');
 -- Owner-only vehicle prices, immutable history and private tables.
 f:=pg_temp.street_player();u:=(f->>'u')::uuid;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'id','sedan','version',1,'sale_value',2400,'enabled',true,'reason','Balance sedan resale value');
 r:=public.scavenging_action('vehicle_model',q);perform pg_temp.street_check(r?'error','Player changed vehicle price');
 update public.game_user_roles set role_id='moderator' where player_id=u;r:=public.scavenging_action('vehicle_model',q);perform pg_temp.street_check(r?'error','Moderator changed economy');
 update public.game_user_roles set role_id='owner' where player_id=u;r:=public.scavenging_action('vehicle_model',q);perform pg_temp.street_check(not r?'error','Owner edit rejected '||r::text);
 set local role authenticated;denied:=false;begin perform 1 from game_private.street_vehicles;exception when insufficient_privilege then denied:=true;end;perform pg_temp.street_check(denied,'Vehicle table exposed');reset role;
 denied:=false;begin delete from game_private.street_history;exception when raise_exception then denied:=true;end;perform pg_temp.street_check(denied,'History can be erased');
 -- Prison island rewards and an expiring event use the same safe loot accounting.
 f:=pg_temp.street_player();u:=(f->>'u')::uuid;select id into island from public.game_districts where slug='blackwater-island';
 update public.game_districts set status='neutral',archived_at=null where id=island;update public.game_district_territory set status='neutral' where season_id=s and district_id=island;
 r:=public.scavenging_action('enter',jsonb_build_object('season_id',s,'district_id',island,'request_id',gen_random_uuid()));perform pg_temp.street_check(not r?'error','Island entry failed '||r::text);perform public.bin_diving_state();
 update public.game_bin_rules set cash_chance=100,pickaxe_chance=0,lockpick_chance=0,pistol_blueprint_chance=0,bullet_blueprint_chance=0,bandages_blueprint_chance=0,cash_min=100,cash_max=100;
 update game_private.street_events set kind='satchel',node=1 where season_id=s and player_id=u and district_id=island returning id into event_id;
 update game_private.scav_sessions set route_points='[[1,0]]',arrives_at=clock_timestamp()-interval '1 second' where player_id=u;
 q:=jsonb_build_object('season_id',s,'event_id',event_id,'request_id',gen_random_uuid());r:=public.scavenging_action('event',q);perform pg_temp.street_check(not r?'error','Event start failed '||r::text);
 update game_private.scav_sessions set pending=jsonb_set(pending,'{ready_at}',to_jsonb(clock_timestamp()-interval '1 second')) where player_id=u;
 q:=jsonb_build_object('season_id',s,'attempt_id',q->>'request_id','request_id',gen_random_uuid());r:=public.scavenging_action('finish',q);perform pg_temp.street_check(not r?'error' and (r#>>'{receipt,cash}')::int=600,'Island/event reward not server-calculated '||r::text);
 -- Moving collision is swept across the whole interval, including player and patrol turns.
 perform pg_temp.street_check(game_private.street_motion_contact('[{"id":"crossing","route_points":[[0,0],[2,0],[0,0]],"epoch":0,"seconds_per_block":1,"radius":0.1}]','[[1,1],[1,0],[1,1]]',to_timestamp(0),to_timestamp(2),to_timestamp(0),to_timestamp(2))='crossing','Between-poll collision missed');
 perform pg_temp.street_check(game_private.street_motion_contact('[{"id":"far","route_points":[[0,0],[2,0],[0,0]],"epoch":0,"seconds_per_block":1,"radius":0.1}]','[[1,2]]',to_timestamp(0),to_timestamp(2),to_timestamp(0),to_timestamp(2)) is null,'Distant police caught player');
 update public.game_settings set value=1 where key='scavenging_patrol_enabled';
 perform pg_temp.street_check(jsonb_array_length(game_private.scav_patrols(island))=4,'Island patrol count missing');
 perform pg_temp.street_check((game_private.scav_patrols(island)->0->>'seconds_per_block')::int=4,'Island patrol speed missing');
end$$;
rollback;
