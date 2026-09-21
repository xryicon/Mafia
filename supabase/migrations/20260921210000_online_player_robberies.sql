-- Move robbery to the global online directory. Preserve all existing balances and outcomes.
select pg_advisory_xact_lock(4704020);
alter table game_private.robbery_attempts alter column district_id drop not null;
-- Keep the historical presence table and function arguments for compatibility; they no longer control eligibility.
create or replace function game_private.robbery_available(s uuid,u uuid,d uuid,t timestamptz) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from game_private.online_players() o join public.game_players p on p.id=o.player_id
 where p.id=u and p.season_id=s
 and not exists(select 1 from public.game_prison_sentences where season_id=s and player_id=u and released_at is null and release_at>t)
 and not exists(select 1 from public.game_range_sessions where season_id=s and player_id=u and status='active' and ends_at>t));
$$;
create or replace function game_private.robbery_state(touch_presence boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();d uuid;t timestamptz:=clock_timestamp();r game_private.robbery_rules;f jsonb;
begin
 perform game_private.require_active();if not game_private.rate('robbery_read',120) then raise exception 'Too many player updates. Wait a moment.';end if;
 s:=game_private.season_guard(false);select * into strict r from game_private.robbery_rules;
 f:=game_private.robbery_factors(s,u);
 return jsonb_build_object('season_id',s,'server_time',t,'district_id',d,'rules',to_jsonb(r)-'singleton','factors',f,'weapon',game_private.robbery_weapon(s,u),
 'available',game_private.robbery_available(s,u,d,t),'ready_at',(select ready_at from game_private.robbery_protection where season_id=s and player_id=u),
 'protected_until',(select protected_until from game_private.robbery_protection where season_id=s and player_id=u),
 'targets',(select coalesce(jsonb_agg(x),'[]') from(select p.id,p.handle,game_private.player_avatar(p.id) avatar_url,p.xp power,
  guard.protected_until,game_private.robbery_chance(f,game_private.robbery_factors(s,p.id),r) chance
  from game_private.online_players() online join public.game_players p on p.id=online.player_id and p.season_id=s
  left join game_private.robbery_protection guard on guard.season_id=s and guard.player_id=p.id
  where p.id<>u and game_private.robbery_available(s,p.id,d,t)
  order by p.handle,p.id limit 100)x),
 'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from(select a.id,a.created_at,a.succeeded,a.cash,a.bullets,a.attacker_id=u attacking,
  case when a.attacker_id=u then v.handle else p.handle end other_name from game_private.robbery_attempts a join public.game_players p on p.id=a.attacker_id join public.game_players v on v.id=a.victim_id
  where a.season_id=s and u in(a.attacker_id,a.victim_id) order by a.created_at desc,a.id desc limit 20)x),
 'management',case when game_private.has_permission('robbery.manage') then jsonb_build_object('gear',(select coalesce(jsonb_agg(x order by x.name),'[]') from(select g.id,g.name,coalesce(gr.attack,0) attack,coalesce(gr.defense,0) defense,coalesce(gr.condition_max,100) condition_max,coalesce(gr.version,0) version from public.game_goods g left join game_private.robbery_gear_rules gr on gr.good_id=g.id where g.equipment_slots&&array['primary','secondary','armor','utility'])x)) end);
end$$;
create or replace function public.robbery_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();target uuid;nonce uuid;prior game_private.robbery_attempts;r game_private.robbery_rules;d uuid;t timestamptz;weapon jsonb;a jsonb;b jsonb;
 chance numeric;shots integer;percentage integer;amount bigint:=0;wallet bigint;won boolean;result jsonb;attempt_id uuid:=gen_random_uuid();reason text;old_version integer;payload_rules jsonb;next_r game_private.robbery_rules;guard game_private.robbery_protection;
