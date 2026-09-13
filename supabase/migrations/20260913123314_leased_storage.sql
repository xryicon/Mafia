-- Reuse carried inventory, gear, ledgers and server capacity enforcement.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Connect city leases and installed fittings to secure storage',true);
-- For expired city leases, goods remain in a private collection locker. They do not
-- consume the next tenant's floor space and can never be taken by that tenant.
create or replace function game_private.storage_load(s uuid,b uuid) returns bigint language sql stable security definer set search_path='' as $$
 select coalesce((select sum(quantity) from public.game_storage_inventory where season_id=s and building_id=b and player_id=auth.uid()),0)
 +coalesce((select sum(quantity) from public.game_inventory_gear where season_id=s and building_id=b and player_id=auth.uid() and location='storage'),0)
 +game_private.property_station_space(s,b,auth.uid())
$$;
do $$declare definition text;old text;begin
 select pg_get_functiondef('game_private.inventory_storage_action_v1(text,jsonb)'::regprocedure) into definition;
 old:='p.owner_type is distinct from ''player'' or p.owner_id is distinct from uid';
 if position(old in definition)=0 then raise exception 'Review plot storage lease integration';end if;
 definition:=replace(definition,old,'not game_private.property_access(s,uid,(p_payload->>''building_id'')::uuid,p_action=''store'')');
 old:='b.owner_type is distinct from ''player'' or b.owner_id is distinct from uid';
 if position(old in definition)=0 then raise exception 'Review building storage lease integration';end if;
 definition:=replace(definition,old,'not game_private.property_access(s,uid,b.id,p_action=''store'')');
 execute definition;
 select pg_get_functiondef('game_private.gear_storage(uuid,uuid,uuid,boolean,integer)'::regprocedure) into definition;
 old:='b.owner_type is distinct from ''player'' or b.owner_id is distinct from u';
 if position(old in definition)=0 then raise exception 'Review leased equipment storage';end if;
 definition:=replace(definition,old,'not game_private.property_access(s,u,bid,storing)');
 old:='p.owner_type is distinct from ''player'' or p.owner_id is distinct from u';
 if position(old in definition)=0 then raise exception 'Review leased equipment plot access';end if;
 definition:=replace(definition,old,'not game_private.property_access(s,u,bid,storing)');
 execute definition;
 select pg_get_functiondef('game_private.inventory_storage_state_v1(integer)'::regprocedure) into definition;
 old:='b.owner_type=''player'' and b.owner_id=uid and p.owner_type=''player'' and p.owner_id=uid';
 if position(old in definition)=0 then raise exception 'Review inventory lease listings';end if;
 definition:=replace(definition,old,'game_private.property_access(s,uid,b.id,false)');
 execute definition;
end$$;
alter function game_private.inventory_state(integer) rename to inventory_state_before_properties;
create function game_private.inventory_state(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb;s uuid;u uuid:=auth.uid();
begin
 v:=game_private.inventory_state_before_properties(p_offset);s:=(v->'season'->>'id')::uuid;
 return v||jsonb_build_object('stores',(select coalesce(jsonb_agg(x||jsonb_build_object(
 'capacity',greatest(0,(x->>'capacity')::bigint-game_private.property_station_space(s,(x->>'id')::uuid,u)),
 'used',(x->>'used')::bigint-game_private.property_station_space(s,(x->>'id')::uuid,u),
 'enabled',(x->>'enabled')::boolean and game_private.property_access(s,u,(x->>'id')::uuid,true),
 'lease',(select jsonb_build_object('ends_at',l.ends_at,'active',l.released_at is null and l.ends_at>clock_timestamp())
  from public.game_property_leases l where l.building_id=(x->>'id')::uuid and l.season_id=s and l.player_id=u order by l.starts_at desc limit 1),
 'station_space',game_private.property_station_space(s,(x->>'id')::uuid,u)
 )),'[]') from jsonb_array_elements(v->'stores')x));
end$$;
revoke all on function game_private.inventory_state_before_properties(integer),game_private.inventory_state(integer) from public,anon,authenticated;
grant execute on function game_private.inventory_state(integer) to authenticated;

create function game_private.protect_property_occupants() returns trigger language plpgsql security definer set search_path='' as $$
declare pid uuid;changed boolean;
begin
 if TG_TABLE_NAME='game_districts' then
  if new.archived_at is distinct from old.archived_at and exists(select 1 from public.game_property_leases l join public.game_district_plots p on p.id=l.plot_id
   where p.district_id=old.id and l.season_id=game_private.current_season() and l.released_at is null and l.ends_at>clock_timestamp()) then raise exception 'A district with active city tenants cannot be archived.';end if;
  return new;
 elsif TG_TABLE_NAME='game_district_plots' then
  pid:=old.id;changed:=TG_OP='DELETE' or (new.owner_type,new.owner_id,new.archived_at,new.season_id,new.district_id) is distinct from (old.owner_type,old.owner_id,old.archived_at,old.season_id,old.district_id) or (new.asking_price is not null and new.asking_price is distinct from old.asking_price);
 elsif TG_TABLE_NAME='game_district_buildings' then
  pid:=old.plot_id;changed:=TG_OP='DELETE' or (new.owner_type,new.owner_id,new.archived_at,new.building_type,new.season_id,new.plot_id,new.construction_status) is distinct from (old.owner_type,old.owner_id,old.archived_at,old.building_type,old.season_id,old.plot_id,old.construction_status);
 else pid:=new.plot_id;changed:=new.status='open';
 end if;
 if changed and (exists(select 1 from public.game_property_leases where plot_id=pid and released_at is null and ends_at>clock_timestamp())
  or exists(select 1 from public.game_property_stations f join public.game_district_buildings b on b.id=f.building_id where b.plot_id=pid and f.removed_at is null and game_private.property_access(f.season_id,f.player_id,f.building_id,true))) then
  raise exception 'Active tenants or installed crafting stations prevent transferring or removing this property.';
 end if;
 return coalesce(new,old);
end$$;
create trigger property_occupant_plot before update or delete on public.game_district_plots for each row execute function game_private.protect_property_occupants();
create trigger property_occupant_building before update or delete on public.game_district_buildings for each row execute function game_private.protect_property_occupants();
create trigger property_occupant_district before update on public.game_districts for each row execute function game_private.protect_property_occupants();
create trigger property_occupant_auction before insert or update on public.game_plot_auctions for each row execute function game_private.protect_property_occupants();
create trigger property_occupant_offer before insert or update on public.game_plot_offers for each row execute function game_private.protect_property_occupants();
revoke all on function game_private.protect_property_occupants() from public,anon,authenticated;
notify pgrst,'reload schema';

create function game_private.property_season_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.reset_at is null and new.reset_at is not null then
  update public.game_property_leases set released_at=clock_timestamp() where season_id=new.id and released_at is null;
  update public.game_property_stations set removed_at=clock_timestamp() where season_id=new.id and removed_at is null;
 elsif old.status='locked' and new.status='open' and old.locked_at is not null then
  update public.game_property_leases set ends_at=ends_at+(clock_timestamp()-old.locked_at) where season_id=new.id and released_at is null and ends_at>old.locked_at;
 end if;
 return new;
end$$;
create trigger property_season_lifecycle after update on public.game_seasons for each row execute function game_private.property_season_lifecycle();
revoke all on function game_private.property_season_lifecycle() from public,anon,authenticated;
