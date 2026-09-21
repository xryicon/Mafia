-- District robbery: cash-only transfers, immutable outcomes, equipment and shared protection.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce player robbery rules',true);
insert into public.game_permissions(id,owner_only) values('robbery.manage',true);
create table game_private.robbery_rules(
 singleton boolean primary key default true check(singleton),enabled boolean not null default true,
 bullet_min integer not null default 0 check(bullet_min between 0 and 100),bullet_max integer not null default 100 check(bullet_max between bullet_min and 100),
 steal_min integer not null default 1 check(steal_min between 1 and 80),steal_max integer not null default 80 check(steal_max between steal_min and 80),
 victim_cooldown_seconds integer not null default 1800 check(victim_cooldown_seconds between 60 and 86400),
 attacker_cooldown_seconds integer not null default 300 check(attacker_cooldown_seconds between 1 and 86400),
 presence_seconds integer not null default 60 check(presence_seconds between 20 and 300),
 base_chance integer not null default 50 check(base_chance between 0 and 100),
 min_chance integer not null default 5 check(min_chance between 0 and 100),max_chance integer not null default 95 check(max_chance between min_chance and 100),
 skill_weight integer not null default 20 check(skill_weight between 0 and 100),accuracy_weight integer not null default 20 check(accuracy_weight between 0 and 100),
 power_weight integer not null default 30 check(power_weight between 0 and 100),gear_weight integer not null default 20 check(gear_weight between 0 and 100),version integer not null default 1
);
insert into game_private.robbery_rules default values;
create table game_private.robbery_gear_rules(
 good_id text primary key references public.game_goods(id),attack integer not null default 0 check(attack between 0 and 1000),
 defense integer not null default 0 check(defense between 0 and 1000),condition_max integer not null default 100 check(condition_max between 1 and 10000),version integer not null default 1
);
insert into game_private.robbery_gear_rules(good_id,attack,defense,condition_max)
 select good_id,case when good_id='m4-carbine' then 35 else 20 end,case when good_id='m4-carbine' then 20 else 10 end,condition_max from public.game_range_weapons;
create table game_private.robbery_presence(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),district_id uuid not null references public.game_districts(id),last_seen_at timestamptz not null,
 primary key(season_id,player_id)
);
create index robbery_presence_district on game_private.robbery_presence(season_id,district_id,last_seen_at desc);
create table game_private.robbery_protection(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),protected_until timestamptz,ready_at timestamptz,
 primary key(season_id,player_id)
);
create table game_private.robbery_attempts(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),attacker_id uuid not null references public.game_players(id),victim_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),request_id uuid not null,payload jsonb not null,result jsonb not null,
 succeeded boolean not null,chance numeric not null check(chance between 0 and 100),bullets integer not null check(bullets between 0 and 100),cash bigint not null check(cash>=0),
 weapon_id uuid not null references public.game_inventory_gear(id),factors jsonb not null,rule_snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),
 unique(season_id,attacker_id,request_id),check(attacker_id<>victim_id),check(succeeded or cash=0)
);
create index robbery_attacker_history on game_private.robbery_attempts(season_id,attacker_id,created_at desc);
create index robbery_victim_history on game_private.robbery_attempts(season_id,victim_id,created_at desc);
create trigger robbery_attempts_retain before update or delete or truncate on game_private.robbery_attempts for each statement execute function game_private.district_immutable();
create trigger robbery_rules_audit after insert or update or delete on game_private.robbery_rules for each row execute function game_private.audit_change();
create trigger robbery_gear_audit after insert or update or delete on game_private.robbery_gear_rules for each row execute function game_private.audit_change();
alter table game_private.robbery_rules enable row level security;
alter table game_private.robbery_gear_rules enable row level security;
alter table game_private.robbery_presence enable row level security;
alter table game_private.robbery_protection enable row level security;
alter table game_private.robbery_attempts enable row level security;
revoke all on game_private.robbery_rules,game_private.robbery_gear_rules,game_private.robbery_presence,game_private.robbery_protection,game_private.robbery_attempts from public,anon,authenticated;

