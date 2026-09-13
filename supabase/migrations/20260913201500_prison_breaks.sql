-- Server-authoritative Blackwater Island jailbreaks, lockpick loot and a seasonal breakout leaderboard.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Introduce Blackwater Island prison breaks',true);

insert into public.game_settings(key,value,minimum,maximum)
values('prison_break_power',50,0,100000);

insert into public.game_goods(id,name,business_name,business_cost,batch_size,cycle_seconds,business_available,inventory_category,inventory_description,weight_grams,equipment_slots)
values('lockpick','Lockpick','Street tool',1,1,60,false,'tools','A single-use lockpick for a Blackwater Island prison-break attempt.',40,'{}');

insert into public.game_season_valuations(season_id,good_id,unit_value)
select id,'lockpick',25 from public.game_seasons on conflict do nothing;

insert into public.game_metric_catalog(id,label,description,available)
values('breakouts','Prison breakouts','Successful Blackwater Island prison breaks this season.',true);
insert into public.game_leaderboards(season_id,metric,label,enabled,direction,include_banned,hall_of_fame)
select id,'breakouts','Prison breakouts',true,'desc',false,true from public.game_seasons on conflict do nothing;

alter table public.game_bin_rules drop constraint game_bin_rules_check1;
alter table public.game_bin_rules add column lockpick_chance numeric(5,2) not null default 5 check(lockpick_chance between 0 and 100);
alter table public.game_bin_rules add constraint game_bin_rules_total_chance_check
 check(cash_chance+pickaxe_chance+pistol_blueprint_chance+bullet_blueprint_chance+lockpick_chance<=100);
alter table public.game_bin_dives drop constraint game_bin_dives_outcome_check;
alter table public.game_bin_dives add constraint game_bin_dives_outcome_check
 check(outcome in ('nothing','cash','pickaxe','pistol_blueprint','bullet_blueprint','lockpick'));

create table game_private.prison_break_attempts(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 rescuer_id uuid not null references public.game_players(id),inmate_id uuid not null references public.game_players(id),
 sentence_id uuid not null,status text not null default 'active' check(status in ('active','succeeded','caught','expired','cancelled')),
 target_angle smallint not null check(target_angle between -80 and 80),attempts_left smallint not null default 5 check(attempts_left between 0 and 5),
 last_turn smallint not null default 0 check(last_turn between 0 and 90),reward_power integer not null default 0 check(reward_power between 0 and 100000),
 started_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null default clock_timestamp()+interval '90 seconds',completed_at timestamptz,
 check(rescuer_id<>inmate_id),check(expires_at>started_at)
);
create unique index prison_break_one_active on game_private.prison_break_attempts(season_id,rescuer_id) where status='active';
create index prison_break_inmate on game_private.prison_break_attempts(season_id,inmate_id,started_at desc);
create index prison_break_history on game_private.prison_break_attempts(season_id,rescuer_id,started_at desc);

create table game_private.prison_break_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),request_id uuid not null,
 action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default clock_timestamp(),
 primary key(season_id,player_id,request_id)
);
create index prison_break_request_player on game_private.prison_break_requests(player_id,created_at desc);
revoke all on game_private.prison_break_attempts,game_private.prison_break_requests from public,anon,authenticated;

create or replace function game_private.bin_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid; uid uuid:=auth.uid();
begin
 perform game_private.require_active();
 s:=game_private.season_guard(false);
 if not exists(select 1 from public.game_players where id=uid) then perform game_private.state(); end if;
 return jsonb_build_object(
  'season',(select jsonb_build_object('id',id,'name',name,'status',status,'ends_at',ends_at) from public.game_seasons where id=s),
  'server_time',clock_timestamp(),
  'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
  'rules',(select to_jsonb(r)-'id' from public.game_bin_rules r),
  'can_manage',game_private.has_permission('bin_diving.manage'),
  'districts',(select coalesce(jsonb_agg(x order by x.name),'[]') from (
   select d.id,d.slug,d.name,d.tagline,d.image_url,d.police_heat,
    case when d.status='lockdown' or t.status='lockdown' then 'lockdown' else coalesce(t.status,d.status) end status
   from public.game_districts d left join public.game_district_territory t on t.district_id=d.id and t.season_id=s
   where d.archived_at is null) x),
  'cash',(select cash from public.game_players where id=uid),
  'inventory',(select coalesce(jsonb_object_agg(good_id,quantity),'{}') from public.game_inventory where season_id=s and player_id=uid and good_id in ('pickaxe','pistol_blueprint','bullet_blueprint','lockpick')),
  'tool_condition',coalesce((select durability from public.game_mining_tools where season_id=s and player_id=uid),0),
  'tool_max',game_private.setting('mining_pickaxe_durability'),
  'mining_shift',exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working'),
  'ready_at',(select max(ready_at) from public.game_bin_dives where season_id=s and player_id=uid),
  'history',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]') from (
   select id,district_id,district_name,outcome,cash,created_at,ready_at from public.game_bin_dives
   where season_id=s and player_id=uid order by created_at desc limit 30) x)
 );
