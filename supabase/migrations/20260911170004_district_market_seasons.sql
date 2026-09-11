create or replace function game_private.act(p_action text, p_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
 uid uuid := auth.uid();
 p public.game_players;
 season uuid:=game_private.current_season();
 good public.game_goods;
 listing public.game_listings;
 biz public.game_businesses;
 qty integer; price integer; total bigint; fee bigint; reward integer; xp_reward integer; cooldown integer;
 batches integer; label text; result_message text;
begin
 if uid is null then raise exception 'Log in to play.'; end if;
 if not exists(select 1 from public.game_players where id = uid) then raise exception 'Reload the game to create your character.'; end if;

 -- Lock a listing before locking wallets. All wallet pairs lock in UUID order.
 -- Inventory operations also hold the owner wallet lock, serializing mutations.
 if p_action in ('buy', 'cancel') then
   select * into listing from public.game_listings where id = (p_payload->>'listing_id')::uuid and season_id=season for update;
   if not found or listing.status <> 'active' then raise exception 'That offer is no longer available. Refresh the market.'; end if;
   if p_action = 'buy' and listing.seller_id = uid then raise exception 'You cannot buy your own offer.'; end if;
   if p_action = 'cancel' and listing.seller_id <> uid then raise exception 'This is not your offer.'; end if;
   perform id from public.game_players where id in (uid, listing.seller_id) order by id for update;
 else
   perform id from public.game_players where id = uid for update;
 end if;
 select * into strict p from public.game_players where id = uid;

 case p_action
 when 'job' then
   if p.job_ready_at > now() then raise exception 'Your crew is still recovering. Wait for the cooldown.'; end if;
   select j.reward,j.xp,j.cooldown,j.name into reward,xp_reward,cooldown,label from public.game_jobs j where j.id=p_payload->>'job';
   if not found then raise exception 'Unknown operation.'; end if;
   update public.game_players set cash = cash + reward, xp = xp + xp_reward,
     job_ready_at = now() + make_interval(secs => cooldown) where id = uid;
   insert into public.game_events(player_id,description,cash_delta) values (uid,label || ' completed',reward);
   result_message := label || ' complete. +$' || reward || ' and +' || xp_reward || ' respect.';
 when 'business' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   if exists(select 1 from public.game_businesses where player_id = uid and good_id = good.id and season_id=season) then raise exception 'You already own that business.'; end if;
   if p.cash < good.business_cost then raise exception 'Not enough cash for this business.'; end if;
   update public.game_players set cash = cash - good.business_cost where id = uid;
   insert into public.game_businesses(player_id,good_id) values (uid,good.id);
   insert into public.game_events(player_id,description,cash_delta) values (uid,'Opened ' || good.business_name,-good.business_cost);
   result_message := good.business_name || ' acquired. Production has started.';
 when 'collect' then
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown business.'; end if;
   select * into biz from public.game_businesses where player_id = uid and good_id = good.id and season_id=season for update;
   if not found then raise exception 'You do not own this business.'; end if;
   batches := least(game_private.setting('offline_batches'), floor(extract(epoch from (now()-biz.collected_at))/good.cycle_seconds)::integer);
   if batches < 1 then raise exception 'Production is not ready yet.'; end if;
   qty := batches * good.batch_size;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values (uid,good.id,qty)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_businesses set collected_at = case
     when extract(epoch from (now()-biz.collected_at)) >= game_private.setting('offline_batches') * good.cycle_seconds then now()
     else biz.collected_at + make_interval(secs => batches * good.cycle_seconds) end
     where player_id = uid and good_id = good.id and season_id=season;
   insert into public.game_events(player_id,description) values (uid,'Collected ' || qty || ' ' || lower(good.name));
   result_message := qty || ' ' || lower(good.name) || ' added to your inventory.';
 when 'list' then
   qty := (p_payload->>'quantity')::integer; price := (p_payload->>'unit_price')::integer;
   if qty is null or price is null or qty < 1 or qty > game_private.setting('max_listing_quantity') or price < 1 or price > game_private.setting('max_unit_price') then raise exception 'Use a quantity of 1–1,000 and a unit price of $1–$1,000,000.'; end if;
   select * into good from public.game_goods where id = p_payload->>'good_id';
   if not found then raise exception 'Unknown goods.'; end if;
   if (select count(*) from public.game_listings where seller_id = uid and status = 'active' and season_id=season) >= game_private.setting('listing_limit') then raise exception 'Your active offer limit has been reached.'; end if;
   update public.game_inventory set quantity = quantity - qty
     where player_id = uid and good_id = good.id and season_id=season and quantity >= qty;
   if not found then raise exception 'You do not have enough goods. Listed stock is already reserved.'; end if;
   if nullif(p_payload->>'district_id','') is not null and not exists(select 1 from public.game_districts d where d.id=(p_payload->>'district_id')::uuid and d.archived_at is null and d.status<>'lockdown' and not exists(select 1 from public.game_district_territory t where t.district_id=d.id and t.season_id=season and t.status='lockdown')) then raise exception 'This district market is unavailable.'; end if;
   insert into public.game_listings(seller_id,seller_handle,good_id,quantity,unit_price,district_id) values(uid,p.handle,good.id,qty,price,nullif(p_payload->>'district_id','')::uuid);
   insert into public.game_events(player_id,description) values (uid,'Listed ' || qty || ' ' || lower(good.name) || ' at $' || price || ' each');
   result_message := 'Offer posted. Your goods are reserved until sold or cancelled.';
 when 'buy' then
   total := listing.quantity::bigint * listing.unit_price;
   fee := (total * game_private.setting('market_fee_percent') + 99) / 100;
   if p.cash < total then raise exception 'Not enough cash to buy this lot.'; end if;
   update public.game_players set cash = cash - total where id = uid;
   update public.game_players set cash = cash + total - fee where id = listing.seller_id;
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'sold' where id = listing.id;
   insert into public.game_events(player_id,description,cash_delta) values
     (uid,'Bought ' || listing.quantity || ' ' || listing.good_id || ' from ' || listing.seller_handle,-total),
     (listing.seller_id,'Sold ' || listing.quantity || ' ' || listing.good_id || ' · $' || fee || ' market fee',total-fee);
   result_message := 'Deal closed. Goods delivered to your inventory.';
 when 'cancel' then
   insert into public.game_inventory as inv(player_id,good_id,quantity) values(uid,listing.good_id,listing.quantity)
     on conflict(season_id,player_id,good_id) do update set quantity = inv.quantity + excluded.quantity;
   update public.game_listings set status = 'cancelled' where id = listing.id;
   insert into public.game_events(player_id,description) values (uid,'Cancelled an offer · ' || listing.quantity || ' ' || listing.good_id || ' returned');
   result_message := 'Offer withdrawn. Reserved stock returned.';
 else raise exception 'Unknown game action.';
 end case;
 return jsonb_build_object('message',result_message);
end $$;
create or replace function game_private.season_scores(p_season uuid,p_metric text)
returns table(player_id uuid,handle text,score numeric) language sql stable security definer set search_path='' as $$
with base as (
 select sp.player_id,p.handle,sp.cash,sp.xp,
 coalesce((select sum(i.quantity::numeric*v.unit_value) from public.game_inventory i join public.game_season_valuations v on v.season_id=i.season_id and v.good_id=i.good_id where i.season_id=p_season and i.player_id=sp.player_id),0)
 +coalesce((select sum(l.quantity::numeric*v.unit_value) from public.game_listings l join public.game_season_valuations v on v.season_id=l.season_id and v.good_id=l.good_id where l.season_id=p_season and l.seller_id=sp.player_id and l.status='active'),0) as stock_value,
 coalesce((select sum(g.business_cost::numeric) from public.game_businesses b join public.game_goods g on g.id=b.good_id where b.season_id=p_season and b.player_id=sp.player_id),0) as business_value,
 coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=sp.player_id),0) +coalesce((select sum(p.base_price::numeric) from public.game_district_plots p where p.season_id=p_season and p.owner_type='player' and p.owner_id=sp.player_id),0)
 +coalesce((select sum(b.cost::numeric) from public.game_district_buildings b where b.season_id=p_season and b.owner_type='player' and b.owner_id=sp.player_id and b.archived_at is null),0)
 +coalesce((select sum(a.escrow::numeric) from public.game_plot_auctions a join public.game_district_plots p on p.id=a.plot_id where p.season_id=p_season and a.bidder_id=sp.player_id and a.status='open'),0)
 +coalesce((select sum(o.escrow::numeric) from public.game_plot_offers o join public.game_district_plots p on p.id=o.plot_id where p.season_id=p_season and o.buyer_id=sp.player_id and o.status='open'),0) as asset_value,
 coalesce((select sum(l.outstanding::numeric) from public.game_season_loans l where l.season_id=p_season and l.player_id=sp.player_id),0) as debt
 from public.game_season_players sp join public.game_players p on p.id=sp.player_id
 join public.game_leaderboards board on board.season_id=sp.season_id and board.metric=p_metric
 where sp.season_id=p_season and p.deleted_at is null and (board.include_banned or not exists(
 select 1 from public.game_sanctions s where s.player_id=p.id and s.kind='ban' and s.revoked_at is null and (s.expires_at is null or s.expires_at>now())))
)
select b.player_id,b.handle,case p_metric
 when 'cash' then b.cash::numeric when 'respect' then b.xp::numeric
 when 'net_worth' then b.cash+b.stock_value+b.business_value+b.asset_value-b.debt
 when 'land' then coalesce((select sum(p.size::numeric) from public.game_district_plots p where p.season_id=p_season and p.owner_type='player' and p.owner_id=b.player_id),0)+coalesce((select sum(a.quantity::numeric) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='land'),0)
 when 'company_value' then coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='company'),0)
 when 'factory_value' then coalesce((select sum(x.cost::numeric) from public.game_district_buildings x where x.season_id=p_season and x.owner_type='player' and x.owner_id=b.player_id and x.archived_at is null),0)+b.business_value+coalesce((select sum(a.quantity::numeric*a.unit_value) from public.game_season_assets a where a.season_id=p_season and a.player_id=b.player_id and a.kind='factory'),0)
 when 'gang_contribution' then coalesce((select sum(m.contribution::numeric) from public.game_season_gang_members m where m.season_id=p_season and m.player_id=b.player_id),0)
 else coalesce((select s.value::numeric from public.game_season_stats s where s.season_id=p_season and s.player_id=b.player_id and s.metric=p_metric),0) end
