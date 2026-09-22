-- Fixed-text, free market receipts. Triggered by confirmed transactions only.
create function game_private.market_trade_telegram(p_season uuid,p_buyer uuid,p_seller uuid,p_good text,p_quantity integer,p_total bigint,p_fee bigint,p_remaining integer default null)
returns void language plpgsql security definer set search_path='' as $$
declare thread uuid;item text;details text;
begin
 select name into item from public.game_goods where id=p_good;
 details:='Buyer: '||game_private.district_owner_name('player',p_buyer)||E'\nSeller: '||game_private.district_owner_name('player',p_seller)||E'\n'||p_quantity||' '||coalesce(item,p_good)||E'\nTotal: $'||p_total||E'\nSeller fee: $'||p_fee||E'\nSeller receives: $'||(p_total-p_fee)||case when p_remaining is null then '' when p_remaining=0 then E'\nBuy order fulfilled.' else E'\nBuy order remaining: '||p_remaining||' items.' end;
 insert into game_private.telegram_threads(first_player,second_player,subject)
 values(p_buyer,p_seller,'Market trade completed') returning id into thread;
 insert into game_private.telegrams(thread_id,sender_id,recipient_id,body,season_id,request_id) values
 (thread,p_seller,p_buyer,'AUTOMATIC MARKET RECEIPT — ITEMS BOUGHT'||E'\n\n'||details||E'\n\nItems delivered to the buyer inventory. This automatic alert has no delivery charge.',p_season,gen_random_uuid()),
 (thread,p_buyer,p_seller,'AUTOMATIC MARKET RECEIPT — ITEMS SOLD'||E'\n\n'||details||E'\n\nPayment delivered to the seller cash balance. This automatic alert has no delivery charge.',p_season,gen_random_uuid());
 insert into game_private.telegram_folders(player_id,thread_id,read_at) values(p_buyer,thread,null),(p_seller,thread,null);
end $$;
create function game_private.market_trade_alert() returns trigger language plpgsql security definer set search_path='' as $$
declare total bigint;fee bigint;remaining integer;
begin
 if tg_table_name='game_listings' then
  if old.status='active' and new.status='sold' then
   total:=new.quantity::bigint*new.unit_price;fee:=ceil(total*game_private.setting('market_fee_percent')::numeric/100);
   perform game_private.market_trade_telegram(new.season_id,auth.uid(),new.seller_id,new.good_id,new.quantity::integer,total,fee);
  end if;
 elsif tg_table_name='game_market_auctions' then
  if old.status='open' and new.status='sold' then
   perform game_private.market_trade_telegram(new.season_id,new.bidder_id,new.seller_id,new.good_id,new.quantity::integer,new.current_bid,new.fee_paid);
  end if;
 elsif new.buy_order_id is not null then
  select remaining_quantity into remaining from public.game_district_buy_orders where id=new.buy_order_id;
  total:=new.quantity::bigint*new.unit_price;fee:=ceil(total*game_private.setting('market_fee_percent')::numeric/100);
  perform game_private.market_trade_telegram(new.season_id,new.buyer_id,new.seller_id,new.good_id,new.quantity::integer,total,fee,remaining);
 end if;
 return new;
end $$;
create trigger market_listing_telegram after update of status on public.game_listings for each row execute function game_private.market_trade_alert();
create trigger market_auction_telegram after update of status on public.game_market_auctions for each row execute function game_private.market_trade_alert();
create trigger market_order_telegram after insert on public.game_district_trades for each row execute function game_private.market_trade_alert();
revoke all on function game_private.market_trade_telegram(uuid,uuid,uuid,text,integer,bigint,bigint,integer),game_private.market_trade_alert() from public,anon,authenticated;
