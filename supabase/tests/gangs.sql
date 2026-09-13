begin;
create function pg_temp.check_gang(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
create function pg_temp.fail_gang_bank() returns trigger language plpgsql as $$begin if current_setting('test.gang_failure',true)='on' then raise exception 'Test ledger failure';end if;return new;end$$;
create trigger gang_failure before update on game_private.gang_accounts for each row execute function pg_temp.fail_gang_bank();
do $$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();c uuid:=gen_random_uuid();outsider uuid:=gen_random_uuid();s uuid:=game_private.current_season();gid uuid;othergang uuid;application uuid;message uuid;thread uuid;next_s uuid;
q jsonb;r jsonb;first jsonb;before_cash bigint;denied boolean;bad jsonb;v integer;
begin
 insert into auth.users(id,raw_user_meta_data) values(a,jsonb_build_object('username','Boss'||left(a::text,8))),(b,jsonb_build_object('username','Recruit'||left(b::text,8))),(c,jsonb_build_object('username','Second'||left(c::text,8))),(outsider,jsonb_build_object('username','Stranger'||left(outsider::text,8)));
 perform set_config('request.jwt.claim.sub',a::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',b::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',c::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',outsider::text,true);perform public.game_state();
 perform set_config('game.reason','Gang regression fixtures',true);update public.game_players set cash=100000 where id in(a,b,c,outsider);
 perform set_config('request.jwt.claim.sub',a::text,true);
 q:=jsonb_build_object('season_id',s,'request_id',gen_random_uuid(),'name','Family '||left(a::text,8));
 set local role authenticated;
 first:=public.gang_action('create',q);perform pg_temp.check_gang(not first?'error','Create failed: '||first::text);gid:=(first->>'gang_id')::uuid;
 r:=public.gang_action('create',q);perform pg_temp.check_gang(r=first,'Creation retry duplicated gang');
 r:=public.gang_workspace(gid);perform pg_temp.check_gang((r->'selected'->>'is_owner')::boolean and (r->'selected'->'bank'->>'balance')::int=0,'Leader or bank missing');
 reset role;
 -- Requests are private and send one fixed-text, free notification, including safe retries.
 perform set_config('request.jwt.claim.sub',b::text,true);select cash into before_cash from public.game_players where id=b;
 q:=jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'body','UNTRUSTED FREE MESSAGE');
 set local role authenticated;
 first:=public.gang_action('request_join',q);perform pg_temp.check_gang(not first?'error','Request failed: '||first::text);application:=(first->>'application_id')::uuid;
 r:=public.gang_action('request_join',q);perform pg_temp.check_gang(r=first,'Join retry changed');
 r:=public.gang_action('request_join',q||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.check_gang((r->>'application_id')::uuid=application,'Duplicate pending request');
 r:=public.gang_workspace(gid);perform pg_temp.check_gang(r->'selected'->'bank'='null'::jsonb and jsonb_array_length(r->'selected'->'requests')=0,'Outsider sees gang finances or requests');
 r:=public.gang_action('deposit',q||'{"amount":1000}');perform pg_temp.check_gang(r?'error','Outsider deposit allowed');
 r:=public.gang_action('accept',q||jsonb_build_object('application_id',application));perform pg_temp.check_gang(r?'error','Applicant approved themselves');
 reset role;
 perform pg_temp.check_gang(not exists(select 1 from public.game_season_gang_members where player_id=b and season_id=s),'Request instantly joined');
 select telegram_id into message from game_private.gang_join_requests where id=application;
 select thread_id into thread from game_private.telegrams where id=message;
 perform pg_temp.check_gang((select recipient_id=a and sender_id=b and body not like '%UNTRUSTED FREE MESSAGE%' from game_private.telegrams where id=message),'Telegram notification recipient or content wrong');
 perform pg_temp.check_gang((select count(*) from game_private.telegram_threads where first_player=b and second_player=a)=1,'Request retry duplicated telegram');
 perform pg_temp.check_gang((select cash=before_cash from public.game_players where id=b),'Automatic notice charged wallet');
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.telegram_state(thread);perform pg_temp.check_gang((r->'messages'->0->>'recruitment_gang_id')::uuid=gid,'Telegram review link missing');
 r:=public.gang_action('accept',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'application_id',application));
 perform pg_temp.check_gang(not r?'error','Leader acceptance failed: '||r::text);
 perform pg_temp.check_gang((select rank_id='associate' from public.game_season_gang_members where player_id=b and season_id=s),'Accepted recruit not Associate');
 -- Rank hierarchy, stale updates, self-promotion and cross-gang attempts.
 q:=jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'player_id',b,'rank_id','underboss','version',1);
 r:=public.gang_action('rank',q);perform pg_temp.check_gang(not r?'error','Leader promotion failed: '||r::text);
 r:=public.gang_action('rank',q||jsonb_build_object('request_id',gen_random_uuid(),'rank_id','capo'));perform pg_temp.check_gang(r?'error','Stale rank accepted');
 perform set_config('request.jwt.claim.sub',b::text,true);
 r:=public.gang_action('rank',q||jsonb_build_object('request_id',gen_random_uuid(),'version',2));perform pg_temp.check_gang(r?'error','Self promotion accepted');
 r:=public.gang_action('remove',q||jsonb_build_object('request_id',gen_random_uuid(),'player_id',a));perform pg_temp.check_gang(r?'error','Leader removed by underboss');
 r:=public.gang_action('withdraw',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',1));perform pg_temp.check_gang(r?'error','Underboss withdrew money');
 -- Add second recruit and test genuine delegated rank authority.
 perform set_config('request.jwt.claim.sub',c::text,true);r:=public.gang_action('request_join',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid()));application:=(r->>'application_id')::uuid;
 perform set_config('request.jwt.claim.sub',b::text,true);r:=public.gang_action('accept',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'application_id',application));perform pg_temp.check_gang(not r?'error','Underboss cannot accept request');
 r:=public.gang_action('rank',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'player_id',c,'rank_id','underboss','version',1));perform pg_temp.check_gang(r?'error','Underboss promoted a peer');
 r:=public.gang_action('rank',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'player_id',c,'rank_id','soldier','version',1));perform pg_temp.check_gang(not r?'error','Underboss cannot promote lower member');
 -- Gang deposits are donations, not personal assets or repeatable contribution points.
 select cash into before_cash from public.game_players where id=b;
 q:=jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'amount',1000,'player_id',a);
 set local role authenticated;
 first:=public.gang_action('deposit',q);perform pg_temp.check_gang(not first?'error','Deposit failed: '||first::text);
 r:=public.gang_action('deposit',q);perform pg_temp.check_gang(r=first,'Deposit retry changed');
 r:=public.gang_action('deposit',q||'{"amount":2000}');perform pg_temp.check_gang(r?'error','Changed idempotent amount accepted');
 denied:=false;begin update game_private.gang_accounts set balance=999999;exception when insufficient_privilege then denied:=true;end;perform pg_temp.check_gang(denied,'Direct bank writes possible');
 denied:=false;begin select count(*) into v from game_private.gang_ledger;exception when insufficient_privilege then denied:=true;end;perform pg_temp.check_gang(denied,'Direct bank ledger reads possible');
 reset role;
 perform pg_temp.check_gang((select cash=before_cash-1000 from public.game_players where id=b),'Wrong wallet charged');
 perform pg_temp.check_gang((select balance=1000 from game_private.gang_accounts where gang_id=gid),'Gang bank not credited');
 perform pg_temp.check_gang((select count(*) from game_private.gang_ledger where gang_id=gid)=1,'Duplicate ledger');
 perform pg_temp.check_gang((select count(*) from public.game_ledger where player_id=b and reason like 'Gang bank %')=1,'Missing wallet ledger');
 perform pg_temp.check_gang((select contribution=0 from public.game_season_gang_members where player_id=b and season_id=s),'Deposits inflated contribution ranking');
 foreach bad in array array['0'::jsonb,'-1'::jsonb,'1.5'::jsonb,'"100"'::jsonb,'null'::jsonb,'1000000001'::jsonb] loop
  r:=public.gang_action('deposit',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',bad));perform pg_temp.check_gang(r?'error','Invalid amount accepted');
 end loop;
 perform set_config('test.gang_failure','on',true);r:=public.gang_action('deposit',q||jsonb_build_object('request_id',gen_random_uuid()));perform set_config('test.gang_failure','off',true);
 perform pg_temp.check_gang(r?'error' and (select cash=before_cash-1000 from public.game_players where id=b),'Failed account write lost cash');
 perform set_config('request.jwt.claim.sub',a::text,true);
 r:=public.gang_action('withdraw',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',1001));perform pg_temp.check_gang(r?'error','Gang overdraft accepted');
 r:=public.gang_action('withdraw',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',250));perform pg_temp.check_gang(not r?'error','Leader withdrawal failed');
 perform pg_temp.check_gang((select balance=750 from game_private.gang_accounts where gang_id=gid),'Withdrawal balance incorrect');
 -- Removed members lose both gang panel and Telegram group access, while financial records survive.
 r:=public.telegram_room_action('gang',jsonb_build_object('request_id',gen_random_uuid()));thread:=(r->>'thread_id')::uuid;
 perform pg_temp.check_gang(game_private.telegram_access(thread,b),'Member cannot access gang conversation');
 r:=public.gang_action('remove',jsonb_build_object('season_id',s,'gang_id',gid,'request_id',gen_random_uuid(),'player_id',b,'version',2));perform pg_temp.check_gang(not r?'error','Member removal failed');
 perform pg_temp.check_gang(not game_private.telegram_access(thread,b),'Removed member retained gang conversation');
 perform set_config('request.jwt.claim.sub',b::text,true);r:=public.gang_workspace(gid);perform pg_temp.check_gang(r->'selected'->'bank'='null'::jsonb,'Removed member sees bank');
 r:=public.gang_action('deposit',q||jsonb_build_object('request_id',gen_random_uuid()));perform pg_temp.check_gang(r?'error','Removed member deposited');
 denied:=false;begin delete from game_private.gang_ledger where gang_id=gid;exception when raise_exception then denied:=true;end;perform pg_temp.check_gang(denied,'Gang financial history deletable');
 perform pg_temp.check_gang(exists(select 1 from public.game_audit where target='game_season_gang_members' and action='game_season_gang_members.update' and actor_id=a),'Rank changes unaudited');
 -- Legacy district joins now request approval too.
 perform set_config('request.jwt.claim.sub',outsider::text,true);
 r:=public.district_action('gang_join',jsonb_build_object('season_id',s,'gang_id',gid));
 perform pg_temp.check_gang(not r?'error' and not exists(select 1 from public.game_season_gang_members where player_id=outsider and season_id=s),'Legacy instant join bypass');
 -- Closed seasons prevent new movement. Archived accounts/history are preserved after reset.
 perform set_config('request.jwt.claim.sub',a::text,true);update public.game_user_roles set role_id='owner' where player_id=a;
 r:=public.season_action('create','{"name":"Gang next season","reason":"Gang season regression"}');next_s:=(r->>'season_id')::uuid;
 r:=public.season_action('lock',jsonb_build_object('season_id',s,'reason','Gang season regression'));perform pg_temp.check_gang(not r?'error','Season lock failed');
 r:=public.gang_action('withdraw',q||jsonb_build_object('request_id',gen_random_uuid(),'amount',1));perform pg_temp.check_gang(r?'error','Closed season moved bank funds');
 r:=public.season_action('snapshot',jsonb_build_object('season_id',s,'reason','Gang season regression'));perform pg_temp.check_gang(not r?'error','Snapshot failed');
 r:=public.season_action('archive',jsonb_build_object('season_id',s,'reason','Gang season regression'));perform pg_temp.check_gang(not r?'error','Archive failed');
 r:=public.season_action('launch_next',jsonb_build_object('season_id',next_s,'expected_current_season',s,'confirmation','RESET '||(select name from public.game_seasons where id=s),'reason','Gang season regression'));perform pg_temp.check_gang(not r?'error','Reset failed: '||r::text);
 r:=public.gang_workspace();perform pg_temp.check_gang(r->'my_gang_id'='null'::jsonb and r->'selected'='null'::jsonb,'Old gang leaked into new season');
 perform pg_temp.check_gang((select balance=750 from game_private.gang_accounts where gang_id=gid) and (select count(*) from game_private.gang_ledger where gang_id=gid)=2,'Reset destroyed financial records');
 set local role anon;denied:=false;begin perform public.gang_workspace(gid);exception when insufficient_privilege then denied:=true;end;perform pg_temp.check_gang(denied,'Anonymous gang access');
 reset role;
end$$;
select 'PASS: gang requests, Telegram notices, permissions, ranks, ledger, retries, removals and season preservation';
rollback;
