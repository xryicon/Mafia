-- Broken weapons become tradeable materials in one replay-safe inventory transaction.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Add broken weapon recycling',true);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots)
 values('scrap-metal','Scrap metal','Salvaged material',1,1,60,false,'materials','Metal salvaged from broken weapons. Carry, store or trade it.',250,'{}');
insert into public.game_season_valuations(season_id,good_id,unit_value) select id,'scrap-metal',0 from public.game_seasons on conflict do nothing;
insert into public.game_settings(key,value,minimum,maximum) values('weapon_scrap_units',1,1,1000);
alter function game_private.inventory_action(text,jsonb) rename to inventory_action_before_scrapping;
create function game_private.inventory_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.inventory_requests;g public.game_inventory_gear;units integer;result jsonb;
begin
 if p_action<>'scrap_weapon' then return game_private.inventory_action_before_scrapping(p_action,p_payload);end if;
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
  if p_payload->>'item_key' not like 'gear:%' then raise exception 'Select an individual broken weapon.';end if;
  select * into g from public.game_inventory_gear where id=substring(p_payload->>'item_key' from 6)::uuid and season_id=s and player_id=u and quantity=1 and location in ('carried','equipped') for update;
  if not found then raise exception 'Select your carried or equipped weapon. Retrieve stored weapons first.';end if;
  if g.condition is distinct from 0 or not exists(select 1 from public.game_goods where id=g.good_id and inventory_category='weapons' and equipment_slots&&array['primary','secondary']) then raise exception 'Only weapons at 0 condition can be scrapped.';end if;
  if exists(select 1 from public.game_range_sessions where season_id=s and player_id=u and weapon_id=g.id and status='active' and ends_at>clock_timestamp()) then raise exception 'Finish your shooting range session first.';end if;
  units:=game_private.setting('weapon_scrap_units');
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason','Scrap broken weapon: '||g.id,true);
  update public.game_inventory_gear set quantity=0,location='retired',equipment_slot=null,building_id=null where id=g.id;
  -- Capacity and inventory ledger triggers apply. Any failure rolls back the weapon retirement too.
  insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'scrap-metal',units)
   on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
  perform game_private.inventory_sync(s,u);
  result:=jsonb_build_object('message','Broken weapon scrapped. Received '||units||' scrap metal.','scrap_units',units,'weapon_id',g.id);
  insert into game_private.inventory_requests values(s,u,nonce,p_action,p_payload,result);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check the selected weapon and refresh inventory.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
alter function game_private.inventory_state(integer) rename to inventory_state_before_scrapping;
create function game_private.inventory_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
begin return game_private.inventory_state_before_scrapping(p_offset)||jsonb_build_object('weapon_scrap_units',game_private.setting('weapon_scrap_units'));end$$;
revoke all on function game_private.inventory_action_before_scrapping(text,jsonb),game_private.inventory_action(text,jsonb),game_private.inventory_state_before_scrapping(integer),game_private.inventory_state(integer) from public,anon,authenticated;
grant execute on function game_private.inventory_action(text,jsonb),game_private.inventory_state(integer) to authenticated;
notify pgrst,'reload schema';
