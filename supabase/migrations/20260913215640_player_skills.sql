-- Seasonal skills use existing verified activity, with immutable XP and editable level curves.
select pg_advisory_xact_lock(4704001);
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce Crafting, Sharpshooting and Lockpicking skills',true);
insert into public.game_permissions(id,owner_only) values('skills.manage',true);
insert into public.game_settings(key,value,minimum,maximum) values('skill_crafting_xp_per_minute',10,1,10000);
create table public.game_skill_definitions(
 id text primary key check(id in ('crafting','sharpshooting','lockpicking')),
 name text not null,description text not null,xp_to_20 integer not null default 10000 check(xp_to_20 between 19 and 1000000000),
 version integer not null default 1,display_order integer not null
);
insert into public.game_skill_definitions(id,name,description,display_order) values
 ('crafting','Crafting','Turn raw materials into something the city needs. Earn XP when you collect completed crafting jobs.',1),
 ('sharpshooting','Sharpshooting','Steady hands. Precise shots. Earn XP from your score when you complete eligible range sessions.',2),
 ('lockpicking','Lockpicking','Find the angle. Keep your nerve. Earn XP by successfully opening prison locks and freeing other players.',3);
create table game_private.skill_xp_ledger(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),skill_id text not null references public.game_skill_definitions(id),
 source_id uuid not null,delta bigint not null check(delta>0),description text not null,created_at timestamptz not null default clock_timestamp(),
 unique(skill_id,source_id)
);
create index skill_xp_player_season on game_private.skill_xp_ledger(player_id,season_id,skill_id) include(delta);
create index skill_xp_recent on game_private.skill_xp_ledger(player_id,season_id,created_at desc,id);
create table game_private.skill_requests(
 player_id uuid not null references public.game_players(id),request_id uuid not null,payload jsonb not null,result jsonb not null,
 primary key(player_id,request_id)
);
alter table public.game_skill_definitions enable row level security;
alter table game_private.skill_xp_ledger enable row level security;
alter table game_private.skill_requests enable row level security;
revoke all on public.game_skill_definitions,game_private.skill_xp_ledger,game_private.skill_requests from public,anon,authenticated;
create trigger skill_definitions_audit after insert or update or delete on public.game_skill_definitions for each row execute function game_private.audit_change();
create trigger skill_xp_retain before update or delete or truncate on game_private.skill_xp_ledger for each statement execute function game_private.district_immutable();
create trigger skill_requests_retain before update or delete or truncate on game_private.skill_requests for each statement execute function game_private.district_immutable();
-- Every level needs at least one more XP; the remaining XP follows a quadratic curve.
create function game_private.skill_threshold(p_level integer,p_total integer) returns bigint language sql immutable set search_path='' as $$
 select (p_level-1)::bigint+floor((p_total-19)::numeric*(p_level-1)*(p_level-1)/361)::bigint;
$$;
create function game_private.skill_level(p_xp bigint,p_total integer) returns integer language sql immutable set search_path='' as $$
 select coalesce(max(l),1) from generate_series(1,20) l where game_private.skill_threshold(l,p_total)<=greatest(0,p_xp);
$$;
-- Crafting awards are fixed when a job is queued, using its actual scheduled work time.
alter table public.game_crafting_batches add column skill_xp bigint not null default 0 check(skill_xp>=0);
update public.game_crafting_batches b set skill_xp=greatest(1,floor(greatest(0,extract(epoch from(j.ready_at-b.starts_at)))*game_private.setting('skill_crafting_xp_per_minute')/60))::bigint
 from public.game_season_jobs j where j.id=b.job_id;
create function game_private.crafting_skill_snapshot() returns trigger language plpgsql set search_path='' as $$
begin
 select greatest(1,floor(greatest(0,extract(epoch from(j.ready_at-new.starts_at)))*game_private.setting('skill_crafting_xp_per_minute')/60))::bigint into new.skill_xp
 from public.game_season_jobs j where j.id=new.job_id;
 return new;
end$$;
create trigger crafting_skill_snapshot before insert on public.game_crafting_batches for each row execute function game_private.crafting_skill_snapshot();
create function game_private.skill_activity_award() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='game_season_jobs' then
  if new.kind='crafting' and new.status='completed' and old.status is distinct from 'completed' then
   insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description)
    select new.season_id,new.player_id,'crafting',new.id,b.skill_xp,'Collected '||b.recipe_name from public.game_crafting_batches b where b.job_id=new.id and b.skill_xp>0 on conflict(skill_id,source_id) do nothing;
  end if;
 elsif tg_table_name='range_xp_ledger' then
  insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
   values(new.season_id,new.player_id,'sharpshooting',new.session_id,new.delta,'Completed range practice',new.created_at) on conflict(skill_id,source_id) do nothing;
 elsif tg_table_name='prison_break_attempts' then
  if new.status='succeeded' and old.status is distinct from 'succeeded' and new.reward_power>0 then
   insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description)
    values(new.season_id,new.rescuer_id,'lockpicking',new.id,new.reward_power,'Opened a Blackwater Island prison lock') on conflict(skill_id,source_id) do nothing;
  end if;
 end if;
 return new;
