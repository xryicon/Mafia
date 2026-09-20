-- Patrols arrest only active searches. Movement alone never creates an offence.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce police patrols for active scavenging searches',true);
insert into public.game_settings(key,value,minimum,maximum) values
 ('scavenging_patrol_enabled',1,0,1),('scavenging_patrol_count',2,1,4),
 ('scavenging_patrol_seconds_per_block',8,2,60),('scavenging_patrol_radius_percent',22,5,50),
 ('scavenging_patrol_sentence_minutes',5,1,10080);

create function game_private.scav_patrols(d uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare routes jsonb:='[[[0,0],[4,0],[4,2],[0,2],[0,0]],[[1,0],[1,1],[3,1],[3,2],[1,2],[1,0]],[[0,1],[4,1],[4,0],[0,0],[0,1]],[[2,0],[2,2],[4,2],[4,0],[2,0]]]';result jsonb:='[]';i integer;
begin
 if game_private.setting('scavenging_patrol_enabled')=0 or d is null then return result;end if;
 for i in 0..game_private.setting('scavenging_patrol_count')::int-1 loop
  result:=result||jsonb_build_array(jsonb_build_object('id','patrol-'||(i+1),'route_points',routes->i,
   'epoch',1700000000+mod(abs(hashtextextended(d::text,i)::numeric),100000),
   'seconds_per_block',game_private.setting('scavenging_patrol_seconds_per_block'),'radius',game_private.setting('scavenging_patrol_radius_percent')/100.0));
 end loop;
 return result;
end$$;

-- Sweep the full search interval, not just poll instants: refreshing late cannot dodge a patrol.
create function game_private.scav_patrol_contact(patrols jsonb,point jsonb,started timestamptz,finished timestamptz) returns text language plpgsql immutable set search_path='' as $$
declare patrol jsonb;route jsonb;a jsonb;b jsonb;i integer;cycle bigint;first_cycle bigint;last_cycle bigint;
 epoch double precision;speed double precision;period double precision;offset_seconds double precision;length double precision;
 lo double precision;hi double precision;window_start double precision:=extract(epoch from started);window_end double precision;
 segment_start double precision;segment_end double precision;ax double precision;ay double precision;bx double precision;end_y double precision;
 dx double precision;dy double precision;t double precision;px double precision:=(point->>0)::double precision;py double precision:=(point->>1)::double precision;
begin
 if finished<started then return null;end if;
 for patrol in select value from jsonb_array_elements(coalesce(patrols,'[]')) loop
  route:=patrol->'route_points';epoch:=(patrol->>'epoch')::double precision;speed:=(patrol->>'seconds_per_block')::double precision;
  period:=game_private.scav_route_length(route)*speed;if period<=0 then continue;end if;
  window_end:=least(extract(epoch from finished),window_start+period);
  first_cycle:=floor((window_start-epoch)/period);last_cycle:=floor((window_end-epoch)/period);
  for cycle in first_cycle..last_cycle loop
   offset_seconds:=0;
   for i in 1..jsonb_array_length(route)-1 loop
    a:=route->(i-1);b:=route->i;length:=game_private.scav_route_length(jsonb_build_array(a,b));
    if length=0 then continue;end if;
    segment_start:=epoch+cycle*period+offset_seconds;segment_end:=segment_start+length*speed;offset_seconds:=offset_seconds+length*speed;
    lo:=greatest(window_start,segment_start);hi:=least(window_end,segment_end);if hi<lo then continue;end if;
    ax:=(a->>0)::double precision+((b->>0)::double precision-(a->>0)::double precision)*(lo-segment_start)/(length*speed);
    ay:=(a->>1)::double precision+((b->>1)::double precision-(a->>1)::double precision)*(lo-segment_start)/(length*speed);
    bx:=(a->>0)::double precision+((b->>0)::double precision-(a->>0)::double precision)*(hi-segment_start)/(length*speed);
    end_y:=(a->>1)::double precision+((b->>1)::double precision-(a->>1)::double precision)*(hi-segment_start)/(length*speed);
    dx:=bx-ax;dy:=end_y-ay;t:=case when dx*dx+dy*dy=0 then 0 else greatest(0,least(1,((px-ax)*dx+(py-ay)*dy)/(dx*dx+dy*dy))) end;
    if (px-ax-t*dx)^2+(py-ay-t*dy)^2<=((patrol->>'radius')::double precision)^2 then return patrol->>'id';end if;
   end loop;
  end loop;
 end loop;
 return null;
end$$;

create table game_private.scav_arrests(
 attempt_id uuid primary key,season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 district_id uuid not null references public.game_districts(id),patrol_id text not null,kind text not null,sentence_id uuid not null,created_at timestamptz not null default clock_timestamp()
);
alter table game_private.scav_arrests enable row level security;
revoke all on game_private.scav_arrests from public,anon,authenticated;
create trigger scav_arrests_retain before update or delete or truncate on game_private.scav_arrests for each statement execute function game_private.district_immutable();

create function game_private.scav_resolve_patrol() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;u uuid:=auth.uid();v game_private.scav_sessions;stamp timestamptz;patrol text;sentence uuid;point jsonb;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 if not exists(select 1 from game_private.scav_sessions where season_id=s and player_id=u and pending is not null and pending?'patrols') then return null;end if;
 -- Same lock order as street actions: season, economy, custody, then rows.
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 select * into v from game_private.scav_sessions where season_id=s and player_id=u for update;
 if v.pending is null or not(v.pending?'patrols') then return null;end if;
 stamp:=clock_timestamp();point:=v.route_points->(jsonb_array_length(v.route_points)-1);
 patrol:=game_private.scav_patrol_contact(v.pending->'patrols',point,(v.pending->>'started_at')::timestamptz,least(stamp,(v.pending->>'ready_at')::timestamptz));
 if patrol is null then return null;end if;
 if not exists(select 1 from public.game_prison_sentences where season_id=s and player_id=u and released_at is null and release_at>stamp) then
  sentence:=game_private.imprison(u,(v.pending->>'patrol_sentence_minutes')::integer,case when v.pending->>'kind'='car' then 'Caught by a police patrol while lockpicking a parked car.' else 'Caught by a police patrol while searching a street bin.' end);
 else select id into sentence from public.game_prison_sentences where season_id=s and player_id=u;end if;
 insert into game_private.scav_arrests(attempt_id,season_id,player_id,district_id,patrol_id,kind,sentence_id) values((v.pending->>'id')::uuid,s,u,v.district_id,patrol,v.pending->>'kind',sentence) on conflict do nothing;
 update game_private.scav_sessions set pending=null where season_id=s and player_id=u;
 insert into public.game_events(player_id,description) values(u,'Caught by a police patrol while scavenging. Transferred to Blackwater Island Prison.');
 return jsonb_build_object('caught',true,'message','Caught by a police patrol. You have been taken to Blackwater Island Prison.');
end$$;

-- Existing searches retain their original risk rules, including if a request is retried.
update game_private.scav_sessions set pending=pending||jsonb_build_object('patrols','[]'::jsonb,'patrol_sentence_minutes',game_private.setting('scavenging_patrol_sentence_minutes')) where pending is not null;
alter function public.scavenging_action(text,jsonb) set schema game_private;
alter function game_private.scavenging_action(text,jsonb) rename to scav_action_before_patrols;
revoke all on function game_private.scav_action_before_patrols(text,jsonb) from public,anon,authenticated;
create function public.scavenging_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;v game_private.scav_sessions;s uuid;
begin
 perform game_private.require_active();s:=game_private.season_guard(false);
 perform pg_advisory_xact_lock(4704020);perform pg_advisory_xact_lock(4704031);
 result:=game_private.scav_resolve_patrol();if result is not null then return result;end if;
 result:=game_private.scav_action_before_patrols(p_action,p_payload);
 if p_action='search' and not(result?'error') then
  select * into v from game_private.scav_sessions where season_id=s and player_id=auth.uid();
  if v.pending is not null and not(v.pending?'patrols') then
   update game_private.scav_sessions set pending=pending||jsonb_build_object('patrols',game_private.scav_patrols(v.district_id),'patrol_sentence_minutes',game_private.setting('scavenging_patrol_sentence_minutes')) where season_id=s and player_id=auth.uid();
  end if;
  result:=coalesce(game_private.scav_resolve_patrol(),result);
 end if;
 return result;
end$$;
revoke all on function public.scavenging_action(text,jsonb) from public,anon;
grant execute on function public.scavenging_action(text,jsonb) to authenticated;

alter function game_private.bin_state() rename to scav_bin_state_before_patrols;
revoke all on function game_private.scav_bin_state_before_patrols() from public,anon,authenticated;
create function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;caught jsonb;patrols jsonb;
begin
 caught:=game_private.scav_resolve_patrol();result:=game_private.scav_bin_state_before_patrols();
 patrols:=coalesce(result#>'{scavenging,session,pending,patrols}',game_private.scav_patrols((result#>>'{scavenging,session,district_id}')::uuid));
 return jsonb_set(result,'{scavenging}',(result->'scavenging')||jsonb_build_object('patrols',patrols,'caught',coalesce((caught->>'caught')::boolean,false)));
end$$;
revoke all on function game_private.bin_state() from public,anon;
grant execute on function game_private.bin_state() to authenticated;

-- Reconnect/navigation resolves missed contact too, using the normal prison entry point.
create function game_private.scav_patrol_prison_state() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.scav_resolve_patrol();return game_private.prison_state();
end$$;
create or replace function public.prison_state() returns jsonb language sql security invoker set search_path='' as $$select game_private.scav_patrol_prison_state()$$;
revoke all on function game_private.scav_patrol_prison_state() from public,anon;
grant execute on function game_private.scav_patrol_prison_state() to authenticated;
revoke all on function game_private.scav_patrols(uuid),game_private.scav_patrol_contact(jsonb,jsonb,timestamptz,timestamptz),game_private.scav_resolve_patrol() from public,anon,authenticated;
