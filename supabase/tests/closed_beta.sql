begin;
create function pg_temp.verify(ok boolean,msg text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception '%',msg;end if;end$$;
do $$
declare owner_id uuid:=gen_random_uuid();ordinary_id uuid:=gen_random_uuid();v jsonb;blocked boolean:=false;launch integer:=1906567200;
begin
 perform pg_temp.verify(exists(select 1 from public.game_settings where key='closed_beta_starts_at_unix'),'Closed beta launch setting is missing');
 set local role anon;
 v:=public.closed_beta_state();
 perform pg_temp.verify(v?'starts_at' and v?'server_time','Anonymous countdown state is incomplete');
 begin perform value from public.game_settings where key='closed_beta_starts_at_unix';exception when insufficient_privilege then blocked:=true;end;
 perform pg_temp.verify(blocked,'Anonymous visitor can read private game settings');
 reset role;

 insert into auth.users(id) values(owner_id),(ordinary_id);
 perform set_config('request.jwt.claim.sub',owner_id::text,true);perform public.game_state();
 perform set_config('request.jwt.claim.sub',ordinary_id::text,true);perform public.game_state();
 update public.game_user_roles set role_id='owner' where player_id=owner_id;
 set local role authenticated;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 v:=public.staff_action('setting',jsonb_build_object('key','closed_beta_starts_at_unix','value',launch,'reason','Closed beta schedule regression test'));
 perform pg_temp.verify(not (v?'error') and game_private.setting('closed_beta_starts_at_unix')=launch,'Owner could not update the launch time');
 perform set_config('request.jwt.claim.sub',ordinary_id::text,true);
 v:=public.staff_action('setting',jsonb_build_object('key','closed_beta_starts_at_unix','value',launch+60,'reason','Unauthorized beta schedule change'));
 perform pg_temp.verify(v?'error' and game_private.setting('closed_beta_starts_at_unix')=launch,'Player changed the Owner launch setting');
 reset role;
end$$;
select 'PASS: public beta countdown, private settings and Owner-only scheduling';
rollback;
