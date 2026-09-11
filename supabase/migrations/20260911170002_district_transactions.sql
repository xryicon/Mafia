
create function game_private.district_wallet(p uuid,delta bigint,reason text) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
begin
 perform set_config('game.reason',reason,true);
 update public.game_players set cash=cash+delta where id=p and season_id=game_private.current_season() and cash+delta>=0;
 if not found then raise exception 'Not enough cash, or this account is unavailable.'; end if;
end $$;
create function game_private.district_transfer(p public.game_district_plots,buyer uuid,price bigint,tax bigint,method text) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare sale uuid; o public.game_plot_offers;
begin
 if p.owner_type='player' then perform game_private.district_wallet(p.owner_id,price,'Property sale: '||p.code);
 elsif p.owner_type in ('company','city') then
  if exists(select 1 from public.game_district_entities where id=p.owner_id and payout_player_id is not null) then
   perform game_private.district_wallet((select payout_player_id from public.game_district_entities where id=p.owner_id),price,'Company property sale: '||p.code);
  end if;
 end if;
 insert into public.game_property_sales(season_id,plot_id,buyer_id,seller_type,seller_id,price,tax,method)
 values(p.season_id,p.id,buyer,p.owner_type,p.owner_id,price,tax,method) returning id into sale;
 insert into public.game_plot_ownership_history(plot_id,previous_owner,new_owner,sale_id,actor_id,reason)
 values(p.id,jsonb_build_object('type',p.owner_type,'id',p.owner_id),jsonb_build_object('type','player','id',buyer),sale,auth.uid(),method);
 update public.game_district_plots set owner_type='player',owner_id=buyer,status='owned',asking_price=null,offers_allowed=false,version=version+1 where id=p.id;
 update public.game_district_buildings set owner_type='player',owner_id=buyer where plot_id=p.id and archived_at is null;
 update public.game_district_businesses set owner_type='player',owner_id=buyer,collected_at=now() where plot_id=p.id and archived_at is null;
 for o in select * from public.game_plot_offers where plot_id=p.id and status='open' loop
  perform game_private.district_wallet(o.buyer_id,o.escrow,'Refund property offer: '||p.code);
  insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(o.buyer_id,p.id,o.id,-o.escrow,'Offer refunded after title transfer');
  update public.game_plot_offers set status='cancelled' where id=o.id;
 end loop;
 perform game_private.district_event(p.district_id,'property','property_sale',p.code||' sold for $'||price,p.id,null,null,jsonb_build_object('sale_id',sale,'price',price,'tax',tax,'buyer_id',buyer));
