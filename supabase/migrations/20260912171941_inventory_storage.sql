-- Keep game_inventory as carried stock: every existing producer, market purchase,
-- mine claim, bin find and Owner grant continues to arrive in the same inventory.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce the inventory and secure storage registry',true);
insert into public.game_permissions(id,owner_only) values('storage.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values('storage_max_transfer',1000000,1,1000000000);
alter table public.game_goods add column inventory_category text not null default 'materials' check(inventory_category in ('materials','commodities','tools','blueprints','weapons','ammunition','armor','medical','consumables','other'));
alter table public.game_goods add column inventory_description text not null default '' check(length(inventory_description)<=1000);
update public.game_goods set inventory_category=case when id in ('whiskey','silk','steel') then 'commodities' when id='pickaxe' then 'tools' when id in ('pistol_blueprint','bullet_blueprint') then 'blueprints' else 'materials' end,
 inventory_description=case when id='pickaxe' then 'Spare mining equipment. Equip it before working a public mine.' when id in ('pistol_blueprint','bullet_blueprint') then 'A found blueprint. Trade it or keep it for future crafting.' when id in ('iron-ore','copper-ore') then 'Mined ore. Refine it into ingots or trade it with another player.' when id='coal' then 'Mined coal. Used by refinery owners to fuel their furnaces.' when id in ('iron-ingot','copper-ingot') then 'Refined metal, ready for the player economy.' else 'Goods from the Blackwater economy. Carry, trade or store them in your property.' end;
-- A garage is a building, not a new collectible or starter gift.
insert into public.game_building_types(id,name,cost,construction_seconds,business_type)
 values('garage','Garage',2000,300,'Storage');
update public.game_zoning set allowed_buildings=array_append(allowed_buildings,'garage')
 where id in ('commercial','industrial','waterfront') and not ('garage'=any(allowed_buildings));
create table public.game_storage_rules(
 building_type text primary key references public.game_building_types(id),
 capacity integer not null check(capacity between 1 and 1000000000),
 enabled boolean not null default true,version integer not null default 1
);
insert into public.game_storage_rules(building_type,capacity) values('warehouse',2000),('garage',200);
create table public.game_storage_inventory(
 season_id uuid not null references public.game_seasons(id),
 building_id uuid not null references public.game_district_buildings(id),
 player_id uuid not null references public.game_players(id),
 good_id text not null references public.game_goods(id),
 quantity integer not null check(quantity>=0),
 primary key(season_id,building_id,player_id,good_id)
);
create index storage_owner on public.game_storage_inventory(player_id,season_id);
create index storage_building on public.game_storage_inventory(building_id);
create index storage_good on public.game_storage_inventory(good_id);
create table public.game_inventory_ledger(
 id bigint generated always as identity primary key,
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 good_id text not null references public.game_goods(id),building_id uuid references public.game_district_buildings(id),
 location text not null check(location in ('carried','storage')),delta bigint not null check(delta<>0),
 quantity_after bigint not null check(quantity_after>=0),reason text not null,request_id uuid,
 created_at timestamptz not null default clock_timestamp()
);
create index inventory_ledger_owner on public.game_inventory_ledger(player_id,season_id,id desc);
create index inventory_ledger_good on public.game_inventory_ledger(good_id);
create index inventory_ledger_building on public.game_inventory_ledger(building_id) where building_id is not null;
create index inventory_ledger_season on public.game_inventory_ledger(season_id);
create table game_private.inventory_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 primary key(season_id,player_id,request_id)
);
create index inventory_request_player on game_private.inventory_requests(player_id);
alter table public.game_storage_rules enable row level security;
alter table public.game_storage_inventory enable row level security;
alter table public.game_inventory_ledger enable row level security;
alter table game_private.inventory_requests enable row level security;
revoke all on public.game_storage_rules,public.game_storage_inventory,public.game_inventory_ledger,game_private.inventory_requests from public,anon,authenticated;
create trigger storage_rules_audit after insert or update or delete on public.game_storage_rules for each row execute function game_private.audit_change();
create trigger inventory_ledger_retain before update or delete or truncate on public.game_inventory_ledger for each statement execute function game_private.district_immutable();
create trigger inventory_requests_retain before update or delete or truncate on game_private.inventory_requests for each statement execute function game_private.district_immutable();
create trigger storage_retain before delete or truncate on public.game_storage_inventory for each statement execute function game_private.district_immutable();
-- Baselines record actual existing quantities, never grant new items.
insert into public.game_inventory_ledger(season_id,player_id,good_id,location,delta,quantity_after,reason)
 select season_id,player_id,good_id,'carried',quantity,quantity,'Inventory registry opening' from public.game_inventory where quantity>0;
