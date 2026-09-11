
create function game_private.telegram_office_data() returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare o public.game_telegram_office; b public.game_district_businesses; p public.game_district_plots; d public.game_districts; manage boolean; operate boolean;
begin
 select * into strict o from public.game_telegram_office;
 select * into strict b from public.game_district_businesses where id=o.business_id;
 select * into strict p from public.game_district_plots where id=o.plot_id;
 select * into strict d from public.game_districts where id=p.district_id;
 manage:=game_private.has_permission('telegrams.manage');
 operate:=b.owner_type='player' and b.owner_id=auth.uid();
 return jsonb_build_object('name',b.name,'description',b.description,'fee',b.telegram_fee,'status',b.status,
 'available',o.available and b.status='open' and b.archived_at is null and d.archived_at is null and p.status<>'locked',
 'owner_type',b.owner_type,'owner_id',b.owner_id,'owner_name',game_private.district_owner_name(b.owner_type,b.owner_id),
 'plot_id',p.id,'plot_code',p.code,'district_name',d.name,'district_slug',d.slug,'building_id',b.building_id,'business_id',b.id,
 'asking_price',p.asking_price,'minimum_fee',o.minimum_fee,'maximum_fee',o.maximum_fee,'can_operate',operate,'can_manage',manage,
 'config',case when manage then to_jsonb(o) else null end,
 'history',coalesce((select jsonb_agg(x order by x.created_at desc) from (select h.*,game_private.district_owner_name(h.new_owner->>'type',(h.new_owner->>'id')::uuid) as new_owner_name from public.game_plot_ownership_history h where h.plot_id=p.id order by h.created_at desc limit 20)x),'[]'::jsonb),
 'stats',case when manage or operate then (
 select jsonb_build_object(
 'today_count',count(*) filter(where created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),
 'week_count',count(*) filter(where created_at>=now()-interval '7 days'),'season_count',count(*),
 'today_revenue',coalesce(sum(fee) filter(where created_at>=date_trunc('day',now() at time zone 'UTC') at time zone 'UTC'),0),
 'week_revenue',coalesce(sum(fee) filter(where created_at>=now()-interval '7 days'),0),'season_revenue',coalesce(sum(fee),0),
 'average_per_day',round(count(*)::numeric/greatest(1,extract(epoch from now()-(select created_at from public.game_seasons where id=o.season_id))/86400),1))
 from game_private.telegram_receipts where season_id=o.season_id) else null end,
 'hours',case when manage or operate then (select jsonb_agg(x order by x.hour) from
 (select h as hour,count(r.message_id) as count from generate_series(0,23) h left join game_private.telegram_receipts r on extract(hour from r.created_at at time zone 'UTC')=h and r.season_id=o.season_id group by h)x) else '[]'::jsonb end,
 'archives',case when manage or operate then coalesce((select jsonb_agg(x order by x.created_at desc) from
 (select s.id,s.name,s.created_at,count(r.message_id) as traffic,coalesce(sum(r.fee),0) as revenue from public.game_seasons s join game_private.telegram_receipts r on r.season_id=s.id where s.id<>o.season_id group by s.id)x),'[]'::jsonb) else '[]'::jsonb end,
 'locations',case when manage then (select jsonb_agg(jsonb_build_object('id',p0.id,'label',d0.name||' / '||p0.code,'owner_name',game_private.district_owner_name(p0.owner_type,p0.owner_id))) from public.game_district_plots p0 join public.game_districts d0 on d0.id=p0.district_id where p0.season_id=o.season_id and p0.archived_at is null and d0.archived_at is null) else '[]'::jsonb end);
end $$;