end $$;

create or replace function game_private.bin_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 s uuid; uid uuid:=auth.uid(); nonce uuid; prior game_private.bin_requests;
 r public.game_bin_rules; d public.game_districts; receipt public.game_bin_dives;
 stamp timestamptz; ready timestamptz; roll integer; amount integer:=0; outcome text; result jsonb; reason text;
begin
 perform game_private.require_active(); if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>4096 then raise exception 'Invalid action details.'; end if;
  s:=game_private.season_guard(false);
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The season changed. Refresh before continuing.'; end if;
  nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null then raise exception 'A request ID is required.'; end if;
  perform pg_advisory_xact_lock(4704020);
  select * into prior from game_private.bin_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This request ID was already used for a different action.'; end if;
   return prior.result;
  end if;
  if p_action='configure' then
   if not game_private.has_permission('bin_diving.manage') then raise exception 'Owner permission required.'; end if;
   reason:=btrim(p_payload->>'reason');
   if reason is null or length(reason) not between 5 and 500 then raise exception 'Add a reason of 5–500 characters for the audit log.'; end if;
   select * into strict r from public.game_bin_rules for update;
   if (p_payload->>'version')::integer is distinct from r.version then raise exception 'Another edit was saved. Refresh and review the current rules.'; end if;
   perform set_config('game.reason','Bin diving rules: '||reason,true);
   update public.game_bin_rules set enabled=(p_payload->>'enabled')::boolean,
    cooldown_seconds=(p_payload->>'cooldown_seconds')::integer,cash_min=(p_payload->>'cash_min')::integer,cash_max=(p_payload->>'cash_max')::integer,
    cash_chance=(p_payload->>'cash_chance')::numeric,pickaxe_chance=(p_payload->>'pickaxe_chance')::numeric,
    pistol_blueprint_chance=(p_payload->>'pistol_blueprint_chance')::numeric,bullet_blueprint_chance=(p_payload->>'bullet_blueprint_chance')::numeric,
    lockpick_chance=(p_payload->>'lockpick_chance')::numeric,version=version+1;
   result:=jsonb_build_object('message','Bin diving rules saved. New districts use these rules automatically.');
  else
   perform game_private.season_guard();
   select * into strict r from public.game_bin_rules for share;
   if p_action='dive' then
    if not r.enabled then raise exception 'Bin diving is paused by the city Owner.'; end if;
    select * into d from public.game_districts where id=(p_payload->>'district_id')::uuid and archived_at is null for share;
    if not found then raise exception 'This district is not open.'; end if;
    if d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown') then raise exception 'This district is in lockdown.'; end if;
   elsif p_action<>'equip' then raise exception 'Unknown bin diving action.'; end if;
   perform 1 from public.game_players where id=uid and season_id=s for update;
   if not found then raise exception 'Open your dashboard to initialize this season.'; end if;
   perform set_config('game.reason','Bin diving '||p_action||': '||nonce,true);
   if p_action='equip' then
    if exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working') then raise exception 'Finish your mining shift before replacing equipment.'; end if;
    update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=uid and good_id='pickaxe' and quantity>0;
    if not found then raise exception 'Find a pickaxe by bin diving or buy one from another player on the market.'; end if;
    insert into public.game_mining_tools(season_id,player_id,durability) values(s,uid,game_private.setting('mining_pickaxe_durability'))
     on conflict(season_id,player_id) do update set durability=excluded.durability
     where public.game_mining_tools.durability<excluded.durability;
    if not found then raise exception 'Your current pickaxe is already in full condition.'; end if;
    result:=jsonb_build_object('message','Pickaxe equipped. Visit a public mine to put it to work.');
   else
    stamp:=clock_timestamp();
    select max(ready_at) into ready from public.game_bin_dives where season_id=s and player_id=uid;
    if ready>stamp then raise exception 'Give the streets a moment. Your cooldown applies across every district.'; end if;
    if (r.pickaxe_chance>0 and not game_private.inventory_fits(s,uid,'pickaxe',1)) or (r.lockpick_chance>0 and not game_private.inventory_fits(s,uid,'lockpick',1)) or (r.pistol_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'pistol_blueprint',1)) or (r.bullet_blueprint_chance>0 and not game_private.inventory_fits(s,uid,'bullet_blueprint',1)) then raise exception 'Free space and weight in Inventory before searching for loot.';end if;
    roll:=floor(random()*10000)::integer;
    outcome:=case when roll<r.cash_chance*100 then 'cash'
     when roll<(r.cash_chance+r.pickaxe_chance)*100 then 'pickaxe'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance)*100 then 'pistol_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance)*100 then 'bullet_blueprint'
     when roll<(r.cash_chance+r.pickaxe_chance+r.pistol_blueprint_chance+r.bullet_blueprint_chance+r.lockpick_chance)*100 then 'lockpick' else 'nothing' end;
    if outcome='cash' then amount:=r.cash_min+floor(random()*(r.cash_max-r.cash_min+1))::integer; end if;
    insert into public.game_bin_dives(season_id,player_id,district_id,district_name,outcome,cash,rules_version,created_at,ready_at)
     values(s,uid,d.id,d.name,outcome,amount,r.version,stamp,stamp+make_interval(secs=>r.cooldown_seconds)) returning * into receipt;
    if outcome='cash' then perform game_private.district_wallet(uid,amount,'Bin diving: '||receipt.id);
    elsif outcome<>'nothing' then
     insert into public.game_inventory(season_id,player_id,good_id,quantity) values(s,uid,outcome,1)
      on conflict(season_id,player_id,good_id) do update set quantity=public.game_inventory.quantity+1;
    end if;
    result:=jsonb_build_object('message',case when outcome='nothing' then 'Nothing useful this time. The next bin tells another story.' else 'You found something worth keeping.' end,'receipt',to_jsonb(receipt));
   end if;
  end if;
  insert into game_private.bin_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
  return result;
 exception
  when check_violation or not_null_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','Check the values: chances must total at most 100%, cash must be a valid range, and cooldown must be 1–86,400 seconds.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end $$;

