begin;
create function pg_temp.precision_check(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI score XP and saved bullseye precision',true);
update public.game_settings set value=0 where key in ('range_move_amplitude','range_move_vertical');
update public.game_settings set value=1 where key='range_rounds';
update public.game_settings set value=2 where key='range_round_seconds';
update public.game_settings set value=200 where key='range_fire_interval_ms';
do $$
declare u uuid:=gen_random_uuid();s uuid:=game_private.current_season();v public.game_range_sessions;r jsonb;q jsonb;c jsonb;elapsed int;i int;denied boolean;
begin
 c:=game_private.range_mode_config('advanced');
 perform pg_temp.precision_check(game_private.range_score_xp(0,c)=0 and game_private.range_score_xp(100,c)=50 and game_private.range_score_xp(200,c)=100 and game_private.range_score_xp(150,c)=75 and game_private.range_score_xp(300,c)=150 and game_private.range_score_xp(999999,c)=150,'Score XP must be proportional and capped');
 perform pg_temp.precision_check(game_private.range_score_xp(175,c)=87 and game_private.range_score_xp(-1,c)=0,'Fractional XP must round down and negative scores yield zero');
 perform pg_temp.precision_check(game_private.range_score_xp(0,c-'xp_version')=150,'Existing active reward snapshots changed');
 perform pg_temp.precision_check(game_private.range_shot_accuracy(1,0,0,50,45,c)=100 and game_private.range_shot_accuracy(1,0,0,50+(c->>'radius_x')::numeric*.3,45+(c->>'radius_y')::numeric*.4,c)=50 and game_private.range_shot_accuracy(1,0,0,0,0,c)=0,'Radial precision is not based on normalized bullseye distance');
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-pistol',1),(s,u,'homemade-bullets',20);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-pistol','equipment_slot','secondary'));perform pg_temp.precision_check(not r?'error','Equip pistol: '||r::text);
 r:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',20));perform pg_temp.precision_check(not r?'error','Equip ammo: '||r::text);
 r:=public.range_state();perform pg_temp.precision_check(r#>'{advanced_stats,average_accuracy}'='null'::jsonb,'No-shot accuracy must be unknown, not a fabricated percentage');
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','advanced'));perform pg_temp.precision_check(not r?'error','Start: '||r::text);
 select * into v from public.game_range_sessions where player_id=u and status='active';
 -- Centre, halfway out, miss, then a repeated centre hit on an already-scored target.
 for i in 0..3 loop
  elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
  q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',case i when 0 then 20 when 1 then 50+(v.config->>'radius_x')::numeric*.5 when 2 then 0 else 20 end,'y',case when i=2 then 0 else 45 end,'accuracy_percent',100000,'score',100000);
  r:=public.range_action('fire',q);perform pg_temp.precision_check(not r?'error','Fire: '||r::text);
  perform pg_temp.precision_check((r#>>'{state,session,last_shot,accuracy_percent}')::numeric=case when i=1 then 50 when i=2 then 0 else 100 end,'Wrong persisted shot precision: '||r::text);
  if i=3 then perform pg_temp.precision_check((r->>'points')::int=0,'Repeated bullseye scored again');end if;
  perform public.range_action('fire',q);perform pg_sleep(.22);
 end loop;
 perform pg_temp.precision_check((r#>>'{state,session,accuracy_percent}')::numeric=62.5 and (r#>>'{state,session,score_xp}')::int=87 and (r#>>'{state,session,score}')::int=175,'Live average or XP quote incorrect');
 perform pg_temp.precision_check((select count(*) from game_private.range_shot_precision where session_id=v.id)=4,'Retry duplicated saved precision');
 perform pg_sleep(greatest(0,2.03-extract(epoch from(clock_timestamp()-v.started_at))));
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'xp_awarded',999999);r:=public.range_action('finish',q);
 perform pg_temp.precision_check((r#>>'{state,session,xp_awarded}')::int=87 and (r#>>'{state,advanced_stats,average_accuracy}')::numeric=62.5,'Completed XP or saved Advanced mean incorrect');
 perform public.range_action('finish',q);r:=public.range_state();
 perform pg_temp.precision_check((select xp from public.game_players where id=u)=87 and (select sum(delta) from game_private.range_xp_ledger where player_id=u)=87 and (r#>>'{advanced_stats,shots}')::int=4,'Rewards or precision duplicated on refresh');
 -- An early exit still contributes its shot precision, but grants no XP.
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where player_id=u;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','advanced'));perform pg_temp.precision_check(not r?'error','Second start: '||r::text);
 select * into v from public.game_range_sessions where player_id=u and status='active';elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',50,'y',45));perform pg_temp.precision_check(not r?'error','Second shot: '||r::text);
 r:=public.range_action('finish',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id));
 perform pg_temp.precision_check((r#>>'{state,session,xp_awarded}')::int=0 and (r#>>'{state,advanced_stats,average_accuracy}')::numeric=70 and (r#>>'{state,advanced_stats,shots}')::int=5,'Early exit was discarded or session averages were averaged without shot weighting');
 -- Firing only misses satisfies participation but cannot generate XP or a zero-value ledger row.
 update public.game_range_sessions set cooldown_until=clock_timestamp()-interval '1 second' where player_id=u;
 r:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary','difficulty','advanced'));perform pg_temp.precision_check(not r?'error','Miss-only start: '||r::text);
 select * into v from public.game_range_sessions where player_id=u and status='active';elapsed:=floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int;
 r:=public.range_action('fire',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',elapsed,'x',0,'y',0));perform pg_temp.precision_check(not r?'error','Miss-only shot: '||r::text);perform pg_sleep(3.05);r:=public.range_state();
 perform pg_temp.precision_check(r#>>'{session,status}'='finished' and (r#>>'{session,xp_awarded}')::int=0 and (r#>>'{advanced_stats,average_accuracy}')::numeric=58.33,'Zero-score expiry or precision average failed');
 perform pg_temp.precision_check((select count(*) from game_private.range_xp_ledger where player_id=u)=1,'Misses generated an XP ledger award');
 perform pg_temp.precision_check((r#>>'{recent,0,accuracy_percent}')::numeric=0 and (r#>>'{stats,best_accuracy}')::numeric=100,'History or best accuracy still uses binary hit rate');
 denied:=false;begin update game_private.range_shot_precision set accuracy_percent=100 where session_id=v.id;exception when raise_exception then denied:=true;end;perform pg_temp.precision_check(denied,'Shot precision history is mutable');
 perform pg_temp.precision_check(not has_table_privilege('authenticated','game_private.range_shot_precision','select') and not has_function_privilege('authenticated','game_private.range_session_accuracy(uuid)','execute'),'Private accuracy internals exposed');
end$$;
select 'PASS: score-proportional XP, radial precision, replay-safe saved averages, early exits, misses, HUD source data';
rollback;