create function game_private.telegram_state(p_thread uuid default null,p_folder text default 'inbox',p_offset integer default 0,p_before uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; t game_private.telegram_threads; result jsonb;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_read',120) then raise exception 'Wait a moment before refreshing.'; end if;
 if not exists(select 1 from public.game_players where id=auth.uid()) then perform game_private.state(); end if;
 s:=game_private.season_guard(false);perform game_private.ensure_districts(s);
 if p_thread is not null then
  select * into t from game_private.telegram_threads where id=p_thread and auth.uid() in(first_player,second_player);
  if t.id is null then raise exception 'Conversation unavailable.'; end if;
  insert into game_private.telegram_folders(player_id,thread_id,read_at) values(auth.uid(),t.id,now())
  on conflict(player_id,thread_id) do update set read_at=now();
 end if;
 select jsonb_build_object('player_id',auth.uid(),'cash',(select cash from public.game_players where id=auth.uid()),
 'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),
 'office',game_private.telegram_office_data(),'server_time',now(),
 'limits',jsonb_build_object('subject',game_private.setting('telegram_subject_limit'),'body',game_private.setting('telegram_body_limit')),
 'unread',(select count(*) from game_private.telegrams m left join game_private.telegram_folders f on f.thread_id=m.thread_id and f.player_id=auth.uid() where m.recipient_id=auth.uid() and m.created_at>coalesce(f.read_at,'-infinity'::timestamptz)),
 'thread',case when t.id is null then null else to_jsonb(t)||jsonb_build_object('other_id',case when t.first_player=auth.uid() then t.second_player else t.first_player end,'other_name',game_private.district_owner_name('player',case when t.first_player=auth.uid() then t.second_player else t.first_player end)) end,
 'threads',coalesce((select jsonb_agg(x order by x.last_at desc,x.id) from (
  select t0.id,t0.subject,case when t0.first_player=auth.uid() then t0.second_player else t0.first_player end as other_id,
  game_private.district_owner_name('player',case when t0.first_player=auth.uid() then t0.second_player else t0.first_player end) as other_name,
  m.created_at as last_at,left(m.body,90) as excerpt,coalesce(f.archived,false) as archived,coalesce(f.starred,false) as starred,
  (select count(*) from game_private.telegrams u where u.thread_id=t0.id and u.recipient_id=auth.uid() and u.created_at>coalesce(f.read_at,'-infinity'::timestamptz)) as unread
  from game_private.telegram_threads t0
  join lateral(select body,created_at from game_private.telegrams where thread_id=t0.id order by created_at desc,id desc limit 1)m on true
  left join game_private.telegram_folders f on f.thread_id=t0.id and f.player_id=auth.uid()
  where auth.uid() in(t0.first_player,t0.second_player) and
   case p_folder when 'archive' then coalesce(f.archived,false) when 'starred' then coalesce(f.starred,false)
    when 'sent' then not coalesce(f.archived,false) and exists(select 1 from game_private.telegrams where thread_id=t0.id and sender_id=auth.uid())
    else not coalesce(f.archived,false) end
  order by m.created_at desc,t0.id limit 50 offset greatest(0,least(coalesce(p_offset,0),100000)))x),'[]'::jsonb),
 'messages',coalesce((select jsonb_agg(x order by x.created_at,x.id) from (
  select m.id,m.thread_id,m.sender_id,m.recipient_id,m.body,m.created_at,game_private.district_owner_name('player',m.sender_id) as sender_name
  from game_private.telegrams m where m.thread_id=t.id and (p_before is null or (m.created_at,m.id)<(select created_at,id from game_private.telegrams where id=p_before and thread_id=t.id))
  order by m.created_at desc,m.id desc limit 50)x),'[]'::jsonb),
 'drafts',coalesce((select jsonb_agg(x order by x.updated_at desc) from(select id,recipient,subject,body,updated_at from game_private.telegram_drafts where player_id=auth.uid() and deleted_at is null order by updated_at desc limit 100)x),'[]'::jsonb),
 'blocks',coalesce((select jsonb_agg(jsonb_build_object('id',blocked_id,'name',game_private.district_owner_name('player',blocked_id))) from game_private.telegram_blocks where player_id=auth.uid()),'[]'::jsonb),
 'reports',coalesce((select jsonb_agg(jsonb_build_object('id',r.case_id,'message_id',r.message_id,'status',c.status,'response',c.response,'created_at',r.created_at) order by r.created_at desc) from game_private.telegram_reports r join public.game_cases c on c.id=r.case_id where r.reporter_id=auth.uid()),'[]'::jsonb)
 ) into result;return result;
end $$;

create function game_private.telegram_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; o public.game_telegram_office; b public.game_district_businesses; t game_private.telegram_threads; m game_private.telegrams;
 recipient uuid; payee uuid; new_id uuid; draft uuid; amount bigint; old_balance bigint; subject text; body text; request uuid;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_action',game_private.setting('telegram_send_rate')) then return jsonb_build_object('error','Too many telegram actions. Try again shortly.'); end if;
 begin
 s:=game_private.season_guard(p_action='send');perform pg_advisory_xact_lock(4704020);perform game_private.ensure_districts(s);
 if p_action='send' then
  request:=(p_payload->>'request_id')::uuid;
  if request is null then raise exception 'Refresh the composer before sending.'; end if;
  select * into m from game_private.telegrams where sender_id=auth.uid() and request_id=request;
  if m.id is not null then return jsonb_build_object('message','Telegram already delivered.','thread_id',m.thread_id); end if;
  if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Review the current delivery fee.'; end if;
  if exists(select 1 from public.game_sanctions where player_id=auth.uid() and kind='mute' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'You are muted.'; end if;
  if nullif(p_payload->>'thread_id','') is not null then
   select * into t from game_private.telegram_threads where id=(p_payload->>'thread_id')::uuid and auth.uid() in(first_player,second_player);
   if t.id is null then raise exception 'Conversation unavailable.'; end if;
   recipient:=case when t.first_player=auth.uid() then t.second_player else t.first_player end;
  else
   select i.player_id into recipient from game_private.identities i join public.game_players p on p.id=i.player_id where lower(i.username)=lower(trim(p_payload->>'recipient')) and p.deleted_at is null;
  end if;
  if recipient is null or recipient=auth.uid() or not exists(select 1 from public.game_players where id=recipient and deleted_at is null)
   or exists(select 1 from public.game_sanctions where player_id=recipient and kind='ban' and revoked_at is null and (expires_at is null or expires_at>now()))
   or exists(select 1 from game_private.telegram_blocks where (player_id=recipient and blocked_id=auth.uid()) or (player_id=auth.uid() and blocked_id=recipient)) then raise exception 'This recipient is unavailable for telegrams.'; end if;
  subject:=trim(coalesce(p_payload->>'subject',''));body:=trim(coalesce(p_payload->>'body',''));
  if length(body) not between 1 and game_private.setting('telegram_body_limit') or (t.id is null and length(subject) not between 1 and game_private.setting('telegram_subject_limit')) then raise exception 'Check the subject and message length.'; end if;
  select * into strict o from public.game_telegram_office for update;
  select * into strict b from public.game_district_businesses where id=o.business_id for update;
  if not o.available or b.status<>'open' or b.archived_at is not null or exists(select 1 from public.game_district_plots p join public.game_districts d on d.id=p.district_id where p.id=o.plot_id and (p.status='locked' or d.archived_at is not null)) then raise exception 'Telegram service is currently unavailable.'; end if;
  amount:=b.telegram_fee;
  if (p_payload->>'fee')::bigint is distinct from amount then raise exception 'The delivery fee changed. Review the new fee before sending.'; end if;
  payee:=case when b.owner_type='player' then b.owner_id else (select payout_player_id from public.game_district_entities where id=b.owner_id) end;
  perform id from public.game_players where id in(auth.uid(),payee) order by id for update;
  if (select cash from public.game_players where id=auth.uid())<amount then raise exception 'Not enough cash for this telegram.'; end if;
  if t.id is null then insert into game_private.telegram_threads(first_player,second_player,subject) values(auth.uid(),recipient,subject) returning * into t; end if;
  insert into game_private.telegrams(thread_id,sender_id,recipient_id,body,season_id,request_id)
   values(t.id,auth.uid(),recipient,body,s,request) returning id into new_id;
  if amount>0 then
   perform game_private.district_wallet(auth.uid(),-amount,'Telegram delivery fee');
   if payee is not null then perform game_private.district_wallet(payee,amount,'Telegram Office revenue'); end if;
  end if;
  if payee is null then
   insert into game_private.telegram_accounts(season_id,owner_type,owner_id) values(s,b.owner_type,b.owner_id) on conflict do nothing;
   select balance into old_balance from game_private.telegram_accounts where season_id=s and owner_type=b.owner_type and owner_id=b.owner_id for update;
   update game_private.telegram_accounts set balance=balance+amount where season_id=s and owner_type=b.owner_type and owner_id=b.owner_id;
   insert into game_private.telegram_account_ledger(season_id,owner_type,owner_id,message_id,delta,balance_before,balance_after,reason)
    values(s,b.owner_type,b.owner_id,new_id,amount,old_balance,old_balance+amount,'Telegram Office revenue');
  end if;
  insert into game_private.telegram_receipts(message_id,season_id,business_id,owner_type,owner_id,payout_player_id,fee) values(new_id,s,b.id,b.owner_type,b.owner_id,payee,amount);
  insert into game_private.telegram_folders(player_id,thread_id,archived,read_at) values(auth.uid(),t.id,false,now())
   on conflict(player_id,thread_id) do update set archived=false,read_at=now();
  insert into game_private.telegram_folders(player_id,thread_id,archived) values(recipient,t.id,false)
   on conflict(player_id,thread_id) do update set archived=false;
  if nullif(p_payload->>'draft_id','') is not null then update game_private.telegram_drafts set deleted_at=now() where id=(p_payload->>'draft_id')::uuid and player_id=auth.uid(); end if;
  return jsonb_build_object('message','Telegram delivered instantly.','thread_id',t.id,'fee',amount);
 elsif p_action in ('archive','star') then
  select * into t from game_private.telegram_threads where id=(p_payload->>'thread_id')::uuid and auth.uid() in(first_player,second_player);
  if t.id is null then raise exception 'Conversation unavailable.'; end if;
  insert into game_private.telegram_folders(player_id,thread_id) values(auth.uid(),t.id) on conflict do nothing;
  if p_action='archive' then update game_private.telegram_folders set archived=not archived where thread_id=t.id and player_id=auth.uid();
  else update game_private.telegram_folders set starred=not starred where thread_id=t.id and player_id=auth.uid();end if;
 elsif p_action in ('draft','delete_draft') then
  draft:=nullif(p_payload->>'id','')::uuid;
  if draft is not null and not exists(select 1 from game_private.telegram_drafts where id=draft and player_id=auth.uid() and deleted_at is null) then raise exception 'Draft unavailable.'; end if;
  if p_action='delete_draft' then update game_private.telegram_drafts set deleted_at=now() where id=draft and player_id=auth.uid();
  elsif draft is null then insert into game_private.telegram_drafts(player_id,recipient,subject,body) values(auth.uid(),left(coalesce(p_payload->>'recipient',''),80),coalesce(p_payload->>'subject',''),coalesce(p_payload->>'body','')) returning id into draft;
  else update game_private.telegram_drafts set recipient=left(coalesce(p_payload->>'recipient',''),80),subject=coalesce(p_payload->>'subject',''),body=coalesce(p_payload->>'body',''),updated_at=now() where id=draft and player_id=auth.uid();end if;
  return jsonb_build_object('message','Draft saved.','draft_id',draft);
 elsif p_action in ('block','unblock') then
  recipient:=(p_payload->>'player_id')::uuid;
  if recipient=auth.uid() or recipient is null then raise exception 'Choose another player.'; end if;
  if p_action='block' then insert into game_private.telegram_blocks(player_id,blocked_id) values(auth.uid(),recipient) on conflict do nothing;
  else delete from game_private.telegram_blocks where player_id=auth.uid() and blocked_id=recipient;end if;
 elsif p_action='report' then
  select * into m from game_private.telegrams where id=(p_payload->>'message_id')::uuid and recipient_id=auth.uid();
  if m.id is null then raise exception 'You can report only a telegram sent to you.'; end if;
  body:=trim(coalesce(p_payload->>'reason',''));
  if length(body) not between 3 and 2000 then raise exception 'Explain the report in 3 to 2000 characters.';end if;
  if exists(select 1 from game_private.telegram_reports where message_id=m.id and reporter_id=auth.uid()) then raise exception 'This telegram has already been reported.'; end if;
  insert into public.game_cases(player_id,kind,subject,body) values(auth.uid(),'report','Reported telegram',body) returning id into new_id;
  insert into game_private.telegram_reports(case_id,message_id,reporter_id) values(new_id,m.id,auth.uid());
  return jsonb_build_object('message','Report submitted. Only this telegram can be inspected as evidence.');
 else raise exception 'Unknown telegram action.';end if;
 return jsonb_build_object('message','Saved.');
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'telegram action failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The telegram action could not be completed. No payment was taken.');
 end;
end $$;


create function game_private.telegram_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; o public.game_telegram_office; b public.game_district_businesses; p public.game_district_plots; dest public.game_district_plots;
 admin boolean; own boolean; reason text; fee integer; target uuid; city uuid; kind text; recipient text;
begin
 perform game_private.require_active();
 if not game_private.rate('telegram_manage',30) then return jsonb_build_object('error','Too many edits. Try again shortly.');end if;
 begin
 s:=game_private.season_guard(p_action in ('transfer','relocate','sale'));perform pg_advisory_xact_lock(4704020);perform game_private.ensure_districts(s);
 select * into strict o from public.game_telegram_office for update;
 select * into strict b from public.game_district_businesses where id=o.business_id for update;
 select * into strict p from public.game_district_plots where id=o.plot_id for update;
 admin:=game_private.has_permission('telegrams.manage');own:=b.owner_type='player' and b.owner_id=auth.uid();
 if not admin and not own then raise exception 'Only the office owner can manage this property.';end if;
 if p_action not in ('office','transfer') and not admin then raise exception 'Game Owner permission required.';end if;
 reason:=trim(coalesce(p_payload->>'reason',''));
 if length(reason) not between 3 and 1000 then raise exception 'Give a reason for the audit history.';end if;
 perform set_config('game.reason',reason,true);
 if p_action='office' or p_action='config' then
  fee:=(p_payload->>'fee')::integer;
  if p_action='config' then
   update public.game_telegram_office set minimum_fee=(p_payload->>'minimum_fee')::integer,maximum_fee=(p_payload->>'maximum_fee')::integer,
    default_fee=(p_payload->>'default_fee')::integer,available=(p_payload->>'available')::boolean,
    reset_sale_price=(p_payload->>'reset_sale_price')::bigint,updated_at=now();
  end if;
  if fee is null or length(trim(coalesce(p_payload->>'name',''))) not between 2 and 80
   or length(coalesce(p_payload->>'description',''))>1000 or coalesce(p_payload->>'status','') not in ('open','closed') then raise exception 'Check the office name, fee and status.';end if;
  update public.game_district_businesses set name=trim(p_payload->>'name'),description=coalesce(p_payload->>'description',''),status=p_payload->>'status',telegram_fee=fee where id=b.id;
  perform game_private.district_event(p.district_id,'business',case when fee<>b.telegram_fee then 'telegram_fee_change' else 'telegram_office_update' end,'Blackwater Telegram Office terms updated',p.id,b.id,null,jsonb_build_object('fee',fee,'status',p_payload->>'status'));
 elsif p_action in ('transfer','relocate','sale') then
  if exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') or exists(select 1 from public.game_plot_offers where plot_id=p.id and status='open') then raise exception 'Settle the property auction and offers first.';end if;
  if p_action='sale' then
   if p.owner_type not in ('city','company') then raise exception 'Player owners list their property in Districts.';end if;
   update public.game_district_plots set asking_price=nullif(p_payload->>'price','')::bigint,version=version+1 where id=p.id;
  elsif p_action='transfer' then
   if p.asking_price is not null then raise exception 'Withdraw the sale listing before transferring this property.';end if;
   if p_payload->>'recipient'='state' and admin then
    select entity_id into city from public.game_plot_templates where id=o.template_id;
    if city is null then raise exception 'Configure a city owner first.';end if;
    insert into public.game_plot_ownership_history(plot_id,previous_owner,new_owner,actor_id,reason)
    values(p.id,jsonb_build_object('type',p.owner_type,'id',p.owner_id),jsonb_build_object('type','city','id',city),auth.uid(),reason);
    update public.game_district_plots set owner_type='city',owner_id=city,offers_allowed=false,version=version+1 where id=p.id;
    update public.game_district_buildings set owner_type='city',owner_id=city where id=o.building_id;
    update public.game_district_businesses set owner_type='city',owner_id=city where id=b.id;
   else
    select i.player_id into target from game_private.identities i join public.game_players pl on pl.id=i.player_id where lower(i.username)=lower(trim(p_payload->>'recipient')) and pl.deleted_at is null;
    if target is null or (p.owner_type='player' and target=p.owner_id) then raise exception 'Choose another active player.';end if;
    if exists(select 1 from public.game_sanctions where player_id=target and kind='ban' and revoked_at is null and (expires_at is null or expires_at>now())) then raise exception 'This player is unavailable.';end if;
    perform id from public.game_players where id in(target,p.owner_id,auth.uid()) order by id for update;
    perform game_private.district_transfer(p,target,0,0,case when admin then 'Owner Telegram Office transfer' else 'Telegram Office gift' end);
   end if;
  else
   if p.asking_price is not null then raise exception 'Withdraw the property sale before relocating.';end if;
   select * into dest from public.game_district_plots where id=(p_payload->>'plot_id')::uuid and season_id=s and archived_at is null for update;
   if dest.id is null or dest.id=p.id or dest.status in ('locked','reserved')
    or exists(select 1 from public.game_districts where id=dest.district_id and archived_at is not null)
    or exists(select 1 from public.game_district_buildings where plot_id=dest.id and archived_at is null)
    or exists(select 1 from public.game_plot_auctions where plot_id=dest.id and status='open')
    or exists(select 1 from public.game_plot_offers where plot_id=dest.id and status='open') or dest.asking_price is not null
    then raise exception 'Choose an empty, unlisted, available destination plot.';end if;
   if dest.owner_id is not null and (dest.owner_id<>p.owner_id or dest.owner_type<>p.owner_type) then raise exception 'The destination must have the same owner or be unclaimed.';end if;
   select entity_id into city from public.game_plot_templates where id=o.template_id;
   -- Preserve the old property title; the entire building/business moves to the new plot.
   update public.game_plot_templates set building_type=null,business_name=null,strategic_type=null where id=o.template_id;
   update public.game_plot_templates set building_type='telegram',entity_id=city,status='owned',business_name='Blackwater Telegram Office',strategic_type='Unique Telegram Office' where id=dest.template_id;
   update public.game_telegram_office set template_id=dest.template_id,plot_id=dest.id,updated_at=now();
   insert into public.game_plot_ownership_history(plot_id,previous_owner,new_owner,actor_id,reason)
    values(dest.id,jsonb_build_object('type',dest.owner_type,'id',dest.owner_id),jsonb_build_object('type',p.owner_type,'id',p.owner_id),auth.uid(),reason);
   update public.game_district_plots set owner_type=p.owner_type,owner_id=p.owner_id,status='owned',strategic_type='Unique Telegram Office',version=version+1 where id=dest.id;
   update public.game_district_plots set strategic_type=null,version=version+1 where id=p.id;
   update public.game_district_buildings set plot_id=dest.id where id=o.building_id;
   update public.game_district_businesses set plot_id=dest.id,district_id=dest.district_id where id=b.id;
   perform game_private.district_event(dest.district_id,'system','telegram_relocation','The unique Telegram Office relocated to '||dest.code,dest.id,b.id);
  end if;
 else raise exception 'Unknown office action.';end if;
 insert into public.game_audit(actor_id,action,target,after_data,reason) values(auth.uid(),'telegram_manage.'||p_action,b.id::text,p_payload-'reason',reason);
 return jsonb_build_object('message','Office updated. The change is recorded in audit history.');
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'telegram management failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','Check the office fields. The change was not saved.');
 end;
