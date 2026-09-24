-- Craftable armour uses existing inventory, crafting and robbery equipment rules.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce craftable reinforced jacket and Kevlar vest',true);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots) values
 ('reinforced-jacket','Reinforced jacket','Crafting station',1,1,60,false,'armor','A reinforced coat for your armour slot. Adds robbery defence while equipped; does not refill the street armour meter.',2500,array['armor']),
 ('kevlar-vest','Kevlar vest','Crafting station',1,1,60,false,'armor','A protective vest for your armour slot. Stronger robbery defence while equipped; does not refill the street armour meter.',3500,array['armor']),
 ('reinforced_jacket_blueprint','Reinforced jacket blueprint','Found blueprint',1,1,60,false,'blueprints','Learn to craft reinforced jackets for this season. Learning consumes one blueprint.',50,'{}'),
 ('kevlar_vest_blueprint','Kevlar vest blueprint','Found blueprint',1,1,60,false,'blueprints','Learn to craft Kevlar vests for this season. Learning consumes one blueprint.',50,'{}');
insert into public.game_season_valuations(season_id,good_id,unit_value)
 select s.id,g.id,0 from public.game_seasons s cross join public.game_goods g where g.id in ('reinforced-jacket','kevlar-vest','reinforced_jacket_blueprint','kevlar_vest_blueprint') on conflict do nothing;
-- Abstract game recipes use materials already obtainable from production and trade.
insert into public.game_crafting_recipes(id,name,description,blueprint_good_id,output_good_id,output_units,seconds,materials) values
 ('reinforced-jacket','Reinforced jacket','Craft a reinforced jacket for your armour slot. Requires the reinforced jacket blueprint.','reinforced_jacket_blueprint','reinforced-jacket',1,180,'{"silk":3,"steel":2}'),
 ('kevlar-vest','Kevlar vest','Craft a stronger protective vest for your armour slot. Requires the Kevlar vest blueprint.','kevlar_vest_blueprint','kevlar-vest',1,360,'{"silk":6,"steel":4,"copper-ingot":2}');
insert into game_private.robbery_gear_rules(good_id,attack,defense,condition_max) values
 ('reinforced-jacket',0,15,100),('kevlar-vest',0,35,100);

-- Armour blueprints use the existing scavenging loot roll and owner controls.
alter table public.game_bin_rules add column reinforced_jacket_blueprint_chance numeric(5,2) not null default 0 check(reinforced_jacket_blueprint_chance between 0 and 100),
 add column kevlar_vest_blueprint_chance numeric(5,2) not null default 0 check(kevlar_vest_blueprint_chance between 0 and 100);
update public.game_bin_rules set reinforced_jacket_blueprint_chance=least(2,greatest(0,100-cash_chance-pickaxe_chance-lockpick_chance-pistol_blueprint_chance-bullet_blueprint_chance-bandages_blueprint_chance));
update public.game_bin_rules set kevlar_vest_blueprint_chance=least(1,greatest(0,100-cash_chance-pickaxe_chance-lockpick_chance-pistol_blueprint_chance-bullet_blueprint_chance-bandages_blueprint_chance-reinforced_jacket_blueprint_chance)),version=version+1;
alter table public.game_bin_rules drop constraint game_bin_rules_total_chance_check;
alter table public.game_bin_rules add constraint game_bin_rules_total_chance_check check(cash_chance+pickaxe_chance+lockpick_chance+pistol_blueprint_chance+bullet_blueprint_chance+bandages_blueprint_chance+reinforced_jacket_blueprint_chance+kevlar_vest_blueprint_chance<=100);
alter table public.game_bin_dives drop constraint game_bin_dives_outcome_check;
alter table public.game_bin_dives add constraint game_bin_dives_outcome_check check(outcome in('nothing','cash','pickaxe','lockpick','pistol_blueprint','bullet_blueprint','bandages_blueprint','reinforced_jacket_blueprint','kevlar_vest_blueprint'));
do $$declare def text;needle text;begin
 select pg_get_functiondef('game_private.bin_action(text,jsonb)'::regprocedure) into def;
 needle:='then ''bandages_blueprint'' else ''nothing'' end;';
 if position(needle in def)=0 then raise exception 'Review armour loot integration';end if;
 def:=replace(def,needle,'then ''bandages_blueprint''
 when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance+r.bandages_blueprint_chance+r.reinforced_jacket_blueprint_chance)*100 then ''reinforced_jacket_blueprint''
 when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance+r.bandages_blueprint_chance+r.reinforced_jacket_blueprint_chance+r.kevlar_vest_blueprint_chance)*100 then ''kevlar_vest_blueprint'' else ''nothing'' end;');
 needle:='bandages_blueprint_chance=coalesce((p_payload->>''bandages_blueprint_chance'')::numeric,r.bandages_blueprint_chance),';
 if position(needle in def)=0 then raise exception 'Review armour owner loot controls';end if;
 def:=replace(def,needle,needle||' reinforced_jacket_blueprint_chance=coalesce((p_payload->>''reinforced_jacket_blueprint_chance'')::numeric,reinforced_jacket_blueprint_chance),kevlar_vest_blueprint_chance=coalesce((p_payload->>''kevlar_vest_blueprint_chance'')::numeric,kevlar_vest_blueprint_chance),');
 needle:='if (r.bandages_blueprint_chance>0';
 if position(needle in def)=0 then raise exception 'Review armour loot capacity';end if;
 def:=replace(def,needle,'if (r.reinforced_jacket_blueprint_chance>0 and not game_private.inventory_fits(s,uid,''reinforced_jacket_blueprint'',1)) or (r.kevlar_vest_blueprint_chance>0 and not game_private.inventory_fits(s,uid,''kevlar_vest_blueprint'',1)) or (r.bandages_blueprint_chance>0');
 execute def;
 select pg_get_functiondef('game_private.bin_loot_state()'::regprocedure) into def;
 if position('''bandages_blueprint''' in def)=0 then raise exception 'Review armour loot inventory';end if;
 def:=replace(def,'''bandages_blueprint''','''bandages_blueprint'',''reinforced_jacket_blueprint'',''kevlar_vest_blueprint''');execute def;
end$$;
