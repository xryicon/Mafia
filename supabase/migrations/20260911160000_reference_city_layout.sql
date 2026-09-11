-- Compact header data for the full-width game. Chat is not part of this response.
insert into public.game_settings(key,value,minimum,maximum) values('city_poll_seconds',30,15,120);

create function game_private.city_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare session uuid:=nullif(auth.jwt()->>'session_id','')::uuid; identity game_private.identities; player public.game_players;
begin
 perform game_private.require_active();
 if not game_private.rate('city_read',90) then raise exception 'Too many requests. Wait a minute.'; end if;
 if session is null or not exists(select 1 from auth.sessions s where s.id=session and s.user_id=auth.uid())
 then raise exception 'Sign in again to reconnect to the city.'; end if;
 if not exists(select 1 from public.game_players where id=auth.uid()) then perform game_private.state(); end if;
 select * into strict identity from game_private.identities where player_id=auth.uid();
 select * into strict player from public.game_players where id=auth.uid();
 insert into game_private.player_presence as p(player_id,session_id,last_seen_at) values(auth.uid(),session,clock_timestamp())
 on conflict(player_id,session_id) do update set last_seen_at=excluded.last_seen_at
 where p.last_seen_at<clock_timestamp()-interval '20 seconds';
 return jsonb_build_object(
 'player_id',auth.uid(),'username',identity.username,'username_claimed',identity.claimed,
 'player',jsonb_build_object('cash',player.cash,'xp',player.xp,'level',coalesce((select level from public.game_season_players where player_id=auth.uid() and season_id=player.season_id),1)),
 'online_count',(select count(*) from game_private.online_players()),
 'window_seconds',game_private.setting('presence_window_seconds'),
 'poll_seconds',least(game_private.setting('city_poll_seconds'),game_private.setting('presence_window_seconds')/2),
 'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=game_private.current_season()),
 'permissions',(select coalesce(jsonb_agg(id),'[]'::jsonb) from public.game_permissions where game_private.has_permission(id)),
 'events',(select coalesce(jsonb_agg(e order by e.created_at desc),'[]'::jsonb) from
 (select id,description,cash_delta,created_at from public.game_events where player_id=auth.uid() and season_id=player.season_id order by created_at desc,id limit 8) e),
 'server_time',clock_timestamp());
end $$;

-- Read the actual seasonal gang register without exposing private gang metadata.
create function game_private.gang_directory() returns jsonb language plpgsql security definer set search_path='' as $$
declare season uuid; result jsonb;
begin
 perform game_private.require_active();season:=game_private.season_guard(false);
 if not game_private.rate('gang_read',60) then raise exception 'Too many requests. Wait a minute.'; end if;
 with standings as (
 select g.id,g.name,count(m.player_id) as members,coalesce(sum(p.xp),0) as respect,
 coalesce(sum(m.contribution),0) as contribution,
 bool_or(m.player_id=auth.uid()) as joined
 from public.game_season_gangs g
 left join public.game_season_gang_members m on m.gang_id=g.id and m.season_id=g.season_id and game_private.visible_player(m.player_id)
 left join public.game_season_players p on p.player_id=m.player_id and p.season_id=g.season_id
 where g.season_id=season group by g.id,g.name
 ), ranked as (select *,rank() over(order by respect desc) as rank from standings)
 select jsonb_build_object(
 'gangs',(select coalesce(jsonb_agg(g order by g.rank,g.id),'[]'::jsonb) from (select * from ranked order by rank,id limit 100) g),
 'total',(select count(*) from standings),
 'season',(select jsonb_build_object('id',s.id,'name',s.name,'status',s.status) from public.game_seasons s where s.id=season),
 'server_time',clock_timestamp()) into result;
 return result;
end $$;
create function public.city_status() returns jsonb language sql security invoker set search_path='' as $$ select game_private.city_status() $$;
create function public.gang_directory() returns jsonb language sql security invoker set search_path='' as $$ select game_private.gang_directory() $$;
revoke all on function public.city_status(),public.gang_directory(),game_private.city_status(),game_private.gang_directory() from public,anon,authenticated;
grant execute on function public.city_status(),public.gang_directory(),game_private.city_status(),game_private.gang_directory() to authenticated;