begin
 perform game_private.require_active();if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>8192 then raise exception 'Invalid mugging request.';end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh the player list.';end if;
  perform pg_advisory_xact_lock(4704020);
  select * into strict r from game_private.robbery_rules for update;
  if p_action in('configure','gear') then
   if not game_private.has_permission('robbery.manage') then raise exception 'Owner mugging permission required.';end if;
   reason:=btrim(p_payload->>'reason');if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5â€“500 characters.';end if;
   perform set_config('game.reason','Mugging rules: '||reason,true);
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
   return jsonb_build_object('message','Mugging settings saved and audited.');
  end if;
  if p_action is distinct from 'attempt' then raise exception 'Unknown mugging action.';end if;
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A request reference is required.';end if;
  select * into prior from game_private.robbery_attempts where season_id=s and attacker_id=u and request_id=nonce;
  if found then if prior.payload is distinct from p_payload then raise exception 'This request reference was already used.';end if;return prior.result;end if;
  perform game_private.season_guard();t:=clock_timestamp();
  if not r.enabled then raise exception 'Muggings are paused by the Owner.';end if;
  if (p_payload->>'rules_version')::int is distinct from r.version then raise exception 'Mugging rules changed. Review them before attempting.';end if;
  target:=(p_payload->>'target_id')::uuid;if target is null or target=u then raise exception 'Choose another player.';end if;
  if not game_private.robbery_available(s,u,d,t) or not game_private.robbery_available(s,target,d,t) then raise exception 'Both players must be online, outside prison and active range sessions.';end if;
  perform 1 from public.game_players where id in(u,target) order by id for update;
  if exists(select 1 from game_private.robbery_protection where season_id=s and player_id=u and ready_at>t) then raise exception 'You are still cooling off after your last mugging.';end if;
  if exists(select 1 from game_private.robbery_protection where season_id=s and player_id=target and protected_until>t) then raise exception 'This player is protected after a recent mugging attempt.';end if;
  select cash into strict wallet from public.game_players where id=target and season_id=s;
  if floor(wallet::numeric*r.steal_max/100)<greatest(1,ceil(wallet::numeric*r.steal_min/100)) then raise exception 'This player does not carry enough cash for a mugging.';end if;
  weapon:=game_private.robbery_weapon(s,u);
  if weapon is null then raise exception 'Equip a working compatible gun first.';end if;
  if (p_payload->>'weapon_id') is distinct from weapon->>'id' then raise exception 'Your equipped weapon changed. Review the attempt again.';end if;
  if (weapon->>'ammo')::integer<r.bullet_max then raise exception 'Equip at least % compatible bullets to cover the maximum possible use.',r.bullet_max;end if;
  a:=game_private.robbery_factors(s,u);b:=game_private.robbery_factors(s,target);chance:=game_private.robbery_chance(a,b,r);
  -- All eligibility checks precede random rolls; every valid attempt is committed, including failure.
  shots:=r.bullet_min+floor(random()*(r.bullet_max-r.bullet_min+1))::integer;won:=random()*100<chance;
  percentage:=r.steal_min+floor(random()*(r.steal_max-r.steal_min+1))::integer;
  perform set_config('game.reason','Mugging: '||attempt_id,true);perform set_config('game.inventory_request',nonce::text,true);
  if shots>0 then
   update public.game_inventory_gear set quantity=quantity-shots,location=case when quantity=shots then 'retired' else location end,equipment_slot=case when quantity=shots then null else equipment_slot end
    where id=(weapon->>'ammo_id')::uuid and season_id=s and player_id=u and location='equipped' and quantity>=shots;
   if not found then raise exception 'Your equipped ammunition changed. Refresh the player list.';end if;
   update public.game_inventory_gear set condition=greatest(0,(weapon->>'condition')::integer-shots*(weapon->>'wear_per_shot')::integer) where id=(weapon->>'id')::uuid;
   update game_private.range_magazines set loaded=greatest(0,loaded-shots),reload_capacity=null,reload_started_at=null,reload_ready_at=null where season_id=s and player_id=u and ammo_id=(weapon->>'ammo_id')::uuid;
  end if;
  if won then
   amount:=least(floor(wallet::numeric*r.steal_max/100),greatest(ceil(wallet::numeric*r.steal_min/100),floor(wallet::numeric*percentage/100)))::bigint;
   perform game_private.district_wallet(target,-amount,'Mugging loss: '||attempt_id);perform game_private.district_wallet(u,amount,'Mugging proceeds: '||attempt_id);
  end if;
  insert into game_private.robbery_protection(season_id,player_id,ready_at) values(s,u,t+make_interval(secs=>r.attacker_cooldown_seconds)) on conflict(season_id,player_id) do update set ready_at=excluded.ready_at;
  insert into game_private.robbery_protection(season_id,player_id,protected_until) values(s,target,t+make_interval(secs=>r.victim_cooldown_seconds)) on conflict(season_id,player_id) do update set protected_until=excluded.protected_until;
  result:=jsonb_build_object('message',case when won then 'Mugging succeeded. Stole $'||amount||'.' else 'Mugging failed. No cash was taken.' end||' Used '||shots||' bullets.','succeeded',won,'cash',amount,'bullets',shots,'chance',chance,'ready_at',t+make_interval(secs=>r.attacker_cooldown_seconds),'protected_until',t+make_interval(secs=>r.victim_cooldown_seconds));
  insert into game_private.robbery_attempts(id,season_id,attacker_id,victim_id,district_id,request_id,payload,result,succeeded,chance,bullets,cash,weapon_id,factors,rule_snapshot,created_at)
   values(attempt_id,s,u,target,d,nonce,p_payload,result,won,chance,shots,amount,(weapon->>'id')::uuid,jsonb_build_object('attacker',a,'defender',b),to_jsonb(r),t);
  insert into public.game_events(player_id,description,cash_delta) values(u,result->>'message',amount),(target,case when won then 'Mugged by '||(select handle from public.game_players where id=u)||'. Lost $'||amount||' carried cash.' else 'You defended against a mugging by '||(select handle from public.game_players where id=u)||'.' end||' Protected for '||r.victim_cooldown_seconds/60||' minutes.',-amount);
  perform game_private.inventory_sync(s,u);return result;
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation or not_null_violation then return jsonb_build_object('error','Check the mugging values and refresh the player list.');
 when raise_exception then return jsonb_build_object('error',SQLERRM);end;
end$$;

-- Keep the existing Scavenging/police state intact without robbery polling or street presence writes.
create or replace function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin return game_private.bin_state_before_robberies();end$$;
-- CREATE OR REPLACE preserves the existing authenticated-only entry points and private helper ACLs.
notify pgrst,'reload schema';