end $$;
create function game_private.district_act(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; p public.game_district_plots; d public.game_districts; a public.game_plot_auctions; o public.game_plot_offers;
 bt public.game_building_types; b public.game_district_buildings; biz public.game_district_businesses;
 price bigint; tax bigint; total bigint; amount bigint; gid uuid; topgang uuid; totalinfluence numeric; points bigint;
 own boolean; result jsonb; new_id uuid; batches integer; quantity integer;
begin
 s:=game_private.season_guard();
 if (payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the district.'; end if;
 perform pg_advisory_xact_lock(4704020);
 if action in ('job','influence') then
  select * into d from public.game_districts where id=(payload->>'district_id')::uuid and archived_at is null;
 else
  select * into p from public.game_district_plots where id=(payload->>'plot_id')::uuid and season_id=s and archived_at is null for update;
  if p.id is null then raise exception 'Plot not found in the current season.'; end if;
  select * into d from public.game_districts where id=p.district_id and archived_at is null;
 end if;
 if d.id is null then raise exception 'District unavailable.'; end if;
 if (d.status='lockdown' or exists(select 1 from public.game_district_territory where season_id=s and district_id=d.id and status='lockdown'))
 and action not in ('watch','offer_cancel','auction_finish','unlist') then raise exception 'This district is under lockdown.'; end if;
 select * into a from public.game_plot_auctions where plot_id=p.id and status='open' for update;
 -- Shared with the market: every affected wallet is locked in UUID order.
 perform id from public.game_players where id in (
  select auth.uid() union select p.owner_id where p.owner_type='player' union select a.bidder_id
  union select buyer_id from public.game_plot_offers where plot_id=p.id and status='open'
  union select payout_player_id from public.game_district_entities where id=p.owner_id
 ) order by id for update;
 own:=p.owner_type='player' and p.owner_id=auth.uid();
 price:=coalesce(p.asking_price,ceil(p.base_price*d.property_value_index/100));
 tax:=ceil(price*coalesce(p.tax_rate,d.tax_rate)/100);
 total:=price+tax;
 perform set_config('game.reason','District action: '||action,true);
 case action
 when 'watch' then
  if exists(select 1 from public.game_plot_watchlists where player_id=auth.uid() and plot_id=p.id) then
   delete from public.game_plot_watchlists where player_id=auth.uid() and plot_id=p.id;
  else insert into public.game_plot_watchlists(player_id,plot_id) values(auth.uid(),p.id); end if;
 when 'buy' then
  if own or a.id is not null or not(p.status='available' or (p.status='owned' and p.asking_price is not null)) then raise exception 'This plot is no longer for sale.'; end if;
  if p.owner_type='gang' then raise exception 'Gang property cannot be sold through individual wallets.'; end if;
  if (payload->>'version')::integer is distinct from p.version or (payload->>'total')::bigint is distinct from total then raise exception 'The quote changed. Refresh before purchasing.'; end if;
  perform game_private.district_wallet(auth.uid(),-total,'Buy plot: '||p.code);
  perform game_private.district_transfer(p,auth.uid(),price,tax,'purchase');
 when 'sell' then
  if not own or a.id is not null then raise exception 'Only the owner can list this plot.'; end if;
  price:=(payload->>'price')::bigint;
  if price is null or price<=0 then raise exception 'Enter a positive asking price.'; end if;
  update public.game_district_plots set asking_price=price,offers_allowed=coalesce((payload->>'offers_allowed')::boolean,false),version=version+1 where id=p.id;
  perform game_private.district_event(d.id,'property','property_listing',p.code||' listed for $'||price,p.id);
 when 'unlist' then
  if not own or a.id is not null then raise exception 'Only the owner can withdraw a sale.'; end if;
  update public.game_district_plots set asking_price=null,offers_allowed=false,version=version+1 where id=p.id;
 when 'auction' then
  if not own or a.id is not null then raise exception 'This plot cannot be auctioned.'; end if;
  price:=(payload->>'price')::bigint;
  if price is null or price<=0 then raise exception 'Enter a positive minimum bid.'; end if;
  insert into public.game_plot_auctions(plot_id,seller_id,minimum_bid,tax_rate,ends_at)
  values(p.id,auth.uid(),price,coalesce(p.tax_rate,d.tax_rate),now()+make_interval(hours=>game_private.setting('district_auction_hours')));
  update public.game_district_plots set asking_price=null,offers_allowed=false,version=version+1 where id=p.id;
  perform game_private.district_event(d.id,'property','plot_auction','Auction opened for '||p.code,p.id);
 when 'bid' then
  price:=(payload->>'price')::bigint;
  if a.id is null or own or a.ends_at<=now() then raise exception 'This auction is not accepting your bid.'; end if;
  if price is null or price<greatest(a.minimum_bid,a.bid+case when a.bidder_id is null then 0 else game_private.setting('district_bid_increment') end) then raise exception 'Your bid is below the current minimum.'; end if;
  total:=price+ceil(price*a.tax_rate/100);
  if a.bidder_id=auth.uid() then
   perform game_private.district_wallet(auth.uid(),-(total-a.escrow),'Increase auction bid: '||p.code);
  else
   perform game_private.district_wallet(auth.uid(),-total,'Reserve auction bid: '||p.code);
   if a.bidder_id is not null then perform game_private.district_wallet(a.bidder_id,a.escrow,'Outbid refund: '||p.code); end if;
  end if;
  if a.bidder_id is not null then insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(a.bidder_id,p.id,a.id,-a.escrow,'Previous bid released'); end if;
  insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(auth.uid(),p.id,a.id,total,'Bid reserved');
  update public.game_plot_auctions set bid=price,bidder_id=auth.uid(),escrow=total where id=a.id;
  perform game_private.district_event(d.id,'property','plot_bid','New bid of $'||price||' on '||p.code,p.id);
 when 'auction_finish' then
  if a.id is null or a.ends_at>now() then raise exception 'The auction has not ended.'; end if;
  if a.bidder_id is null then update public.game_plot_auctions set status='expired' where id=a.id;
  else
   update public.game_plot_auctions set status='sold',escrow=0 where id=a.id;
   insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(a.bidder_id,p.id,a.id,-a.escrow,'Auction settled');
   perform game_private.district_transfer(p,a.bidder_id,a.bid,a.escrow-a.bid,'auction');
  end if;
 when 'offer' then
  price:=(payload->>'price')::bigint;
  if own or p.owner_type<>'player' or not p.offers_allowed or a.id is not null then raise exception 'The owner is not accepting offers.'; end if;
  if price is null or price<=0 then raise exception 'Enter a positive offer.'; end if;
  if exists(select 1 from public.game_plot_offers where plot_id=p.id and buyer_id=auth.uid() and status='open') then raise exception 'Cancel your existing offer first.'; end if;
  total:=price+ceil(price*coalesce(p.tax_rate,d.tax_rate)/100);
  perform game_private.district_wallet(auth.uid(),-total,'Reserve property offer: '||p.code);
  insert into public.game_plot_offers(plot_id,buyer_id,seller_id,price,escrow,tax_rate,ends_at)
  values(p.id,auth.uid(),p.owner_id,price,total,coalesce(p.tax_rate,d.tax_rate),now()+make_interval(hours=>game_private.setting('district_offer_hours'))) returning id into new_id;
  insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(auth.uid(),p.id,new_id,total,'Offer reserved');
 when 'offer_cancel','offer_accept' then
  select * into o from public.game_plot_offers where id=(payload->>'offer_id')::uuid and plot_id=p.id and status='open' for update;
  if o.id is null then raise exception 'Offer no longer available.'; end if;
  if action='offer_accept' then
   if not own or o.seller_id<>auth.uid() or o.ends_at<=now() or a.id is not null then raise exception 'This offer cannot be accepted.'; end if;
   update public.game_plot_offers set status='accepted' where id=o.id;
   insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(o.buyer_id,p.id,o.id,-o.escrow,'Offer settled');
   perform game_private.district_transfer(p,o.buyer_id,o.price,o.escrow-o.price,'offer');
  else
   if o.buyer_id<>auth.uid() and not own and o.ends_at>now() then raise exception 'This is not your offer.'; end if;
   update public.game_plot_offers set status=case when o.ends_at<=now() then 'expired' else 'cancelled' end where id=o.id;
   perform game_private.district_wallet(o.buyer_id,o.escrow,'Property offer refund: '||p.code);
   insert into public.game_plot_escrow_entries(player_id,plot_id,reference_id,amount,reason) values(o.buyer_id,p.id,o.id,-o.escrow,'Offer refunded');
  end if;
 when 'build' then
  if not own or a.id is not null or p.asking_price is not null then raise exception 'Own an unlisted plot to start construction.'; end if;
  if exists(select 1 from public.game_district_buildings where plot_id=p.id and archived_at is null) then raise exception 'This plot already has a building.'; end if;
  select * into bt from public.game_building_types where id=payload->>'building_type' and active;
  if bt.id is null or not exists(select 1 from public.game_zoning where id=p.zoning and bt.id=any(allowed_buildings))
   or bt.capacity_required>p.build_capacity or bt.minimum_utility>p.utility_level or bt.minimum_infrastructure>p.infrastructure_level then raise exception 'This building does not meet the plot requirements.'; end if;
  if (payload->>'cost')::bigint is distinct from bt.cost then raise exception 'Construction costs changed. Refresh first.'; end if;
  perform game_private.district_wallet(auth.uid(),-bt.cost,'Construction: '||p.code||' '||bt.name);
  insert into public.game_district_buildings(season_id,plot_id,building_type,owner_type,owner_id,construction_status,cost,ready_at)
  values(s,p.id,bt.id,'player',auth.uid(),'building',bt.cost,now()+make_interval(secs=>bt.construction_seconds));
  perform game_private.district_event(d.id,'property','construction',bt.name||' construction started on '||p.code,p.id);
 when 'complete' then
  if not own then raise exception 'Only the owner can complete construction.'; end if;
  select * into b from public.game_district_buildings where plot_id=p.id and archived_at is null for update;
  if b.id is null or b.construction_status<>'building' or b.ready_at>now() then raise exception 'Construction is not ready.'; end if;
  update public.game_district_buildings set construction_status='ready',built_at=now() where id=b.id;
  select * into strict bt from public.game_building_types where id=b.building_type;
  insert into public.game_district_businesses(season_id,district_id,plot_id,building_id,owner_type,owner_id,name,business_type,sells,buys,telegram_fee)
  values(s,d.id,p.id,b.id,'player',auth.uid(),p.code||' '||bt.name,bt.business_type,
  case when bt.good_id is null then '{}'::text[] else array[bt.good_id] end,
  case when bt.input_good_id is null then '{}'::text[] else array[bt.input_good_id] end,bt.telegram_fee) returning id into new_id;
  perform game_private.record_metric(auth.uid(),'construction',1);
  perform game_private.district_event(d.id,'business','business_opening',bt.name||' opened on '||p.code,p.id,new_id);
 when 'business','collect' then
  if not own then raise exception 'Only the owner can manage this business.'; end if;
  select * into biz from public.game_district_businesses where plot_id=p.id and archived_at is null for update;
  if biz.id is null then raise exception 'No business exists on this plot.'; end if;
  if action='business' then
   if length(trim(payload->>'name')) not between 2 and 80 or length(coalesce(payload->>'description',''))>1000 or (payload->>'status') not in ('open','closed') then raise exception 'Check the business name, description and status.'; end if;
   update public.game_district_businesses set name=trim(payload->>'name'),description=coalesce(payload->>'description',''),
   status=payload->>'status',collected_at=case when status<>payload->>'status' then now() else collected_at end,
   telegram_fee=case when telegram_fee is not null then (payload->>'telegram_fee')::bigint else null end
   where id=biz.id;
   perform game_private.district_event(d.id,'business',case when biz.status<>payload->>'status' then 'business_'||case when payload->>'status'='open' then 'opening' else 'closure' end else 'business_update' end,
   trim(payload->>'name')||' updated',p.id,biz.id);
  else
   select bt0.* into bt from public.game_building_types bt0 join public.game_district_buildings b0 on b0.building_type=bt0.id where b0.id=biz.building_id and b0.archived_at is null and b0.construction_status='ready';
   if biz.status<>'open' or bt.good_id is null or bt.batch_size=0 then raise exception 'This business is not producing goods.'; end if;
   batches:=least(game_private.setting('district_offline_batches'),floor(extract(epoch from now()-biz.collected_at)/bt.cycle_seconds)::integer);
   if batches<1 then raise exception 'Production is not ready.'; end if;
   if bt.input_good_id is not null and bt.input_quantity>0 then
    update public.game_inventory set quantity=quantity-batches*bt.input_quantity where season_id=s and player_id=auth.uid() and good_id=bt.input_good_id and quantity>=batches*bt.input_quantity;
    if not found then raise exception 'Not enough input goods in your inventory.'; end if;
   end if;
   quantity:=batches*bt.batch_size;
   insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(s,auth.uid(),bt.good_id,quantity)
   on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
   update public.game_district_businesses set collected_at=now() where id=biz.id;
   perform game_private.record_metric(auth.uid(),'production',quantity);
   perform game_private.district_event(d.id,'resources','resource_extraction',biz.name||' produced '||quantity||' '||bt.good_id,p.id,biz.id,null,jsonb_build_object('quantity',quantity,'good_id',bt.good_id));
  end if;
 when 'job' then
  if not exists(select 1 from public.game_district_jobs where district_id=d.id and job_id=payload->>'job') then raise exception 'This operation is not available here.'; end if;
  result:=game_private.act('job',payload);
  perform game_private.record_metric(auth.uid(),'crime',1);
  perform game_private.district_event(d.id,'economy','district_job',game_private.district_owner_name('player',auth.uid())||' completed '||(select name from public.game_jobs where id=payload->>'job'));
 when 'influence' then
  select gang_id into gid from public.game_season_gang_members where season_id=s and player_id=auth.uid();
  if gid is null then raise exception 'Join a gang before contributing influence.'; end if;
  if exists(select 1 from public.game_district_contributions where season_id=s and district_id=d.id and player_id=auth.uid() and created_at>now()-make_interval(secs=>game_private.setting('district_influence_cooldown'))) then raise exception 'Your influence operation is cooling down.'; end if;
  amount:=game_private.setting('district_influence_cost');
  perform game_private.district_wallet(auth.uid(),-amount,'Gang influence: '||d.name);
  insert into public.game_district_contributions(season_id,district_id,player_id,gang_id,amount) values(s,d.id,auth.uid(),gid,amount);
  insert into public.game_district_gang_control as c(season_id,district_id,gang_id,influence) values(s,d.id,gid,1) on conflict(season_id,district_id,gang_id) do update set influence=c.influence+1;
  update public.game_season_gang_members set contribution=contribution+amount where season_id=s and player_id=auth.uid();
  select sum(influence)+(select neutral_influence from public.game_district_territory where season_id=s and district_id=d.id) into totalinfluence from public.game_district_gang_control where season_id=s and district_id=d.id;
  select gang_id,influence into topgang,points from public.game_district_gang_control where season_id=s and district_id=d.id order by influence desc,gang_id limit 1;
  update public.game_district_territory set controller_gang_id=case when points*100/totalinfluence>=game_private.setting('district_control_threshold') then topgang else null end,
   status=case when exists(select 1 from public.game_district_wars where season_id=s and district_id=d.id and status<>'finished') then 'contested'
   when points*100/totalinfluence>=game_private.setting('district_control_threshold') then 'controlled' else 'neutral' end where season_id=s and district_id=d.id;
  perform game_private.district_event(d.id,'gang','gang_influence',game_private.district_owner_name('gang',gid)||' gained district influence',null,null,gid);
 else raise exception 'Unknown district action.';
 end case;
 return coalesce(result,jsonb_build_object('message','District updated.'));
end $$;
create function game_private.district_action(p_action text,p_payload jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again in a minute.'); end if;
 begin return game_private.district_act(p_action,p_payload);
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
  raise log 'district action failure code=% action=%',SQLSTATE,p_action;
  return jsonb_build_object('error','The action could not be completed. Refresh and check your values.');
 end;
end $$;
create function public.district_action(p_action text,p_payload jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select game_private.district_action(p_action,p_payload) $$;
revoke all on function game_private.district_wallet(uuid,bigint,text),game_private.district_transfer(public.game_district_plots,uuid,bigint,bigint,text),game_private.district_act(text,jsonb),game_private.district_action(text,jsonb),public.district_action(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.district_action(text,jsonb),public.district_action(text,jsonb) to authenticated;