end$$;
create trigger skill_crafting_award after update of status on public.game_season_jobs for each row execute function game_private.skill_activity_award();
create trigger skill_range_award after insert on game_private.range_xp_ledger for each row execute function game_private.skill_activity_award();
create trigger skill_lockpicking_award after update of status on game_private.prison_break_attempts for each row execute function game_private.skill_activity_award();
-- Import earned history once; no wallet, respect or original activity record is altered.
insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
 select j.season_id,j.player_id,'crafting',j.id,b.skill_xp,'Collected '||b.recipe_name,coalesce(j.ready_at,b.created_at) from public.game_crafting_batches b join public.game_season_jobs j on j.id=b.job_id where j.status='completed' and b.skill_xp>0;
insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
 select season_id,player_id,'sharpshooting',session_id,delta,'Completed range practice',created_at from game_private.range_xp_ledger;
insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
 select season_id,rescuer_id,'lockpicking',id,reward_power,'Opened a Blackwater Island prison lock',coalesce(completed_at,started_at) from game_private.prison_break_attempts where status='succeeded' and reward_power>0;
create function game_private.skills_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=u) then perform game_private.state();end if;
 return jsonb_build_object('season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),'player_id',u,'server_time',clock_timestamp(),'max_level',20,
 'can_manage',game_private.has_permission('skills.manage'),'crafting_xp_per_minute',game_private.setting('skill_crafting_xp_per_minute'),
 'skills',(select jsonb_agg(to_jsonb(c)||jsonb_build_object('xp',a.xp,'level',l.level,'level_xp',game_private.skill_threshold(l.level,c.xp_to_20),'next_level_xp',case when l.level<20 then game_private.skill_threshold(l.level+1,c.xp_to_20) else null end,
 'thresholds',(select jsonb_agg(jsonb_build_object('level',v,'xp',game_private.skill_threshold(v,c.xp_to_20)) order by v) from generate_series(1,20) v)) order by c.display_order)
 from public.game_skill_definitions c cross join lateral(select coalesce(sum(delta),0)::bigint xp from game_private.skill_xp_ledger where skill_id=c.id and player_id=u and season_id=s)a
 cross join lateral(select game_private.skill_level(a.xp,c.xp_to_20) level)l),
 'recent',(select coalesce(jsonb_agg(x order by x.created_at desc,x.id),'[]') from(select id,skill_id,delta,description,created_at from game_private.skill_xp_ledger where player_id=u and season_id=s order by created_at desc,id limit 20)x));
end$$;
create function game_private.skills_manage(p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();nonce uuid;prior game_private.skill_requests;d public.game_skill_definitions;n numeric;rate_value numeric;reason text;result jsonb;
begin
 perform game_private.require_active();if not game_private.has_permission('skills.manage') then raise exception 'Owner skill-management permission required.';end if;
 if not game_private.rate('skills_manage',20) then return jsonb_build_object('error','Please wait before changing skills again.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid skill settings.';end if;
  perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
  nonce:=(p_payload->>'request_id')::uuid;if nonce is null then raise exception 'A save reference is required.';end if;
  select * into prior from game_private.skill_requests where player_id=u and request_id=nonce;
  if found then if prior.payload is distinct from p_payload then raise exception 'This save reference was already used.';end if;return prior.result||jsonb_build_object('state',game_private.skills_state());end if;
  select * into d from public.game_skill_definitions where id=p_payload->>'skill_id' for update;
  if not found then raise exception 'Choose an existing skill.';end if;
  if (p_payload->>'version')::int is distinct from d.version then raise exception 'These settings changed. Refresh before saving.';end if;
  n:=(p_payload->>'xp_to_20')::numeric;reason:=btrim(p_payload->>'reason');
  if n is null or n<>trunc(n) or n not between 19 and 1000000000 then raise exception 'Choose a whole XP target between 19 and 1,000,000,000.';end if;
  if reason is null or length(reason) not between 5 and 500 then raise exception 'Add an audit reason of 5 to 500 characters.';end if;
  if d.id='crafting' then
   rate_value:=(p_payload->>'crafting_xp_per_minute')::numeric;
   if rate_value is null or rate_value<>trunc(rate_value) or rate_value not between 1 and 10000 then raise exception 'Crafting XP per minute must be a whole number from 1 to 10,000.';end if;
   if (p_payload->>'expected_crafting_rate')::numeric is distinct from game_private.setting('skill_crafting_xp_per_minute') then raise exception 'Crafting rewards changed. Refresh before saving.';end if;
  end if;
  perform set_config('game.reason','Skill configuration: '||reason,true);
  update public.game_skill_definitions set xp_to_20=n::integer,version=version+1 where id=d.id;
  if d.id='crafting' then update public.game_settings set value=rate_value where key='skill_crafting_xp_per_minute';end if;
  result:=jsonb_build_object('message',d.name||' progression saved. Earned XP is preserved.');
  insert into game_private.skill_requests values(u,nonce,p_payload,result);
  return result||jsonb_build_object('state',game_private.skills_state());
 exception when invalid_text_representation or numeric_value_out_of_range or check_violation then return jsonb_build_object('error','Check the skill values and try again.');
 when raise_exception then return jsonb_build_object('error',sqlerrm);end;
end$$;
create function public.skills_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.skills_state()$$;
create function public.skills_manage(p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.skills_manage(p_payload)$$;
revoke all on function game_private.skill_threshold(integer,integer),game_private.skill_level(bigint,integer),game_private.crafting_skill_snapshot(),game_private.skill_activity_award(),game_private.skills_state(),game_private.skills_manage(jsonb),public.skills_state(),public.skills_manage(jsonb) from public,anon,authenticated;
grant execute on function game_private.skills_state(),game_private.skills_manage(jsonb),public.skills_state(),public.skills_manage(jsonb) to authenticated;
notify pgrst,'reload schema';
