-- Authoritative blueprint learning and property crafting, sharing the economy lock.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce learned blueprints and property crafting',true);
insert into public.game_permissions(id,owner_only) values('crafting.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('crafting_queue_limit',3,1,20),('crafting_max_batches',20,1,100);
insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots)
values ('homemade-pistol','Homemade pistol','Crafting station',1,1,60,false,'weapons','A crafted Blackwater sidearm. Trade, store or equip it in your secondary slot.',2000,array['secondary']),
 ('homemade-bullets','Homemade bullets','Crafting station',1,1,60,false,'ammunition','A batch of crafted Blackwater ammunition. Trade, store or equip it in your ammo slot.',30,array['ammo']);
update public.game_goods set inventory_description='Learn this blueprint to unlock its crafting recipe for the current season. Learning consumes one blueprint.' where id in ('pistol_blueprint','bullet_blueprint');
create table public.game_crafting_recipes(
 id text primary key check(id~'^[a-z0-9-]{2,50}$'),name text not null check(length(name) between 2 and 80),
 description text not null default '' check(length(description)<=600),blueprint_good_id text not null unique references public.game_goods(id),
 output_good_id text not null references public.game_goods(id),output_units integer not null check(output_units between 1 and 10000),
 seconds integer not null check(seconds between 1 and 604800),materials jsonb not null check(jsonb_typeof(materials)='object'),
 enabled boolean not null default true,version integer not null default 1
);
create index crafting_recipe_output on public.game_crafting_recipes(output_good_id);
insert into public.game_crafting_recipes(id,name,description,blueprint_good_id,output_good_id,output_units,seconds,materials) values
 ('homemade-pistol','Homemade pistol','Turn refined metal into a sidearm for your Blackwater loadout.','pistol_blueprint','homemade-pistol',1,150,'{"iron-ingot":4,"copper-ingot":2}'),
 ('homemade-bullets','Homemade bullets','Produce ammunition for trade or your Blackwater loadout.','bullet_blueprint','homemade-bullets',12,60,'{"iron-ingot":1,"copper-ingot":1}');
create table public.game_learned_blueprints(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 recipe_id text not null references public.game_crafting_recipes(id),learned_at timestamptz not null default clock_timestamp(),
 primary key(season_id,player_id,recipe_id)
);
create index learned_player on public.game_learned_blueprints(player_id,season_id);
create index learned_recipe on public.game_learned_blueprints(recipe_id);
-- Queue lifecycle remains in the existing seasonal job registry.
create table public.game_crafting_batches(
 job_id uuid primary key references public.game_season_jobs(id),station_id uuid not null references public.game_property_stations(id),
 recipe_id text not null references public.game_crafting_recipes(id),recipe_version integer not null,
 output_good_id text not null references public.game_goods(id),output_units integer not null check(output_units>0),
 inputs jsonb not null,created_at timestamptz not null default clock_timestamp(),starts_at timestamptz not null,recipe_name text not null
);
create index crafting_batch_station on public.game_crafting_batches(station_id);
create index crafting_batch_recipe on public.game_crafting_batches(recipe_id);
create index crafting_batch_output on public.game_crafting_batches(output_good_id);
create table game_private.crafting_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,primary key(season_id,player_id,request_id)
);
create index crafting_request_player on game_private.crafting_requests(player_id);
alter table public.game_crafting_recipes enable row level security;
alter table public.game_learned_blueprints enable row level security;
alter table public.game_crafting_batches enable row level security;
alter table game_private.crafting_requests enable row level security;
revoke all on public.game_crafting_recipes,public.game_learned_blueprints,public.game_crafting_batches,game_private.crafting_requests from public,anon,authenticated;
create trigger crafting_recipe_audit after insert or update or delete on public.game_crafting_recipes for each row execute function game_private.audit_change();
create trigger learned_retain before update or delete or truncate on public.game_learned_blueprints for each statement execute function game_private.district_immutable();
create trigger crafting_batch_retain before delete or truncate on public.game_crafting_batches for each statement execute function game_private.district_immutable();
create trigger crafting_requests_retain before update or delete or truncate on game_private.crafting_requests for each statement execute function game_private.district_immutable();
create function game_private.crafting_materials_valid() returns trigger language plpgsql set search_path='' as $$
declare k text;v jsonb;
begin
 if (select count(*) from jsonb_each(new.materials)) not between 1 and 12 then raise exception 'Choose 1–12 materials.';end if;
 for k,v in select * from jsonb_each(new.materials) loop
  if jsonb_typeof(v)<>'number' or (v::text)::numeric<>trunc((v::text)::numeric) or (v::text)::numeric not between 1 and 10000
   or not exists(select 1 from public.game_goods where id=k) or k in(new.output_good_id,new.blueprint_good_id) then raise exception 'Choose existing input goods and whole quantities from 1 to 10,000.';end if;
 end loop;
 if new.blueprint_good_id=new.output_good_id then raise exception 'A blueprint cannot be its own output.';end if;
 return new;
