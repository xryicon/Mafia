begin;
create function pg_temp.check_range(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI shooting range rules and inventory conservation',true);
update public.game_settings set value=100000 where key='inventory_weight_limit_grams';
update public.game_settings set value=0 where key in ('range_move_amplitude','range_move_vertical');
update public.game_settings set value=200 where key='range_fire_interval_ms';
do $$
declare u uuid:=gen_random_uuid();other uuid:=gen_random_uuid();s uuid:=game_private.current_season();v public.game_range_sessions;g uuid;a uuid;q jsonb;res jsonb;again jsonb;hp int;qty int;denied boolean;new_season uuid;
begin
 insert into auth.users(id) values(u),(other);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 update public.game_inventory set quantity=0 where player_id=u;
 insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'homemade-pistol',2),(s,u,'homemade-bullets',3);
 res:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary'));perform pg_temp.check_range(res?'error','Started without equipped weapon');
 res:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-pistol','equipment_slot','secondary'));perform pg_temp.check_range(not res?'error','Weapon equip failed');
 res:=public.range_action('start',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary'));perform pg_temp.check_range(res?'error','Started without equipped bullets');
 res:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','good:homemade-bullets','equipment_slot','ammo','quantity',3));perform pg_temp.check_range(not res?'error','Ammo equip failed');
 select id into g from public.game_inventory_gear where player_id=u and equipment_slot='secondary';select id into a from public.game_inventory_gear where player_id=u and equipment_slot='ammo';
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'equipment_slot','secondary');res:=public.range_action('start',q);perform pg_temp.check_range(not res?'error','Session failed: '||res::text);
 again:=public.range_action('start',q);perform pg_temp.check_range(again->>'session_id'=res->>'session_id' and (select count(*) from public.game_range_sessions where player_id=u)=1,'Start retry created another session');
 select * into v from public.game_range_sessions where player_id=u;
 res:=public.range_action('start',q||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.check_range(res?'error','Started overlapping session');
 -- Client score/hit fields are ignored; a valid bullseye is calculated server-side.
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id,'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int,'x',20,'y',45,'score',999999,'hit',false);
 res:=public.range_action('fire',q);perform pg_temp.check_range(not res?'error' and (res->>'points')::int=game_private.setting('range_bullseye_points'),'Valid bullseye failed: '||res::text);
 -- Exercise the real JSON response, not only the score/result fields.
 perform pg_temp.check_range(jsonb_typeof(res#>'{state,session,last_shot}')='object','last_shot must be a complete object, not the x coordinate');
 perform pg_temp.check_range(
  res#>'{state,session,last_shot}'=(select jsonb_build_object('id',shot_row.id,'hit',shot_row.hit,'points',shot_row.points,'round',shot_row.round,'lane',shot_row.lane,'x',shot_row.x,'y',shot_row.y,'elapsed_ms',shot_row.elapsed_ms,'created_at',shot_row.created_at) from public.game_range_shots shot_row where shot_row.session_id=v.id),
  'Rendered shot fields differ from the accepted database record');
 perform pg_temp.check_range((res#>>'{state,session,last_shot,elapsed_ms}')::int=(q->>'elapsed_ms')::int and res#>'{state,session,last_shot,x}'='20'::jsonb and res#>'{state,session,last_shot,y}'='45'::jsonb,'Impact coordinates or timestamp missing from RPC');
 again:=public.range_action('fire',q);perform pg_temp.check_range(again->>'points'=res->>'points' and (select count(*) from public.game_range_shots where session_id=v.id)=1,'Shot retry duplicated a shot');
 perform pg_temp.check_range((select condition from public.game_inventory_gear where id=g)=99 and (select quantity from public.game_inventory_gear where id=a)=2,'Shot did not consume exactly one bullet and one condition');
 res:=public.range_action('fire',q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',999999));perform pg_temp.check_range(res?'error','Future shot accepted');
 res:=public.range_action('fire',q||jsonb_build_object('x',50));perform pg_temp.check_range(res?'error','Same reference accepted changed coordinates');
 res:=public.range_action('fire',q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int+1));perform pg_temp.check_range(res?'error','Shot cooldown was ignored');
 perform pg_sleep(.22);
 q:=q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int,'x',0,'y',0,'hit',true);
 res:=public.range_action('fire',q);perform pg_temp.check_range(not res?'error' and not (res->>'hit')::boolean and (res->>'points')::int=0,'Client claimed an off-target hit');
 perform pg_temp.check_range(jsonb_typeof(res#>'{state,session,last_shot}')='object' and res#>'{state,session,last_shot,lane}'='null'::jsonb and res#>'{state,session,last_shot,hit}'='false'::jsonb and res#>'{state,session,last_shot,x}'='0'::jsonb,'Miss details are not a real shot object');
 perform pg_temp.check_range((select condition from public.game_inventory_gear where id=g)=98 and (select quantity from public.game_inventory_gear where id=a)=1,'A miss did not consume ammunition and wear');
 -- Changing equipment mid-session cannot fire the old weapon or refund its wear.
 res:=public.inventory_action('unequip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','gear:'||g));perform pg_temp.check_range(not res?'error','Worn weapon unequip failed');
 perform pg_temp.check_range(jsonb_typeof(res#>'{state,session,last_shot}')='object' and res#>'{state,session,last_shot,lane}'='null'::jsonb and res#>'{state,session,last_shot,hit}'='false'::jsonb and res#>'{state,session,last_shot,x}'='0'::jsonb,'Miss details are not a real shot object');
 perform pg_temp.check_range((select condition from public.game_inventory_gear where id=g)=98 and (select location from public.game_inventory_gear where id=g)='carried','Worn weapon was reset or restacked');
 perform pg_sleep(.22);
 q:=q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int);
 res:=public.range_action('fire',q);perform pg_temp.check_range(res?'error' and (select quantity from public.game_inventory_gear where id=a)=1,'Fired an unequipped weapon');
 res:=public.inventory_action('equip',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'item_key','gear:'||g,'equipment_slot','secondary'));perform pg_temp.check_range(not res?'error','Worn weapon re-equip failed');
 res:=public.range_action('reload',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id));perform pg_temp.check_range(not res?'error','Reload after re-equipping failed');perform pg_sleep(1.85);
 update public.game_inventory_gear set condition=1 where id=g;
 q:=q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int,'x',20,'y',45);
 res:=public.range_action('fire',q);perform pg_temp.check_range(not res?'error' and (res->>'points')::int=0,'An already scored target paid points again');
 perform pg_temp.check_range((select condition from public.game_inventory_gear where id=g)=0 and (select quantity=0 and location='retired' from public.game_inventory_gear where id=a),'Final shot did not break weapon and empty Ammo');
 perform pg_sleep(.22);q:=q||jsonb_build_object('request_id',gen_random_uuid(),'elapsed_ms',floor(extract(epoch from(clock_timestamp()-v.started_at))*1000)::int);
 res:=public.range_action('fire',q);perform pg_temp.check_range(res?'error' and (select count(*) from public.game_range_shots where session_id=v.id)=3,'Broken/empty weapon fired');
 perform pg_temp.check_range((select sum(delta) from public.game_inventory_ledger where gear_id=a)=0,'Ammunition ledger does not balance after exhaustion');
 res:=public.range_action('finish',jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'session_id',v.id));perform pg_temp.check_range(not res?'error','Finish failed');
 res:=public.range_state();perform pg_temp.check_range((res->'stats'->>'shots')::int=3 and (res->'stats'->>'hits')::int=1 and (res->'stats'->>'sessions')::int=1,'Range stats are not real session totals');
 perform pg_temp.check_range(jsonb_typeof(res#>'{session,last_shot}')='object' and (res#>>'{session,last_shot,elapsed_ms}')::int>=0,'Refresh lost the full shot response');
 -- Foreign sessions and direct writes are forbidden; shot history is immutable.
 perform set_config('request.jwt.claim.sub',other::text,true);perform public.game_state();
 res:=public.range_action('fire',q||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.check_range(res?'error','Another player fired a foreign session');
 set local role authenticated;denied:=false;begin update public.game_range_sessions set score=999999;exception when insufficient_privilege then denied:=true;end;reset role;perform pg_temp.check_range(denied,'Direct score editing allowed');
 denied:=false;begin perform public.range_manage('settings','{"settings":{"range_hit_points":999},"reason":"Unauthorized score edit"}');exception when raise_exception then denied:=true;end;perform pg_temp.check_range(denied,'Player edited range settings');
 denied:=false;begin delete from public.game_range_shots where session_id=v.id;exception when raise_exception then denied:=true;end;perform pg_temp.check_range(denied,'Shot evidence deleted');
 perform pg_temp.check_range(not has_function_privilege('anon','public.range_action(text,jsonb)','execute') and not has_function_privilege('authenticated','game_private.range_target(integer,integer,integer,integer,jsonb)','execute'),'Internal range API exposed');
 -- Owner changes are audited and use optimistic versions for weapon rules.
 update public.game_user_roles set role_id='owner' where player_id=other;
 res:=public.range_manage('weapon','{"good_id":"homemade-pistol","ammo_good_id":"homemade-bullets","condition_max":100,"wear_per_shot":2,"enabled":true,"version":1,"reason":"CI double practice wear"}');perform pg_temp.check_range(not res?'error' and (select wear_per_shot from public.game_range_weapons where good_id='homemade-pistol')=2,'Owner cannot configure wear');
 perform pg_temp.check_range((v.weapon_rule->>'wear_per_shot')::int=1,'Existing session lost original wear rules');
 perform pg_temp.check_range(exists(select 1 from public.game_audit where actor_id=other and reason like 'Shooting range controls:%'),'Owner change missing audit');
 perform set_config('request.jwt.claim.sub',u::text,true);
 -- Old-season records remain retained but do not appear in a fresh season's stats.
 insert into public.game_seasons(name,status,starting_cash,starting_crates) values('Range next season','draft',10000,5) returning id into new_season;
 if new_season is not null then update game_private.season_runtime set season_id=new_season where singleton;res:=public.range_state();perform pg_temp.check_range((res->'stats'->>'sessions')::int=0,'Range statistics leaked between seasons');end if;
end$$;
-- Movement changes the target coordinates without client-authored scores.
select pg_temp.check_range(game_private.range_target(1,0,0,0,game_private.range_config()||'{"move_amplitude":10,"move_vertical":8}')<>game_private.range_target(1,0,0,500,game_private.range_config()||'{"move_amplitude":10,"move_vertical":8}'),'Targets do not move');
select 'PASS: range equipment, bullet conservation, wear, timing, replay safety, scores, privacy, permissions and season isolation';
rollback;