end $$;

create function game_private.telegram_evidence(p_case uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform game_private.require_active();
 if not game_private.has_permission('reports.review') or not game_private.has_permission('evidence.view') then raise exception 'Report review and evidence permissions are required.';end if;
 if not game_private.rate('telegram_evidence',30) then raise exception 'Too many evidence reads.';end if;
 select jsonb_build_object('message_id',m.id,'subject',t.subject,'body',m.body,'sender_name',game_private.district_owner_name('player',m.sender_id),'recipient_name',game_private.district_owner_name('player',m.recipient_id),'created_at',m.created_at)
 into result from game_private.telegram_reports r join public.game_cases c on c.id=r.case_id join game_private.telegrams m on m.id=r.message_id join game_private.telegram_threads t on t.id=m.thread_id
 where c.id=p_case and c.kind='report' and c.status='investigating';
 if result is null then raise exception 'Open a specific Telegram report and set it to investigating before inspecting evidence.';end if;
 insert into public.game_audit(actor_id,action,target,reason) values(auth.uid(),'telegram.evidence_read',p_case::text,'Inspected the specifically reported telegram');
 return result;
end $$;
create function public.telegram_state(p_thread uuid default null,p_folder text default 'inbox',p_offset integer default 0,p_before uuid default null) returns jsonb language sql security invoker set search_path='' as $$select game_private.telegram_state(p_thread,p_folder,p_offset,p_before)$$;
create function public.telegram_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.telegram_action(p_action,p_payload)$$;
create function public.telegram_manage(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.telegram_manage(p_action,p_payload)$$;
create function public.telegram_evidence(p_case uuid) returns jsonb language sql security invoker set search_path='' as $$select game_private.telegram_evidence(p_case)$$;
revoke all on function game_private.telegram_office_data(),game_private.telegram_state(uuid,text,integer,uuid),game_private.telegram_action(text,jsonb),game_private.telegram_manage(text,jsonb),game_private.telegram_evidence(uuid),public.telegram_state(uuid,text,integer,uuid),public.telegram_action(text,jsonb),public.telegram_manage(text,jsonb),public.telegram_evidence(uuid) from public,anon,authenticated;
grant execute on function game_private.telegram_state(uuid,text,integer,uuid),game_private.telegram_action(text,jsonb),game_private.telegram_manage(text,jsonb),game_private.telegram_evidence(uuid),public.telegram_state(uuid,text,integer,uuid),public.telegram_action(text,jsonb),public.telegram_manage(text,jsonb),public.telegram_evidence(uuid) to authenticated;


-- Reset the office in the same transaction as the season switch.
create function game_private.telegram_season_switch() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.season_id is distinct from old.season_id then perform game_private.ensure_districts(new.season_id);end if;
 return new;
end $$;
create trigger telegram_season_switch after update of season_id on game_private.season_runtime for each row execute function game_private.telegram_season_switch();
revoke all on function game_private.telegram_season_switch() from public,anon,authenticated;


-- Wallet statements identify office income without identifying private senders.
-- The private receipt and message retain the complete accounting relationship.
create function game_private.telegram_receipt_privacy() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.reason='Telegram Office revenue' then new.actor_id:=null;end if;
 return new;
end $$;
create trigger telegram_receipt_privacy before insert on public.game_ledger for each row execute function game_private.telegram_receipt_privacy();
revoke all on function game_private.telegram_receipt_privacy() from public,anon,authenticated;


-- Realtime carries only an account's mailbox revision, never message text or peers.
create table public.game_telegram_signals (
 player_id uuid primary key references public.game_players(id), revision bigint not null default 1
);
alter table public.game_telegram_signals enable row level security;
revoke all on public.game_telegram_signals from public,anon,authenticated;
grant select on public.game_telegram_signals to authenticated;
create policy own_mailbox_revision on public.game_telegram_signals for select to authenticated using(player_id=(select auth.uid()));
create function game_private.telegram_signal() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.game_telegram_signals as signal(player_id) values(new.sender_id),(new.recipient_id)
 on conflict(player_id) do update set revision=signal.revision+1;
 return new;
end $$;
create trigger telegram_signal after insert on game_private.telegrams for each row execute function game_private.telegram_signal();
revoke all on function game_private.telegram_signal() from public,anon,authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.game_telegram_signals;
 end if;
end $$;