create function game_private.expire_prison_break(s uuid,uid uuid,stamp timestamptz) returns boolean
language plpgsql security definer set search_path='' as $$
declare attempt game_private.prison_break_attempts;target public.game_prison_sentences;target_handle text;
begin
 perform pg_advisory_xact_lock(4704031);
 select * into attempt from game_private.prison_break_attempts where season_id=s and rescuer_id=uid and status='active' and expires_at<=stamp order by started_at limit 1 for update;
 if not found then return false;end if;
 if exists(select 1 from public.game_prison_sentences where season_id=s and player_id=uid and released_at is null and release_at>stamp) then
  update game_private.prison_break_attempts set status='cancelled',completed_at=stamp where id=attempt.id;return false;
 end if;
 select p.* into target from public.game_prison_sentences p where p.id=attempt.sentence_id and p.season_id=s and p.player_id=attempt.inmate_id and p.released_at is null and p.release_at>stamp for update;
 if not found then update game_private.prison_break_attempts set status='cancelled',completed_at=stamp where id=attempt.id;return false;end if;
 select handle into target_handle from public.game_players where id=target.player_id;
 perform set_config('game.reason','Caught after prison-break timer expired for '||attempt.inmate_id,true);
 update game_private.prison_break_attempts set status='caught',attempts_left=0,completed_at=stamp where id=attempt.id;
 insert into public.game_prison_sentences as p(season_id,player_id,reason,started_at,release_at,actor_id)
  values(s,uid,'Caught trying to break '||target_handle||' out of prison',stamp,target.release_at,uid)
  on conflict(season_id,player_id) do update set id=gen_random_uuid(),reason=excluded.reason,started_at=excluded.started_at,release_at=excluded.release_at,released_at=null,actor_id=excluded.actor_id;
 insert into public.game_events(player_id,description) values(uid,'Caught when a Blackwater Island prison-break timer expired. Sentence matched to the target inmate.');
 return true;
