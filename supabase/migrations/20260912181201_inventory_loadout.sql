-- Twenty carried stacks, six equipment spaces, and server-authoritative weight.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce carried capacity and equipment',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('inventory_slot_limit',20,1,100),('inventory_weight_limit_grams',100000,1000,1000000000);
alter table public.game_goods add column weight_grams integer not null default 1000 check(weight_grams between 1 and 1000000);
alter table public.game_goods add column equipment_slots text[] not null default '{}' check(equipment_slots <@ array['primary','secondary','ammo','armor','utility','medical']::text[]);
update public.game_goods set weight_grams=case when id='pickaxe' then 2500 when id like '%_blueprint' then 50 when id in ('whiskey','steel') then 2000 else 1000 end,
 equipment_slots=case when id='pickaxe' then array['utility'] else '{}'::text[] end;
create table public.game_inventory_gear(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),good_id text not null references public.game_goods(id),
 quantity integer not null default 1 check(quantity between 1 and 1000000),condition integer check(condition>=0),
 location text not null check(location in ('carried','equipped','storage')),
 equipment_slot text check(equipment_slot in ('primary','secondary','ammo','armor','utility','medical')),
 building_id uuid references public.game_district_buildings(id),created_at timestamptz not null default now(),
 check((location='equipped')=(equipment_slot is not null)),check((location='storage')=(building_id is not null))
);
create unique index gear_one_per_equipment_slot on public.game_inventory_gear(season_id,player_id,equipment_slot) where location='equipped';
create index gear_owner on public.game_inventory_gear(player_id,season_id);
create index gear_good on public.game_inventory_gear(good_id);
create index gear_building on public.game_inventory_gear(building_id) where building_id is not null;
create table game_private.inventory_bags(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),version bigint not null default 1,
 primary key(season_id,player_id)
);
create index bag_owner on game_private.inventory_bags(player_id);
create table game_private.inventory_positions(
 season_id uuid not null,player_id uuid not null,position integer not null check(position between 1 and 100),item_key text not null,
 primary key(season_id,player_id,position),unique(season_id,player_id,item_key),
 foreign key(season_id,player_id) references game_private.inventory_bags(season_id,player_id)
);
create table public.game_inventory_deliveries(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),good_id text not null references public.game_goods(id),
 quantity integer not null check(quantity>=0),reason text not null,created_at timestamptz not null default clock_timestamp()
);
create index deliveries_owner on public.game_inventory_deliveries(player_id,season_id);
create index deliveries_season on public.game_inventory_deliveries(season_id);
create index deliveries_good on public.game_inventory_deliveries(good_id);
alter table public.game_inventory_gear enable row level security;
alter table public.game_inventory_deliveries enable row level security;
alter table game_private.inventory_bags enable row level security;
alter table game_private.inventory_positions enable row level security;
revoke all on public.game_inventory_gear,public.game_inventory_deliveries,game_private.inventory_bags,game_private.inventory_positions from public,anon,authenticated;
create trigger gear_retain before delete or truncate on public.game_inventory_gear for each statement execute function game_private.district_immutable();
create trigger deliveries_retain before delete or truncate on public.game_inventory_deliveries for each statement execute function game_private.district_immutable();
alter table public.game_inventory_ledger drop constraint game_inventory_ledger_location_check;
alter table public.game_inventory_ledger add constraint game_inventory_ledger_location_check check(location in ('carried','storage','equipped','delivery'));
alter table public.game_inventory_ledger add column gear_id uuid references public.game_inventory_gear(id);
create index inventory_ledger_gear on public.game_inventory_ledger(gear_id) where gear_id is not null;