create function game_private.inventory_entry() returns trigger language plpgsql security definer set search_path='' as $$
declare row_data jsonb;before_qty bigint:=0;after_qty bigint:=0;building uuid;
begin
 if TG_OP<>'INSERT' then before_qty:=old.quantity;end if;
 if TG_OP<>'DELETE' then after_qty:=new.quantity;end if;
 row_data:=case when TG_OP='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if TG_OP='UPDATE' and (new.season_id<>old.season_id or new.player_id<>old.player_id or new.good_id<>old.good_id or (to_jsonb(new)->>'building_id') is distinct from (to_jsonb(old)->>'building_id')) then raise exception 'Inventory identity cannot change.';end if;
 if before_qty<>after_qty then
  building:=(row_data->>'building_id')::uuid;
  insert into public.game_inventory_ledger(season_id,player_id,good_id,building_id,location,delta,quantity_after,reason,request_id)
  values((row_data->>'season_id')::uuid,(row_data->>'player_id')::uuid,row_data->>'good_id',building,
   case when TG_TABLE_NAME='game_inventory' then 'carried' else 'storage' end,after_qty-before_qty,after_qty,
   coalesce(nullif(current_setting('game.reason',true),''),'Inventory change'),nullif(current_setting('game.inventory_request',true),'')::uuid);
 end if;
 return coalesce(new,old);
end$$;
create trigger carried_inventory_entry after insert or update or delete on public.game_inventory for each row execute function game_private.inventory_entry();
create trigger stored_inventory_entry after insert or update on public.game_storage_inventory for each row execute function game_private.inventory_entry();
-- Stock cannot follow a property sale or become stranded by removing its building.
create function game_private.protect_stored_goods() returns trigger language plpgsql security definer set search_path='' as $$
declare plot uuid;changed boolean:=true;
begin
 if TG_TABLE_NAME='game_districts' then
  if (TG_OP='DELETE' or new.archived_at is distinct from old.archived_at) and exists(select 1 from public.game_storage_inventory i join public.game_district_buildings b on b.id=i.building_id join public.game_district_plots p on p.id=b.plot_id where p.district_id=old.id and i.season_id=game_private.current_season() and i.quantity>0) then raise exception 'Empty the district storage buildings before archiving this district.';end if;
  return coalesce(new,old);
 elsif TG_TABLE_NAME='game_district_buildings' then
  plot:=old.plot_id;
  changed:=TG_OP='DELETE' or new.owner_type is distinct from old.owner_type or new.owner_id is distinct from old.owner_id or new.archived_at is distinct from old.archived_at or new.building_type is distinct from old.building_type or new.plot_id is distinct from old.plot_id or new.season_id is distinct from old.season_id or new.construction_status is distinct from old.construction_status;
 elsif TG_TABLE_NAME='game_district_plots' then
  plot:=old.id;
  changed:=TG_OP='DELETE' or new.owner_type is distinct from old.owner_type or new.owner_id is distinct from old.owner_id or new.archived_at is distinct from old.archived_at or new.status is distinct from old.status or new.season_id is distinct from old.season_id or new.district_id is distinct from old.district_id or (new.asking_price is not null and new.asking_price is distinct from old.asking_price);
 else plot:=new.plot_id;changed:=new.status='open';end if;
 if changed and exists(select 1 from public.game_storage_inventory i join public.game_district_buildings b on b.id=i.building_id where b.plot_id=plot and i.quantity>0) then
  raise exception 'Empty this property''s secure storage before selling, auctioning or replacing its building.';
 end if;
 return coalesce(new,old);
