
create function game_private.mining_finish(a public.game_plot_auctions,cancel_sale boolean default false) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare p public.game_district_plots;
begin
 select * into strict p from public.game_district_plots where id=a.plot_id for update;
 perform id from public.game_players where id in (a.bidder_id,a.seller_id) order by id for update;
 if cancel_sale or a.bidder_id is null then
  if a.escrow>0 then
   perform game_private.district_wallet(a.bidder_id,a.escrow,'Mine auction refund: '||p.code);
   insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(a.bidder_id,p.id,a.id,-a.escrow,'Mine auction reserve returned');
  end if;
  update public.game_plot_auctions set status=case when cancel_sale then 'cancelled' else 'expired' end,escrow=0 where id=a.id;
  update public.game_mines set operated_at=now() where plot_id=p.id;
  perform game_private.district_event(p.district_id,'property','plot_auction','Mine auction '||case when cancel_sale then 'cancelled' else 'ended without bids' end||': '||p.code,p.id);
 else
  update public.game_plot_auctions set status='sold',escrow=0 where id=a.id;
  insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(a.bidder_id,p.id,a.id,-a.escrow,'Mine auction settled');
  perform game_private.district_transfer(p,a.bidder_id,a.bid,a.escrow-a.bid,'auction');
 end if;
end $$;
create function game_private.mining_close_due(finalize boolean default false) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; a public.game_plot_auctions; r public.game_mining_runs;
begin
 s:=game_private.season_guard(false);
 if not finalize and not exists(select 1 from public.game_seasons where id=s and status='open' and (ends_at is null or ends_at>clock_timestamp())) then return;end if;
 perform pg_advisory_xact_lock(4704020);
 perform set_config('game.reason',case when finalize then 'Close mining before final season rankings' else 'Settle expired mine auction' end,true);
 for a in select a.* from public.game_plot_auctions a join public.game_mines m on m.plot_id=a.plot_id
  where m.season_id=s and a.status='open' and (finalize or a.ends_at<=now()) order by a.id for update of a loop
  perform game_private.mining_finish(a,finalize);
 end loop;
 if finalize then
  for r in select * from public.game_mining_runs where season_id=s and status='working' order by id for update loop
   update public.game_mines set remaining=remaining+r.quantity where id=r.mine_id;
   update public.game_mining_runs set status='cancelled',completed_at=now() where id=r.id;
  end loop;
 end if;
end $$;

