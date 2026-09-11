-- Isolated identity, presence and authorization regression tests. Always roll back fixtures.
begin;
do $$
declare
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
 sa uuid:=gen_random_uuid(); sa2 uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid(); sc uuid:=gen_random_uuid();
 an text:='Boss_'||left(replace(a::text,'-',''),12); bn text:='Dock_'||left(replace(b::text,'-',''),12);
 cn text:='Rose_'||left(replace(c::text,'-',''),12); renamed text:='Trader_'||left(replace(b::text,'-',''),12);
 result jsonb; balance_before bigint; ledger_before bigint; total_online integer; case_id uuid;
begin
 insert into auth.users(id,raw_user_meta_data) values(a,jsonb_build_object('username',an,'role','owner')),(b,jsonb_build_object('username',bn));
 insert into auth.users(id) values(c);
 if (select claimed from game_private.identities where player_id=c) then raise exception 'Legacy signup should require a name claim'; end if;
 if not (public.username_available('A_valid_Name')->>'available')::boolean then raise exception 'Valid name rejected'; end if;
 if (public.username_available(lower(an))->>'available')::boolean then raise exception 'Case-insensitive duplicate is available'; end if;
 if (public.username_available('OWNER')->>'available')::boolean then raise exception 'Reserved name is available'; end if;
 begin
  insert into auth.users(id,raw_user_meta_data) values(gen_random_uuid(),jsonb_build_object('username',lower(an)));
  raise exception 'Duplicate username accepted';
 exception when unique_violation then null; end;
 begin
  insert into auth.users(id,raw_user_meta_data) values(gen_random_uuid(),jsonb_build_object('username','owner'));
  raise exception 'Reserved username accepted';
 exception when raise_exception then if SQLERRM='Reserved username accepted' then raise; end if; end;
 begin
  insert into auth.users(id,raw_user_meta_data) values(gen_random_uuid(),jsonb_build_object('username','two words'));
  raise exception 'Invalid username accepted';
 exception when raise_exception then if SQLERRM='Invalid username accepted' then raise; end if; end;
 update auth.users set raw_user_meta_data=jsonb_build_object('username','Impersonator','role','owner') where id=b;
 if (select username from game_private.identities where player_id=b)<>bn then raise exception 'User metadata changed identity'; end if;

 insert into auth.sessions(id,user_id) values(sa,a),(sa2,a),(sb,b),(sc,c);
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sa)::text,true);
 result:=public.game_state();
 if result->'player'->>'handle'<>an then raise exception 'Signup username was not used for player'; end if;
 if game_private.has_permission('roles.manage') then raise exception 'Auth metadata promoted a player'; end if;
 update public.game_user_roles set role_id='owner' where player_id=a;
 result:=public.social_state();
 if (result->>'online_count')::integer<>1 then raise exception 'First session count incorrect'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sa2)::text,true);
 result:=public.social_state();
 if (result->>'online_count')::integer<>1 then raise exception 'Two sessions double-counted player'; end if;
 perform public.presence_leave();
 if (select count(*) from game_private.online_players())<>1 then raise exception 'Leaving one device removed another session'; end if;

 perform set_config('request.jwt.claim.sub',b::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'session_id',sb)::text,true);
 perform public.game_state(); result:=public.social_state();
 if (result->>'online_count')::integer<>2 then raise exception 'Second player missing from presence'; end if;
 update game_private.player_presence set last_seen_at=now()-interval '10 minutes' where player_id=b;
 if (select count(*) from game_private.online_players())<>1 then raise exception 'Stale presence counted'; end if;
 perform public.social_state();
 update public.game_players set sessions_revoked_at=clock_timestamp() where id=b;
 if exists(select 1 from game_private.online_players() where player_id=b) then raise exception 'Kicked session counted'; end if;
 begin
  perform public.social_state();raise exception 'Kicked session heartbeat accepted';
 exception when raise_exception then if SQLERRM='Kicked session heartbeat accepted' then raise; end if; end;
 update public.game_players set sessions_revoked_at=null where id=b;
 update public.game_user_roles set role_id='moderator' where player_id=b;
 result:=public.staff_action('username',jsonb_build_object('player_id',a,'username','StolenBoss','reason','Should be forbidden'));
 if result->>'error' is null then raise exception 'Moderator renamed an Owner'; end if;
 if game_private.has_permission('players.rename') then raise exception 'Owner-only permission granted to Moderator'; end if;

 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'session_id',sc)::text,true);
 perform public.game_state();
 select cash into balance_before from public.game_players where id=c;
 select count(*) into ledger_before from public.game_ledger where player_id=c;
 result:=public.claim_username(lower(an));
 if result->>'error' is null then raise exception 'Duplicate name claim accepted'; end if;
 result:=public.claim_username(cn);
 if result->>'error' is not null then raise exception 'Valid legacy name claim failed: %',result; end if;
 if (select handle from public.game_players where id=c)<>cn then raise exception 'Claim did not update display name'; end if;
 if (select cash from public.game_players where id=c)<>balance_before or (select count(*) from public.game_ledger where player_id=c)<>ledger_before then raise exception 'Name claim changed money or ledger'; end if;
 result:=public.claim_username('SecondName');
 if result->>'error' is null then raise exception 'Repeat name claim accepted'; end if;
 perform public.social_state();

 update public.game_players set xp=300 where id in(a,b);
 update public.game_players set xp=100 where id=c;
 result:=public.player_directory(cn,false,0);
 if result->'players'->0->>'rank'<>'3' then raise exception 'Search changed global rank: %',result; end if;
 result:=public.player_directory(an,false,0);
 if result->'players'->0->>'rank'<>'1' then raise exception 'Highest respect not ranked first'; end if;
 result:=public.player_directory(bn,false,0);
 if result->'players'->0->>'rank'<>'1' then raise exception 'Equal respect did not share rank'; end if;
 insert into public.game_sanctions(player_id,kind,reason,actor_id) values(b,'ban','Presence exclusion test',a);
 if exists(select 1 from game_private.online_players() where player_id=b) then raise exception 'Banned player counted online'; end if;
 if (public.player_directory(bn,false,0)->>'total')::integer<>0 then raise exception 'Banned player listed'; end if;
 update public.game_sanctions set revoked_at=now() where player_id=b and kind='ban';

 perform set_config('request.jwt.claim.sub',b::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'session_id',sb)::text,true);
 result:=public.community_action('chat',jsonb_build_object('body','A named message'));
 if result->>'error' is not null then raise exception 'Chat send failed: %',result; end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'session_id',sa)::text,true);
 result:=public.staff_action('username',jsonb_build_object('player_id',b,'username',renamed,'reason','Approved support name change'));
 if result->>'error' is not null then raise exception 'Owner rename failed: %',result; end if;
 result:=public.social_state();
 if not exists(select 1 from jsonb_array_elements(result->'chat') m where m->>'username'=renamed and m->>'body'='A named message') then raise exception 'Chat did not resolve trusted username'; end if;
 if not exists(select 1 from public.game_audit where action='identities.update' and after_data->>'username'=renamed and reason='Approved support name change') then raise exception 'Username change not audited'; end if;
 result:=public.community_action('ticket',jsonb_build_object('subject','Private support','body','Only authorized people should see this.'));
 if result->>'error' is not null then raise exception 'Ticket creation failed'; end if;
 result:=public.support_state();
 if result ? 'chat' or jsonb_array_length(result->'cases')<>1 then raise exception 'Support mixes chat or loses tickets'; end if;
 perform set_config('request.jwt.claim.sub',c::text,true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',c,'session_id',sc)::text,true);
 if jsonb_array_length(public.support_state()->'cases')<>0 then raise exception 'Private ticket leaked to another player'; end if;

 if has_function_privilege('anon','public.social_state()','execute')
 or has_function_privilege('anon','public.player_directory(text,boolean,integer)','execute')
 or has_function_privilege('anon','public.support_state()','execute')
 or has_function_privilege('authenticated','game_private.rename_identity(uuid,text)','execute')
 or has_table_privilege('authenticated','game_private.identities','update')
 or has_table_privilege('authenticated','game_private.player_presence','insert') then raise exception 'Identity, presence or private RPC grants are too broad'; end if;
 if not has_function_privilege('anon','public.username_available(text)','execute') then raise exception 'Signup cannot check username'; end if;
end $$;
rollback;
select 'PASS: atomic usernames, protected identity, deduplicated session presence, respect ranks, private tickets and audited permissions' as result;