end$$;
create or replace function game_private.prison_state() returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;t timestamptz:=clock_timestamp();sentence jsonb;uid uuid:=auth.uid();
begin
 perform game_private.require_active();s:=game_private.season_guard(false);perform game_private.expire_prison_break(s,uid,t);
 select jsonb_build_object('id',p.id,'reason',p.reason,'started_at',p.started_at,'release_at',p.release_at) into sentence
 from public.game_prison_sentences p where p.season_id=s and p.player_id=uid and p.released_at is null and p.release_at>t;
 return jsonb_build_object('season_id',s,'player_id',uid,'jailed',sentence is not null,'sentence',sentence,'district_slug','blackwater-island',
  'server_time',t,'can_manage',game_private.has_permission('prison.manage'),'reward_power',game_private.setting('prison_break_power'),
  'lockpicks',coalesce((select quantity from public.game_inventory where season_id=s and player_id=uid and good_id='lockpick'),0),
  'inmates',(select coalesce(jsonb_agg(x order by x.release_at),'[]') from (
   select p.id as sentence_id,p.player_id,g.handle,p.release_at from public.game_prison_sentences p join public.game_players g on g.id=p.player_id
   where p.season_id=s and p.player_id<>uid and p.released_at is null and p.release_at>t and g.deleted_at is null order by p.release_at limit 100)x),
  'attempt',(select jsonb_build_object('id',a.id,'sentence_id',a.sentence_id,'inmate_id',a.inmate_id,'inmate_handle',g.handle,
    'attempts_left',a.attempts_left,'last_turn',a.last_turn,'started_at',a.started_at,'expires_at',a.expires_at)
   from game_private.prison_break_attempts a join public.game_players g on g.id=a.inmate_id
   where a.season_id=s and a.rescuer_id=uid and a.status='active' and a.expires_at>t order by a.started_at desc limit 1),
  'leaderboard',(select coalesce(jsonb_agg(x order by x.rank,x.handle),'[]') from (
   select p.id as player_id,p.handle,st.value::integer as breakouts,rank() over(order by st.value desc) as rank
   from public.game_season_stats st join public.game_players p on p.id=st.player_id
   where st.season_id=s and st.metric='breakouts' and st.value>0 and game_private.visible_player(p.id)
   order by st.value desc,p.handle limit 10)x),
  'my_breakouts',coalesce((select value from public.game_season_stats where season_id=s and player_id=uid and metric='breakouts'),0),
  'my_rank',(select rank from (select player_id,rank() over(order by value desc) rank from public.game_season_stats where season_id=s and metric='breakouts' and value>0)r where player_id=uid));
end$$;