create function game_private.mining_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; uid uuid:=auth.uid(); nonce uuid; previous game_private.mining_requests;
 m public.game_mines; def public.game_mine_definitions; p public.game_district_plots; d public.game_districts;
 a public.game_plot_auctions; r public.game_mining_runs; result jsonb; qty integer; durability integer; price bigint; minutes integer; finish_at timestamptz; batches integer;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
 s:=game_private.season_guard();
 if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the mines.';end if;
 nonce:=nullif(p_payload->>'request_id','')::uuid;
 if nonce is null then raise exception 'A request reference is required. Refresh and try again.';end if;
 perform pg_advisory_xact_lock(4704020);
 select * into previous from game_private.mining_requests where season_id=s and player_id=uid and request_id=nonce;
 if found then
  if previous.action<>p_action or previous.payload<>p_payload then raise exception 'This request reference was already used for another action.';end if;
  return previous.result;
 end if;
 perform game_private.ensure_districts(s);
 perform set_config('game.reason','Mining action: '||p_action,true);
 if p_action='pickaxe' then
  perform id from public.game_players where id=uid for update;
  price:=game_private.setting('mining_pickaxe_cost');
  if (p_payload->>'price')::bigint is distinct from price then raise exception 'The pickaxe price changed. Refresh first.';end if;
  if coalesce((select durability from public.game_mining_tools where season_id=s and player_id=uid),0)>=game_private.setting('mining_pickaxe_durability') then raise exception 'Your pickaxe is already in full condition.';end if;
  perform game_private.district_wallet(uid,-price,'Purchase mining pickaxe');
  insert into public.game_mining_tools(season_id,player_id,durability) values(s,uid,game_private.setting('mining_pickaxe_durability'))
  on conflict(season_id,player_id) do update set durability=excluded.durability;
  result:=jsonb_build_object('message','Pickaxe ready. Choose a public mine to start a shift.');
 else
  select * into m from public.game_mines where id=(p_payload->>'mine_id')::uuid and season_id=s for update;
  if m.id is null then raise exception 'Mine not found in this season.';end if;
  select * into strict def from public.game_mine_definitions where id=m.definition_id and archived_at is null;
  select * into strict p from public.game_district_plots where id=m.plot_id and archived_at is null for update;
  select * into strict d from public.game_districts where id=p.district_id and archived_at is null;
  select * into a from public.game_plot_auctions where plot_id=p.id and status='open' for update;
  if p_action not in ('claim','cancel','settle','cancel_auction') and (d.status='lockdown' or p.status='locked' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown')) then raise exception 'The district is under lockdown.';end if;
  case p_action
  when 'start' then
   if m.status<>'open' or (m.access_mode<>'public' and not(p.owner_type='player' and p.owner_id=uid)) or a.id is not null or p.asking_price is not null then raise exception 'This mine is not open to your crew.';end if;
   if exists(select 1 from public.game_mining_runs where season_id=s and player_id=uid and status='working') then raise exception 'Finish or cancel your current mining shift first.';end if;
   perform id from public.game_players where id=uid for update;
   select t.durability into durability from public.game_mining_tools t where season_id=s and player_id=uid for update;
   if coalesce(durability,0)<def.tool_wear then raise exception 'A usable pickaxe is required. Replace your pickaxe at the supply desk.';end if;
   qty:=least(def.hand_yield,m.remaining)::integer;
   if qty<1 then raise exception 'This deposit is exhausted.';end if;
   if coalesce((select quantity from public.game_inventory where season_id=s and player_id=uid and good_id=def.good_id),0)+qty>1000000 then raise exception 'Sell some of this resource before gathering more.';end if;
   finish_at:=now()+make_interval(secs=>def.hand_seconds);
   if exists(select 1 from public.game_seasons where id=s and ends_at is not null and finish_at>ends_at) then raise exception 'There is not enough time for a shift before the season ends.';end if;
   update public.game_mining_tools set durability=durability-def.tool_wear where season_id=s and player_id=uid;
   update public.game_mines set remaining=remaining-qty where id=m.id;
   insert into public.game_mining_runs(season_id,player_id,mine_id,good_id,quantity,respect,wear,ready_at)
   values(s,uid,m.id,def.good_id,qty,game_private.setting('mining_respect_per_shift'),def.tool_wear,finish_at) returning * into r;
   result:=jsonb_build_object('message','Shift started. Return when your resources are ready.','run_id',r.id);
  when 'claim','cancel' then
   select * into r from public.game_mining_runs where id=(p_payload->>'run_id')::uuid and player_id=uid and season_id=s and mine_id=m.id for update;
   if r.id is null or r.status<>'working' then raise exception 'This shift has already been completed or is not yours.';end if;
   perform id from public.game_players where id=uid for update;
   if p_action='claim' then
    if r.ready_at>now() then raise exception 'Your mining shift is still running.';end if;
    insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(s,uid,r.good_id,r.quantity)
    on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
    update public.game_players set xp=xp+r.respect where id=uid;
    insert into public.game_mining_yields(season_id,player_id,mine_id,good_id,quantity,source,run_id) values(s,uid,m.id,r.good_id,r.quantity,'hand_mining',r.id);
    perform game_private.record_metric(uid,'production',r.quantity);
    perform game_private.district_event(d.id,'resources','resource_extraction',game_private.district_owner_name('player',uid)||' mined '||r.quantity||' '||(select name from public.game_goods where id=r.good_id)||' at '||p.code,p.id,null,null,jsonb_build_object('quantity',r.quantity,'good_id',r.good_id));
    result:=jsonb_build_object('message',r.quantity||' resources added to your inventory. Trade them on the market.');
   else
    update public.game_mines set remaining=remaining+r.quantity where id=m.id;
    result:=jsonb_build_object('message','Shift cancelled. The reserved resources remain in the mine; pickaxe wear is retained.');
   end if;
   update public.game_mining_runs set status=case when p_action='claim' then 'claimed' else 'cancelled' end,completed_at=now() where id=r.id;
  when 'collect' then
   if p.owner_type<>'player' or p.owner_id<>uid or m.status<>'open' or a.id is not null or p.asking_price is not null then raise exception 'Only the owner can collect from an open, unlisted mine.';end if;
   perform id from public.game_players where id=uid for update;
   batches:=least(game_private.setting('mining_offline_cycles'),floor(extract(epoch from now()-m.operated_at)/def.operation_seconds)::integer);
   qty:=least(m.remaining,batches::bigint*def.operation_yield)::integer;
   if qty<1 then raise exception 'No extraction output is ready yet.';end if;
   insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(s,uid,def.good_id,qty)
   on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
   update public.game_mines set remaining=remaining-qty,operated_at=case when extract(epoch from now()-operated_at)>=game_private.setting('mining_offline_cycles')*def.operation_seconds then now() else operated_at+make_interval(secs=>batches*def.operation_seconds) end where id=m.id;
   insert into public.game_mining_yields(season_id,player_id,mine_id,good_id,quantity,source) values(s,uid,m.id,def.good_id,qty,'operation');
   perform game_private.record_metric(uid,'production',qty);
   perform game_private.district_event(d.id,'resources','resource_extraction',def.name||' delivered '||qty||' '||(select name from public.game_goods where id=def.good_id),p.id,null,null,jsonb_build_object('quantity',qty,'good_id',def.good_id));
   result:=jsonb_build_object('message',qty||' resources collected from your mine.');
  when 'auction' then
   if not (p.owner_type='player' and p.owner_id=uid) and not (p.owner_type='city' and game_private.has_permission('mines.manage')) then raise exception 'Only the property owner or the city Owner can auction this mine.';end if;
   if m.status<>'open' or a.id is not null or m.remaining<1 then raise exception 'Open an available mine with reserves before starting an auction.';end if;
   if exists(select 1 from public.game_mining_runs where mine_id=m.id and status='working') then raise exception 'Wait for all mining shifts to finish before auctioning this site.';end if;
   price:=(p_payload->>'price')::bigint;minutes:=(p_payload->>'minutes')::integer;
   if price is null or price not between 1 and 1000000000 or minutes is null or minutes not between game_private.setting('mining_auction_min_minutes') and game_private.setting('mining_auction_max_minutes') then raise exception 'Choose a valid minimum bid and auction duration.';end if;
   if length(trim(p_payload->>'reason')) not between 3 and 1000 or p_payload->>'reason' is null then raise exception 'Give a reason for the auction record.';end if;
   finish_at:=now()+make_interval(mins=>minutes);
   if exists(select 1 from public.game_seasons where id=s and ends_at is not null and finish_at>ends_at) then raise exception 'The auction must end before the season deadline.';end if;
   perform set_config('game.reason',p_payload->>'reason',true);
   insert into public.game_plot_auctions(plot_id,seller_id,city_sale,minimum_bid,tax_rate,ends_at)
   values(p.id,case when p.owner_type='player' then uid end,p.owner_type='city',price,coalesce(p.tax_rate,d.tax_rate),finish_at) returning * into a;
   update public.game_district_plots set asking_price=null,offers_allowed=false,version=version+1 where id=p.id;
   update public.game_mines set operated_at=now() where id=m.id;
   perform game_private.district_event(d.id,'property','plot_auction','Extraction rights auction opened for '||def.name,p.id,null,null,jsonb_build_object('auction_id',a.id,'minimum_bid',price,'ends_at',finish_at));
   result:=jsonb_build_object('message','Mine auction opened. Extraction is paused until the auction ends.','auction_id',a.id);
  when 'bid' then
   result:=game_private.district_act('bid',p_payload||jsonb_build_object('plot_id',p.id));
   result:=result||jsonb_build_object('message','Bid reserved. You will be refunded automatically if outbid.');
  when 'settle','cancel_auction' then
   if a.id is null then raise exception 'There is no open auction at this site.';end if;
   if p_action='settle' and a.ends_at>now() then raise exception 'This auction has not ended yet.';end if;
   if p_action='cancel_auction' and (a.bidder_id is not null or not((p.owner_type='player' and p.owner_id=uid) or (p.owner_type='city' and game_private.has_permission('mines.manage')))) then raise exception 'Only the seller can cancel an auction before its first bid.';end if;
   perform game_private.mining_finish(a,p_action='cancel_auction');
   result:=jsonb_build_object('message','Auction completed. The property registry has been updated.');
  else raise exception 'Unknown mining action.';
  end case;
 end if;
 insert into game_private.mining_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'mining failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The action was not saved. Refresh and check your inputs and inventory capacity.');
 end;
