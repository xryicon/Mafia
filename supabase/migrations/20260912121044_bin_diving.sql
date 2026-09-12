-- Bin diving: one server roll, city-wide cooldown and permanent reward receipts.
insert into public.game_permissions(id,owner_only) values('bin_diving.manage',true);
create table public.game_bin_rules(
 id boolean primary key default true check(id), enabled boolean not null default true,
 cooldown_seconds integer not null default 120 check(cooldown_seconds between 1 and 86400),
 cash_min integer not null default 25 check(cash_min between 1 and 1000000),
 cash_max integer not null default 150 check(cash_max between cash_min and 1000000),
 cash_chance numeric(5,2) not null default 35 check(cash_chance between 0 and 100),
 pickaxe_chance numeric(5,2) not null default 8 check(pickaxe_chance between 0 and 100),
 pistol_blueprint_chance numeric(5,2) not null default 3 check(pistol_blueprint_chance between 0 and 100),
 bullet_blueprint_chance numeric(5,2) not null default 4 check(bullet_blueprint_chance between 0 and 100),
 version integer not null default 1 check(version>0),
 check(cash_chance+pickaxe_chance+pistol_blueprint_chance+bullet_blueprint_chance<=100)
);
insert into public.game_bin_rules(id) values(true);
create table public.game_bin_inventory(
 season_id uuid not null references public.game_seasons(id), player_id uuid not null references public.game_players(id),
 item text not null check(item in ('pickaxe','pistol_blueprint','bullet_blueprint')),
 quantity integer not null check(quantity between 0 and 1000000), primary key(season_id,player_id,item)
);
create table public.game_bin_dives(
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id), district_id uuid not null references public.game_districts(id),
 district_name text not null, outcome text not null check(outcome in ('nothing','cash','pickaxe','pistol_blueprint','bullet_blueprint')),
 cash integer not null default 0 check(cash>=0), rules_version integer not null,
 created_at timestamptz not null, ready_at timestamptz not null check(ready_at>created_at),
 check((outcome='cash' and cash>0) or (outcome<>'cash' and cash=0))
);
create index bin_dives_player_time on public.game_bin_dives(season_id,player_id,created_at desc);
create index bin_dives_district on public.game_bin_dives(district_id);
create index bin_inventory_player on public.game_bin_inventory(player_id);
create table game_private.bin_requests(
 season_id uuid not null references public.game_seasons(id), player_id uuid not null references public.game_players(id),
 request_id uuid not null, action text not null, payload jsonb not null, result jsonb not null,
 created_at timestamptz not null default now(), primary key(season_id,player_id,request_id)
);
create index bin_requests_player on game_private.bin_requests(player_id);
alter table public.game_bin_rules enable row level security;
alter table public.game_bin_inventory enable row level security;
alter table public.game_bin_dives enable row level security;
alter table game_private.bin_requests enable row level security;
-- RPC-only access scopes reads to the caller and writes to checked transactions.
revoke all on public.game_bin_rules,public.game_bin_inventory,public.game_bin_dives,game_private.bin_requests from public,anon,authenticated;
create trigger bin_rules_audit after insert or update or delete on public.game_bin_rules for each row execute function game_private.audit_change();
create trigger bin_inventory_audit after insert or update or delete on public.game_bin_inventory for each row execute function game_private.audit_change();
create trigger bin_dives_immutable before update or delete or truncate on public.game_bin_dives for each statement execute function game_private.district_immutable();
create trigger bin_requests_immutable before update or delete or truncate on game_private.bin_requests for each statement execute function game_private.district_immutable();

create function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; uid uuid:=auth.uid();
begin
 perform game_private.require_active();
 perform game_private.state();
 s:=game_private.season_guard(false);
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
  'inventory',(select coalesce(jsonb_object_agg(item,quantity),'{}') from public.game_bin_inventory where season_id=s and player_id=uid),
  'tool_condition',coalesce((select durability from public.game_mining_tools where season_id=s and player_id=uid),0),
  'tool_max',game_private.setting('mining_pickaxe_durability'),
  'mining_shift',exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working'),
  'ready_at',(select max(ready_at) from public.game_bin_dives where season_id=s and player_id=uid),
  'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from (
   select id,district_id,district_name,outcome,cash,created_at,ready_at from public.game_bin_dives
   where season_id=s and player_id=uid order by created_at desc limit 30) x)
 );
end $$;

create function game_private.bin_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 s uuid; uid uuid:=auth.uid(); nonce uuid; prior game_private.bin_requests;
 r public.game_bin_rules; d public.game_districts; receipt public.game_bin_dives;
 stamp timestamptz; ready timestamptz; roll integer; amount integer:=0; outcome text; result jsonb; reason text;