create function game_private.gear_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare from_location text;before_qty int:=0;after_qty int;bid uuid;gid uuid;
begin
 if TG_OP='UPDATE' and (new.season_id,new.player_id,new.good_id) is distinct from (old.season_id,old.player_id,old.good_id) then raise exception 'Item ownership cannot change.';end if;
 if TG_TABLE_NAME='game_inventory_gear' then
  gid:=new.id;after_qty:=new.quantity;bid:=new.building_id;
  if TG_OP='UPDATE' then
   if (old.location,old.equipment_slot,old.building_id,old.quantity) is not distinct from (new.location,new.equipment_slot,new.building_id,new.quantity) then return new;end if;
   insert into public.game_inventory_ledger(season_id,player_id,good_id,building_id,gear_id,location,delta,quantity_after,reason,request_id)
   values(old.season_id,old.player_id,old.good_id,old.building_id,old.id,old.location,-old.quantity,0,coalesce(nullif(current_setting('game.reason',true),''),'Equipment moved'),nullif(current_setting('game.inventory_request',true),'')::uuid);
  end if;
  insert into public.game_inventory_ledger(season_id,player_id,good_id,building_id,gear_id,location,delta,quantity_after,reason,request_id)
  values(new.season_id,new.player_id,new.good_id,bid,gid,new.location,after_qty,after_qty,coalesce(nullif(current_setting('game.reason',true),''),'Equipment registered'),nullif(current_setting('game.inventory_request',true),'')::uuid);
 else
  if TG_OP='UPDATE' then before_qty:=old.quantity;end if;
  if new.quantity<>before_qty then insert into public.game_inventory_ledger(season_id,player_id,good_id,location,delta,quantity_after,reason,request_id)
   values(new.season_id,new.player_id,new.good_id,'delivery',new.quantity-before_qty,new.quantity,new.reason,nullif(current_setting('game.inventory_request',true),'')::uuid);end if;
 end if;return new;
end$$;
create trigger gear_item_history after insert or update on public.game_inventory_gear for each row execute function game_private.gear_entry();
create trigger delivery_item_history after insert or update on public.game_inventory_deliveries for each row execute function game_private.gear_entry();
-- Register existing working tools; these were already paid for/consumed on equip.
insert into public.game_inventory_gear(season_id,player_id,good_id,condition,location,equipment_slot)
 select season_id,player_id,'pickaxe',durability,'equipped','utility' from public.game_mining_tools where durability>0;

create function game_private.carried_load(s uuid,u uuid) returns table(grams bigint,slots bigint) language sql stable security definer set search_path='' as $$
 select coalesce((select sum(i.quantity::bigint*g.weight_grams) from public.game_inventory i join public.game_goods g on g.id=i.good_id where i.season_id=s and i.player_id=u),0)+
 coalesce((select sum(i.quantity::bigint*g.weight_grams) from public.game_inventory_gear i join public.game_goods g on g.id=i.good_id where i.season_id=s and i.player_id=u and i.location in ('carried','equipped')),0),
 (select count(*) from public.game_inventory where season_id=s and player_id=u and quantity>0)+(select count(*) from public.game_inventory_gear where season_id=s and player_id=u and location='carried');
$$;
create function game_private.inventory_fits(s uuid,u uuid,g text,n integer) returns boolean language sql stable security definer set search_path='' as $$
 select c.grams+n::bigint*(select weight_grams from public.game_goods where id=g)<=game_private.setting('inventory_weight_limit_grams')
 and c.slots+case when exists(select 1 from public.game_inventory where season_id=s and player_id=u and good_id=g and quantity>0) then 0 else 1 end<=game_private.setting('inventory_slot_limit')
 from game_private.carried_load(s,u) c;
$$;
create function game_private.inventory_capacity() returns trigger language plpgsql security definer set search_path='' as $$
declare delta integer; c record;
begin
 delta:=new.quantity-case when TG_OP='INSERT' then 0 else old.quantity end;
 if delta<=0 then return new;end if;
 perform 1 from public.game_players where id=new.player_id for update;
 select * into c from game_private.carried_load(new.season_id,new.player_id);
 if c.grams>game_private.setting('inventory_weight_limit_grams') or c.slots>game_private.setting('inventory_slot_limit') then
  -- Auction settlement and other people's payments cannot be blocked by a full bag.
  -- Hold these owed goods outside usable inventory until explicitly collected.
  if current_setting('game.inventory_delivery',true)='on' or new.player_id is distinct from auth.uid() then
   update public.game_inventory set quantity=quantity-delta where season_id=new.season_id and player_id=new.player_id and good_id=new.good_id;
   insert into public.game_inventory_deliveries(season_id,player_id,good_id,quantity,reason)
    values(new.season_id,new.player_id,new.good_id,delta,coalesce(nullif(current_setting('game.reason',true),''),'Delivery awaiting inventory space'));
  else raise exception 'Your carried inventory is full or too heavy. Store items in your property before receiving more.';end if;
 end if;return new;