end$$;
create trigger crafting_materials_valid before insert or update on public.game_crafting_recipes for each row execute function game_private.crafting_materials_valid();

create function game_private.crafting_station_ready(s uuid,u uuid,bid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select game_private.property_access(s,u,bid,true) and exists(
 select 1 from public.game_property_stations f join public.game_district_buildings b on b.id=f.building_id
 join public.game_district_plots p on p.id=b.plot_id join public.game_storage_rules r on r.building_type=b.building_type
 join public.game_districts d on d.id=p.district_id
 where f.season_id=s and f.player_id=u and b.id=bid and f.removed_at is null and b.construction_status='ready' and b.condition>0 and r.enabled
 and (b.owner_type='player' or exists(select 1 from public.game_property_leases l where l.building_id=bid and l.player_id=u and l.season_id=s and l.released_at is null and l.ends_at>clock_timestamp()))
 and p.status not in ('locked','reserved') and p.asking_price is null and d.archived_at is null and d.status<>'lockdown'
 and not exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown')
 and not exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open')
 and not exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open'))
$$;
-- Only the authenticated player's stock can be consumed. Storage is used first in combined mode.
create function game_private.crafting_consume(s uuid,u uuid,bid uuid,g text,n integer,source text) returns void language plpgsql security definer set search_path='' as $$
declare available integer;take integer:=0;
begin
 if source not in ('carried','storage','both') or source is null or n<1 or u is distinct from auth.uid() then raise exception 'Invalid material source.';end if;
 if source in ('storage','both') then
  if bid is null or not game_private.property_access(s,u,bid,true) or not exists(
   select 1 from public.game_district_buildings b where b.id=bid and
   (b.owner_type='player' and b.owner_id=u or exists(select 1 from public.game_property_leases l where l.building_id=bid and l.player_id=u and l.season_id=s and l.released_at is null and l.ends_at>clock_timestamp())))
   then raise exception 'An active property is required to use its materials.';end if;
  select quantity into available from public.game_storage_inventory where season_id=s and player_id=u and building_id=bid and good_id=g for update;
  take:=least(n,coalesce(available,0));
  if take>0 then update public.game_storage_inventory set quantity=quantity-take where season_id=s and player_id=u and building_id=bid and good_id=g;end if;
 end if;
 if n>take then
  if source='storage' then raise exception 'Not enough materials in this property.';end if;
  update public.game_inventory set quantity=quantity-(n-take) where season_id=s and player_id=u and good_id=g and quantity>=n-take;
  if not found then raise exception 'Not enough materials. Refresh your stock.';end if;
 end if;
end$$;
create function game_private.crafting_state(p_building uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb;s uuid;u uuid:=auth.uid();manager boolean;
begin
 v:=game_private.inventory_state(0);s:=(v->'season'->>'id')::uuid;manager:=game_private.has_permission('crafting.manage');
 return jsonb_build_object('inventory',v,'server_time',clock_timestamp(),'building_id',p_building,'can_manage',manager,
 'settings',jsonb_build_object('queue_limit',game_private.setting('crafting_queue_limit'),'max_batches',game_private.setting('crafting_max_batches')),
 'recipes',(select coalesce(jsonb_agg(to_jsonb(r) order by r.name),'[]') from public.game_crafting_recipes r where r.enabled or manager or exists(select 1 from public.game_learned_blueprints l where l.recipe_id=r.id and l.player_id=u and l.season_id=s)),
 'learned',(select coalesce(jsonb_agg(recipe_id),'[]') from public.game_learned_blueprints where season_id=s and player_id=u),
 'stations',(select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'building_id',b.id,'code',p.code,'name',t.name,'district',d.name,'slug',d.slug,
 'ready',game_private.crafting_station_ready(s,u,b.id),'image_url',coalesce(nullif(pt.image_url,''),d.image_url)) order by p.code),'[]')
 from public.game_property_stations f join public.game_district_buildings b on b.id=f.building_id
 join public.game_district_plots p on p.id=b.plot_id join public.game_districts d on d.id=p.district_id
 join public.game_building_types t on t.id=b.building_type join public.game_plot_templates pt on pt.id=p.template_id
 where f.season_id=s and f.player_id=u and f.removed_at is null and game_private.property_access(s,u,b.id,true)),
 'jobs',(select coalesce(jsonb_agg(x order by x.created_at),'[]') from (
 select j.id,j.status,j.ready_at,c.created_at,c.starts_at,c.recipe_id,c.recipe_name,c.output_good_id,c.output_units,c.inputs,c.station_id,f.building_id,p.code
 from public.game_season_jobs j join public.game_crafting_batches c on c.job_id=j.id join public.game_property_stations f on f.id=c.station_id
 join public.game_district_buildings b on b.id=f.building_id join public.game_district_plots p on p.id=b.plot_id
 where j.season_id=s and j.player_id=u and j.status in ('queued','running') order by c.created_at limit 100)x));
