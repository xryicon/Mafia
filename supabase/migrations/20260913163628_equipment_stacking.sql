-- Restack unused equipment without deleting its immutable movement history.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Repair equipment stacking and ammunition quantities',true);
alter table public.game_inventory_gear drop constraint game_inventory_gear_quantity_check;
alter table public.game_inventory_gear drop constraint game_inventory_gear_location_check;
alter table public.game_inventory_gear add constraint game_inventory_gear_quantity_check check(quantity between 0 and 1000000);
alter table public.game_inventory_gear add constraint game_inventory_gear_location_check check(location in ('carried','equipped','storage','retired'));
alter table public.game_inventory_gear add constraint gear_retired_quantity check((quantity=0)=(location='retired'));

create function game_private.restack_gear(s uuid,u uuid,gid uuid) returns text language plpgsql security definer set search_path='' as $$
declare g public.game_inventory_gear;before_load record;after_load record;previous text:=coalesce(current_setting('game.inventory_restack',true),'');
begin
 perform 1 from public.game_players where id=u for update;
 select * into g from public.game_inventory_gear where id=gid and season_id=s and player_id=u and quantity>0 for update;
 if not found then raise exception 'This equipment is no longer available.';end if;
 if g.location not in ('carried','storage') or not (g.condition is null or (g.good_id='pickaxe' and g.condition=game_private.setting('mining_pickaxe_durability'))) then return 'gear:'||g.id;end if;
 select * into before_load from game_private.carried_load(s,u);
 -- Retain the equipment row and its ledger links, with no usable quantity.
 update public.game_inventory_gear set quantity=0,location='retired',equipment_slot=null,building_id=null where id=g.id;
 if g.location='carried' then
  -- This is representation-only: even an existing overweight bag must be repairable.
  perform set_config('game.inventory_restack','on',true);
  insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,g.good_id,g.quantity)
   on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
  perform set_config('game.inventory_restack',previous,true);
  select * into after_load from game_private.carried_load(s,u);
  if after_load.grams<>before_load.grams or after_load.slots>before_load.slots then raise exception 'Equipment stacking must preserve inventory capacity.';end if;
  update game_private.inventory_positions set item_key='good:'||g.good_id where season_id=s and player_id=u and item_key='gear:'||g.id
   and not exists(select 1 from game_private.inventory_positions where season_id=s and player_id=u and item_key='good:'||g.good_id);
 else
  insert into public.game_storage_inventory(season_id,building_id,player_id,good_id,quantity) values(s,g.building_id,u,g.good_id,g.quantity)
   on conflict(season_id,building_id,player_id,good_id) do update set quantity=game_storage_inventory.quantity+excluded.quantity;
 end if;
 return 'good:'||g.good_id;
end$$;
revoke all on function game_private.restack_gear(uuid,uuid,uuid) from public,anon,authenticated;

-- Zero-quantity retired rows produce only the outgoing ledger debit.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.gear_entry()'::regprocedure) into definition;definition:=replace(definition,chr(13),'');
 if position('values(new.season_id,new.player_id,new.good_id,bid,gid,new.location,after_qty' in definition)=0 then raise exception 'Review gear ledger integration';end if;
 definition:=replace(definition,'  insert into public.game_inventory_ledger(season_id,player_id,good_id,building_id,gear_id,location,delta,quantity_after,reason,request_id)'||chr(10)||'  values(new.season_id', '  if after_qty>0 then'||chr(10)||'  insert into public.game_inventory_ledger(season_id,player_id,good_id,building_id,gear_id,location,delta,quantity_after,reason,request_id)'||chr(10)||'  values(new.season_id');
 definition:=replace(definition,' else'||chr(10)||'  if TG_OP=', '  end if;'||chr(10)||' else'||chr(10)||'  if TG_OP=');
 execute definition;
 select pg_get_functiondef('game_private.inventory_capacity()'::regprocedure) into definition;definition:=replace(definition,chr(13),'');
 if position(' delta:=new.quantity' in definition)=0 then raise exception 'Review inventory capacity integration';end if;
 definition:=replace(definition,' delta:=new.quantity',' if current_setting(''game.inventory_restack'',true)=''on'' then return new;end if;'||chr(10)||' delta:=new.quantity');
 execute definition;
 select pg_get_functiondef('game_private.inventory_state_before_properties(integer)'::regprocedure) into definition;definition:=replace(definition,chr(13),'');
 if position('from public.game_inventory_gear g where season_id=s and player_id=u)' in definition)=0 then raise exception 'Review inventory state integration';end if;
 definition:=replace(definition,'from public.game_inventory_gear g where season_id=s and player_id=u)','from public.game_inventory_gear g where season_id=s and player_id=u and quantity>0)');
 execute definition;