end $$;


create function game_private.mining_manage(p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; m public.game_mines; def public.game_mine_definitions; p public.game_district_plots; nonce uuid; previous game_private.mining_requests; result jsonb; stamp timestamptz;
begin
 perform game_private.require_active();
 if not game_private.has_permission('mines.manage') then raise exception 'Owner mining permission required.';end if;
 if not game_private.rate('mining_manage',60) then raise exception 'Too many edits. Try again shortly.';end if;
 begin
 s:=game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the mine controls.';end if;
 nonce:=nullif(p_payload->>'request_id','')::uuid;
 if nonce is null then raise exception 'A request reference is required.';end if;
 select * into previous from game_private.mining_requests where season_id=s and player_id=auth.uid() and request_id=nonce;
 if found then
  if previous.action<>'manage' or previous.payload<>p_payload then raise exception 'This request reference is already in use.';end if;
  return previous.result;
 end if;
 if length(trim(p_payload->>'reason')) not between 3 and 1000 or p_payload->>'reason' is null then raise exception 'Give a reason for the audit history.';end if;
 select * into m from public.game_mines where id=(p_payload->>'mine_id')::uuid and season_id=s for update;
 if m.id is null then raise exception 'Mine not found.';end if;
 select * into strict def from public.game_mine_definitions where id=m.definition_id for update;
 select * into strict p from public.game_district_plots where id=m.plot_id for update;
 if exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open') then raise exception 'Finish the auction before editing its advertised terms.';end if;
 if exists(select 1 from public.game_mining_runs where mine_id=m.id and status='working') then raise exception 'Wait for active shifts to finish before editing this site.';end if;
 perform set_config('game.reason',p_payload->>'reason',true);
 select * into def from jsonb_populate_record(def,p_payload-'id'-'plot_template_id'-'good_id');
 if def.tool_wear>game_private.setting('mining_pickaxe_durability') then raise exception 'Pickaxe wear cannot exceed a new pickaxe condition.';end if;
 select coalesce(locked_at,now()) into stamp from public.game_seasons where id=s;
 update public.game_mine_definitions set name=def.name,description=def.description,image_url=def.image_url,map_x=def.map_x,map_y=def.map_y,
  initial_status=coalesce(p_payload->>'status',m.status),initial_access=coalesce(p_payload->>'access_mode',m.access_mode),
  initial_reserve=coalesce((p_payload->>'remaining')::bigint,initial_reserve),hand_yield=def.hand_yield,hand_seconds=def.hand_seconds,
  tool_wear=def.tool_wear,operation_yield=def.operation_yield,operation_seconds=def.operation_seconds,transport=def.transport,survey_status=def.survey_status where id=m.definition_id;
 update public.game_mines set status=coalesce(p_payload->>'status',status),access_mode=coalesce(p_payload->>'access_mode',access_mode),
  remaining=coalesce((p_payload->>'remaining')::bigint,remaining),operated_at=stamp where id=m.id;
 if p_payload?'base_price' then
  if (p_payload->>'base_price')::bigint not between 1 and 1000000000 then raise exception 'Base value must be between $1 and $1 billion.';end if;
  update public.game_plot_templates set base_price=(p_payload->>'base_price')::bigint where id=p.template_id;
  update public.game_district_plots set base_price=(p_payload->>'base_price')::bigint,version=version+1 where id=p.id;
 end if;
 perform game_private.district_event(p.district_id,'resources','mining_access',def.name||' is '||coalesce(p_payload->>'status',m.status)||' · '||coalesce(p_payload->>'access_mode',m.access_mode)||' access',p.id);
 result:=jsonb_build_object('message','Mine saved. Access, rates and reserves are recorded in the audit history.');
 insert into game_private.mining_requests(season_id,player_id,request_id,action,payload,result) values(s,auth.uid(),nonce,'manage',p_payload,result);
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'mining management failure code=%',SQLSTATE;
  return jsonb_build_object('error','The mine was not changed. Check the values and try again.');
 end;
end $$;
create function game_private.mining_state(p_slug text default 'mines-and-quarries') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare world jsonb; s uuid; d uuid; stamp timestamptz;
begin
 perform game_private.require_active();
 perform game_private.mining_close_due();
 world:=game_private.district_state(p_slug);s:=(world->'season'->>'id')::uuid;d:=(world->'district'->>'id')::uuid;
 select case when status='locked' then locked_at else least(now(),coalesce(ends_at,now())) end into stamp from public.game_seasons where id=s;
 return jsonb_build_object('world',world,'can_manage',game_private.has_permission('mines.manage'),'server_time',now(),
 'playable',(select status='open' and (ends_at is null or ends_at>clock_timestamp()) from public.game_seasons where id=s),
 'season_end',(select ends_at from public.game_seasons where id=s),
 'sites',coalesce((select jsonb_agg(to_jsonb(def)||to_jsonb(m)||jsonb_build_object(
  'code',p.code,'district_id',p.district_id,'owner_type',p.owner_type,'owner_id',p.owner_id,
  'owner_name',game_private.district_owner_name(p.owner_type,p.owner_id),'base_price',p.base_price,
  'tax_rate',coalesce(p.tax_rate,(world->'district'->>'tax_rate')::numeric),
  'good_name',g.name,'active_shifts',(select count(*) from public.game_mining_runs r where r.mine_id=m.id and r.status='working'),
  'auction',(select to_jsonb(a)||jsonb_build_object('bidder_name',case when a.bidder_id is not null then game_private.district_owner_name('player',a.bidder_id) end) from public.game_plot_auctions a where a.plot_id=p.id and a.status='open'),
  'ready_output',case when m.status='open' and p.owner_type='player' and p.owner_id=auth.uid() and not exists(select 1 from public.game_plot_auctions where plot_id=p.id and status='open')
  then greatest(0,least(m.remaining,least(game_private.setting('mining_offline_cycles'),floor(extract(epoch from stamp-m.operated_at)/def.operation_seconds))::bigint*def.operation_yield)) else 0 end,
  'output_today',coalesce((select sum(quantity) from public.game_mining_yields where mine_id=m.id and created_at>=date_trunc('day',now())),0)) order by p.code)
  from public.game_mines m join public.game_mine_definitions def on def.id=m.definition_id
  join public.game_district_plots p on p.id=m.plot_id join public.game_goods g on g.id=def.good_id
  where m.season_id=s and p.district_id=d and p.archived_at is null and def.archived_at is null),'[]'),
 'tool',jsonb_build_object('durability',coalesce((select durability from public.game_mining_tools where season_id=s and player_id=auth.uid()),0)),
 'shift',(select to_jsonb(r)||jsonb_build_object('mine_name',def.name,'code',p.code,'good_name',g.name) from public.game_mining_runs r join public.game_mines m on m.id=r.mine_id join public.game_mine_definitions def on def.id=m.definition_id join public.game_district_plots p on p.id=m.plot_id join public.game_goods g on g.id=r.good_id where r.season_id=s and r.player_id=auth.uid() and r.status='working'),
 'inventory',coalesce((select jsonb_agg(jsonb_build_object('good_id',g.id,'name',g.name,'quantity',coalesce(i.quantity,0)) order by g.name) from public.game_goods g left join public.game_inventory i on i.good_id=g.id and i.season_id=s and i.player_id=auth.uid() where not g.business_available),'[]'),
 'history',coalesce((select jsonb_agg(q order by q.created_at desc) from (
  select y.*,def.name as mine_name,g.name as good_name from public.game_mining_yields y join public.game_mines m on m.id=y.mine_id join public.game_mine_definitions def on def.id=m.definition_id join public.game_goods g on g.id=y.good_id
  where y.season_id=s and y.player_id=auth.uid() order by y.created_at desc limit 30) q),'[]'),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'mining_%' or key='district_bid_increment'));