end$$;

create function game_private.crafting_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();nonce uuid;prior game_private.crafting_requests;r public.game_crafting_recipes;station public.game_property_stations;
 job public.game_season_jobs;batch public.game_crafting_batches;bid uuid;source text;n integer;k text;v jsonb;inputs jsonb:='{}';result jsonb;
 start_time timestamptz;finish_time timestamptz;lease_end timestamptz;dest text;rule public.game_storage_rules;out_n integer;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again shortly.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid crafting request.';end if;
  s:=game_private.season_guard(false);nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Refresh the current season before continuing.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.crafting_requests where season_id=s and player_id=u and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This crafting reference has already been used.';end if;
   return prior.result;
  end if;
  perform game_private.season_guard();
  perform 1 from public.game_players where id=u and season_id=s for update;
  if not found then raise exception 'Open your dashboard to join this season.';end if;
  perform set_config('game.inventory_request',nonce::text,true);
  perform set_config('game.reason','Crafting: '||coalesce(p_action,''),true);
  bid:=(p_payload->>'building_id')::uuid;source:=p_payload->>'source';
  if p_action in ('learn','start') then
   select * into r from public.game_crafting_recipes where id=p_payload->>'recipe_id' for share;
   if not found or not r.enabled then raise exception 'This recipe is not available.';end if;
   if (p_payload->>'version')::integer is distinct from r.version then raise exception 'The recipe changed. Review its current requirements.';end if;
   if p_action='learn' then
    if exists(select 1 from public.game_learned_blueprints where season_id=s and player_id=u and recipe_id=r.id) then raise exception 'You already know this recipe. Keep or trade the spare blueprint.';end if;
    perform game_private.crafting_consume(s,u,bid,r.blueprint_good_id,1,source);
    insert into public.game_learned_blueprints(season_id,player_id,recipe_id) values(s,u,r.id);
    result:=jsonb_build_object('message','Recipe learned for this season. One blueprint was consumed.');
   else
    if not exists(select 1 from public.game_learned_blueprints where season_id=s and player_id=u and recipe_id=r.id) then raise exception 'Learn the blueprint before crafting this item.';end if;
    if not game_private.crafting_station_ready(s,u,bid) then raise exception 'Use an installed station in your active, unlisted garage or warehouse.';end if;
    select * into station from public.game_property_stations where building_id=bid and player_id=u and season_id=s and removed_at is null for update;
    if (select count(*) from public.game_crafting_batches c join public.game_season_jobs j on j.id=c.job_id where c.station_id=station.id and j.status in ('queued','running'))>=game_private.setting('crafting_queue_limit') then raise exception 'This station queue is full. Collect or cancel a job first.';end if;
    n:=(p_payload->>'batches')::integer;
    if n is null or n<1 or n>game_private.setting('crafting_max_batches') then raise exception 'Choose a valid number of batches.';end if;
    select greatest(clock_timestamp(),coalesce(max(j.ready_at),clock_timestamp())) into start_time from public.game_season_jobs j join public.game_crafting_batches c on c.job_id=j.id where c.station_id=station.id and j.status in ('queued','running');
    finish_time:=start_time+make_interval(secs=>r.seconds*n);
    select ends_at into lease_end from public.game_property_leases where building_id=bid and season_id=s and player_id=u and released_at is null and ends_at>clock_timestamp();
    if lease_end is not null and finish_time>lease_end then raise exception 'Extend your lease before starting a job that would finish after it expires.';end if;
    for k,v in select * from jsonb_each(r.materials) order by key loop
     perform game_private.crafting_consume(s,u,bid,k,(v::text)::integer*n,source);
     inputs:=inputs||jsonb_build_object(k,(v::text)::integer*n);
    end loop;
    insert into public.game_season_jobs(season_id,player_id,kind,status,ready_at,data)
     values(s,u,'crafting','queued',finish_time,jsonb_build_object('building_id',bid,'recipe',r.id)) returning * into job;
    insert into public.game_crafting_batches(job_id,station_id,recipe_id,recipe_version,output_good_id,output_units,inputs,starts_at,recipe_name)
     values(job.id,station.id,r.id,r.version,r.output_good_id,r.output_units*n,inputs,start_time,r.name);
    result:=jsonb_build_object('message','Materials reserved. Crafting job added to this station.','job_id',job.id);
   end if;
  elsif p_action in ('collect','cancel') then
   select * into job from public.game_season_jobs where id=(p_payload->>'job_id')::uuid and player_id=u and season_id=s and kind='crafting' for update;
   if not found or job.status not in ('queued','running') then raise exception 'This crafting job is no longer waiting for you.';end if;
   select * into batch from public.game_crafting_batches where job_id=job.id;
   if not found then raise exception 'Invalid crafting job.';end if;
   if p_action='cancel' then
    for k,v in select * from jsonb_each(batch.inputs) order by key loop
     insert into public.game_inventory_deliveries(season_id,player_id,good_id,quantity,reason) values(s,u,k,(v::text)::integer,'Returned crafting materials');
    end loop;
    update public.game_season_jobs set status='cancelled' where id=job.id;
    result:=jsonb_build_object('message','Job cancelled. Materials are waiting in Inventory deliveries for collection.');
   else
    if job.ready_at>clock_timestamp() then raise exception 'This crafting job is still running.';end if;
    dest:=p_payload->>'destination';out_n:=batch.output_units;
    if dest='storage' then
     select building_id into bid from public.game_property_stations where id=batch.station_id;
     if not game_private.crafting_station_ready(s,u,bid) then raise exception 'This property is no longer available. Collect into your inventory instead.';end if;
     select sr.* into rule from public.game_storage_rules sr join public.game_district_buildings b on b.building_type=sr.building_type where b.id=bid for share of sr;
     if game_private.storage_load(s,bid)+out_n>rule.capacity then raise exception 'Free up storage space or collect into your inventory.';end if;
     insert into public.game_storage_inventory(season_id,building_id,player_id,good_id,quantity) values(s,bid,u,batch.output_good_id,out_n)
      on conflict(season_id,building_id,player_id,good_id) do update set quantity=game_storage_inventory.quantity+excluded.quantity;
    elsif dest='carried' then
     if not game_private.inventory_fits(s,u,batch.output_good_id,out_n) then raise exception 'Free up carried slots or weight before collecting this job.';end if;
     insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,batch.output_good_id,out_n)
      on conflict(season_id,player_id,good_id) do update set quantity=game_inventory.quantity+excluded.quantity;
    else raise exception 'Choose inventory or this property for the finished items.';end if;
    update public.game_season_jobs set status='completed' where id=job.id;
    perform game_private.record_metric(u,'crafting',out_n);
    result:=jsonb_build_object('message','Crafted items collected. Ready to store, trade or equip.');
   end if;
  else raise exception 'Choose a supported crafting action.';end if;
  perform game_private.inventory_sync(s,u);
  insert into game_private.crafting_requests values(s,u,nonce,p_action,p_payload,result);
  return result;
 exception when check_violation or not_null_violation or foreign_key_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the crafting details and refresh.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

