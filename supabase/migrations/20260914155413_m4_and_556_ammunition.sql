-- Add a modern primary carbine and its dedicated 5.56x45mm ammunition.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce M4 carbine and 5.56x45mm ammunition',true);

insert into public.game_goods(
 id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,
 inventory_category,inventory_description,weight_grams,equipment_slots
) values
 (
  'm4-carbine','M4 carbine','M4 armory',1,1,60,false,
  'weapons',
  'A reliable primary carbine chambered for 5.56x45mm ammunition. Trade, store or equip it in your primary slot.',
  3100,array['primary']
 ),
 (
  '556x45mm-ammo','5.56x45mm ammunition','Ammunition bench',1,30,60,false,
  'ammunition',
  'Standard 5.56x45mm rounds for the M4 carbine. Trade, store or equip them in your ammo slot.',
  12,array['ammo']
 );

insert into public.game_range_weapons(
 good_id,ammo_good_id,condition_max,wear_per_shot,enabled,magazine_capacity,reload_ms
) values('m4-carbine','556x45mm-ammo',250,1,true,30,2400);