create function game_private.robbery_factors(s uuid,u uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('power',p.xp,'level',game_private.skill_level(coalesce((select sum(delta) from game_private.skill_xp_ledger where season_id=s and player_id=u and skill_id='sharpshooting'),0)::bigint,d.xp_to_20),
 'accuracy',coalesce((select round(sum(a.total)/nullif(sum(r.shots),0),2) from public.game_range_sessions r cross join lateral(select sum(accuracy_percent) as total from game_private.range_shot_precision where session_id=r.id)a where r.season_id=s and r.player_id=u and r.difficulty='advanced' and r.status<>'active' and r.shots>0),0),
 'attack',coalesce(g.attack,0),'defense',coalesce(g.defense,0))
 from public.game_players p cross join public.game_skill_definitions d
 cross join lateral(select sum(r.attack*least(1,greatest(0,coalesce(g.condition,r.condition_max)::numeric/r.condition_max))) attack,
 sum(r.defense*least(1,greatest(0,coalesce(g.condition,r.condition_max)::numeric/r.condition_max))) defense
 from public.game_inventory_gear g join game_private.robbery_gear_rules r on r.good_id=g.good_id
 where g.season_id=s and g.player_id=u and g.location='equipped' and g.quantity>0 and g.equipment_slot not in ('ammo','medical'))g
 where p.id=u and p.season_id=s and d.id='sharpshooting';
$$;
create function game_private.robbery_chance(a jsonb,b jsonb,r game_private.robbery_rules) returns numeric language sql immutable set search_path='' as $$
 select round(greatest(r.min_chance,least(r.max_chance,r.base_chance
 +((a->>'level')::numeric-(b->>'level')::numeric)/19*r.skill_weight
 +((a->>'accuracy')::numeric-(b->>'accuracy')::numeric)/100*r.accuracy_weight
 +((a->>'power')::numeric-(b->>'power')::numeric)/greatest(1,(a->>'power')::numeric+(b->>'power')::numeric)*r.power_weight
 +((a->>'attack')::numeric-(b->>'defense')::numeric)/greatest(1,(a->>'attack')::numeric+(b->>'defense')::numeric)*r.gear_weight)),2);
$$;
create function game_private.robbery_weapon(s uuid,u uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',g.id,'name',i.name,'good_id',g.good_id,'condition',least(w.condition_max,coalesce(g.condition,w.condition_max)),
 'condition_max',w.condition_max,'wear_per_shot',w.wear_per_shot,'ammo_good_id',w.ammo_good_id,'ammo_id',a.id,'ammo',coalesce(a.quantity,0))
 from public.game_inventory_gear g join public.game_range_weapons w on w.good_id=g.good_id and w.enabled join public.game_goods i on i.id=g.good_id
 left join public.game_inventory_gear a on a.season_id=s and a.player_id=u and a.location='equipped' and a.equipment_slot='ammo' and a.good_id=w.ammo_good_id and a.quantity>0
 where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot in('primary','secondary') and g.quantity=1 and coalesce(g.condition,w.condition_max)>0
 order by coalesce(a.quantity,0) desc,g.equipment_slot,g.id limit 1;
$$;
create function game_private.robbery_available(s uuid,u uuid,d uuid,t timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from game_private.scav_sessions v join game_private.robbery_presence pr on pr.season_id=v.season_id and pr.player_id=v.player_id
 join public.game_players p on p.id=v.player_id and p.season_id=s cross join game_private.robbery_rules r
 join public.game_districts district on district.id=d
 where v.season_id=s and v.player_id=u and v.district_id=d and pr.district_id=d and pr.last_seen_at>t-make_interval(secs=>r.presence_seconds)
 and v.pending is null and v.arrives_at<=t and p.deleted_at is null and district.archived_at is null and district.status<>'lockdown'
 and not exists(select 1 from public.game_district_territory where season_id=s and district_id=d and status='lockdown')
 and not exists(select 1 from public.game_prison_sentences where season_id=s and player_id=u and released_at is null and release_at>t)
 and not exists(select 1 from public.game_sanctions where player_id=u and kind='ban' and revoked_at is null and (expires_at is null or expires_at>t))
 and not exists(select 1 from public.game_range_sessions where season_id=s and player_id=u and status='active' and ends_at>t));
$$;
create function game_private.robbery_state(touch_presence boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();d uuid;t timestamptz:=clock_timestamp();r game_private.robbery_rules;f jsonb;
begin
 perform game_private.require_active();if not game_private.rate('robbery_read',120) then raise exception 'Too many street updates. Wait a moment.';end if;
 s:=game_private.season_guard(false);select * into strict r from game_private.robbery_rules;
 select district_id into d from game_private.scav_sessions where season_id=s and player_id=u;
 if touch_presence and d is not null then
  insert into game_private.robbery_presence values(s,u,d,t) on conflict(season_id,player_id) do update set district_id=excluded.district_id,last_seen_at=excluded.last_seen_at;
 end if;
 f:=game_private.robbery_factors(s,u);
 return jsonb_build_object('season_id',s,'server_time',t,'district_id',d,'rules',to_jsonb(r)-'singleton','factors',f,'weapon',game_private.robbery_weapon(s,u),
 'available',game_private.robbery_available(s,u,d,t),'ready_at',(select ready_at from game_private.robbery_protection where season_id=s and player_id=u),
 'protected_until',(select protected_until from game_private.robbery_protection where season_id=s and player_id=u),
 'targets',(select coalesce(jsonb_agg(x),'[]') from(select p.id,p.handle,game_private.player_avatar(p.id) avatar_url,p.xp power,
  guard.protected_until,game_private.robbery_chance(f,game_private.robbery_factors(s,p.id),r) chance
  from game_private.robbery_presence pr join public.game_players p on p.id=pr.player_id and p.season_id=s
  left join game_private.robbery_protection guard on guard.season_id=s and guard.player_id=p.id
  where pr.season_id=s and pr.district_id=d and pr.last_seen_at>t-make_interval(secs=>r.presence_seconds) and p.id<>u and game_private.robbery_available(s,p.id,d,t)
  order by p.handle,p.id limit 100)x),
 'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select a.id,a.created_at,a.succeeded,a.cash,a.bullets,a.attacker_id=u attacking,
  case when a.attacker_id=u then v.handle else p.handle end other_name from game_private.robbery_attempts a join public.game_players p on p.id=a.attacker_id join public.game_players v on v.id=a.victim_id
  where a.season_id=s and u in(a.attacker_id,a.victim_id) order by a.created_at desc,a.id desc limit 20)x),
 'management',case when game_private.has_permission('robbery.manage') then jsonb_build_object('gear',(select coalesce(jsonb_agg(x order by x.name),'[]') from(select g.id,g.name,coalesce(gr.attack,0) attack,coalesce(gr.defense,0) defense,coalesce(gr.condition_max,100) condition_max,coalesce(gr.version,0) version from public.game_goods g left join game_private.robbery_gear_rules gr on gr.good_id=g.id where g.equipment_slots&&array['primary','secondary','armor','utility'])x)) end);
