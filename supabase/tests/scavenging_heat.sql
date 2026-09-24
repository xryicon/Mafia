begin;
create function pg_temp.heat_check(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
select set_config('game.reason','CI scavenging heat and skill coverage',true);
do $$
declare u uuid:=gen_random_uuid();s uuid:=game_private.current_season();d uuid;other_d uuid;r jsonb;p jsonb;before_radius numeric;after_radius numeric;nonce uuid:=gen_random_uuid();q jsonb;target jsonb;
begin
 insert into auth.users(id) values(u);perform set_config('request.jwt.claim.sub',u::text,true);perform public.game_state();
 select id into d from public.game_districts where slug='the-waterfront';select id into other_d from public.game_districts where id<>d limit 1;
 update public.game_settings set value=0 where key in ('scavenging_patrol_enabled','scavenging_event_chance');
 q:=jsonb_build_object('season_id',s,'district_id',d,'request_id',gen_random_uuid());r:=public.scavenging_action('enter',q);
 select x into target from jsonb_array_elements(public.bin_diving_state()#>'{scavenging,targets}')x where x->>'kind'='bin' limit 1;
 r:=public.scavenging_action('move',q||jsonb_build_object('request_id',gen_random_uuid(),'node',target->'node'));
 update game_private.scav_sessions set arrives_at=clock_timestamp()-interval '1 second' where player_id=u;
 q:=q||jsonb_build_object('request_id',nonce,'target_id',target->>'id','heat',0,'level',20);
 r:=public.scavenging_action('search',q);perform pg_temp.heat_check(not r?'error','Search failed: '||r::text);
 perform pg_temp.heat_check((select searches=1 and heat=8 from game_private.scav_district_heat where player_id=u),'Search did not add heat exactly once');
 r:=public.scavenging_action('search',q);perform pg_temp.heat_check((select searches=1 from game_private.scav_district_heat where player_id=u),'Replay added heat');
 r:=game_private.scav_risk(s,u,d);perform pg_temp.heat_check((r->>'level')::int=1 and (r->>'detection_multiplier')::numeric>1,'Client spoofed risk or heat does not increase detection');
 perform pg_temp.heat_check((game_private.scav_risk(s,u,other_d)->>'heat')::numeric=0,'Heat leaked across districts');
 p:=(select pending from game_private.scav_sessions where player_id=u);perform pg_temp.heat_check((p#>>'{risk,heat}')::numeric>7,'Search risk snapshot missed new heat');
 insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description) select s,u,'scavenging',gen_random_uuid(),xp_to_20,'CI max skill' from public.game_skill_definitions where id='scavenging';
 perform pg_temp.heat_check((game_private.scav_risk(s,u,d)->>'detection_multiplier')::numeric<(r->>'detection_multiplier')::numeric,'High skill did not reduce detection');
 perform pg_temp.heat_check((game_private.scav_risk(s,u,d)->>'level')::int=20,'Max skill not read from ledger');
 perform pg_temp.heat_check((select pending=p from game_private.scav_sessions where player_id=u),'Skill change rerolled active search');
 update game_private.scav_district_heat set updated_at=clock_timestamp()-interval '20 minutes' where player_id=u;
 perform pg_temp.heat_check((game_private.scav_risk(s,u,d)->>'heat')::numeric=0,'Heat did not cool');
 perform pg_temp.heat_check(not has_table_privilege('authenticated','game_private.scav_district_heat','update') and not has_function_privilege('authenticated','game_private.scav_risk(uuid,uuid,uuid)','execute'),'Risk internals exposed');
 r:=public.bin_diving_state();perform pg_temp.heat_check(r#>'{scavenging,district_risk}'?d::text,'Risk not returned to UI');
 -- Real sweep: a close patrol detects the novice but misses the smaller expert search radius.
 before_radius:=0.22;after_radius:=before_radius*(game_private.scav_risk(s,u,d)->>'detection_multiplier')::numeric;
 p:=jsonb_build_array(jsonb_build_object('id','test','route_points','[[0,0],[1,0],[0,0]]'::jsonb,'epoch',0,'seconds_per_block',1,'radius',before_radius));
 perform pg_temp.heat_check(game_private.scav_patrol_contact(p,'[0.5,0.18]',now(),now()+interval '2 seconds')='test','Novice detection fixture failed');
 p:=jsonb_set(p,'{0,radius}',to_jsonb(after_radius));
 perform pg_temp.heat_check(game_private.scav_patrol_contact(p,'[0.5,0.18]',now(),now()+interval '2 seconds') is null,'Expert was detected outside reduced radius');
end$$;
select 'PASS: server skill, increasing district heat, replay protection, cooling, private data, and reduced patrol detection';
rollback;
