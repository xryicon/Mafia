begin;
create function pg_temp.range_check(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI range difficulty, radial scoring and completion XP',true);
update public.game_settings set value=0 where key in ('range_move_amplitude','range_move_vertical');
update public.game_settings set value=2 where key in ('range_rounds','range_round_seconds');
update public.game_settings set value=200 where key='range_fire_interval_ms';

do $$
declare u uuid:=gen_random_uuid();s uuid:=game_private.current_season();v public.game_range_sessions;q jsonb;r jsonb;points int[]:='{}';i int;elapsed int;xp_before bigint;denied boolean;old_season uuid;
begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 select xp into xp_before from public.game_players where id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-pistol',1),(s,u,'homemade-bullets',30);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-pistol','equipment_slot','secondary'));perform pg_temp.range_check(not r?'error','Equip pistol: '||r);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',30));perform pg_temp.range_check(not r?'error','Equip ammo: '||r);
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','impossible','completion_xp',999999,'config','{"cooldown_seconds":0}');
 r:=public.range_action('start',q);perform pg_temp.range_check(r?'error','Invalid difficulty accepted');
 q:=q||jsonb_build_object('request_id',gen_random_uuid(),'difficulty','beginner');r:=public.range_action('start',q);perform pg_temp.range_check(not r?'error','Beginner start: '||r);
 select * into v from public.game_range_sessions where player_id=u;
 perform pg_temp.range_check(v.difficulty='beginner' and (v.config->>'completion_xp')::int=50 and (v.config->>'cooldown_seconds')::int=600,'Client forged session rules');
 perform pg_temp.range_check(jsonb_array_length(r#>'{state,difficulties}')=2 and (r#>>'{state,difficulties,1,config,radius_x}')::numeric<(v.config->>'radius_x')::numeric and (r#>>'{state,difficulties,1,config,move_speed}')::numeric=(v.config->>'move_speed')::numeric*2.5,'Advanced is not smaller and 2.5x faster');
 -- Three separate target hits at outer, middle and centre positions use the real action.
 for i in 0..2 loop
  elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
  r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',20+30*i+case i when 0 then 3.6 when 1 then 2 else 0 end,'y',45,'points',999999));
  perform pg_temp.range_check(not r?'error','Scoring shot: '||r);points:=array_append(points,(r->>'points')::int);perform pg_sleep(.22);
 end loop;
 perform pg_temp.range_check(points=array[55,75,100],'Closer shots must earn 55, 75, 100: '||points::text);
 perform pg_sleep(greatest(0,2.02-extract(epoch from(clock_timestamp()-v.started_at))));
 elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',50,'y',45));perform pg_temp.range_check(not r?'error','Second-round shot: '||r);
 perform pg_temp.range_check((r#>>'{state,session,participated_rounds}')::int=2 and (select xp from public.game_players where id=u)=xp_before,'XP awarded before completion or participation missing');
 perform pg_sleep(greatest(0,4.03-extract(epoch from(clock_timestamp()-v.started_at))));
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'xp',999999);r:=public.range_action('finish',q);
 perform pg_temp.range_check(not r?'error' and (r#>>'{state,session,xp_awarded}')::int=50,'Beginner completion XP: '||r);
 perform pg_temp.range_check((select xp from public.game_players where id=u)=xp_before+50 and (select xp from public.game_season_players where player_id=u and season_id=s)=xp_before+50,'XP not synchronized to seasonal respect');
 perform public.range_action('finish',q);perform public.range_action('finish',q||jsonb_build_object('request_id',gen_random_uuid()));perform public.range_state();
 perform pg_temp.range_check((select count(*) from game_private.range_xp_ledger where session_id=v.id)=1 and (select xp from public.game_players where id=u)=xp_before+50,'Duplicate completion paid XP again');
 perform pg_temp.range_check((select cooldown_until=ends_at+interval '10 minutes' from public.game_range_sessions where id=v.id),'Cooldown is not ten minutes after completion');
 for i in 0..1 loop
  r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty',case when i=0 then 'beginner' else 'advanced' end,'cooldown_until','2000-01-01'));
  perform pg_temp.range_check(r->>'error' like '%cooldown%','Mode switching bypassed recovery');
 end loop;
 -- Advance only the test recovery clock, then exercise Advanced expiry via real state RPC.
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where id=v.id;
 update public.game_settings set value=1 where key='range_rounds';
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','advanced'));perform pg_temp.range_check(not r?'error','Advanced start: '||r);
 select * into v from public.game_range_sessions where player_id=u and status='active';
 elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',50,'y',45));perform pg_temp.range_check(not r?'error','Advanced fire: '||r);
 -- Active session reward remains snapshotted even when Owner edits later.
 update public.game_settings set value=200 where key='range_advanced_completion_xp';
 perform pg_sleep(3.05);r:=public.range_state();
 perform pg_temp.range_check((r#>>'{session,xp_awarded}')::int=150 and (r#>>'{stats,xp_earned}')::int=200,'Expired session did not settle original Advanced reward');
 -- Early exit and an idle full session both yield zero XP, with the same recovery.
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where player_id=u;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','beginner'));perform pg_temp.range_check(not r?'error','Early session start: '||r);
 select * into v from public.game_range_sessions where player_id=u and status='active';
 r:=public.range_action('finish',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id));
 perform pg_temp.range_check((r#>>'{session,xp_awarded}') is null and (r#>>'{state,session,xp_awarded}')::int=0 and r#>>'{state,session,status}'='stopped','Early exit paid XP');
 perform pg_temp.range_check((select cooldown_until=finished_at+interval '10 minutes' from public.game_range_sessions where id=v.id),'Early exit bypassed recovery');
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where player_id=u;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary'));perform pg_temp.range_check(not r?'error','Idle start: '||r);
 perform pg_sleep(3.05);r:=public.range_state();perform pg_temp.range_check((r#>>'{session,xp_awarded}')::int=0,'Idle session generated XP');
 -- Locking the season settles eligible attempts before final rankings freeze.
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where player_id=u;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','beginner'));perform pg_temp.range_check(not r?'error','Season boundary start: '||r);
 select * into v from public.game_range_sessions where player_id=u and status='active';elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',50,'y',45));perform pg_temp.range_check(not r?'error','Season boundary shot: '||r);perform pg_sleep(2.05);
 update public.game_seasons set status='locked' where id=s;
 perform pg_temp.range_check((select xp_awarded=50 and status='finished' from public.game_range_sessions where id=v.id),'Season lock lost completed XP');
 perform pg_temp.range_check((select xp from public.game_season_players where season_id=s and player_id=u)=xp_before+250,'Season totals do not include final range XP');
 perform pg_temp.range_check(not has_table_privilege('authenticated','game_private.range_xp_ledger','select') and not has_function_privilege('authenticated','game_private.range_mode_config(text)','execute'),'Private reward internals exposed');
 denied:=false;begin update game_private.range_xp_ledger set delta=1 where player_id=u;exception when raise_exception then denied:=true;end;perform pg_temp.range_check(denied,'XP ledger mutable');
 perform pg_temp.range_check((select sum(delta)=250 and bool_and(l.xp_after=l.xp_before+l.delta) from game_private.range_xp_ledger l where player_id=u),'XP ledger cannot reconcile');
 -- New season has no old cooldown or range XP while historical rewards remain.
 insert into public.game_seasons(name,status,starting_cash,starting_crates) values('Range difficulty next season','draft',10000,5) returning id into old_season;
 update game_private.season_runtime set season_id=old_season where singleton;
 r:=public.range_state();perform pg_temp.range_check(r->'cooldown_until'='null'::jsonb and (r#>>'{stats,xp_earned}')::int=0,'Cooldown or XP leaked into next season');
end$$;
select 'PASS: gradual scores, difficulty snapshots, actual XP ledger, shared cooldown, no idle/early rewards, season boundary';
rollback;
