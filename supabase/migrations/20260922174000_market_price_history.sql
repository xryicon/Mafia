-- Completed transactions, never asking prices. Amounts are fictional game currency.
create table game_private.market_price_sales(source_kind text not null,source_id text not null,season_id uuid not null references public.game_seasons(id),good_id text not null references public.game_goods(id),quantity bigint not null check(quantity>0),total bigint not null check(total>0),created_at timestamptz not null,primary key(source_kind,source_id));
create index market_price_history on game_private.market_price_sales(season_id,good_id,created_at desc);
alter table game_private.market_price_sales enable row level security;
revoke all on game_private.market_price_sales from public,anon,authenticated;
create trigger market_price_sales_retain before update or delete or truncate on game_private.market_price_sales for each statement execute function game_private.district_immutable();
insert into game_private.market_price_sales select case when buy_order_id is null then 'listing' else 'order' end,coalesce(listing_id::text,id::text),season_id,good_id,quantity,quantity::bigint*unit_price,created_at from public.game_district_trades on conflict do nothing;
insert into game_private.market_price_sales select 'auction',id::text,season_id,good_id,quantity,current_bid,completed_at from public.game_market_auctions where status='sold' on conflict do nothing;
create function game_private.market_price_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='game_listings' then
  if old.status='active' and new.status='sold' then insert into game_private.market_price_sales values('listing',new.id::text,new.season_id,new.good_id,new.quantity,new.quantity::bigint*new.unit_price,clock_timestamp()) on conflict do nothing;end if;
 elsif tg_table_name='game_market_auctions' then
  if old.status='open' and new.status='sold' then insert into game_private.market_price_sales values('auction',new.id::text,new.season_id,new.good_id,new.quantity,new.current_bid,clock_timestamp()) on conflict do nothing;end if;
 elsif new.buy_order_id is not null then
  insert into game_private.market_price_sales values('order',new.id::text,new.season_id,new.good_id,new.quantity,new.quantity::bigint*new.unit_price,clock_timestamp()) on conflict do nothing;
 end if;
 return new;
end$$;
create trigger market_listing_price after update of status on public.game_listings for each row execute function game_private.market_price_record();
create trigger market_auction_price after update of status on public.game_market_auctions for each row execute function game_private.market_price_record();
create trigger market_order_price after insert on public.game_district_trades for each row execute function game_private.market_price_record();
create function public.market_price_history(p_good text,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare s uuid;result jsonb;
begin
 perform game_private.require_active();s:=game_private.current_season();
 if p_offset<0 or p_offset>100000 or p_offset is null then raise exception 'Invalid history page.';end if;
 if not exists(select 1 from public.game_goods where id=p_good) then raise exception 'Unknown item.';end if;
 with sales as (select * from game_private.market_price_sales where season_id=s and good_id=p_good and created_at>=clock_timestamp()-interval '30 days')
 select jsonb_build_object('good_id',p_good,'total',count(*),'units',coalesce(sum(quantity),0),'average',sum(total)::numeric/nullif(sum(quantity),0),'low',min(total::numeric/quantity),'high',max(total::numeric/quantity),
 'recent',(select coalesce(jsonb_agg(x order by x.created_at desc,x.source_id),'[]') from(select source_id,source_kind,quantity,total,round(total::numeric/quantity,2) unit_price,created_at from sales order by created_at desc,source_id offset p_offset limit 10)x),
 'daily',(select coalesce(jsonb_agg(x order by x.day),'[]') from(select (created_at at time zone 'UTC')::date as day,sum(quantity) units,round(sum(total)::numeric/sum(quantity),2) average from sales group by 1)x)) into result from sales;
 return result;
end$$;
revoke all on function game_private.market_price_record(),public.market_price_history(text,integer) from public,anon,authenticated;
grant execute on function public.market_price_history(text,integer) to authenticated;
