-- Personal district heat persists across visits, decays over time, and resets by season.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Scavenging skill avoidance and district heat',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_heat_per_search',8,0,100),
 ('scavenging_heat_decay_per_minute',1,0,100),
 ('scavenging_heat_detection_bonus_percent',100,0,300),
 ('scavenging_skill_detection_reduction_percent',50,0,90);
create table game_private.scav_district_heat(
 season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),
 heat numeric not null default 0 check(heat between 0 and 100),
 searches bigint not null default 0 check(searches>=0),
 updated_at timestamptz not null default clock_timestamp(),
 primary key(season_id,player_id,district_id)
);
alter table game_private.scav_district_heat enable row level security;
revoke all on game_private.scav_district_heat from public,anon,authenticated;
create function game_private.scav_heat_value(h numeric,stamp timestamptz,t timestamptz) returns numeric
language sql stable security definer set search_path='' as $$
 select greatest(0,h-greatest(0,extract(epoch from t-stamp))/60*game_private.setting('scavenging_heat_decay_per_minute'));
$$;
create function game_private.scav_risk(s uuid,u uuid,d uuid) returns jsonb
language sql volatile security definer set search_path='' as $$
 select jsonb_build_object('level',l.level,'heat',round(h.heat,1),'searches',h.searches,
 'skill_reduction_percent',round((l.level-1)*game_private.setting('scavenging_skill_detection_reduction_percent')/19.0,1),
 'detection_multiplier',(1+h.heat*game_private.setting('scavenging_heat_detection_bonus_percent')/10000)*(1-(l.level-1)*game_private.setting('scavenging_skill_detection_reduction_percent')/1900.0),
 'heat_per_search',game_private.setting('scavenging_heat_per_search'),'cooling_per_minute',game_private.setting('scavenging_heat_decay_per_minute'))
 from (select game_private.skill_level(coalesce((select sum(delta)::bigint from game_private.skill_xp_ledger where season_id=s and player_id=u and skill_id='scavenging'),0),xp_to_20) level from public.game_skill_definitions where id='scavenging')l
 cross join lateral(select coalesce((select game_private.scav_heat_value(heat,updated_at,statement_timestamp()) from game_private.scav_district_heat where season_id=s and player_id=u and district_id=d),0) heat,
 coalesce((select searches from game_private.scav_district_heat where season_id=s and player_id=u and district_id=d),0) searches)h;
$$;
create function game_private.scav_search_heat() returns trigger
language plpgsql security definer set search_path='' as $$
declare risk jsonb;units jsonb;
begin
 if new.pending is null then return new;end if;
 if old.pending->>'id' is distinct from new.pending->>'id' then
  insert into game_private.scav_district_heat(season_id,player_id,district_id,heat,searches)
  values(new.season_id,new.player_id,new.district_id,game_private.setting('scavenging_heat_per_search'),1)
  on conflict(season_id,player_id,district_id) do update set
   heat=least(100,game_private.scav_heat_value(scav_district_heat.heat,scav_district_heat.updated_at,clock_timestamp())+game_private.setting('scavenging_heat_per_search')),
   searches=scav_district_heat.searches+1,updated_at=clock_timestamp();
  new.pending:=new.pending||jsonb_build_object('risk',game_private.scav_risk(new.season_id,new.player_id,new.district_id));
 end if;
 -- Base search attaches patrols in a second update. Snapshot once, before any resolver.
 if new.pending?'patrols' and not coalesce((new.pending->>'risk_applied')::boolean,false) then
  risk:=coalesce(new.pending->'risk',game_private.scav_risk(new.season_id,new.player_id,new.district_id));
  select coalesce(jsonb_agg(x||jsonb_build_object('radius',(x->>'radius')::numeric*(risk->>'detection_multiplier')::numeric)),'[]') into units from jsonb_array_elements(new.pending->'patrols')x;
  new.pending:=new.pending||jsonb_build_object('risk',risk,'risk_applied',true,'patrols',units);
 end if;
 return new;
end$$;
create trigger scav_search_heat before update of pending on game_private.scav_sessions for each row execute function game_private.scav_search_heat();
alter function game_private.bin_state() rename to bin_state_before_heat;
create function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;s uuid;u uuid:=auth.uid();districts jsonb;
begin
 result:=game_private.bin_state_before_heat();s:=(result#>>'{season,id}')::uuid;
 select coalesce(jsonb_object_agg(d->>'id',game_private.scav_risk(s,u,(d->>'id')::uuid)),'{}') into districts from jsonb_array_elements(result->'districts')d;
 return jsonb_set(result,'{scavenging}',(result->'scavenging')||jsonb_build_object('district_risk',districts));
end$$;
revoke all on function game_private.scav_heat_value(numeric,timestamptz,timestamptz),game_private.scav_risk(uuid,uuid,uuid),game_private.scav_search_heat(),game_private.bin_state_before_heat(),game_private.bin_state() from public,anon,authenticated;
grant execute on function game_private.bin_state() to authenticated;
notify pgrst,'reload schema';
