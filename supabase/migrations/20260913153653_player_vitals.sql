-- Private, season-aware health and armour. No consumable or equipment actions are added.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce dashboard health and armour',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('health_normal_max',100,1,1000),('health_boost_max',120,1,1000),
 ('health_boost_decay_seconds',60,1,86400),('armour_max',100,1,1000);
-- NULL health means full normal health until a gameplay action changes it.
alter table public.game_season_players
 add column health numeric(8,3) check(health between 0 and 1000),
 add column health_updated_at timestamptz not null default clock_timestamp(),
 add column armour numeric(8,3) not null default 0 check(armour between 0 and 1000);
create function game_private.vitals_changed() returns trigger language plpgsql set search_path='' as $$
begin
 if new.health is distinct from old.health then new.health_updated_at:=clock_timestamp();end if;
 return new;
end$$;
create trigger vitals_changed before update of health on public.game_season_players for each row execute function game_private.vitals_changed();
create trigger vitals_audit after update of health,armour on public.game_season_players for each row
 when(old.health is distinct from new.health or old.armour is distinct from new.armour) execute function game_private.audit_change();
create function game_private.vitals_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();v public.game_season_players;normal numeric;cap numeric;armour_limit numeric;decay numeric;health_now numeric;t timestamptz:=clock_timestamp();
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 normal:=game_private.setting('health_normal_max');cap:=greatest(normal,game_private.setting('health_boost_max'));
 armour_limit:=game_private.setting('armour_max');decay:=game_private.setting('health_boost_decay_seconds');
 select * into v from public.game_season_players where season_id=s and player_id=u;
 health_now:=least(cap,coalesce(v.health,normal));
 -- Only overheal decays. Injuries and ordinary health never heal or decay here.
 if health_now>normal then health_now:=greatest(normal,health_now-greatest(0,extract(epoch from(t-v.health_updated_at)))/decay);end if;
 return jsonb_build_object('season_id',s,'health',health_now,'health_max',normal,'health_cap',cap,
 'armour',least(armour_limit,coalesce(v.armour,0)),'armour_max',armour_limit,'decay_seconds',decay,'server_time',t);
end$$;
create function public.vitals_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.vitals_state()$$;
revoke all on function game_private.vitals_changed(),game_private.vitals_state(),public.vitals_state() from public,anon,authenticated;
grant execute on function game_private.vitals_state(),public.vitals_state() to authenticated;
-- Existing season-player RLS and revoked table access also cover these columns.
notify pgrst,'reload schema';
