-- Power displays the existing respect score. Rank honors Owner-configured thresholds.
create or replace function game_private.city_status() returns jsonb language plpgsql security definer set search_path='' as $$
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
 'player',jsonb_build_object('cash',player.cash,'xp',player.xp,'power',player.xp,
 'rank',case when player.xp>=game_private.setting('rank_underboss') then 'Underboss'
 when player.xp>=game_private.setting('rank_caporegime') then 'Caporegime'
 when player.xp>=game_private.setting('rank_soldier') then 'Soldier' else 'Associate' end,'level',coalesce((select level from public.game_season_players where player_id=auth.uid() and season_id=player.season_id),1)),
 'online_count',(select count(*) from game_private.online_players()),
 'window_seconds',game_private.setting('presence_window_seconds'),
 'poll_seconds',least(game_private.setting('city_poll_seconds'),game_private.setting('presence_window_seconds')/2),
 'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=game_private.current_season()),
 'permissions',(select coalesce(jsonb_agg(id),'[]'::jsonb) from public.game_permissions where game_private.has_permission(id)),
 'events',(select coalesce(jsonb_agg(e order by e.created_at desc),'[]'::jsonb) from
 (select id,description,cash_delta,created_at from public.game_events where player_id=auth.uid() and season_id=player.season_id order by created_at desc,id limit 8) e),
 'server_time',clock_timestamp());
end $$;

