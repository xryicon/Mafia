-- Permanent descriptions; gameplay and ranking data stay authoritative and seasonal.
select set_config('game.reason','Introduce Blackwater player profiles',true);
insert into public.game_settings(key,value,minimum,maximum) values('profile_description_limit',300,50,1000);
alter table game_private.identities add column description text not null default '' check(length(description)<=1000);
alter table game_private.identities add column description_version integer not null default 1;
create function game_private.profile_description(p_description text,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare body text:=btrim(replace(coalesce(p_description,''),E'\r\n',E'\n'));v integer;
begin
 perform game_private.require_active();
 if not game_private.rate('profile_description',10) then return jsonb_build_object('error','Wait a moment before editing your description again.');end if;
 if length(body)>game_private.setting('profile_description_limit') then return jsonb_build_object('error','Your description is too long.');end if;
 if body ~ E'[\x01-\x08\x0B\x0C\x0E-\x1F\x7F]' then return jsonb_build_object('error','Use plain text for your description.');end if;
 select description_version into v from game_private.identities where player_id=auth.uid() for update;
 if v is null then raise exception 'Profile not found.';end if;
 if v is distinct from p_version then return jsonb_build_object('error','Your description changed in another tab. Reopen the editor and try again.','conflict',true);end if;
 perform set_config('game.reason','Player updated their profile description',true);
 update game_private.identities set description=body,description_version=description_version+1 where player_id=auth.uid() returning description_version into v;
 return jsonb_build_object('message','Profile description saved.','description',body,'description_version',v);
end$$;
create function public.profile_description(p_description text,p_version integer) returns jsonb language sql security invoker set search_path='' as $$select game_private.profile_description(p_description,p_version)$$;

create function game_private.player_profile(p_player uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;identity game_private.identities;sp public.game_season_players;base jsonb;businesses jsonb;total integer;
begin
 perform game_private.require_active();
 if not game_private.rate('player_profile',60) then raise exception 'Too many profile requests. Try again in a minute.';end if;
 s:=game_private.season_guard(false);
 if not game_private.visible_player(p_player) then return null;end if;
 select * into strict identity from game_private.identities where player_id=p_player;
 select * into sp from public.game_season_players where player_id=p_player and season_id=s;
 base:=game_private.season_profile(p_player);
 with holdings as (
  select 'district:'||b.id::text as id,b.name,b.business_type as kind,
   case when p.status='locked' or d.status='lockdown' or exists(select 1 from public.game_district_territory t where t.season_id=s and t.district_id=d.id and t.status='lockdown') then 'closed' else b.status end as status,
   d.name as district,d.slug as district_slug,p.id as plot_id,p.code as plot_code,d.image_url,'/districts/'||d.slug||'?registry=1&tab=Businesses&plot='||p.id::text as href
  from public.game_district_businesses b join public.game_district_plots p on p.id=b.plot_id join public.game_districts d on d.id=b.district_id
  where b.season_id=s and b.owner_type='player' and b.owner_id=p_player and b.archived_at is null and p.archived_at is null and d.archived_at is null
  union all
  select 'production:'||b.good_id,g.business_name,'production','open',null,null,null,null,'/art/harbor.webp','/market?good='||g.id
  from public.game_businesses b join public.game_goods g on g.id=b.good_id where b.season_id=s and b.player_id=p_player
 )
 select (select count(*) from holdings),(select coalesce(jsonb_agg(x order by x.name),'[]') from (select * from holdings order by name,id limit 60) x) into total,businesses;
 return jsonb_build_object(
 'player_id',p_player,'handle',identity.username,'is_self',p_player=auth.uid(),
 'avatar_url',game_private.player_avatar(p_player),'description',identity.description,
 'description_version',case when p_player=auth.uid() then identity.description_version end,
 'description_limit',game_private.setting('profile_description_limit'),
 'joined_at',(select created_at from public.game_players where id=p_player),'online',exists(select 1 from game_private.online_players() o where o.player_id=p_player),
 'role',coalesce((select role_id from public.game_user_roles where player_id=p_player),'player'),
 'respect',coalesce(sp.xp,0),'level',coalesce(sp.level,1),
 'title',case when coalesce(sp.xp,0)>=game_private.setting('rank_underboss') then 'Underboss' when coalesce(sp.xp,0)>=game_private.setting('rank_caporegime') then 'Caporegime' when coalesce(sp.xp,0)>=game_private.setting('rank_soldier') then 'Soldier' else 'Associate' end,
 'respect_rank',(select rank from (select player_id,rank() over(order by xp desc) as rank from public.game_season_players where season_id=s and game_private.visible_player(player_id)) ranks where player_id=p_player),
 'gang',(select jsonb_build_object('id',g.id,'name',g.name) from public.game_season_gang_members m join public.game_season_gangs g on g.id=m.gang_id and g.season_id=m.season_id where m.season_id=s and m.player_id=p_player),
 'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),
 'current',base->'current','previous',base->'previous',
 'businesses',businesses,'business_total',total,
 'plot_count',(select count(*) from public.game_district_plots p join public.game_districts d on d.id=p.district_id where p.season_id=s and p.owner_type='player' and p.owner_id=p_player and p.archived_at is null and d.archived_at is null),
 'districts',(select coalesce(jsonb_agg(x order by x.name),'[]') from (select distinct d.id,d.name,d.slug from public.game_district_plots p join public.game_districts d on d.id=p.district_id where p.season_id=s and p.owner_type='player' and p.owner_id=p_player and p.archived_at is null and d.archived_at is null) x),
 'server_time',clock_timestamp()
 );
end$$;
create function public.player_profile(p_player uuid) returns jsonb language sql security invoker set search_path='' as $$select game_private.player_profile(p_player)$$;
revoke all on function game_private.profile_description(text,integer),public.profile_description(text,integer),game_private.player_profile(uuid),public.player_profile(uuid) from public,anon,authenticated;
grant execute on function game_private.profile_description(text,integer),public.profile_description(text,integer),game_private.player_profile(uuid),public.player_profile(uuid) to authenticated;
-- The player list uses exactly the same portrait as profiles and Telegrams.
do $$declare definition text;begin
 select pg_get_functiondef('public.player_directory(text,boolean,integer)'::regprocedure) into definition;
 if position('p.id,p.handle as username,sp.xp as respect' in definition)=0 then raise exception 'Review directory portrait integration';end if;
 execute replace(definition,'p.id,p.handle as username,sp.xp as respect','p.id,p.handle as username,game_private.player_avatar(p.id) as avatar_url,sp.xp as respect');
end$$;
notify pgrst,'reload schema';
