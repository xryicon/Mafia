begin;
create function pg_temp.check_patrol(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
do $$
declare u uuid:=gen_random_uuid();s uuid:=game_private.current_season();d uuid;v jsonb;q jsonb;r jsonb;target jsonb;patrols jsonb;point jsonb;attempt uuid;sentence uuid;cash_before bigint;count_before bigint;t timestamptz:=clock_timestamp();denied boolean;
begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 select id into d from public.game_districts where slug='the-waterfront';
 perform set_config('game.reason','CI police patrol tests',true);
 update public.game_settings set value=2 where key='scavenging_patrol_count';
 update public.game_settings set value=0 where key='scavenging_event_chance';
 patrols:=jsonb_build_array(jsonb_build_object('id','test-patrol','route_points','[[0,0],[4,0],[0,0]]'::jsonb,'epoch',extract(epoch from t),'seconds_per_block',1,'radius',0.2));
 perform pg_temp.check_patrol(game_private.scav_patrol_contact(patrols,'[2,0]',t,t+interval '4 seconds')='test-patrol','Patrol crossing between polls was missed');
 perform pg_temp.check_patrol(game_private.scav_patrol_contact(patrols,'[2,1]',t,t+interval '20 seconds') is null,'Patrol caught an out-of-range player');
 perform pg_temp.check_patrol(game_private.scav_patrol_contact(patrols,'[0,0]',t+interval '7 seconds',t+interval '9 seconds')='test-patrol','Loop boundary detection failed');
 perform pg_temp.check_patrol(game_private.scav_patrol_contact(patrols,'[2,0]',t,t+interval '1 second') is null,'A future patrol contact caused an early arrest');
 update public.game_settings set value=0 where key='scavenging_patrol_enabled';
 q:=jsonb_build_object('season_id',s,'district_id',d,'request_id',gen_random_uuid());r:=public.scavenging_action('enter',q);
 perform pg_temp.check_patrol(not r?'error','Cannot enter patrol test district');
 update public.game_settings set value=1 where key='scavenging_patrol_enabled';
 r:=public.bin_diving_state();perform pg_temp.check_patrol(jsonb_array_length(r#>'{scavenging,patrols}')=2,'Visible patrol descriptors are missing');
 perform pg_temp.check_patrol(not (public.prison_state()->>'jailed')::boolean,'Idle player arrested');
 update public.game_settings set value=0 where key='scavenging_patrol_enabled';
 foreach v in array array['"bin"'::jsonb,'"car"'::jsonb] loop
  select x into target from jsonb_array_elements(public.bin_diving_state()#>'{scavenging,targets}')x where x->'kind'=v limit 1;
  point:=jsonb_build_array((target->>'node')::int%5,(target->>'node')::int/5);
  r:=public.scavenging_action('move',q||jsonb_build_object('request_id',gen_random_uuid(),'node',(target->>'node')::int));perform pg_temp.check_patrol(not r?'error','Walking failed');
  update game_private.scav_sessions set arrives_at=clock_timestamp()-interval '1 second' where player_id=u;
  if v='"car"'::jsonb then insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,u,'lockpick',1) on conflict(season_id,player_id,good_id) do update set quantity=1;end if;
  select cash into cash_before from public.game_players where id=u;select count(*) into count_before from public.game_bin_dives where player_id=u;
  attempt:=gen_random_uuid();r:=public.scavenging_action('search',q||jsonb_build_object('request_id',attempt,'target_id',target->>'id'));
  perform pg_temp.check_patrol(not r?'error','Search start failed: '||r::text);
  -- Trusted fixture: a patrol traversed the target during the search, but is far away at collection.
  patrols:=jsonb_build_array(jsonb_build_object('id','test-patrol','route_points',jsonb_build_array(point,jsonb_build_array(case when (point->>0)::int=4 then 3 else (point->>0)::int+1 end,point->1),point),'epoch',extract(epoch from t),'seconds_per_block',1,'radius',0.2));
  update game_private.scav_sessions set pending=pending||jsonb_build_object('patrols',patrols,'patrol_sentence_minutes',5,'started_at',t,'ready_at',t+interval '2 seconds') where player_id=u;
  -- Capture through normal read/finish endpoints; a client cannot turn detection off with payload fields.
  if v='"bin"'::jsonb then r:=public.bin_diving_state();else r:=public.scavenging_action('finish',q||jsonb_build_object('request_id',gen_random_uuid(),'attempt_id',attempt,'patrols','[]'::jsonb,'caught',false));end if;
  r:=public.prison_state();perform pg_temp.check_patrol((r->>'jailed')::boolean,'Caught search did not reach prison');sentence:=(r#>>'{sentence,id}')::uuid;
  perform pg_temp.check_patrol((r#>>'{sentence,release_at}')::timestamptz>clock_timestamp()+interval '4 minutes','Sentence length ignored');
  perform pg_temp.check_patrol((select cash from public.game_players where id=u)=cash_before and (select count(*) from public.game_bin_dives where player_id=u)=count_before,'Caught search paid loot');
  perform pg_temp.check_patrol(not exists(select 1 from game_private.skill_xp_ledger where player_id=u and source_id=attempt),'Caught lockpick awarded XP');
  perform pg_temp.check_patrol((select pending is null from game_private.scav_sessions where player_id=u),'Caught search remained active');
  if v='"car"'::jsonb then perform pg_temp.check_patrol((select quantity from public.game_inventory where player_id=u and good_id='lockpick')=0,'Arrest refunded the consumed lockpick');end if;
  r:=public.scavenging_action('finish',q||jsonb_build_object('request_id',gen_random_uuid(),'attempt_id',attempt));
  perform pg_temp.check_patrol((select id from public.game_prison_sentences where player_id=u and season_id=s)=sentence,'Retry extended or duplicated prison sentence');
  perform pg_temp.check_patrol((select count(*) from game_private.scav_arrests where attempt_id=attempt)=1,'Arrest history missing or duplicated');
  perform set_config('game.reason','CI release between patrol scenarios',true);update public.game_prison_sentences set released_at=clock_timestamp() where player_id=u;
 end loop;
 set local role authenticated;
 denied:=false;begin perform game_private.scav_resolve_patrol();exception when insufficient_privilege then denied:=true;end;perform pg_temp.check_patrol(denied,'Browser can invoke private arrest resolver');
 denied:=false;begin perform game_private.scav_action_before_patrols('finish','{}');exception when insufficient_privilege then denied:=true;end;perform pg_temp.check_patrol(denied,'Browser can bypass patrols through old action');
 r:=public.bin_diving_state();perform pg_temp.check_patrol(r?'scavenging','Authenticated map read broken');r:=public.prison_state();perform pg_temp.check_patrol(r?'jailed','Authenticated prison read broken');reset role;
 denied:=false;begin delete from game_private.scav_arrests where player_id=u;exception when raise_exception then denied:=true;end;perform pg_temp.check_patrol(denied,'Arrest history can be deleted');
end$$;
select 'PASS: visible patrols, swept contact, safe walking, arrests, no rewards, sentence persistence, and private permissions';
rollback;
