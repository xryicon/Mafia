-- Refinery titles use the existing plot/building/business registry.
insert into public.game_permissions(id,owner_only) values('refineries.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('refinery_max_cash_fee',10000,0,1000000),('refinery_max_output_percent',50,0,90),
 ('refinery_max_batches',100,1,10000),('refinery_default_cash_fee',20,0,1000000),
 ('refinery_default_output_percent',10,0,90),('refinery_fuel_capacity',10000,1,100000000),
 ('refinery_iron_value',100,0,1000000),('refinery_copper_value',150,0,1000000);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available) values
 ('iron-ingot','Iron ingots','Ore refining',1,1,60,false),
 ('copper-ingot','Copper ingots','Ore refining',1,1,60,false);
create table public.game_refining_recipes(
 id text primary key check(id~'^[a-z0-9-]{2,50}$'),name text not null check(length(name) between 2 and 80),
 input_good_id text not null references public.game_goods(id),output_good_id text not null references public.game_goods(id),
 fuel_good_id text not null references public.game_goods(id),
 input_units integer not null check(input_units between 1 and 10000),
 output_units integer not null check(output_units between 1 and 10000),
 fuel_units integer not null check(fuel_units between 1 and 10000),
 enabled boolean not null default true,version integer not null default 1,
 check(input_good_id<>output_good_id and fuel_good_id<>output_good_id)
);
insert into public.game_refining_recipes values
 ('iron','Iron refining','iron-ore','iron-ingot','coal',20,10,5,true,1),
 ('copper','Copper refining','copper-ore','copper-ingot','coal',20,10,5,true,1);