end$$;

create or replace function game_private.inventory_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.inventory_requests;g public.game_inventory_gear;outgoing public.game_inventory_gear;
 item public.game_goods;key text;slot text;n integer;bid uuid;receipt public.game_inventory_deliveries;result jsonb;before_load record;after_load record;
begin
 if p_action in ('store','retrieve') then return game_private.inventory_storage_action_v1(p_action,p_payload);end if;
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid inventory action.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh inventory.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'An action reference is required.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.inventory_requests where season_id=s and player_id=u and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This action reference was already used.';end if;return prior.result;
  end if;
  perform game_private.season_guard();
  perform 1 from public.game_players where id=u and season_id=s for update;
  if not found then raise exception 'Open your dashboard to initialize this season.';end if;
  perform game_private.inventory_sync(s,u);
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason','Inventory '||p_action,true);
  select * into before_load from game_private.carried_load(s,u);
  key:=p_payload->>'item_key';slot:=p_payload->>'equipment_slot';
  if key like 'gear:%' then
   select * into g from public.game_inventory_gear where id=substring(key from 6)::uuid and season_id=s and player_id=u and quantity>0 for update;
   if not found then raise exception 'This equipment is not yours.';end if;
  end if;
  if p_action='move' then
   if (p_payload->>'version')::bigint is distinct from (select version from game_private.inventory_bags where season_id=s and player_id=u) then raise exception 'Inventory changed. Review the refreshed slots and try again.';end if;
   perform game_private.inventory_reorder(s,u,key,(p_payload->>'position')::int);
  elsif p_action='equip' then
   if slot is null or slot not in ('primary','secondary','ammo','armor','utility','medical') then raise exception 'Choose an equipment slot.';end if;
   n:=coalesce((p_payload->>'quantity')::integer,1);
   if (p_payload?'quantity' and (jsonb_typeof(p_payload->'quantity') is distinct from 'number' or (p_payload->>'quantity')::numeric is distinct from n::numeric))
    or n not between 1 and game_private.setting('storage_max_transfer') or (slot<>'ammo' and n<>1) then raise exception 'Choose a whole quantity. Only Ammo can hold multiple units.';end if;
   if g.id is not null then
    if g.location not in ('carried','equipped') then raise exception 'Retrieve this item first.';end if;
    if g.location='equipped' and g.equipment_slot=slot then raise exception 'This item is already equipped there.';end if;
    if g.quantity<n then raise exception 'You do not carry that many items.';end if;
    select * into item from public.game_goods where id=g.good_id;
   else
    select * into item from public.game_goods where id=substring(key from 6) and key like 'good:%';
    if not found then raise exception 'Select a carried item.';end if;
   end if;
   if not (slot=any(item.equipment_slots)) or (item.id='pickaxe' and slot<>'utility') then raise exception 'This item does not fit that equipment slot.';end if;
   if item.id='pickaxe' and g.id is not null and coalesce(g.condition,0)=0 then raise exception 'This pickaxe is broken.';end if;
   if (slot='utility' or g.equipment_slot='utility') and exists(select 1 from public.game_mining_runs where season_id=s and player_id=u and status='working') then raise exception 'Finish your mining shift before changing Utility equipment.';end if;
   select * into outgoing from public.game_inventory_gear where season_id=s and player_id=u and location='equipped' and equipment_slot=slot for update;
   if g.id is null then
    update public.game_inventory set quantity=quantity-n where season_id=s and player_id=u and good_id=item.id and quantity>=n;
    if not found then raise exception 'You do not carry that many items. Refresh inventory.';end if;
   end if;
   if slot='ammo' and outgoing.good_id=item.id and outgoing.condition is not distinct from g.condition then
    -- Adding the same ammunition increases the equipped stack atomically.
    if g.id is not null then
     if g.quantity=n then update public.game_inventory_gear set quantity=0,location='retired',equipment_slot=null,building_id=null where id=g.id;
     else update public.game_inventory_gear set quantity=quantity-n where id=g.id;end if;
    end if;
    update public.game_inventory_gear set quantity=quantity+n where id=outgoing.id;
   else
    if outgoing.id is not null then update public.game_inventory_gear set location='carried',equipment_slot=null where id=outgoing.id;end if;
    if g.id is null then
     insert into public.game_inventory_gear(season_id,player_id,good_id,quantity,condition,location,equipment_slot)
      values(s,u,item.id,n,case when item.id='pickaxe' then game_private.setting('mining_pickaxe_durability') end,'equipped',slot);
    elsif g.quantity=n then update public.game_inventory_gear set location='equipped',equipment_slot=slot where id=g.id;
    else
     update public.game_inventory_gear set quantity=quantity-n where id=g.id;
     insert into public.game_inventory_gear(season_id,player_id,good_id,quantity,condition,location,equipment_slot) values(s,u,item.id,n,g.condition,'equipped',slot);
    end if;
    if outgoing.id is not null then perform game_private.restack_gear(s,u,outgoing.id);end if;
   end if;
   perform game_private.refresh_mining_equipment(s,u);
  elsif p_action in ('unequip','gear_store','gear_retrieve') then
   if g.id is null then raise exception 'Select your equipment.';end if;
   if g.equipment_slot='utility' and exists(select 1 from public.game_mining_runs where season_id=s and player_id=u and status='working') then raise exception 'Finish your mining shift before changing Utility equipment.';end if;
   if p_action='unequip' then
    if g.location<>'equipped' then raise exception 'This item is not equipped.';end if;
    update public.game_inventory_gear set location='carried',equipment_slot=null where id=g.id;
   elsif p_action='gear_store' then
    if g.location not in ('carried','equipped') then raise exception 'Retrieve this item before moving it to another property.';end if;
    bid:=(p_payload->>'building_id')::uuid;perform game_private.gear_storage(s,u,bid,true,g.quantity);
    update public.game_inventory_gear set location='storage',building_id=bid,equipment_slot=null where id=g.id;
   else
    if g.location<>'storage' then raise exception 'This item is not stored.';end if;
    perform game_private.gear_storage(s,u,g.building_id,false,g.quantity);
    update public.game_inventory_gear set location='carried',building_id=null where id=g.id;
   end if;
   key:=game_private.restack_gear(s,u,g.id);
   perform game_private.refresh_mining_equipment(s,u);
  elsif p_action='claim_delivery' then
   n:=(p_payload->>'quantity')::integer;
   if jsonb_typeof(p_payload->'quantity') is distinct from 'number' or (p_payload->>'quantity')::numeric<>n or n is null or n not between 1 and game_private.setting('storage_max_transfer') then raise exception 'Enter a whole item quantity.';end if;
   select * into receipt from public.game_inventory_deliveries where id=(p_payload->>'delivery_id')::uuid and player_id=u and season_id=s for update;
   if not found or receipt.quantity<n then raise exception 'These goods are no longer waiting for collection.';end if;
   if not game_private.inventory_fits(s,u,receipt.good_id,n) then raise exception 'Free a slot or reduce carried weight before collecting these goods.';end if;
   update public.game_inventory_deliveries set quantity=quantity-n where id=receipt.id;
   insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,receipt.good_id,n) on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
  else raise exception 'Unknown inventory action.';end if;
  select * into after_load from game_private.carried_load(s,u);
  if (after_load.grams>game_private.setting('inventory_weight_limit_grams') and after_load.grams>before_load.grams) or (after_load.slots>game_private.setting('inventory_slot_limit') and after_load.slots>before_load.slots) then raise exception 'Your carried inventory is full or too heavy. Store something first.';end if;
  perform game_private.inventory_sync(s,u);
  if p_action='unequip' and p_payload?'position' then perform game_private.inventory_reorder(s,u,key,(p_payload->>'position')::int);end if;
  result:=jsonb_build_object('message',case p_action when 'move' then 'Item moved.' when 'equip' then 'Equipment updated.' when 'unequip' then 'Item returned to your inventory with its condition preserved.' when 'gear_store' then 'Equipment secured in your property.' when 'gear_retrieve' then 'Equipment returned to your inventory.' else 'Delivery collected.' end);
  insert into game_private.inventory_requests values(s,u,nonce,p_action,p_payload,result);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check the item and slot, then refresh inventory.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

-- Repair already split, pristine carried/storage items in the current season.
-- Worn tools keep their condition and individual identity. Equipped quantities stay equipped.
do $$declare g record;begin
 for g in select id,season_id,player_id from public.game_inventory_gear
  where season_id=game_private.current_season() and location in ('carried','storage')
   and (condition is null or (good_id='pickaxe' and condition=game_private.setting('mining_pickaxe_durability')))
  order by player_id,id loop
  perform game_private.restack_gear(g.season_id,g.player_id,g.id);
  perform game_private.inventory_sync(g.season_id,g.player_id);
 end loop;
end$$;
notify pgrst,'reload schema';