end$$;
create trigger inventory_capacity after insert or update on public.game_inventory for each row execute function game_private.inventory_capacity();

create function game_private.inventory_sync(s uuid,u uuid) returns void language plpgsql security definer set search_path='' as $$
declare k text;p integer;changed boolean:=false;removed int;
begin
 insert into game_private.inventory_bags values(s,u,1) on conflict do nothing;
 delete from game_private.inventory_positions x where season_id=s and player_id=u and
 (position>game_private.setting('inventory_slot_limit') or not exists(
  select 1 from public.game_inventory i where i.season_id=s and i.player_id=u and i.quantity>0 and x.item_key='good:'||i.good_id
  union all select 1 from public.game_inventory_gear g where g.season_id=s and g.player_id=u and g.location='carried' and x.item_key='gear:'||g.id::text));
 get diagnostics removed=ROW_COUNT;changed:=removed>0;
 for k in select 'good:'||good_id from public.game_inventory where season_id=s and player_id=u and quantity>0
  union all select 'gear:'||id::text from public.game_inventory_gear where season_id=s and player_id=u and location='carried' order by 1 loop
  if not exists(select 1 from game_private.inventory_positions where season_id=s and player_id=u and item_key=k) then
   select n into p from generate_series(1,game_private.setting('inventory_slot_limit')) n where not exists(select 1 from game_private.inventory_positions where season_id=s and player_id=u and position=n) order by n limit 1;
   if p is not null then insert into game_private.inventory_positions values(s,u,p,k);changed:=true;end if;
  end if;
 end loop;
 if changed then update game_private.inventory_bags set version=version+1 where season_id=s and player_id=u;end if;
end$$;
create function game_private.inventory_reorder(s uuid,u uuid,k text,target integer) returns void language plpgsql security definer set search_path='' as $$
declare source integer;other text;
begin
 if target is null or target not between 1 and game_private.setting('inventory_slot_limit') then raise exception 'Choose a valid inventory slot.';end if;
 select position into source from game_private.inventory_positions where season_id=s and player_id=u and item_key=k;
 if source is null then raise exception 'This item is no longer carried. Refresh inventory.';end if;
 if source=target then return;end if;
 select item_key into other from game_private.inventory_positions where season_id=s and player_id=u and position=target;
 delete from game_private.inventory_positions where season_id=s and player_id=u and position in (source,target);
 insert into game_private.inventory_positions values(s,u,target,k);
 if other is not null then insert into game_private.inventory_positions values(s,u,source,other);end if;
 update game_private.inventory_bags set version=version+1 where season_id=s and player_id=u;
end$$;
create function game_private.gear_tool_sync() returns trigger language plpgsql security definer set search_path='' as $$
declare g public.game_inventory_gear;
begin
 if current_setting('game.gear_sync',true)='on' then return new;end if;
 select * into g from public.game_inventory_gear where season_id=new.season_id and player_id=new.player_id and equipment_slot='utility' and location='equipped' for update;
 if found then
  if g.good_id<>'pickaxe' and new.durability>0 then raise exception 'Unequip your Utility item before equipping a pickaxe.';end if;
  if g.good_id='pickaxe' then update public.game_inventory_gear set condition=new.durability where id=g.id;end if;
 elsif new.durability>0 then
  insert into public.game_inventory_gear(season_id,player_id,good_id,condition,location,equipment_slot) values(new.season_id,new.player_id,'pickaxe',new.durability,'equipped','utility');
 end if;return new;