create index refinery_recipe_input on public.game_refining_recipes(input_good_id);
create index refinery_recipe_output on public.game_refining_recipes(output_good_id);
create index refinery_recipe_fuel on public.game_refining_recipes(fuel_good_id);
create table public.game_refineries(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 plot_id uuid not null unique references public.game_district_plots(id),
 business_id uuid not null unique references public.game_district_businesses(id),
 fee_mode text not null default 'cash' check(fee_mode in ('cash','output')),
 cash_fee integer not null check(cash_fee between 0 and 1000000),
 output_percent numeric(5,2) not null check(output_percent between 0 and 90),
 version integer not null default 1
);
create index refinery_season on public.game_refineries(season_id);
create table public.game_refinery_fuel(
 refinery_id uuid not null references public.game_refineries(id),
 good_id text not null references public.game_goods(id),
 quantity integer not null check(quantity between 0 and 100000000),primary key(refinery_id,good_id)
);
create index refinery_fuel_good on public.game_refinery_fuel(good_id);
create table public.game_refinery_receipts(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 refinery_id uuid not null references public.game_refineries(id),
 customer_id uuid not null references public.game_players(id),owner_id uuid not null references public.game_players(id),
 recipe_id text not null references public.game_refining_recipes(id),recipe_version integer not null,tariff_version integer not null,
 input_good_id text not null references public.game_goods(id),input_quantity integer not null check(input_quantity>0),
 output_good_id text not null references public.game_goods(id),output_quantity integer not null check(output_quantity>0),
 fuel_good_id text not null references public.game_goods(id),fuel_quantity integer not null check(fuel_quantity>0),
 cash_fee bigint not null check(cash_fee>=0),owner_quantity integer not null check(owner_quantity>=0),
 customer_quantity integer not null check(customer_quantity>0),created_at timestamptz not null default now(),
 check(customer_quantity+owner_quantity=output_quantity),check(cash_fee=0 or owner_quantity=0)
);
create index refinery_receipt_customer on public.game_refinery_receipts(customer_id,season_id,created_at desc);
create index refinery_receipt_owner on public.game_refinery_receipts(owner_id,season_id,created_at desc);
create index refinery_receipt_refinery on public.game_refinery_receipts(refinery_id,created_at desc);
create index refinery_receipt_season on public.game_refinery_receipts(season_id);
create index refinery_receipt_recipe on public.game_refinery_receipts(recipe_id);
create index refinery_receipt_input on public.game_refinery_receipts(input_good_id);
create index refinery_receipt_output on public.game_refinery_receipts(output_good_id);
create index refinery_receipt_fuel on public.game_refinery_receipts(fuel_good_id);
create table public.game_refinery_fuel_ledger(
 id bigint generated always as identity primary key,refinery_id uuid not null references public.game_refineries(id),
 actor_id uuid not null references public.game_players(id),good_id text not null references public.game_goods(id),
 delta integer not null check(delta<>0),reason text not null,created_at timestamptz not null default now()
);
create index refinery_fuel_ledger_refinery on public.game_refinery_fuel_ledger(refinery_id,created_at desc);
create index refinery_fuel_ledger_actor on public.game_refinery_fuel_ledger(actor_id);
create index refinery_fuel_ledger_good on public.game_refinery_fuel_ledger(good_id);
create table game_private.refinery_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,
 created_at timestamptz not null default now(),primary key(season_id,player_id,request_id)
);
create index refinery_request_player on game_private.refinery_requests(player_id);
do $$ declare t text;begin
 foreach t in array array['game_refining_recipes','game_refineries','game_refinery_fuel','game_refinery_receipts','game_refinery_fuel_ledger'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  if t in ('game_refinery_receipts','game_refinery_fuel_ledger') then
   execute format('create trigger refinery_immutable before update or delete or truncate on public.%I for each statement execute function game_private.district_immutable()',t);
  else execute format('create trigger refinery_audit after insert or update or delete on public.%I for each row execute function game_private.audit_change()',t);end if;
 end loop;
end $$;
alter table game_private.refinery_requests enable row level security;
revoke all on game_private.refinery_requests from public,anon,authenticated;
create trigger refinery_requests_immutable before update or delete or truncate on game_private.refinery_requests for each statement execute function game_private.district_immutable();

insert into public.game_building_types(id,name,cost,construction_seconds,capacity_required,minimum_utility,minimum_infrastructure,business_type)
 values('refinery','Ore Refinery',25000,900,2,50,50,'Refinery');
update public.game_zoning set allowed_buildings=array_append(allowed_buildings,'refinery') where id='industrial' and not ('refinery'=any(allowed_buildings));
insert into public.game_district_entities(name,entity_type) values('Blackwater Refining Authority','city') on conflict(name) do nothing;
-- A new plot preserves every existing player's property.
insert into public.game_plot_templates(district_id,code,polygon,size,zoning,status,base_price,utility_level,infrastructure_level,build_capacity,entity_id,building_type,business_name,description)
select d.id,'RF-01','[[980,150],[1110,150],[1110,310],[980,310]]',2400,'industrial','available',35000,80,80,3,e.id,'refinery','Copper Quay Refinery',
 'A coal-fired ore refinery. Purchase the property, stock its fuel bunker and earn fees from player refining.'
from public.game_districts d cross join public.game_district_entities e where d.slug='the-waterfront' and e.name='Blackwater Refining Authority';

alter function game_private.ensure_districts(uuid) rename to ensure_districts_before_refineries;
create function game_private.ensure_districts(s uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform game_private.ensure_districts_before_refineries(s);
 if exists(select 1 from public.game_district_businesses b join public.game_district_buildings x on x.id=b.building_id
  where b.season_id=s and x.building_type='refinery' and x.construction_status='ready' and b.archived_at is null and x.archived_at is null
  and not exists(select 1 from public.game_refineries r where r.business_id=b.id)) then
  perform pg_advisory_xact_lock(4704020);
  perform set_config('game.reason','Register seasonal refineries',true);
  insert into public.game_refineries(season_id,plot_id,business_id,cash_fee,output_percent)
  select s,b.plot_id,b.id,least(game_private.setting('refinery_default_cash_fee'),game_private.setting('refinery_max_cash_fee')),
   least(game_private.setting('refinery_default_output_percent'),game_private.setting('refinery_max_output_percent'))
  from public.game_district_businesses b join public.game_district_buildings x on x.id=b.building_id
  where b.season_id=s and x.building_type='refinery' and x.construction_status='ready' and b.archived_at is null and x.archived_at is null
  on conflict(plot_id) do nothing;
 end if;
 insert into public.game_season_valuations(season_id,good_id,unit_value)
 values(s,'iron-ingot',game_private.setting('refinery_iron_value')),(s,'copper-ingot',game_private.setting('refinery_copper_value')) on conflict do nothing;
end $$;
revoke all on function game_private.ensure_districts_before_refineries(uuid),game_private.ensure_districts(uuid) from public,anon,authenticated;
select game_private.ensure_districts(game_private.current_season());

-- Preserve fuel value in net worth when stock is moved out of a player's inventory.
do $$ declare definition text;begin
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as stock_value,' in definition)=0 then raise exception 'Review season valuation integration';end if;
 execute replace(definition,' as stock_value,',
 ' +coalesce((select sum(f.quantity::numeric*v.unit_value) from public.game_refinery_fuel f join public.game_refineries r on r.id=f.refinery_id join public.game_district_plots rp on rp.id=r.plot_id join public.game_season_valuations v on v.season_id=r.season_id and v.good_id=f.good_id where r.season_id=p_season and rp.owner_type=''player'' and rp.owner_id=sp.player_id),0) as stock_value,');
end $$;

create function game_private.refinery_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; uid uuid:=auth.uid();begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid) then perform game_private.state();end if;
 perform game_private.ensure_districts(s);
 return jsonb_build_object('player_id',uid,'season',(select to_jsonb(x) from public.game_seasons x where id=s),
 'server_time',clock_timestamp(),'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
 'can_manage',game_private.has_permission('refineries.manage'),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'refinery_%'),
 'cash',(select cash from public.game_players where id=uid),
 'goods',(select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name) from public.game_goods),
 'inventory',(select coalesce(jsonb_object_agg(good_id,quantity),'{}') from public.game_inventory where season_id=s and player_id=uid),
 'recipes',(select coalesce(jsonb_agg(to_jsonb(r) order by r.name),'[]') from public.game_refining_recipes r),
 'refineries',(select coalesce(jsonb_agg(x order by x.name),'[]') from (
  select r.*,p.code,p.owner_type,p.owner_id,game_private.district_owner_name(p.owner_type,p.owner_id) owner_name,
   b.name,b.status,b.description,d.name district_name,d.slug district_slug,d.id district_id,
   (d.status='lockdown' or coalesce(t.status='lockdown',false) or p.status='locked') locked,
   p.version plot_version,coalesce(p.asking_price,ceil(p.base_price*d.property_value_index/100)) price,
   coalesce(p.tax_rate,d.tax_rate) tax_rate,p.status='available' or p.asking_price is not null for_sale,
   exists(select 1 from public.game_plot_auctions a where a.plot_id=p.id and a.status='open') auction,
   coalesce((select jsonb_object_agg(f.good_id,f.quantity) from public.game_refinery_fuel f where f.refinery_id=r.id),'{}') fuel,
   coalesce((select sum(cash_fee) from public.game_refinery_receipts z where z.refinery_id=r.id and z.owner_id=uid),0) my_cash_revenue,
   coalesce((select jsonb_object_agg(y.output_good_id,y.quantity) from (select output_good_id,sum(owner_quantity) quantity from public.game_refinery_receipts z where z.refinery_id=r.id and z.owner_id=uid group by output_good_id) y),'{}') my_output_revenue
  from public.game_refineries r join public.game_district_plots p on p.id=r.plot_id
   join public.game_district_businesses b on b.id=r.business_id join public.game_district_buildings bl on bl.id=b.building_id
   join public.game_districts d on d.id=p.district_id left join public.game_district_territory t on t.season_id=s and t.district_id=d.id
  where r.season_id=s and p.archived_at is null and b.archived_at is null and bl.archived_at is null
   and bl.construction_status='ready' and d.archived_at is null) x),
 'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from (select z.*,b.name refinery_name from public.game_refinery_receipts z join public.game_refineries r on r.id=z.refinery_id join public.game_district_businesses b on b.id=r.business_id where z.season_id=s and (z.customer_id=uid or z.owner_id=uid) order by z.created_at desc limit 40) x)
 );