from base b
$$;
create function game_private.district_trade_record() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
begin
 if new.district_id is not null and new.status='sold' and old.status='active' then
  insert into public.game_district_trades(season_id,district_id,listing_id,good_id,quantity,unit_price,buyer_id,seller_id)
  values(new.season_id,new.district_id,new.id,new.good_id,new.quantity,new.unit_price,auth.uid(),new.seller_id);
  perform game_private.district_event(new.district_id,'economy','market_transaction',new.quantity||' '||new.good_id||' traded for $'||(new.quantity::bigint*new.unit_price),null,null,null,jsonb_build_object('listing_id',new.id,'good_id',new.good_id,'quantity',new.quantity,'unit_price',new.unit_price));
 end if;return new;
end $$;
create trigger district_market_trade after update of status on public.game_listings for each row execute function game_private.district_trade_record();
create function game_private.district_season_reopen() returns trigger language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare pause interval;
begin
 if old.status='locked' and new.status='open' and old.locked_at is not null then
  pause:=clock_timestamp()-old.locked_at;
  update public.game_district_buildings set ready_at=ready_at+pause where season_id=new.id and construction_status='building' and archived_at is null;
  update public.game_district_businesses set collected_at=collected_at+pause where season_id=new.id and archived_at is null;
  update public.game_plot_auctions a set ends_at=a.ends_at+pause from public.game_district_plots p where p.id=a.plot_id and p.season_id=new.id and a.status='open';
  update public.game_plot_offers o set ends_at=o.ends_at+pause from public.game_district_plots p where p.id=o.plot_id and p.season_id=new.id and o.status='open';
 end if;return new;
end $$;
create trigger district_season_clock after update of status on public.game_seasons for each row execute function game_private.district_season_reopen();
revoke all on function game_private.district_trade_record(),game_private.district_season_reopen() from public,anon,authenticated;