end$$;
create trigger inventory_tool_sync after insert or update on public.game_mining_tools for each row execute function game_private.gear_tool_sync();
create function game_private.refresh_mining_equipment(s uuid,u uuid) returns void language plpgsql security definer set search_path='' as $$
declare previous text:=coalesce(current_setting('game.gear_sync',true),'');
begin
 perform set_config('game.gear_sync','on',true);
 insert into public.game_mining_tools(season_id,player_id,durability) values(s,u,coalesce((select condition from public.game_inventory_gear where season_id=s and player_id=u and location='equipped' and equipment_slot='utility' and good_id='pickaxe'),0))
 on conflict(season_id,player_id) do update set durability=excluded.durability;
 perform set_config('game.gear_sync',previous,true);
end$$;
create function game_private.storage_load(s uuid,b uuid) returns bigint language sql stable security definer set search_path='' as $$
 select coalesce((select sum(quantity) from public.game_storage_inventory where season_id=s and building_id=b),0)+coalesce((select sum(quantity) from public.game_inventory_gear where season_id=s and building_id=b and location='storage'),0)
$$;
create function game_private.gear_storage(s uuid,u uuid,bid uuid,storing boolean,n integer) returns void language plpgsql security definer set search_path='' as $$
declare b public.game_district_buildings;p public.game_district_plots;r public.game_storage_rules;
begin
 select * into b from public.game_district_buildings where id=bid and season_id=s for update;
 if not found or b.owner_type is distinct from 'player' or b.owner_id is distinct from u or b.archived_at is not null or b.construction_status<>'ready' then raise exception 'Choose your completed storage building.';end if;
 select * into p from public.game_district_plots where id=b.plot_id and season_id=s for update;
 if not found or p.owner_type is distinct from 'player' or p.owner_id is distinct from u or p.archived_at is not null or p.status='locked' then raise exception 'This is not an accessible property you own.';end if;
 if not exists(select 1 from public.game_districts where id=p.district_id and archived_at is null and status<>'lockdown') or exists(select 1 from public.game_district_territory where season_id=s and district_id=p.district_id and status='lockdown') then raise exception 'Storage is inaccessible during district lockdown.';end if;
 select * into r from public.game_storage_rules where building_type=b.building_type for share;
 if not found then raise exception 'This building does not provide storage.';end if;
 if storing then
  if not r.enabled or p.asking_price is not null or exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'This property is not accepting new storage deposits.';end if;
  if game_private.storage_load(s,bid)+n>r.capacity then raise exception 'This building does not have enough free storage space.';end if;
 end if;
end$$;

alter function game_private.inventory_action(text,jsonb) rename to inventory_storage_action_v1;
create function game_private.inventory_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
   select * into g from public.game_inventory_gear where id=substring(key from 6)::uuid and season_id=s and player_id=u for update;
   if not found then raise exception 'This equipment is not yours.';end if;
  end if;
  if p_action='move' then
   if (p_payload->>'version')::bigint is distinct from (select version from game_private.inventory_bags where season_id=s and player_id=u) then raise exception 'Inventory changed. Review the refreshed slots and try again.';end if;
   perform game_private.inventory_reorder(s,u,key,(p_payload->>'position')::int);
  elsif p_action='equip' then
   if slot is null or slot not in ('primary','secondary','ammo','armor','utility','medical') then raise exception 'Choose an equipment slot.';end if;
   if g.id is not null then
    if g.location not in ('carried','equipped') then raise exception 'Retrieve this item first.';end if;
    if g.location='equipped' and g.equipment_slot=slot then raise exception 'This item is already equipped there.';end if;
    select * into item from public.game_goods where id=g.good_id;
   else
    select * into item from public.game_goods where id=substring(key from 6) and key like 'good:%';
    if not found then raise exception 'Select a carried item.';end if;
   end if;
   if not (slot=any(item.equipment_slots)) or (item.id='pickaxe' and slot<>'utility') then raise exception 'This item does not fit that equipment slot.';end if;
   if item.id='pickaxe' and g.id is not null and coalesce(g.condition,0)=0 then raise exception 'This pickaxe is broken.';end if;
   if (slot='utility' or g.equipment_slot='utility') and exists(select 1 from public.game_mining_runs where season_id=s and player_id=u and status='working') then raise exception 'Finish your mining shift before changing Utility equipment.';end if;
   select * into outgoing from public.game_inventory_gear where season_id=s and player_id=u and location='equipped' and equipment_slot=slot for update;
   if found then update public.game_inventory_gear set location='carried',equipment_slot=null where id=outgoing.id;end if;
   if g.id is null then
    update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=u and good_id=item.id and quantity>0;
    if not found then raise exception 'This item is no longer carried.';end if;
    insert into public.game_inventory_gear(season_id,player_id,good_id,condition,location,equipment_slot) values(s,u,item.id,case when item.id='pickaxe' then game_private.setting('mining_pickaxe_durability') end,'equipped',slot) returning * into g;
   else update public.game_inventory_gear set location='equipped',equipment_slot=slot where id=g.id;end if;
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