end $$;

create function game_private.refinery_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid;uid uuid:=auth.uid();nonce uuid; prior game_private.refinery_requests; result jsonb; r public.game_refineries;
 p public.game_district_plots;b public.game_district_businesses;recipe public.game_refining_recipes;receipt public.game_refinery_receipts;
 qty integer;input_qty integer;output_qty integer;fuel_qty integer;share integer:=0;fee bigint:=0;reason text;own boolean;fuel text;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid action details.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the refinery.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A request ID is required.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.refinery_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This request ID was used for a different action.';end if;
   return prior.result;
  end if;
  if p_action='recipe' then
   if not game_private.has_permission('refineries.manage') then raise exception 'Owner permission required.';end if;
   reason:=btrim(p_payload->>'reason');if reason is null or length(reason) not between 5 and 500 then raise exception 'Add an audit reason of 5–500 characters.';end if;
   select * into recipe from public.game_refining_recipes where id=p_payload->>'id' for update;
   if not found or (p_payload->>'version')::integer is distinct from recipe.version then raise exception 'Recipe changed. Refresh before saving.';end if;
   perform set_config('game.reason','Refining recipe: '||reason,true);
   update public.game_refining_recipes set name=btrim(p_payload->>'name'),input_good_id=p_payload->>'input_good_id',
    output_good_id=p_payload->>'output_good_id',fuel_good_id=p_payload->>'fuel_good_id',input_units=(p_payload->>'input_units')::integer,
    output_units=(p_payload->>'output_units')::integer,fuel_units=(p_payload->>'fuel_units')::integer,enabled=(p_payload->>'enabled')::boolean,version=version+1 where id=recipe.id;
   result:=jsonb_build_object('message','Refining recipe saved. Future orders use the new recipe.');
  else
   perform game_private.season_guard();perform game_private.ensure_districts(s);
   select p0.* into p from public.game_district_plots p0 join public.game_refineries r0 on r0.plot_id=p0.id
    where r0.id=(p_payload->>'refinery_id')::uuid and r0.season_id=s and p0.archived_at is null for update of p0;
   if not found then raise exception 'Refinery unavailable in this season.';end if;
   select * into strict r from public.game_refineries where plot_id=p.id for update;
   select b0.* into b from public.game_district_businesses b0 join public.game_district_buildings bl on bl.id=b0.building_id
    where b0.id=r.business_id and b0.archived_at is null and bl.archived_at is null and bl.construction_status='ready' for update of b0;
   if not found or not exists(select 1 from public.game_districts where id=p.district_id and archived_at is null) then raise exception 'Refinery unavailable.';end if;
   own:=p.owner_type='player' and p.owner_id=uid;
   if p_action<>'buy' then perform id from public.game_players where id in(uid,case when p.owner_type='player' then p.owner_id end) order by id for update;end if;
   if p_action='buy' then
    result:=game_private.district_act('buy',jsonb_build_object('plot_id',p.id,'season_id',s,'version',p_payload->'plot_version','total',p_payload->'total'));
    result:=jsonb_build_object('message','Refinery acquired. Set your fees and supply fuel to open for customers.');
   else
    if (p_payload->>'plot_version')::integer is distinct from p.version or (p_payload->>'version')::integer is distinct from r.version then raise exception 'Ownership or fees changed. Refresh and review the quote.';end if;
    perform set_config('game.reason','Refinery '||p_action||': '||nonce,true);
    if p_action='settings' then
     if not own then raise exception 'Only the refinery owner can change fees.';end if;
     if (p_payload->>'cash_fee')::integer>game_private.setting('refinery_max_cash_fee') or (p_payload->>'output_percent')::numeric>game_private.setting('refinery_max_output_percent') then raise exception 'Fees exceed the city limits.';end if;
     update public.game_refineries set fee_mode=p_payload->>'fee_mode',cash_fee=(p_payload->>'cash_fee')::integer,
      output_percent=(p_payload->>'output_percent')::numeric,version=version+1 where id=r.id;
     update public.game_district_businesses set status=p_payload->>'status' where id=b.id;
     perform game_private.district_event(p.district_id,'business','refinery_terms',b.name||' updated its refining terms',p.id,b.id);
     result:=jsonb_build_object('message','Refinery fees and opening status saved.');
    elsif p_action in ('stock','withdraw') then
     if not own then raise exception 'Only the refinery owner can manage fuel.';end if;
     qty:=(p_payload->>'quantity')::integer;fuel:=p_payload->>'good_id';
     if qty is null or qty<1 or qty>game_private.setting('refinery_fuel_capacity') then raise exception 'Enter a valid fuel quantity.';end if;
     if p_action='stock' then
      if not exists(select 1 from public.game_refining_recipes where fuel_good_id=fuel) then raise exception 'Choose a refinery fuel.';end if;
      if coalesce((select sum(quantity) from public.game_refinery_fuel where refinery_id=r.id),0)+qty>game_private.setting('refinery_fuel_capacity') then raise exception 'The fuel bunker is full.';end if;
      update public.game_inventory set quantity=quantity-qty where season_id=s and player_id=uid and good_id=fuel and quantity>=qty;
      if not found then raise exception 'Not enough fuel in your inventory. Buy it from the player market.';end if;
      insert into public.game_refinery_fuel(refinery_id,good_id,quantity) values(r.id,fuel,qty)
       on conflict(refinery_id,good_id) do update set quantity=game_refinery_fuel.quantity+excluded.quantity;
     else
      update public.game_refinery_fuel set quantity=quantity-qty where refinery_id=r.id and good_id=fuel and quantity>=qty;
      if not found then raise exception 'Not enough fuel in the bunker.';end if;
      insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,fuel,qty)
       on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
     end if;
     insert into public.game_refinery_fuel_ledger(refinery_id,actor_id,good_id,delta,reason) values(r.id,uid,fuel,case when p_action='stock' then qty else -qty end,p_action);
     result:=jsonb_build_object('message','Fuel moved. The refinery owner pays for every batch burned.');
    elsif p_action='refine' then
     if p.owner_type<>'player' or b.status<>'open' or p.status='locked'
      or exists(select 1 from public.game_districts where id=p.district_id and status='lockdown')
      or exists(select 1 from public.game_district_territory where season_id=s and district_id=p.district_id and status='lockdown') then raise exception 'This refinery is not accepting orders.';end if;
     if exists(select 1 from public.game_players where id=p.owner_id and deleted_at is not null) or exists(select 1 from public.game_sanctions where player_id=p.owner_id and kind='ban' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'This refinery is unavailable.';end if;
     select * into recipe from public.game_refining_recipes where id=p_payload->>'recipe_id' and enabled for share;
     if not found or (p_payload->>'recipe_version')::integer is distinct from recipe.version then raise exception 'Recipe changed. Refresh and review the output.';end if;
     qty:=(p_payload->>'batches')::integer;
     if qty is null or qty<1 or qty>game_private.setting('refinery_max_batches') then raise exception 'Choose a valid number of batches.';end if;
     input_qty:=qty*recipe.input_units;output_qty:=qty*recipe.output_units;fuel_qty:=qty*recipe.fuel_units;
     if not own then
      if r.fee_mode='cash' then fee:=qty::bigint*r.cash_fee;else share:=ceil(output_qty::numeric*r.output_percent/100);end if;
     end if;
     if output_qty-share<1 then raise exception 'This order would leave no output. Choose more batches.';end if;
     update public.game_inventory set quantity=quantity-input_qty where season_id=s and player_id=uid and good_id=recipe.input_good_id and quantity>=input_qty;
     if not found then raise exception 'Not enough ore in your inventory.';end if;
     update public.game_refinery_fuel set quantity=quantity-fuel_qty where refinery_id=r.id and good_id=recipe.fuel_good_id and quantity>=fuel_qty;
     if not found then raise exception 'The refinery needs more fuel. The owner must restock before this order can run.';end if;
     insert into public.game_refinery_receipts(season_id,refinery_id,customer_id,owner_id,recipe_id,recipe_version,tariff_version,
      input_good_id,input_quantity,output_good_id,output_quantity,fuel_good_id,fuel_quantity,cash_fee,owner_quantity,customer_quantity)
     values(s,r.id,uid,p.owner_id,recipe.id,recipe.version,r.version,recipe.input_good_id,input_qty,recipe.output_good_id,output_qty,
      recipe.fuel_good_id,fuel_qty,fee,share,output_qty-share) returning * into receipt;
     if fee>0 then
      perform game_private.district_wallet(uid,-fee,'Refining fee: '||receipt.id);
      perform game_private.district_wallet(p.owner_id,fee,'Refinery revenue: '||receipt.id);
     end if;
     insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,recipe.output_good_id,output_qty-share)
      on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
     if share>0 then insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,p.owner_id,recipe.output_good_id,share)
      on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;end if;
     insert into public.game_refinery_fuel_ledger(refinery_id,actor_id,good_id,delta,reason) values(r.id,uid,recipe.fuel_good_id,-fuel_qty,'Refining: '||receipt.id);
     perform game_private.record_metric(uid,'production',output_qty);
     perform game_private.district_event(p.district_id,'resources','ore_refined',b.name||' refined '||input_qty||' units of ore',p.id,b.id,null,jsonb_build_object('receipt_id',receipt.id,'input',input_qty,'output',output_qty));
     result:=jsonb_build_object('message','Ore refined. Your output is in your inventory.','receipt',to_jsonb(receipt));
    else raise exception 'Unknown refinery action.';end if;
   end if;
  end if;
  insert into game_private.refinery_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation or foreign_key_violation then return jsonb_build_object('error','Check your quantities, fees and selected goods.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;
create function public.refinery_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.refinery_state()$$;
create function public.refinery_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.refinery_action(p_action,p_payload)$$;
revoke all on function game_private.refinery_state(),game_private.refinery_action(text,jsonb),public.refinery_state(),public.refinery_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.refinery_state(),game_private.refinery_action(text,jsonb),public.refinery_state(),public.refinery_action(text,jsonb) to authenticated;