create function game_private.crafting_manage(p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.game_crafting_recipes;reason text;
begin
 perform game_private.require_active();
 if not game_private.has_permission('crafting.manage') then raise exception 'Crafting management permission required.';end if;
 if not game_private.rate('crafting_manage',60) then return jsonb_build_object('error','Too many recipe edits.');end if;
 begin
  perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid recipe edit.';end if;
  reason:=btrim(p_payload->>'reason');if reason is null or length(reason) not between 5 and 500 then raise exception 'Add an audit reason of 5–500 characters.';end if;
  perform set_config('game.reason','Crafting recipe: '||reason,true);
  select * into r from public.game_crafting_recipes where id=p_payload->>'id' for update;
  if not found or (p_payload->>'version')::integer is distinct from r.version then raise exception 'Recipe changed. Refresh before saving.';end if;
  update public.game_crafting_recipes set name=btrim(p_payload->>'name'),description=btrim(p_payload->>'description'),
   seconds=(p_payload->>'seconds')::integer,output_units=(p_payload->>'output_units')::integer,
   materials=p_payload->'materials',enabled=(p_payload->>'enabled')::boolean,version=version+1 where id=r.id;
  return jsonb_build_object('message','Recipe saved. Already queued jobs keep their original materials and output.');
 exception when check_violation or not_null_violation or foreign_key_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the recipe values.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

create function game_private.crafting_station_retain() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.removed_at is null and new.removed_at is not null
 and exists(select 1 from public.game_seasons where id=old.season_id and status='open' and reset_at is null)
 and game_private.property_access(old.season_id,old.player_id,old.building_id,true)
 and exists(select 1 from public.game_crafting_batches c join public.game_season_jobs j on j.id=c.job_id where c.station_id=old.id and j.status in ('queued','running'))
 then raise exception 'Collect or cancel this station’s jobs before removing it or returning the keys.';end if;
 return new;
end$$;
create trigger crafting_station_retain before update on public.game_property_stations for each row execute function game_private.crafting_station_retain();
create function game_private.crafting_season_lifecycle() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.reset_at is null and new.reset_at is not null then
  update public.game_season_jobs set status='cancelled' where season_id=new.id and kind='crafting' and status in ('queued','running');
 elsif old.status='locked' and new.status='open' and old.locked_at is not null then
  update public.game_crafting_batches c set starts_at=c.starts_at+(clock_timestamp()-old.locked_at)
   from public.game_season_jobs j where j.id=c.job_id and j.season_id=new.id and j.status in ('queued','running') and j.ready_at>old.locked_at;
  update public.game_season_jobs set ready_at=ready_at+(clock_timestamp()-old.locked_at) where season_id=new.id and kind='crafting' and status in ('queued','running') and ready_at>old.locked_at;
 end if;return new;
end$$;
create trigger crafting_season_lifecycle after update on public.game_seasons for each row execute function game_private.crafting_season_lifecycle();
update public.game_metric_catalog set available=true where id='crafting';

create function public.crafting_state(p_building uuid default null) returns jsonb language sql security invoker set search_path='' as $$select game_private.crafting_state(p_building)$$;
create function public.crafting_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.crafting_action(p_action,p_payload)$$;
create function public.crafting_manage(p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.crafting_manage(p_payload)$$;
revoke all on function game_private.crafting_materials_valid(),game_private.crafting_station_ready(uuid,uuid,uuid),game_private.crafting_consume(uuid,uuid,uuid,text,integer,text),game_private.crafting_state(uuid),game_private.crafting_action(text,jsonb),game_private.crafting_manage(jsonb),game_private.crafting_station_retain(),game_private.crafting_season_lifecycle(),public.crafting_state(uuid),public.crafting_action(text,jsonb),public.crafting_manage(jsonb) from public,anon,authenticated;
grant execute on function game_private.crafting_state(uuid),game_private.crafting_action(text,jsonb),game_private.crafting_manage(jsonb),public.crafting_state(uuid),public.crafting_action(text,jsonb),public.crafting_manage(jsonb) to authenticated;
notify pgrst,'reload schema';

-- Retain pending work when a player tries to return an active city's keys.
create function game_private.crafting_lease_retain() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.released_at is null and new.released_at is not null and old.ends_at>clock_timestamp()
 and exists(select 1 from public.game_seasons where id=old.season_id and status='open' and reset_at is null)
 and exists(select 1 from public.game_property_stations f join public.game_crafting_batches c on c.station_id=f.id join public.game_season_jobs j on j.id=c.job_id
  where f.building_id=old.building_id and f.player_id=old.player_id and f.season_id=old.season_id and j.status in ('queued','running'))
 then raise exception 'Collect or cancel your crafting jobs before returning the keys.';end if;
 return new;
end$$;
create trigger crafting_lease_retain before update on public.game_property_leases for each row execute function game_private.crafting_lease_retain();
revoke all on function game_private.crafting_lease_retain() from public,anon,authenticated;
-- Reserved materials continue to count towards net worth until converted or returned.
do $$declare definition text;begin
 select pg_get_functiondef('game_private.season_scores(uuid,text)'::regprocedure) into definition;
 if position(' as stock_value,' in definition)=0 then raise exception 'Review crafting escrow valuation';end if;
 execute replace(definition,' as stock_value,',
 ' +coalesce((select sum((i.value::text)::numeric*v.unit_value) from public.game_season_jobs j join public.game_crafting_batches c on c.job_id=j.id cross join lateral jsonb_each(c.inputs) i join public.game_season_valuations v on v.season_id=j.season_id and v.good_id=i.key where j.season_id=p_season and j.player_id=sp.player_id and j.status in (''queued'',''running'')),0) as stock_value,');
end$$;

insert into public.game_season_valuations(season_id,good_id,unit_value)
 select s.id,g.id,case g.id when 'homemade-pistol' then 700 else 20 end
 from public.game_seasons s cross join public.game_goods g
 where s.status in ('draft','open','locked') and g.id in ('homemade-pistol','homemade-bullets')
 on conflict do nothing;
