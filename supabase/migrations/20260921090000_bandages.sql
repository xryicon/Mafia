-- Bandages reuse seasonal crafting, scavenging, inventory ledgers and private vitals.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce bandages and learnable medical blueprint',true);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots) values
 ('bandages','Bandages','Crafting station',1,1,60,false,'medical','Use one to restore health up to your normal maximum. Carry it or equip it in Medical. Healing is set by the city Owner.',100,array['medical']),
 ('bandages_blueprint','Bandages blueprint','Found blueprint',1,1,60,false,'blueprints','Learn this blueprint to craft bandages for the current season. Learning consumes one blueprint.',50,'{}');
insert into public.game_season_valuations(season_id,good_id,unit_value)
 select s.id,g.id,0 from public.game_seasons s cross join public.game_goods g where g.id in ('bandages','bandages_blueprint') on conflict do nothing;
insert into public.game_crafting_recipes(id,name,description,blueprint_good_id,output_good_id,output_units,seconds,materials)
 values('bandages','Bandages','Cut and fold cloth into bandages for your medical supplies.','bandages_blueprint','bandages',5,60,'{"silk":1}');
insert into public.game_settings(key,value,minimum,maximum) values('bandage_heal_amount',20,1,1000);
alter table public.game_bin_rules add column bandages_blueprint_chance numeric(5,2) not null default 0 check(bandages_blueprint_chance between 0 and 100);
-- Use up to 3 percentage points of the existing empty result; preserve configured prizes.
update public.game_bin_rules set bandages_blueprint_chance=least(3,greatest(0,100-cash_chance-pickaxe_chance-lockpick_chance-pistol_blueprint_chance-bullet_blueprint_chance)),version=version+1;
alter table public.game_bin_rules drop constraint game_bin_rules_total_chance_check;
alter table public.game_bin_rules add constraint game_bin_rules_total_chance_check check(cash_chance+pickaxe_chance+lockpick_chance+pistol_blueprint_chance+bullet_blueprint_chance+bandages_blueprint_chance<=100);
alter table public.game_bin_dives drop constraint game_bin_dives_outcome_check;
alter table public.game_bin_dives add constraint game_bin_dives_outcome_check check(outcome in('nothing','cash','pickaxe','lockpick','pistol_blueprint','bullet_blueprint','bandages_blueprint'));
create or replace function game_private.bin_loot_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; uid uuid:=auth.uid();
begin
 perform game_private.require_active();
 s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid) then perform game_private.state(); end if;
 return jsonb_build_object(
  'season',(select jsonb_build_object('id',id,'name',name,'status',status,'ends_at',ends_at) from public.game_seasons where id=s),
  'server_time',clock_timestamp(),
  'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
  'rules',(select to_jsonb(r)-'id' from public.game_bin_rules r),
  'can_manage',game_private.has_permission('bin_diving.manage'),
  'districts',(select coalesce(jsonb_agg(x order by x.name),'[]') from (
   select d.id,d.slug,d.name,d.tagline,d.image_url,d.police_heat,
    case when d.status='lockdown' or t.status='lockdown' then 'lockdown' else coalesce(t.status,d.status) end status
   from public.game_districts d left join public.game_district_territory t on t.district_id=d.id and t.season_id=s
   where d.archived_at is null) x),
  'cash',(select cash from public.game_players where id=uid),
  'inventory',(select coalesce(jsonb_object_agg(good_id,quantity),'{}') from public.game_inventory where season_id=s and player_id=uid and good_id in ('pickaxe','pistol_blueprint','bullet_blueprint','lockpick','bandages_blueprint')),
  'tool_condition',coalesce((select durability from public.game_mining_tools where season_id=s and player_id=uid),0),
  'tool_max',game_private.setting('mining_pickaxe_durability'),
  'mining_shift',exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working'),
  'ready_at',(select max(ready_at) from public.game_bin_dives where season_id=s and player_id=uid),
  'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from (
   select id,district_id,district_name,outcome,cash,created_at,ready_at from public.game_bin_dives
   where season_id=s and player_id=uid order by created_at desc limit 30) x)
 );
end $$;