end$$;
create trigger protect_district_storage before update or delete on public.game_districts for each row execute function game_private.protect_stored_goods();
create trigger protect_building_storage before update or delete on public.game_district_buildings for each row execute function game_private.protect_stored_goods();
create trigger protect_plot_storage before update or delete on public.game_district_plots for each row execute function game_private.protect_stored_goods();
create trigger protect_storage_auction before insert or update on public.game_plot_auctions for each row execute function game_private.protect_stored_goods();
create trigger protect_storage_offer before insert or update on public.game_plot_offers for each row execute function game_private.protect_stored_goods();

create function game_private.inventory_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();v_offset int:=greatest(0,least(coalesce(p_offset,0),1000000));
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid and season_id=s) then perform game_private.state();end if;
 perform game_private.ensure_districts(s);
 return jsonb_build_object(
 'season',(select to_jsonb(x) from public.game_seasons x where id=s),'server_time',clock_timestamp(),
 'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
 'player_id',uid,'cash',(select cash from public.game_players where id=uid),
 'goods',(select jsonb_agg(jsonb_build_object('id',id,'name',name,'category',inventory_category,'description',inventory_description) order by name) from public.game_goods),
 'carried',(select coalesce(jsonb_agg(jsonb_build_object('good_id',good_id,'quantity',quantity)),'[]') from public.game_inventory where season_id=s and player_id=uid and quantity>0),
 'stores',(select coalesce(jsonb_agg(x order by x.district,x.code),'[]') from (
  select b.id,b.plot_id,b.building_type,bt.name,p.code,d.name district,d.slug district_slug,
   b.construction_status,b.ready_at,b.condition,r.capacity,r.enabled,r.version,
   p.asking_price is not null or exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') as listed,
   p.status='locked' or d.status='lockdown' or exists(select 1 from public.game_district_territory where district_id=d.id and season_id=s and status='lockdown') as locked,
   coalesce((select sum(quantity) from public.game_storage_inventory where season_id=s and building_id=b.id and player_id=uid),0) as used,
   (select coalesce(jsonb_agg(jsonb_build_object('good_id',good_id,'quantity',quantity)),'[]') from public.game_storage_inventory where season_id=s and building_id=b.id and player_id=uid and quantity>0) as contents
  from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id join public.game_districts d on d.id=p.district_id join public.game_building_types bt on bt.id=b.building_type join public.game_storage_rules r on r.building_type=b.building_type
  where b.season_id=s and p.season_id=s and b.owner_type='player' and b.owner_id=uid and p.owner_type='player' and p.owner_id=uid and b.archived_at is null and p.archived_at is null and d.archived_at is null) x),
 'committed',(select coalesce(jsonb_agg(x),'[]') from (
  select good_id,sum(quantity) quantity,'market' destination from (
   select good_id,quantity from public.game_listings where season_id=s and seller_id=uid and status='active'
   union all select good_id,quantity from public.game_market_auctions where season_id=s and seller_id=uid and status='open') m group by good_id
  union all select f.good_id,sum(f.quantity),'refineries' from public.game_refinery_fuel f join public.game_refineries r on r.id=f.refinery_id join public.game_district_plots p on p.id=r.plot_id where r.season_id=s and p.owner_type='player' and p.owner_id=uid and f.quantity>0 group by f.good_id) x),
 'tool',jsonb_build_object('condition',coalesce((select durability from public.game_mining_tools where season_id=s and player_id=uid),0),'maximum',game_private.setting('mining_pickaxe_durability'),'working',exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working')),
 'max_transfer',game_private.setting('storage_max_transfer'),
 'history',(select coalesce(jsonb_agg(x order by x.id desc),'[]') from (select id,good_id,building_id,location,delta,quantity_after,reason,created_at from public.game_inventory_ledger where season_id=s and player_id=uid order by id desc limit 20 offset v_offset) x),
 'history_total',(select count(*) from public.game_inventory_ledger where season_id=s and player_id=uid),'offset',v_offset,
 'management',case when game_private.has_permission('storage.manage') then jsonb_build_object('rules',(select jsonb_agg(r) from public.game_storage_rules r),'building_types',(select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.game_building_types)) else null end
 );
end$$;
create function game_private.inventory_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();nonce uuid;prior game_private.inventory_requests;p public.game_district_plots;b public.game_district_buildings;r public.game_storage_rules;g text;n numeric;used bigint;result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid storage request.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh your inventory.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A transfer reference is required.';end if;
  -- Same coordinator and row order as district transfers and mining.
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.inventory_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This transfer reference was already used.';end if;
   return prior.result;
  end if;
  perform game_private.season_guard();
  if p_action not in ('store','retrieve') or p_action is null then raise exception 'Choose store or retrieve.';end if;
  select * into p from public.game_district_plots where id=(select plot_id from public.game_district_buildings where id=(p_payload->>'building_id')::uuid and season_id=s) and season_id=s for update;
  if not found or p.owner_type is distinct from 'player' or p.owner_id is distinct from uid or p.archived_at is not null then raise exception 'This is not your property.';end if;
  select * into b from public.game_district_buildings where id=(p_payload->>'building_id')::uuid and plot_id=p.id and season_id=s for update;
  if not found or b.owner_type is distinct from 'player' or b.owner_id is distinct from uid or b.archived_at is not null or b.construction_status<>'ready' then raise exception 'Storage requires your completed building.';end if;
  select * into r from public.game_storage_rules where building_type=b.building_type for share;
  if not found then raise exception 'This building does not provide storage.';end if;
  if p.status='locked' or not exists(select 1 from public.game_districts where id=p.district_id and archived_at is null and status<>'lockdown') or exists(select 1 from public.game_district_territory where season_id=s and district_id=p.district_id and status='lockdown') then raise exception 'Storage is inaccessible during this district lockdown.';end if;
  perform 1 from public.game_players where id=uid and season_id=s for update;
  if not found then raise exception 'Open the dashboard to initialize this season.';end if;
  g:=p_payload->>'good_id';if not exists(select 1 from public.game_goods where id=g) then raise exception 'Choose an existing item.';end if;
  if jsonb_typeof(p_payload->'quantity') is distinct from 'number' then raise exception 'Enter a whole item quantity.';end if;
  n:=(p_payload->>'quantity')::numeric;
  if n<>trunc(n) or n<1 or n>game_private.setting('storage_max_transfer') then raise exception 'Quantity is outside the transfer limit.';end if;
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason',case when p_action='store' then 'Stored at ' else 'Retrieved from ' end||p.code||' '||(select name from public.game_building_types where id=b.building_type),true);
  if p_action='store' then
   if not r.enabled then raise exception 'New storage deposits are paused. Existing stock can still be retrieved.';end if;
   if p.asking_price is not null or exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'Unlist this property and settle its offers before storing goods.';end if;
   select coalesce(sum(quantity),0) into used from public.game_storage_inventory where season_id=s and building_id=b.id;
   if used+n>r.capacity then raise exception 'This building does not have enough free storage space.';end if;
   update public.game_inventory set quantity=quantity-n::int where season_id=s and player_id=uid and good_id=g and quantity>=n;
   if not found then raise exception 'Not enough carried stock. Refresh your inventory.';end if;
   insert into public.game_storage_inventory(season_id,building_id,player_id,good_id,quantity) values(s,b.id,uid,g,n::int)
    on conflict(season_id,building_id,player_id,good_id) do update set quantity=game_storage_inventory.quantity+excluded.quantity;
  else
   update public.game_storage_inventory set quantity=quantity-n::int where season_id=s and building_id=b.id and player_id=uid and good_id=g and quantity>=n;
   if not found then raise exception 'Not enough stored stock. Refresh your inventory.';end if;
   insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,g,n::int)
    on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
  end if;
  result:=jsonb_build_object('message',case when p_action='store' then 'Items secured in your property.' else 'Items returned to your carried inventory.' end);
  insert into game_private.inventory_requests values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the quantity and refresh your inventory.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
