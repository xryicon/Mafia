-- Pickaxes are discovery equipment. Keep existing tools and financial history intact.
-- Removing the server purchase path also rejects requests from older open browser tabs.
create or replace function game_private.mining_action(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; uid uuid:=auth.uid(); nonce uuid; previous game_private.mining_requests;
 m public.game_mines; def public.game_mine_definitions; p public.game_district_plots; d public.game_districts;
 a public.game_plot_auctions; r public.game_mining_runs; result jsonb; qty integer; durability integer; price bigint; minutes integer; finish_at timestamptz; batches integer;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.');end if;
 begin
 if p_action='pickaxe' then raise exception 'Pickaxes cannot be purchased. Finding equipment will be available in a future update.';end if;
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
   if coalesce(durability,0)<def.tool_wear then raise exception 'A usable pickaxe is required. Finding equipment will be available in a future update.';end if;
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
 insert into game_private.mining_requests(season_id,player_id,request_id,action,payload,result) values(s,uid,nonce,p_action,p_payload,result);
 return result;
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM);end if;
  raise log 'mining failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The action was not saved. Refresh and check your inputs and inventory capacity.');
 end;
end $$;