alter function game_private.inventory_state(integer) rename to inventory_storage_state_v1;
create function game_private.inventory_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();d jsonb;c record;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 d:=game_private.inventory_storage_state_v1(p_offset);perform 1 from public.game_players where id=u for update;
 perform game_private.inventory_sync(s,u);select * into c from game_private.carried_load(s,u);
 return d||jsonb_build_object(
 'goods',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'category',inventory_category,'description',inventory_description,'weight_grams',weight_grams,'equipment_slots',equipment_slots) order by name) from public.game_goods),
 'capacity',jsonb_build_object('slots',game_private.setting('inventory_slot_limit'),'weight_grams',game_private.setting('inventory_weight_limit_grams'),'used_slots',c.slots,'used_grams',c.grams),
 'layout',(select coalesce(jsonb_agg(jsonb_build_object('position',position,'item_key',item_key) order by position),'[]') from game_private.inventory_positions where season_id=s and player_id=u),
 'version',(select version from game_private.inventory_bags where season_id=s and player_id=u),
 'gear',(select coalesce(jsonb_agg(g order by g.created_at),'[]') from public.game_inventory_gear g where season_id=s and player_id=u),
 'deliveries',(select coalesce(jsonb_agg(g order by g.created_at),'[]') from public.game_inventory_deliveries g where season_id=s and player_id=u and quantity>0),
 'stores',(select coalesce(jsonb_agg(x||jsonb_build_object('used',game_private.storage_load(s,(x->>'id')::uuid))),'[]') from jsonb_array_elements(d->'stores') x)
 );
end$$;
-- Keep existing storage and property protection aware of individual equipment.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.inventory_storage_action_v1(text,jsonb)'::regprocedure) into definition;
 if position('select coalesce(sum(quantity),0) into used' in definition)=0 then raise exception 'Review storage capacity integration';end if;
 definition:=replace(definition,'select coalesce(sum(quantity),0) into used from public.game_storage_inventory where season_id=s and building_id=b.id;','used:=game_private.storage_load(s,b.id);');
 execute definition;
 select pg_get_functiondef('game_private.protect_stored_goods()'::regprocedure) into definition;
 definition:=replace(definition,'and i.quantity>0) then','and i.quantity>0) then');
 definition:=replace(definition,'where p.district_id=old.id and i.season_id=game_private.current_season() and i.quantity>0)', 'where p.district_id=old.id and i.season_id=game_private.current_season() and i.quantity>0) or exists(select 1 from public.game_inventory_gear g join public.game_district_buildings b on b.id=g.building_id join public.game_district_plots p on p.id=b.plot_id where p.district_id=old.id and g.season_id=game_private.current_season() and g.location=''storage'')');
 -- Parenthesize the whole stock predicate; otherwise unrelated district updates would be blocked.
 definition:=replace(definition,'if (TG_OP=''DELETE'' or new.archived_at is distinct from old.archived_at) and exists(', 'if (TG_OP=''DELETE'' or new.archived_at is distinct from old.archived_at) and (exists(');
 definition:=replace(definition,'g.location=''storage'') then raise exception ''Empty the district','g.location=''storage'')) then raise exception ''Empty the district');
 definition:=replace(definition,'if changed and exists(', 'if changed and (exists(');
 definition:=replace(definition,'where b.plot_id=plot and i.quantity>0) then','where b.plot_id=plot and i.quantity>0) or exists(select 1 from public.game_inventory_gear g join public.game_district_buildings b on b.id=g.building_id where b.plot_id=plot and g.location=''storage'')) then');
 execute definition;