create or replace function game_private.prison_break_action(p_action text,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;uid uuid:=auth.uid();nonce uuid;prior game_private.prison_break_requests;stamp timestamptz:=clock_timestamp();
 attempt game_private.prison_break_attempts;target public.game_prison_sentences;target_handle text;chosen integer;distance integer;turn_amount integer;
 reward integer;result jsonb;season_status text;season_end timestamptz;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Let the guards pass before trying again.');end if;
 begin
  if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2048 then raise exception 'Invalid prison-break action.';end if;
  s:=game_private.season_guard(false);nonce:=(p_payload->>'request_id')::uuid;
  if nonce is null or (p_payload->>'season_id')::uuid is distinct from s then raise exception 'The prison register changed. Refresh before continuing.';end if;
  select * into prior from game_private.prison_break_requests where season_id=s and player_id=uid and request_id=nonce;
  if found then
   if prior.action is distinct from p_action or prior.payload is distinct from p_payload then raise exception 'This action reference was already used.';end if;
   return prior.result;
  end if;
  perform pg_advisory_xact_lock(4704031);
  select status,ends_at into season_status,season_end from public.game_seasons where id=s;
  if season_status<>'open' or (season_end is not null and stamp>=season_end) then raise exception 'This season is closed for gameplay.';end if;
  if game_private.expire_prison_break(s,uid,stamp) then
   select * into target from public.game_prison_sentences where season_id=s and player_id=uid and released_at is null and release_at>stamp for share;
   result:=jsonb_build_object('message','Caught. The guard timer expired, so you are serving the same remaining time as the inmate you tried to free.','outcome','caught','turn',0,'attempts_left',0,'release_at',target.release_at);
   insert into game_private.prison_break_requests values(s,uid,nonce,p_action,p_payload,result,stamp);
   return result;
  end if;
  if exists(select 1 from public.game_prison_sentences where season_id=s and player_id=uid and released_at is null and release_at>stamp) then raise exception 'You cannot stage a prison break while serving a sentence.';end if;
  update game_private.prison_break_attempts set status='expired',completed_at=stamp where season_id=s and rescuer_id=uid and status='active' and expires_at<=stamp;
  if p_action='start' then
   select p.* into target from public.game_prison_sentences p where p.id=(p_payload->>'sentence_id')::uuid and p.season_id=s and p.released_at is null and p.release_at>stamp for update;
   if not found then raise exception 'That inmate is no longer available for a breakout.';end if;
   if target.player_id=uid then raise exception 'You cannot break yourself out.';end if;
   if exists(select 1 from game_private.prison_break_attempts where season_id=s and rescuer_id=uid and status='active') then raise exception 'Finish your active lock before starting another.';end if;
   perform pg_advisory_xact_lock(4704020);
   perform set_config('game.reason','Prison-break lockpick: '||nonce,true);perform set_config('game.inventory_request',nonce::text,true);
   perform 1 from public.game_players where id=uid and season_id=s for update;
   update public.game_inventory set quantity=quantity-1 where season_id=s and player_id=uid and good_id='lockpick' and quantity>0;
   if not found then raise exception 'You need a lockpick. Find one while bin diving or buy one on the market.';end if;
   insert into game_private.prison_break_attempts(season_id,rescuer_id,inmate_id,sentence_id,target_angle)
    values(s,uid,target.player_id,target.id,floor(random()*161)::integer-80) returning * into attempt;
   select handle into target_handle from public.game_players where id=target.player_id;
   result:=jsonb_build_object('message','Lockpick committed. Find the hidden angle before the guard reaches you.','outcome','started','attempt',
    jsonb_build_object('id',attempt.id,'sentence_id',attempt.sentence_id,'inmate_id',attempt.inmate_id,'inmate_handle',target_handle,'attempts_left',attempt.attempts_left,'last_turn',0,'started_at',attempt.started_at,'expires_at',attempt.expires_at));
  elsif p_action='tension' then
   select * into attempt from game_private.prison_break_attempts where id=(p_payload->>'attempt_id')::uuid and season_id=s and rescuer_id=uid for update;
   if not found or attempt.status<>'active' then raise exception 'This lock is no longer active. Refresh the prison register.';end if;
   if attempt.expires_at<=stamp then update game_private.prison_break_attempts set status='expired',completed_at=stamp where id=attempt.id;raise exception 'The guards passed your position. The lockpick is gone.';end if;
   select p.* into target from public.game_prison_sentences p where p.id=attempt.sentence_id and p.season_id=s and p.player_id=attempt.inmate_id and p.released_at is null and p.release_at>stamp for update;
   if not found then
    update game_private.prison_break_attempts set status='cancelled',completed_at=stamp where id=attempt.id;
    result:=jsonb_build_object('message','The inmate is no longer in custody. The attempt has ended.','outcome','cancelled');
   else
    chosen:=(p_payload->>'angle')::integer;
    if chosen is null or chosen not between -80 and 80 then raise exception 'Choose a valid lockpick angle.';end if;
    distance:=abs(chosen-attempt.target_angle);
    if distance<=6 then
     reward:=game_private.setting('prison_break_power');
     perform set_config('game.reason','Successful prison break for '||attempt.inmate_id,true);
     update public.game_prison_sentences set released_at=stamp where id=target.id and released_at is null and release_at>stamp;
     if not found then raise exception 'Another crew reached this inmate first.';end if;
     update game_private.prison_break_attempts set status='succeeded',attempts_left=attempts_left-1,last_turn=90,reward_power=reward,completed_at=stamp where id=attempt.id;
     update public.game_players set xp=xp+reward where id=uid;
     perform game_private.record_metric(uid,'breakouts',1);
     insert into public.game_events(player_id,description) values
      (uid,'Broke '||(select handle from public.game_players where id=target.player_id)||' out of Blackwater Island Prison · +'||reward||' power'),
      (target.player_id,'Broken out of Blackwater Island Prison by '||(select handle from public.game_players where id=uid));
     result:=jsonb_build_object('message','The lock opened. The inmate is free and you earned +'||reward||' power.','outcome','success','turn',90,'attempts_left',attempt.attempts_left-1,'reward_power',reward);
    else
     turn_amount:=greatest(8,least(75,78-round(distance*.75)::integer));
     if attempt.attempts_left<=1 then
      perform set_config('game.reason','Caught attempting a prison break for '||attempt.inmate_id,true);
      update game_private.prison_break_attempts set status='caught',attempts_left=0,last_turn=turn_amount,completed_at=stamp where id=attempt.id;
      insert into public.game_prison_sentences as p(season_id,player_id,reason,started_at,release_at,actor_id)
       values(s,uid,'Caught trying to break '||(select handle from public.game_players where id=target.player_id)||' out of prison',stamp,target.release_at,uid)
       on conflict(season_id,player_id) do update set id=gen_random_uuid(),reason=excluded.reason,started_at=excluded.started_at,release_at=excluded.release_at,released_at=null,actor_id=excluded.actor_id;
      insert into public.game_events(player_id,description) values(uid,'Caught during a Blackwater Island prison break. Sentence matched to the target inmate.');
      result:=jsonb_build_object('message','Caught. You are now serving the same remaining time as the inmate you tried to free.','outcome','caught','turn',turn_amount,'attempts_left',0,'release_at',target.release_at);
     else
      update game_private.prison_break_attempts set attempts_left=attempts_left-1,last_turn=turn_amount where id=attempt.id;
      result:=jsonb_build_object('message',case when turn_amount>=60 then 'Almost there. The cylinder nearly turned.' when turn_amount>=35 then 'The lock moved. Adjust the angle.' else 'The pick barely caught. Try farther away.' end,
       'outcome','continue','turn',turn_amount,'attempts_left',attempt.attempts_left-1);
     end if;
    end if;
   end if;
  else raise exception 'Choose a supported prison-break action.';end if;
  insert into game_private.prison_break_requests values(s,uid,nonce,p_action,p_payload,result,stamp);
  return result;
 exception
  when check_violation or not_null_violation or foreign_key_violation or numeric_value_out_of_range or invalid_text_representation then return jsonb_build_object('error','The lockpick move was invalid. Refresh and try again.');
  when raise_exception then return jsonb_build_object('error',SQLERRM);
 end;
end$$;

create or replace function game_private.prison_manage(p_action text,p_payload jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare s uuid;target_id uuid;sentence_id uuid;reason text:=trim(p_payload->>'reason');n integer;setting_row public.game_settings;
begin
 perform game_private.require_active();
 if not game_private.has_permission('prison.manage') then raise exception 'Owner permission required.';end if;
 s:=game_private.season_guard(false);
 if p_action='list' then
  return jsonb_build_object('sentences',(select coalesce(jsonb_agg(x),'[]') from (
   select p.id,p.player_id,g.handle,p.reason,p.started_at,p.release_at from public.game_prison_sentences p join public.game_players g on g.id=p.player_id
   where p.season_id=s and p.released_at is null and p.release_at>clock_timestamp() order by p.release_at limit 200)x),
   'reward_power',(select jsonb_build_object('value',value,'minimum',minimum,'maximum',maximum) from public.game_settings where key='prison_break_power'));
 end if;
 if reason is null or length(reason) not between 3 and 2000 then raise exception 'Enter a reason between 3 and 2000 characters.';end if;
 if p_action='configure_breakout' then
  n:=(p_payload->>'reward_power')::integer;select * into strict setting_row from public.game_settings where key='prison_break_power' for update;
  if n not between setting_row.minimum and setting_row.maximum then raise exception 'Choose a power reward within the allowed limits.';end if;
  perform set_config('game.reason','Prison-break reward: '||reason,true);update public.game_settings set value=n where key='prison_break_power';
  return jsonb_build_object('message','Prison-break power reward saved.','reward_power',n);
 end if;
 target_id:=(p_payload->>'player_id')::uuid;
 if p_action='jail' then
  sentence_id:=game_private.imprison(target_id,(p_payload->>'minutes')::integer,reason);
  return jsonb_build_object('message','Player transferred to Blackwater Island Prison.','sentence_id',sentence_id);
 elsif p_action='release' then
  perform pg_advisory_xact_lock(4704031);perform set_config('game.reason',reason,true);
  update public.game_prison_sentences set released_at=clock_timestamp() where season_id=s and player_id=target_id
   and id=(p_payload->>'sentence_id')::uuid and released_at is null and release_at>clock_timestamp();
  if not found then raise exception 'This sentence has already ended or changed. Refresh the prison register.';end if;
  return jsonb_build_object('message','Player released from Blackwater Island Prison.');
 end if;
 raise exception 'Unknown prison action.';
end$$;

create function public.prison_break_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$
 select game_private.prison_break_action(p_action,p_payload)
$$;
revoke all on function game_private.expire_prison_break(uuid,uuid,timestamptz),game_private.prison_break_action(text,jsonb),public.prison_break_action(text,jsonb) from public,anon,authenticated;
grant execute on function public.prison_break_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';