end$$;
create function public.robbery_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.robbery_state(false)$$;
alter function game_private.bin_state() rename to bin_state_before_robberies;
create function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=game_private.bin_state_before_robberies();
 return result||jsonb_build_object('robbery',game_private.robbery_state(not coalesce((result#>>'{scavenging,caught}')::boolean,false)));
end$$;

create function public.robbery_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();target uuid;nonce uuid;prior game_private.robbery_attempts;r game_private.robbery_rules;d uuid;t timestamptz;weapon jsonb;a jsonb;b jsonb;
 chance numeric;shots integer;percentage integer;amount bigint:=0;wallet bigint;won boolean;result jsonb;attempt_id uuid:=gen_random_uuid();reason text;old_version integer;payload_rules jsonb;next_r game_private.robbery_rules;guard game_private.robbery_protection;
begin
 perform game_private.require_active();if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 then raise exception 'Invalid robbery request.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the streets.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into strict r from game_private.robbery_rules for update;
  if p_action in('configure','gear') then
   if not game_private.has_permission('robbery.manage') then raise exception 'Owner robbery permission required.';end if;
   reason:=btrim(p_payload->>'reason');if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5–500 characters.';end if;
   perform set_config('game.reason','Robbery rules: '||reason,true);
   if p_action='configure' then
    if (p_payload->>'version')::integer is distinct from r.version then raise exception 'The rules changed. Refresh before saving.';end if;
    payload_rules:=p_payload->'rules';if jsonb_typeof(payload_rules) is distinct from 'object' then raise exception 'Provide valid rules.';end if;
    next_r:=jsonb_populate_record(r,payload_rules-'singleton'-'version');
    update game_private.robbery_rules set enabled=next_r.enabled,bullet_min=next_r.bullet_min,bullet_max=next_r.bullet_max,steal_min=next_r.steal_min,steal_max=next_r.steal_max,
     victim_cooldown_seconds=next_r.victim_cooldown_seconds,attacker_cooldown_seconds=next_r.attacker_cooldown_seconds,presence_seconds=next_r.presence_seconds,
     base_chance=next_r.base_chance,min_chance=next_r.min_chance,max_chance=next_r.max_chance,skill_weight=next_r.skill_weight,accuracy_weight=next_r.accuracy_weight,power_weight=next_r.power_weight,gear_weight=next_r.gear_weight,version=r.version+1;
   else
    if not exists(select 1 from public.game_goods where id=p_payload->>'good_id' and equipment_slots&&array['primary','secondary','armor','utility']) then raise exception 'Choose equippable gear.';end if;
    select version into old_version from game_private.robbery_gear_rules where good_id=p_payload->>'good_id';
    if (p_payload->>'version')::integer is distinct from coalesce(old_version,0) then raise exception 'The gear rule changed. Refresh before saving.';end if;
    insert into game_private.robbery_gear_rules(good_id,attack,defense,condition_max) values(p_payload->>'good_id',(p_payload->>'attack')::integer,(p_payload->>'defense')::integer,(p_payload->>'condition_max')::integer)
    on conflict(good_id) do update set attack=excluded.attack,defense=excluded.defense,condition_max=excluded.condition_max,version=robbery_gear_rules.version+1;
    update game_private.robbery_rules set version=version+1;
   end if;
   return jsonb_build_object('message','Robbery settings saved and audited.');
  end if;
  if p_action is distinct from 'attempt' then raise exception 'Unknown robbery action.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A request reference is required.';end if;
  select * into prior from game_private.robbery_attempts where season_id=s and attacker_id=u and request_id=nonce;
  if found then if prior.payload is distinct from p_payload then raise exception 'This request reference was already used.';end if;return prior.result;end if;
  perform game_private.season_guard();t:=clock_timestamp();
  if not r.enabled then raise exception 'Robberies are paused by the Owner.';end if;
  if (p_payload->>'rules_version')::int is distinct from r.version then raise exception 'Robbery rules changed. Review them before attempting.';end if;
  target:=(p_payload->>'target_id')::uuid;if target is null or target=u then raise exception 'Choose another player.';end if;
  select district_id into d from game_private.scav_sessions where season_id=s and player_id=u;
  if not game_private.robbery_available(s,u,d,t) or not game_private.robbery_available(s,target,d,t) then raise exception 'Both players must be active and stationary in the same Scavenging district, outside searches, prison and range sessions.';end if;
  perform 1 from public.game_players where id in(u,target) order by id for update;
  if exists(select 1 from game_private.robbery_protection where season_id=s and player_id=u and ready_at>t) then raise exception 'You are still cooling off after your last robbery.';end if;
  if exists(select 1 from game_private.robbery_protection where season_id=s and player_id=target and protected_until>t) then raise exception 'This player is protected after a recent robbery attempt.';end if;
  select cash into strict wallet from public.game_players where id=target and season_id=s;
  if floor(wallet::numeric*r.steal_max/100)<greatest(1,ceil(wallet::numeric*r.steal_min/100)) then raise exception 'This player does not carry enough cash for a robbery.';end if;
  weapon:=game_private.robbery_weapon(s,u);
  if weapon is null then raise exception 'Equip a working compatible gun first.';end if;
  if (p_payload->>'weapon_id') is distinct from weapon->>'id' then raise exception 'Your equipped weapon changed. Review the attempt again.';end if;
  if (weapon->>'ammo')::integer<r.bullet_max then raise exception 'Equip at least % compatible bullets to cover the maximum possible use.',r.bullet_max;end if;
  a:=game_private.robbery_factors(s,u);b:=game_private.robbery_factors(s,target);chance:=game_private.robbery_chance(a,b,r);
  -- All eligibility checks precede random rolls; every valid attempt is committed, including failure.
  shots:=r.bullet_min+floor(random()*(r.bullet_max-r.bullet_min+1))::integer;won:=random()*100<chance;
  percentage:=r.steal_min+floor(random()*(r.steal_max-r.steal_min+1))::integer;
  perform set_config('game.reason','Robbery: '||attempt_id,true);perform set_config('game.inventory_request',nonce::text,true);
  if shots>0 then
   update public.game_inventory_gear set quantity=quantity-shots,location=case when quantity=shots then 'retired' else location end,equipment_slot=case when quantity=shots then null else equipment_slot end
    where id=(weapon->>'ammo_id')::uuid and season_id=s and player_id=u and location='equipped' and quantity>=shots;
   if not found then raise exception 'Your equipped ammunition changed. Refresh the streets.';end if;
   update public.game_inventory_gear set condition=greatest(0,(weapon->>'condition')::integer-shots*(weapon->>'wear_per_shot')::integer) where id=(weapon->>'id')::uuid;
   update game_private.range_magazines set loaded=greatest(0,loaded-shots),reload_capacity=null,reload_started_at=null,reload_ready_at=null where season_id=s and player_id=u and ammo_id=(weapon->>'ammo_id')::uuid;
  end if;
  if won then
   amount:=least(floor(wallet::numeric*r.steal_max/100),greatest(ceil(wallet::numeric*r.steal_min/100),floor(wallet::numeric*percentage/100)))::bigint;
   perform game_private.district_wallet(target,-amount,'Robbery loss: '||attempt_id);perform game_private.district_wallet(u,amount,'Robbery proceeds: '||attempt_id);
  end if;
  insert into game_private.robbery_protection(season_id,player_id,ready_at) values(s,u,t+make_interval(secs=>r.attacker_cooldown_seconds)) on conflict(season_id,player_id) do update set ready_at=excluded.ready_at;
  insert into game_private.robbery_protection(season_id,player_id,protected_until) values(s,target,t+make_interval(secs=>r.victim_cooldown_seconds)) on conflict(season_id,player_id) do update set protected_until=excluded.protected_until;
  result:=jsonb_build_object('message',case when won then 'Robbery succeeded. Stole $'||amount||'.' else 'Robbery failed. No cash was taken.' end||' Used '||shots||' bullets.','succeeded',won,'cash',amount,'bullets',shots,'chance',chance,'ready_at',t+make_interval(secs=>r.attacker_cooldown_seconds),'protected_until',t+make_interval(secs=>r.victim_cooldown_seconds));
  insert into game_private.robbery_attempts(id,season_id,attacker_id,victim_id,district_id,request_id,payload,result,succeeded,chance,bullets,cash,weapon_id,factors,rule_snapshot,created_at)
   values(attempt_id,s,u,target,d,nonce,p_payload,result,won,chance,shots,amount,(weapon->>'id')::uuid,jsonb_build_object('attacker',a,'defender',b),to_jsonb(r),t);
  insert into public.game_events(player_id,description,cash_delta) values(u,result->>'message',amount),(target,case when won then 'Robbed by '||(select handle from public.game_players where id=u)||'. Lost $'||amount||' carried cash.' else 'You defended against a robbery by '||(select handle from public.game_players where id=u)||'.' end||' Protected for '||r.victim_cooldown_seconds/60||' minutes.',-amount);
  perform game_private.inventory_sync(s,u);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check the robbery values and refresh the streets.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;
revoke all on function game_private.robbery_factors(uuid,uuid),game_private.robbery_chance(jsonb,jsonb,game_private.robbery_rules),game_private.robbery_weapon(uuid,uuid),game_private.robbery_available(uuid,uuid,uuid,timestamptz),game_private.robbery_state(boolean),public.robbery_state(),game_private.bin_state_before_robberies(),game_private.bin_state(),public.robbery_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.robbery_state(boolean),public.robbery_state(),game_private.bin_state(),public.robbery_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';