end$$;
-- Guaranteed auction deliveries can wait for capacity; no escrow or goods are lost.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.market_finish(public.game_market_auctions,boolean)'::regprocedure) into definition;
 definition:=replace(definition,'declare fee bigint; recipient uuid;','declare fee bigint; recipient uuid; delivery_mode text:=coalesce(current_setting(''game.inventory_delivery'',true),'''');');
 if position('insert into public.game_inventory as inv' in definition)=0 then raise exception 'Review auction delivery integration';end if;
 definition:=replace(definition,'insert into public.game_inventory as inv','perform set_config(''game.inventory_delivery'',''on'',true);'||chr(10)||' insert into public.game_inventory as inv');
 definition:=replace(definition,'on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;','on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;'||chr(10)||' perform set_config(''game.inventory_delivery'',delivery_mode,true);');
 execute definition;
 -- Check every possible item before rolling so a full bag cannot reroll unwanted loot.
 select pg_get_functiondef('game_private.bin_action(text,jsonb)'::regprocedure) into definition;
 if position('roll:=floor(random()*10000)::integer;' in definition)=0 then raise exception 'Review bin capacity integration';end if;
 definition:=replace(definition,'roll:=floor(random()*10000)::integer;', 'if (r.pickaxe_chance>0 and not game_private.inventory_fits(s,uid,''pickaxe'',1)) or (r.pistol_blueprint_chance>0 and not game_private.inventory_fits(s,uid,''pistol_blueprint'',1)) or (r.bullet_blueprint_chance>0 and not game_private.inventory_fits(s,uid,''bullet_blueprint'',1)) then raise exception ''Free space and weight in Inventory before searching for loot.'';end if;'||chr(10)||'    roll:=floor(random()*10000)::integer;');
 execute definition;
 -- Include individually equipped/carried/stored equipment and owed deliveries once.
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as stock_value,' in definition)=0 then raise exception 'Review equipment net worth integration';end if;
 definition:=replace(definition,' as stock_value,',' +coalesce((select sum(x.quantity::numeric*v.unit_value) from (select season_id,player_id,good_id,quantity from public.game_inventory_gear union all select season_id,player_id,good_id,quantity from public.game_inventory_deliveries) x join public.game_season_valuations v on v.season_id=x.season_id and v.good_id=x.good_id where x.season_id=p_season and x.player_id=sp.player_id),0) as stock_value,');
 execute definition;
end$$;
-- Extend the audited Owner editor; preserve compatibility with older forms.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.inventory_manage(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,'inventory_description=btrim(p_payload->>''description'')','inventory_description=btrim(p_payload->>''description''),weight_grams=coalesce((p_payload->>''weight_grams'')::int,weight_grams),equipment_slots=case when p_payload?''equipment_slots'' then array(select jsonb_array_elements_text(p_payload->''equipment_slots'')) else equipment_slots end');
 execute definition;
end$$;
revoke all on function game_private.gear_entry(),game_private.carried_load(uuid,uuid),game_private.inventory_fits(uuid,uuid,text,integer),game_private.inventory_capacity(),game_private.inventory_sync(uuid,uuid),game_private.inventory_reorder(uuid,uuid,text,integer),game_private.gear_tool_sync(),game_private.refresh_mining_equipment(uuid,uuid),game_private.storage_load(uuid,uuid),game_private.gear_storage(uuid,uuid,uuid,boolean,integer),game_private.inventory_storage_action_v1(text,jsonb),game_private.inventory_storage_state_v1(integer),game_private.inventory_action(text,jsonb),game_private.inventory_state(integer) from public,anon,authenticated;
grant execute on function game_private.inventory_action(text,jsonb),game_private.inventory_state(integer) to authenticated;
notify pgrst,'reload schema';
