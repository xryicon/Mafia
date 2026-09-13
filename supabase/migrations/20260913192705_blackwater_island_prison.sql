-- Blackwater Island is the city prison. No existing players are sentenced.
select set_config('game.reason','Designate Blackwater Island as the city prison',true);
update public.game_districts set district_type='prison',
 tagline='Beyond the harbor. Behind bars.',
 description='Blackwater Island houses the city prison. Guard towers watch the harbor while inmates serve their sentences behind its walls.',
 industries=array['City prison','Maximum security'],
 strategic_importance='Jailed players are held on Blackwater Island until their sentence expires or the Owner authorizes release.',
 map_data=map_data||'{"transport":"Prison ferry","designation":"City prison"}'::jsonb
where slug='blackwater-island';
insert into public.game_permissions(id,owner_only) values('prison.manage',true);
create table public.game_prison_sentences (
 season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),
 id uuid not null unique default gen_random_uuid(),
 reason text not null check(length(reason) between 3 and 2000),
 started_at timestamptz not null default clock_timestamp(),
 release_at timestamptz not null, released_at timestamptz,
 actor_id uuid references public.game_players(id),
 primary key(season_id,player_id), check(release_at>started_at)
);
alter table public.game_prison_sentences enable row level security;
revoke all on public.game_prison_sentences from public,anon,authenticated;
grant select on public.game_prison_sentences to authenticated;
create policy prison_read on public.game_prison_sentences for select to authenticated
 using(player_id=(select auth.uid()));
create trigger prison_audit after insert or update or delete on public.game_prison_sentences
 for each row execute function game_private.audit_change();

-- Shared custody lock permits concurrent gameplay; sentencing takes it exclusively.
-- Sentencing never acquires economic locks or changes wallet rows.
create or replace function game_private.season_guard(require_open boolean default true)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.game_seasons;
begin
 perform pg_advisory_xact_lock_shared(4704001);
 select * into strict s from public.game_seasons where id=game_private.current_season();
 if require_open then
  if s.status<>'open' or (s.ends_at is not null and clock_timestamp()>=s.ends_at) then raise exception 'This season is closed for gameplay.';end if;
  perform pg_advisory_xact_lock_shared(4704031);
  if exists(select 1 from public.game_prison_sentences where season_id=s.id and player_id=auth.uid() and released_at is null and release_at>clock_timestamp()) then
   raise exception 'You are in Blackwater Island Prison until your release.';
  end if;
 end if;
 return s.id;
end$$;

create function game_private.prison_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;t timestamptz:=clock_timestamp();sentence jsonb;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 select jsonb_build_object('id',p.id,'reason',p.reason,'started_at',p.started_at,'release_at',p.release_at) into sentence
 from public.game_prison_sentences p where p.season_id=s and p.player_id=auth.uid() and p.released_at is null and p.release_at>t;
 return jsonb_build_object('jailed',sentence is not null,'sentence',sentence,'district_slug','blackwater-island',
  'server_time',t,'can_manage',game_private.has_permission('prison.manage'));
end$$;

-- Trusted entry point for future arrest mechanics; never granted to clients.
create function game_private.imprison(target_id uuid,minutes integer,reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare s uuid;sentence_id uuid;
begin
 s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704031);
 if minutes is null or minutes not between 1 and 10080 then raise exception 'Sentence must be between 1 minute and 7 days.';end if;
 if reason is null or length(trim(reason)) not between 3 and 2000 then raise exception 'Enter a reason between 3 and 2000 characters.';end if;
 if not exists(select 1 from public.game_players where id=target_id and deleted_at is null) then raise exception 'Player not found.';end if;
 if exists(select 1 from public.game_prison_sentences where season_id=s and player_id=target_id and released_at is null and release_at>clock_timestamp()) then raise exception 'This player is already in prison.';end if;
 perform set_config('game.reason',trim(reason),true);
 insert into public.game_prison_sentences as p(season_id,player_id,reason,release_at,actor_id)
 values(s,target_id,trim(reason),clock_timestamp()+make_interval(mins=>minutes),auth.uid())
 on conflict(season_id,player_id) do update set id=gen_random_uuid(),reason=excluded.reason,
 started_at=excluded.started_at,release_at=excluded.release_at,released_at=null,actor_id=excluded.actor_id returning id into sentence_id;
 return sentence_id;
end$$;

create function game_private.prison_manage(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;target_id uuid;sentence_id uuid;reason text:=trim(p_payload->>'reason');
begin
 perform game_private.require_active();
 if not game_private.has_permission('prison.manage') then raise exception 'Owner permission required.';end if;
 s:=game_private.season_guard(false);
 if p_action='list' then
  return jsonb_build_object('sentences',(select coalesce(jsonb_agg(x),'[]') from (
   select p.id,p.player_id,g.handle,p.reason,p.started_at,p.release_at from public.game_prison_sentences p join public.game_players g on g.id=p.player_id
   where p.season_id=s and p.released_at is null and p.release_at>clock_timestamp() order by p.release_at limit 200)x));
 end if;
 if reason is null or length(reason) not between 3 and 2000 then raise exception 'Enter a reason between 3 and 2000 characters.';end if;
 target_id:=(p_payload->>'player_id')::uuid;
 if p_action='jail' then
  sentence_id:=game_private.imprison(target_id,(p_payload->>'minutes')::integer,reason);
  return jsonb_build_object('message','Player transferred to Blackwater Island Prison.','sentence_id',sentence_id);
 elsif p_action='release' then
  perform pg_advisory_xact_lock(4704031);perform set_config('game.reason',reason,true);
  update public.game_prison_sentences set released_at=clock_timestamp() where season_id=s and player_id=target_id
   and id=(p_payload->>'sentence_id')::uuid and released_at is null and release_at>clock_timestamp();
  if not found then raise exception 'This sentence has already ended or changed. Refresh the prison register.';end if;
  return jsonb_build_object('message','Player released from Blackwater Island Prison.');
 end if;
 raise exception 'Unknown prison action.';
end$$;
create function public.prison_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.prison_state()$$;
create function public.prison_manage(p_action text,p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select game_private.prison_manage(p_action,p_payload)$$;
revoke all on function game_private.imprison(uuid,integer,text),game_private.prison_state(),game_private.prison_manage(text,jsonb),public.prison_state(),public.prison_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.prison_state(),game_private.prison_manage(text,jsonb),public.prison_state(),public.prison_manage(text,jsonb) to authenticated;
notify pgrst,'reload schema';