create or replace function game_private.bin_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 s uuid; uid uuid:=auth.uid(); nonce uuid; prior game_private.bin_requests;
 r public.game_bin_rules; d public.game_districts; receipt public.game_bin_dives;
 stamp timestamptz; ready timestamptz; roll integer; amount integer:=0; outcome text; result jsonb; reason text;
begin
 perform game_private.require_active(); if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid action details.'; end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh before continuing.'; end if;
  nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null then raise exception 'A request ID is required.'; end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.bin_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This request ID was already used for a different action.'; end if;
   return prior.result;
  end if;
  if p_action='configure' then
   if not game_private.has_permission('bin_diving.manage') then raise exception 'Owner permission required.'; end if;
   reason:=btrim(p_payload->>'reason');
   if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5â€“500 characters for the audit log.'; end if;
   select * into strict r from public.game_bin_rules for update;
   if (p_payload->>'version')::integer is distinct from r.version then raise exception 'Another edit was saved. Refresh and review the current rules.'; end if;
   perform set_config('game.reason','Bin diving rules: '||reason,true);
   update public.game_bin_rules set enabled=(p_payload->>'enabled')::boolean,
    cooldown_seconds=(p_payload->>'cooldown_seconds')::integer,cash_min=(p_payload->>'cash_min')::integer,cash_max=(p_payload->>'cash_max')::integer,
    cash_chance=(p_payload->>'cash_chance')::numeric,pickaxe_chance=(p_payload->>'pickaxe_chance')::numeric,
    pistol_blueprint_chance=(p_payload->>'pistol_blueprint_chance')::numeric,bullet_blueprint_chance=(p_payload->>'bullet_blueprint_chance')::numeric,
    lockpick_chance=(p_payload->>'lockpick_chance')::numeric,bandages_blueprint_chance=coalesce((p_payload->>'bandages_blueprint_chance')::numeric,r.bandages_blueprint_chance),version=version+1;
   result:=jsonb_build_object('message','Bin diving rules saved. New districts use these rules automatically.');
  else
   perform game_private.season_guard();
   select * into strict r from public.game_bin_rules for share;
   if p_action='dive' then
    if not r.enabled then raise exception 'Bin diving is paused by the city Owner.'; end if;
    select * into d from public.game_districts where id=(p_payload->>'district_id')::uuid and archived_at is null for share;
    if not found then raise exception 'This district is not open.'; end if;
    if d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') then raise exception 'This district is in lockdown.'; end if;
   elsif p_action<>'equip' then raise exception 'Unknown bin diving action.'; end if;
   perform 1 from public.game_players where id=uid and season_id=s for update;
   if not found then raise exception 'Open your dashboard to initialize this season.'; end if;
   perform set_config('game.reason','Bin diving '||p_action||': '||nonce,true);
   if p_action='equip' then
    if exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working') then raise exception 'Finish your mining shift before replacing equipment.'; end if;
    update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=uid and good_id='pickaxe' and quantity>0;
    if not found then raise exception 'Find a pickaxe by bin diving or buy one from another player on the market.'; end if;
    insert into public.game_mining_tools(season_id,player_id,durability) values(s,uid,game_private.setting('mining_pickaxe_durability'))
     on conflict(season_id,player_id) do update set durability=excluded.durability
     where public.game_mining_tools.durability<excluded.durability;
    if not found then raise exception 'Your current pickaxe is already in full condition.'; end if;
    result:=jsonb_build_object('message','Pickaxe equipped. Visit a public mine to put it to work.');
   else
    stamp:=clock_timestamp();
    select max(ready_at) into ready from public.game_bin_dives where season_id=s and player_id=uid;
    if ready>stamp then raise exception 'Give the streets a moment. Your cooldown applies across every district.'; end if;
    if (r.bandages_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'bandages_blueprint',1)) or (r.pickaxe_chance>0 and not game_private.inventory_fits(s,uid,'pickaxe',1)) or (r.lockpick_chance>0 and not game_private.inventory_fits(s,uid,'lockpick',1)) or (r.pistol_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'pistol_blueprint',1)) or (r.bullet_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'bullet_blueprint',1)) then raise exception 'Free space and weight in Inventory before searching for loot.';end if;
    roll:=floor(random()*10000)::integer;
    outcome:=case when roll<r.cash_chance*100 then 'cash'
     when roll<(r.cash_chance+r.pickaxe_chance)*100 then 'pickaxe'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance)*100 then 'pistol_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance)*100 then 'bullet_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance)*100 then 'lockpick'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance+r.bandages_blueprint_chance)*100 then 'bandages_blueprint' else 'nothing' end;
    if outcome='cash' then amount:=r.cash_min+floor(random()*(r.cash_max-r.cash_min+1))::integer; end if;
    insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at)
     values(s,uid,d.id,d.name,outcome,amount,r.version,stamp,stamp+make_interval(secs=>r.cooldown_seconds)) returning * into receipt;
    if outcome='cash' then perform game_private.district_wallet(uid,amount,'Bin diving: '||receipt.id);
    elsif outcome<>'nothing' then
     insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,outcome,1)
      on conflict(season_id,player_id,good_id) do update set quantity=public.game_inventory.quantity+1;
    end if;
    result:=jsonb_build_object('message',case when outcome='nothing' then 'Nothing useful this time. The next bin tells another story.' else 'You found something worth keeping.' end,'receipt',to_jsonb(receipt));
   end if;
  end if;
  insert into game_private.bin_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception
  when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the values: chances must total at most 100%, cash must be a valid range, and cooldown must be 1â€“86,400 seconds.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;