begin
 perform game_private.require_active(); if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh before continuing.'; end if;
  nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null then raise exception 'A request ID is required.'; end if;
  -- Follow mining's lock order: season, district-operation lock, rules/district, player, tool.
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.bin_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This request ID was already used for a different action.'; end if;
   return prior.result;
  end if;
  if p_action='configure' then
   if not game_private.has_permission('bin_diving.manage') then raise exception 'Owner permission required.'; end if;
   reason:=btrim(p_payload->>'reason');
   if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5–500 characters for the audit log.'; end if;
   select * into strict r from public.game_bin_rules for update;
   if (p_payload->>'version')::integer is distinct from r.version then raise exception 'Another edit was saved. Refresh and review the current rules.'; end if;
   perform set_config('game.reason','Bin diving rules: '||reason,true);
   update public.game_bin_rules set enabled=(p_payload->>'enabled')::boolean,
    cooldown_seconds=(p_payload->>'cooldown_seconds')::integer,cash_min=(p_payload->>'cash_min')::integer,cash_max=(p_payload->>'cash_max')::integer,
    cash_chance=(p_payload->>'cash_chance')::numeric,pickaxe_chance=(p_payload->>'pickaxe_chance')::numeric,
    pistol_blueprint_chance=(p_payload->>'pistol_blueprint_chance')::numeric,bullet_blueprint_chance=(p_payload->>'bullet_blueprint_chance')::numeric,
    version=version+1;
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
    update public.game_bin_inventory set quantity=quantity-1 where season_id=s and player_id=uid and item='pickaxe' and quantity>0;
    if not found then raise exception 'Find a pickaxe by bin diving first.'; end if;
    -- Replacing a worn pickaxe consumes a spare; the UI makes this explicit.
    insert into public.game_mining_tools(season_id,player_id,durability) values(s,uid,game_private.setting('mining_pickaxe_durability'))
     on conflict(season_id,player_id) do update set durability=excluded.durability
     where public.game_mining_tools.durability<excluded.durability;
    if not found then raise exception 'Your current pickaxe is already in full condition.'; end if;
    result:=jsonb_build_object('message','Pickaxe equipped. Visit a public mine to put it to work.');
   else
    stamp:=clock_timestamp();
    select max(ready_at) into ready from public.game_bin_dives where season_id=s and player_id=uid;
    if ready>stamp then raise exception 'Give the streets a moment. Your cooldown applies across every district.'; end if;
    roll:=floor(random()*10000)::integer;
    outcome:=case when roll<r.cash_chance*100 then 'cash'
     when roll<(r.cash_chance+r.pickaxe_chance)*100 then 'pickaxe'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance)*100 then 'pistol_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance)*100 then 'bullet_blueprint' else 'nothing' end;
    if outcome='cash' then amount:=r.cash_min+floor(random()*(r.cash_max-r.cash_min+1))::integer; end if;
    insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at)
     values(s,uid,d.id,d.name,outcome,amount,r.version,stamp,stamp+make_interval(secs=>r.cooldown_seconds)) returning * into receipt;
    if outcome='cash' then perform game_private.district_wallet(uid,amount,'Bin diving: '||receipt.id);
    elsif outcome<>'nothing' then
     insert into public.game_bin_inventory(season_id,player_id,item,quantity) values(s,uid,outcome,1)
      on conflict(season_id,player_id,item) do update set quantity=public.game_bin_inventory.quantity+1;
    end if;
    result:=jsonb_build_object('message',case when outcome='nothing' then 'Nothing useful this time. The next bin tells another story.' else 'You found something worth keeping.' end,'receipt',to_jsonb(receipt));
   end if;
  end if;
  insert into game_private.bin_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception
  when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the values: chances must total at most 100%, cash must be a valid range, and cooldown must be 1–86,400 seconds.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;
create function public.bin_diving_state() returns jsonb language sql security invoker set search_path='' as $$ select game_private.bin_state() $$;
create function public.bin_diving_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.bin_action(p_action,p_payload) $$;
revoke all on function game_private.bin_state(),game_private.bin_action(text,jsonb),public.bin_diving_state(),public.bin_diving_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.bin_state(),game_private.bin_action(text,jsonb),public.bin_diving_state(),public.bin_diving_action(text,jsonb) to authenticated;

-- Preserve the mining economy, updating only the equipment guidance.
do $$ declare definition text;
begin
 select pg_get_functiondef('game_private.mining_action(text,jsonb)'::regprocedure) into definition;
 if position('Finding equipment will be available in a future update.' in definition)=0 then raise exception 'Mining equipment guidance changed; review integration.'; end if;
 execute replace(definition,'Finding equipment will be available in a future update.','Find equipment by bin diving.');
end $$;