end $$;
create function game_private.mining_season_reopen() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status='locked' and new.status='open' and old.locked_at is not null then
  update public.game_mining_runs set ready_at=ready_at+(clock_timestamp()-old.locked_at) where season_id=new.id and status='working';
  update public.game_mines set operated_at=operated_at+(clock_timestamp()-old.locked_at) where season_id=new.id;
 end if;return new;
end $$;
create trigger mining_season_clock after update of status on public.game_seasons for each row execute function game_private.mining_season_reopen();
do $$
declare definition text;
begin
 select pg_get_functiondef('game_private.season_action(text,jsonb)'::regprocedure) into definition;
 if position('for board_config in select * from public.game_leaderboards' in definition)=0 then raise exception 'Unexpected season snapshot definition';end if;
 definition:=replace(definition,'for board_config in select * from public.game_leaderboards','perform game_private.mining_close_due(true);'||chr(10)||' for board_config in select * from public.game_leaderboards');
 execute definition;
end $$;
create function public.mining_state(p_slug text default 'mines-and-quarries') returns jsonb language sql security invoker set search_path='' as $$select game_private.mining_state(p_slug)$$;
create function public.mining_action(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.mining_action(p_action,p_payload)$$;
create function public.mining_manage(p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$select game_private.mining_manage(p_payload)$$;
revoke all on function game_private.mining_finish(public.game_plot_auctions,boolean),game_private.mining_close_due(boolean),game_private.mining_season_reopen(),
 game_private.mining_state(text),game_private.mining_action(text,jsonb),game_private.mining_manage(jsonb),
 public.mining_state(text),public.mining_action(text,jsonb),public.mining_manage(jsonb) from public,anon,authenticated;
grant execute on function game_private.mining_state(text),game_private.mining_action(text,jsonb),game_private.mining_manage(jsonb),
 public.mining_state(text),public.mining_action(text,jsonb),public.mining_manage(jsonb) to authenticated;
do $$
begin
 if exists(select 1 from pg_extension where extname='pg_cron') then
  perform cron.schedule('blackwater-mine-auctions','* * * * *','select game_private.mining_close_due();');
 end if;
end $$;

