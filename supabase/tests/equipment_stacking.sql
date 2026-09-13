begin;
create function pg_temp.check_stacking(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI equipment conservation and ammunition quantities',true);
update public.game_settings set value=100000 where key='inventory_weight_limit_grams';
do $$
declare u uuid:=gen_random_uuid();other uuid:=gen_random_uuid();s uuid:=game_private.current_season();q jsonb;r jsonb;first jsonb;g uuid;old_gear uuid;bid uuid;plot uuid;grams bigint;i int;failed boolean;
begin
 insert into auth.users(id) values(u),(other);
 perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 update public.game_inventory set quantity=0 where player_id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-bullets',100),(s,u,'homemade-pistol',3),(s,u,'pickaxe',2);
 select c.grams into grams from game_private.carried_load(s,u) c;
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',30);
 first:=public.inventory_action('equip',q);perform pg_temp.check_stacking(not first?'error','Ammo quantity equip failed: '||first::text);
 r:=public.inventory_action('equip',q);perform pg_temp.check_stacking(r=first,'Retry changed equipment result');
 select id into g from public.game_inventory_gear where player_id=u and equipment_slot='ammo';
 perform pg_temp.check_stacking((select quantity from public.game_inventory_gear where id=g)=30 and (select quantity from public.game_inventory where player_id=u and good_id='homemade-bullets')=70,'Equipping ignored quantity or retry duplicated it');
 r:=public.inventory_action('equip',q||jsonb_build_object('quantity',20));perform pg_temp.check_stacking(r?'error','Reused nonce accepted a changed quantity');
 r:=public.inventory_action('equip',q||jsonb_build_object('request_id',gen_random_uuid(),'quantity',20));perform pg_temp.check_stacking(not r?'error' and (select quantity from public.game_inventory_gear where id=g)=50,'Ammo did not top up');
 for i in 0..3 loop
  r:=public.inventory_action('equip',q||jsonb_build_object('request_id',gen_random_uuid(),'quantity',case i when 0 then '-1'::jsonb when 1 then '0'::jsonb when 2 then '1.5'::jsonb else '51'::jsonb end));
  perform pg_temp.check_stacking(r?'error','Invalid or unavailable ammo quantity accepted');
 end loop;
 r:=public.inventory_action('equip',q||jsonb_build_object('request_id',gen_random_uuid(),'quantity','2'));perform pg_temp.check_stacking(r?'error','String quantity accepted');
 perform pg_temp.check_stacking((select quantity from public.game_inventory_gear where id=g)=50,'Failed equip changed ammunition');
 -- Twenty occupied carried slots can still receive ammo into an existing stack.
 for i in 1..17 loop
  insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,weight_grams) values('ci-restack-'||i,'CI stack '||i,'Test only',1,1,60,false,1);
  insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'ci-restack-'||i,1);
 end loop;
 r:=public.inventory_state();
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','gear:'||g,'position',20);
 first:=public.inventory_action('unequip',q);perform pg_temp.check_stacking(not first?'error','Full bag failed to restack: '||first::text);
 r:=public.inventory_action('unequip',q);perform pg_temp.check_stacking(r=first,'Unequip retry duplicated stock');
 perform pg_temp.check_stacking((select quantity from public.game_inventory where player_id=u and good_id='homemade-bullets')=100 and (select slots from game_private.carried_load(s,u))=20,'Unequip created an extra stack or lost bullets');
 perform pg_temp.check_stacking((select location='retired' and quantity=0 from public.game_inventory_gear where id=g),'Original gear record not retained');
 perform pg_temp.check_stacking((select coalesce(sum(delta),0) from public.game_inventory_ledger where gear_id=g)=0,'Retired equipment ledger is not balanced');
 perform pg_temp.check_stacking(exists(select 1 from game_private.inventory_positions where player_id=u and item_key='good:homemade-bullets' and position=20),'Unequip drag did not move the merged stack');
 r:=public.inventory_state();perform pg_temp.check_stacking(not exists(select 1 from jsonb_array_elements(r->'gear') x where (x->>'quantity')::int=0),'Retired entries exposed as inventory');
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','gear:'||g,'equipment_slot','ammo'));perform pg_temp.check_stacking(r?'error','Retired equipment reused');
 update public.game_inventory set quantity=0 where player_id=u and good_id like 'ci-restack-%';
 -- Swapping pristine pistols rejoins the same source stack; only one weapon is equipped.
 q:=jsonb_build_object('season_id',s,'item_key','good:homemade-pistol','equipment_slot','secondary','request_id',gen_random_uuid());
 r:=public.inventory_action('equip',q);perform pg_temp.check_stacking(not r?'error','Pistol equip failed');
 select id into old_gear from public.game_inventory_gear where player_id=u and equipment_slot='secondary';
 r:=public.inventory_action('equip',q||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.check_stacking(not r?'error','Pistol swap failed');
 perform pg_temp.check_stacking((select quantity from public.game_inventory where player_id=u and good_id='homemade-pistol')=2 and (select location from public.game_inventory_gear where id=old_gear)='retired','Pistol swap fragmented stack');
 r:=public.inventory_action('equip',q||jsonb_build_object('request_id',gen_random_uuid(),'quantity',2));perform pg_temp.check_stacking(r?'error','Equipped multiple weapons');
 perform pg_temp.check_stacking((select c.grams from game_private.carried_load(s,u) c)=grams,'Equipment changes altered total weight');
 -- A full unused pickaxe stacks again; worn pickaxes remain individually tracked.
 q:=jsonb_build_object('season_id',s,'item_key','good:pickaxe','equipment_slot','utility','request_id',gen_random_uuid());
 r:=public.inventory_action('equip',q);perform pg_temp.check_stacking(not r?'error','Pickaxe equip failed');
 select id into old_gear from public.game_inventory_gear where player_id=u and equipment_slot='utility';
 r:=public.inventory_action('unequip',jsonb_build_object('season_id',s,'item_key','gear:'||old_gear,'request_id',gen_random_uuid()));perform pg_temp.check_stacking(not r?'error' and (select quantity from public.game_inventory where player_id=u and good_id='pickaxe')=2,'Unused pickaxe did not restack');
 -- Stored pristine equipment becomes ordinary property stock and can be retrieved normally.
 select id into plot from public.game_district_plots where season_id=s and status='available' and owner_type='none' and zoning='industrial' and archived_at is null and not exists(select 1 from public.game_district_buildings where plot_id=game_district_plots.id and archived_at is null) order by code limit 1;
 update public.game_district_plots set owner_id=u,owner_type='player',status='owned',asking_price=null where id=plot;
 insert into public.game_district_buildings(season_id,plot_id,building_type,owner_id,owner_type,construction_status,cost,ready_at) values(s,plot,'warehouse',u,'player','ready',3000,now()) returning id into bid;
 select id into old_gear from public.game_inventory_gear where player_id=u and equipment_slot='secondary';
 r:=public.inventory_action('gear_store',jsonb_build_object('season_id',s,'item_key','gear:'||old_gear,'building_id',bid,'request_id',gen_random_uuid()));
 perform pg_temp.check_stacking(not r?'error' and (select quantity from public.game_storage_inventory where building_id=bid and player_id=u and good_id='homemade-pistol')=1,'Equipment failed to join property stock: '||r::text);
 r:=public.inventory_action('retrieve',jsonb_build_object('season_id',s,'good_id','homemade-pistol','quantity',1,'building_id',bid,'request_id',gen_random_uuid()));
 perform pg_temp.check_stacking(not r?'error' and (select quantity from public.game_inventory where player_id=u and good_id='homemade-pistol')=3,'Stored pistol failed to rejoin carried stock');
 -- Legacy duplicate repair also preserves assets if an Owner has lowered capacity.
 insert into public.game_inventory_gear(season_id,player_id,good_id,quantity,location) values(s,u,'homemade-pistol',2,'carried') returning id into old_gear;
 select c.grams into grams from game_private.carried_load(s,u) c;
 update public.game_settings set value=1000 where key='inventory_weight_limit_grams';
 perform game_private.restack_gear(s,u,old_gear);
 perform pg_temp.check_stacking((select c.grams from game_private.carried_load(s,u) c)=grams and (select quantity from public.game_inventory where player_id=u and good_id='homemade-pistol')=5,'Repair changed assets in an overweight bag');
 perform pg_temp.check_stacking(not exists(select 1 from public.game_inventory_deliveries where player_id=u),'Repair incorrectly redirected existing equipment to delivery');
 perform pg_temp.check_stacking(current_setting('game.inventory_restack',true) is distinct from 'on','Internal capacity context was not restored');
 update public.game_settings set value=100000 where key='inventory_weight_limit_grams';
 q:=jsonb_build_object('season_id',s,'item_key','good:homemade-pistol','equipment_slot','secondary','request_id',gen_random_uuid());
 r:=public.inventory_action('equip',q);perform pg_temp.check_stacking(not r?'error','Cannot equip repaired item');
 -- Source ownership, access and immutable history remain enforced.
 perform set_config('request.jwt.claim.sub',other::text,true);perform public.game_state();
 select id into old_gear from public.game_inventory_gear where player_id=u and equipment_slot='secondary';
 r:=public.inventory_action('unequip',jsonb_build_object('season_id',s,'item_key','gear:'||old_gear,'request_id',gen_random_uuid()));perform pg_temp.check_stacking(r?'error','Other player moved equipment');
 perform pg_temp.check_stacking(not has_function_privilege('authenticated','game_private.restack_gear(uuid,uuid,uuid)','execute'),'Internal stacking helper exposed');
 failed:=false;begin delete from public.game_inventory_gear where id=g;exception when raise_exception then failed:=true;end;perform pg_temp.check_stacking(failed,'Equipment history destructively deleted');
end$$;
select 'PASS: ammo quantities, top-ups, retry safety, full bags, stacking, wear, ownership and ledger conservation';
rollback;
