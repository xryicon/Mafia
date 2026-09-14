begin;
create function pg_temp.m4_check(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI M4 carbine inventory and range integration',true);
update public.game_settings set value=0 where key in ('range_move_amplitude','range_move_vertical');
do $$
declare owner uuid:=gen_random_uuid();player uuid:=gen_random_uuid();s uuid:=game_private.current_season();r jsonb;sid uuid;gun uuid;ammo uuid;started timestamptz;
begin
 perform pg_temp.m4_check((select name='M4 carbine' and not business_available and inventory_category='weapons' and weight_grams=3100 and equipment_slots=array['primary'] from public.game_goods where id='m4-carbine'),'M4 inventory metadata is incorrect');
 perform pg_temp.m4_check((select name='5.56x45mm ammunition' and not business_available and inventory_category='ammunition' and weight_grams=12 and equipment_slots=array['ammo'] from public.game_goods where id='556x45mm-ammo'),'5.56 ammunition metadata is incorrect');
 perform pg_temp.m4_check((select ammo_good_id='556x45mm-ammo' and condition_max=250 and wear_per_shot=1 and enabled and magazine_capacity=30 and reload_ms=2400 from public.game_range_weapons where good_id='m4-carbine'),'M4 range rules are incorrect');

 insert into auth.users(id) values(owner),(player);
 perform set_config('request.jwt.claim.sub',owner::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',player::text,true);perform public.game_state();
 update public.game_user_roles set role_id='owner' where player_id=owner;
 perform set_config('request.jwt.claim.sub',owner::text,true);
 r:=public.staff_action('spawn_asset',jsonb_build_object('player_id',player,'good_id','m4-carbine','quantity',1,'reason','Issue test M4'));
 perform pg_temp.m4_check(not r?'error','Owner could not grant the M4: '||r::text);
 r:=public.staff_action('spawn_asset',jsonb_build_object('player_id',player,'good_id','556x45mm-ammo','quantity',35,'reason','Issue test 5.56 ammunition'));
 perform pg_temp.m4_check(not r?'error','Owner could not grant 5.56 ammunition: '||r::text);
 r:=public.staff_action('spawn_asset',jsonb_build_object('player_id',player,'good_id','homemade-bullets','quantity',1,'reason','Verify incompatible ammunition'));
 perform pg_temp.m4_check(not r?'error','Owner could not grant compatibility fixture ammunition');

 perform set_config('request.jwt.claim.sub',player::text,true);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:m4-carbine','equipment_slot','primary'));
 perform pg_temp.m4_check(not r?'error','M4 did not equip in the primary slot: '||r::text);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',1));
 perform pg_temp.m4_check(not r?'error','Compatibility fixture ammunition did not equip');
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','primary'));
 perform pg_temp.m4_check(r->>'error' like '%compatible bullets%','M4 accepted homemade pistol ammunition');
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:556x45mm-ammo','equipment_slot','ammo','quantity',35));
 perform pg_temp.m4_check(not r?'error','5.56 ammunition did not equip: '||r::text);
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','primary'));
 perform pg_temp.m4_check(not r?'error','M4 range session failed: '||r::text);sid:=(r->>'session_id')::uuid;
 select weapon_id,started_at into gun,started from public.game_range_sessions where id=sid;
 select id into ammo from public.game_inventory_gear where player_id=player and equipment_slot='ammo';
 r:=public.range_state();
 perform pg_temp.m4_check((r#>>'{weapons,0,magazine,loaded}')::int=30 and (r#>>'{weapons,0,magazine,capacity}')::int=30 and (r#>>'{weapons,0,magazine,reload_ms}')::int=2400,'M4 magazine did not load its server rules');
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',sid,'elapsed_ms',floor(extract(epoch from(clock_timestamp()-started))*1000)::int,'x',0,'y',0));
 perform pg_temp.m4_check(not r?'error','M4 shot failed: '||r::text);
 perform pg_temp.m4_check((select condition=249 from public.game_inventory_gear where id=gun) and (select quantity=34 from public.game_inventory_gear where id=ammo),'M4 shot did not consume one condition and one 5.56 round');
 perform public.range_action('finish',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',sid));
end$$;
select 'PASS: M4 metadata, Owner grants, ammunition compatibility, primary equipment, magazine and range consumption';
rollback;