create function game_private.inventory_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.game_storage_rules;reason text;
begin
 perform game_private.require_active();
 if not game_private.has_permission('storage.manage') then raise exception 'Owner inventory permission required.';end if;
 if not game_private.rate('storage_manage',60) then return jsonb_build_object('error','Too many edits. Try again later.');end if;
 begin
  perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid inventory control.';end if;
  reason:=btrim(p_payload->>'reason');
  if reason is null or length(reason) not between 5 and 500 then raise exception 'Add an audit reason of 5–500 characters.';end if;
  perform set_config('game.reason','Inventory rules: '||reason,true);
  if p_action='rule' then
   select * into r from public.game_storage_rules where building_type=p_payload->>'building_type' for update;
   if found and (p_payload->>'version')::int is distinct from r.version then raise exception 'These storage rules changed. Refresh first.';end if;
   insert into public.game_storage_rules(building_type,capacity,enabled) values(p_payload->>'building_type',(p_payload->>'capacity')::int,(p_payload->>'enabled')::boolean)
    on conflict(building_type) do update set capacity=excluded.capacity,enabled=excluded.enabled,version=game_storage_rules.version+1;
  elsif p_action='good' then
   update public.game_goods set inventory_category=p_payload->>'category',inventory_description=btrim(p_payload->>'description') where id=p_payload->>'good_id';
   if not found then raise exception 'Choose an existing item.';end if;
  else raise exception 'Unknown inventory control.';end if;
  return jsonb_build_object('message','Inventory rules saved and recorded in the audit history.');
 exception when check_violation or not_null_violation or foreign_key_violation or invalid_text_representation or numeric_value_out_of_range then return jsonb_build_object('error','Check the inventory rule values.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
create function public.inventory_state(p_offset int default 0) returns jsonb language sql security invoker set search_path='' as $$select game_private.inventory_state(p_offset)$$;
create function public.inventory_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.inventory_action(p_action,p_payload)$$;
create function public.inventory_manage(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.inventory_manage(p_action,p_payload)$$;
revoke all on function game_private.inventory_entry(),game_private.protect_stored_goods(),game_private.inventory_state(integer),game_private.inventory_action(text,jsonb),game_private.inventory_manage(text,jsonb),public.inventory_state(integer),public.inventory_action(text,jsonb),public.inventory_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.inventory_state(integer),game_private.inventory_action(text,jsonb),game_private.inventory_manage(text,jsonb),public.inventory_state(integer),public.inventory_action(text,jsonb),public.inventory_manage(text,jsonb) to authenticated;
-- Secure stock retains its book value. Existing market escrow, bank funds and
-- refinery stock contributions remain unchanged.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as stock_value,' in definition)=0 then raise exception 'Review stored-goods net-worth integration';end if;
 execute replace(definition,' as stock_value,',' +coalesce((select sum(si.quantity::numeric*v.unit_value) from public.game_storage_inventory si join public.game_season_valuations v on v.season_id=si.season_id and v.good_id=si.good_id where si.season_id=p_season and si.player_id=sp.player_id),0) as stock_value,');
end$$;
notify pgrst,'reload schema';