-- Existing inventory endpoint delegates unchanged actions; the retired helper is not callable by players.
alter function game_private.inventory_action(text,jsonb) rename to inventory_action_before_bandages;
create function game_private.inventory_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.inventory_requests;g public.game_inventory_gear;v jsonb;hp numeric;normal numeric;healed numeric;result jsonb;key text;
begin
 if p_action<>'use_bandage' then return game_private.inventory_action_before_bandages(p_action,p_payload);end if;
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
  perform 1 from public.game_season_players where season_id=s and player_id=u for update;
  if not found then raise exception 'Open your dashboard to initialize this season.';end if;
  v:=game_private.vitals_state();hp:=(v->>'health')::numeric;normal:=(v->>'health_max')::numeric;
  if hp>=normal then raise exception 'Your health is already full. No bandage was used.';end if;
  healed:=least(game_private.setting('bandage_heal_amount'),normal-hp);
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason','Use bandage: '||nonce,true);
  key:=p_payload->>'item_key';
  if key='good:bandages' then
   update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=u and good_id='bandages' and quantity>0;
   if not found then raise exception 'Carry a bandage in your inventory first.';end if;
  elsif key like 'gear:%' then
   select * into g from public.game_inventory_gear where id=substring(key from 6)::uuid and season_id=s and player_id=u and good_id='bandages' and quantity>0 and location in ('carried','equipped') for update;
   if not found then raise exception 'Select your carried or equipped bandage. Retrieve stored supplies first.';end if;
   update public.game_inventory_gear set quantity=quantity-1,location=case when quantity=1 then 'retired' else location end,
    equipment_slot=case when quantity=1 then null else equipment_slot end where id=g.id;
  else raise exception 'Select a bandage from your inventory or Medical slot.';end if;
  update public.game_season_players set health=hp+healed where season_id=s and player_id=u;
  perform game_private.inventory_sync(s,u);
  result:=jsonb_build_object('message','Bandage used. Restored '||healed||' health.','healed',healed,'health',hp+healed);
  insert into game_private.inventory_requests values(s,u,nonce,p_action,p_payload,result);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check the item and refresh inventory.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
alter function game_private.inventory_state(integer) rename to inventory_state_before_bandages;
create function game_private.inventory_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return game_private.inventory_state_before_bandages(p_offset)||jsonb_build_object('vitals',game_private.vitals_state(),'bandage_heal',game_private.setting('bandage_heal_amount'));
end$$;
revoke all on function game_private.inventory_action_before_bandages(text,jsonb),game_private.inventory_state_before_bandages(integer),game_private.inventory_action(text,jsonb),game_private.inventory_state(integer) from public,anon,authenticated;
grant execute on function game_private.inventory_action(text,jsonb),game_private.inventory_state(integer) to authenticated;
notify pgrst,'reload schema';
