create table public.game_district_buy_orders (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 district_id uuid not null references public.game_districts(id), buyer_id uuid not null references public.game_players(id),
 good_id text not null references public.game_goods(id), quantity integer not null check(quantity>0),
 unit_price integer not null check(unit_price>0), escrow bigint not null check(escrow>=0),
 status text not null default 'open' check(status in ('open','filled','cancelled')),
 created_at timestamptz not null default now(), completed_at timestamptz
);
create index district_buy_order_book on public.game_district_buy_orders(season_id,district_id,status);
alter table public.game_district_buy_orders enable row level security;
revoke all on public.game_district_buy_orders from public,anon,authenticated;
create trigger audit_buy_order after insert or update on public.game_district_buy_orders for each row execute function game_private.audit_change();
alter table public.game_district_trades alter column listing_id drop not null;
alter table public.game_district_trades add column buy_order_id uuid unique references public.game_district_buy_orders(id);
alter table public.game_district_trades add constraint trade_source check(num_nonnulls(listing_id,buy_order_id)=1);

create function game_private.district_market_order(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; d uuid; o public.game_district_buy_orders; qty integer; price integer; total bigint; fee bigint;
begin
 perform game_private.require_active();
 if not game_private.rate('actions',game_private.setting('actions_per_minute')) then return jsonb_build_object('error','Too many actions. Try again shortly.'); end if;
 begin
 s:=game_private.season_guard();
 if (p_payload->>'season_id')::uuid is distinct from s then raise exception 'Season changed. Refresh the market.'; end if;
 perform pg_advisory_xact_lock(4704020);
 if p_action='create' then d:=(p_payload->>'district_id')::uuid;
 else
  select * into o from public.game_district_buy_orders where id=(p_payload->>'order_id')::uuid and season_id=s and status='open' for update;
  if o.id is null then raise exception 'This order is no longer open.'; end if;
  d:=o.district_id;
 end if;
 if p_action<>'cancel' and not exists(select 1 from public.game_districts where id=d and archived_at is null and status<>'lockdown'
 and not exists(select 1 from public.game_district_territory where season_id=s and district_id=d and status='lockdown')) then raise exception 'The district exchange is unavailable.'; end if;
 perform id from public.game_players where id in(auth.uid(),o.buyer_id) order by id for update;
 perform set_config('game.reason','District buy order: '||p_action,true);
 case p_action
 when 'create' then
  qty:=(p_payload->>'quantity')::integer;price:=(p_payload->>'unit_price')::integer;
  if qty is null or qty not between 1 and game_private.setting('max_listing_quantity') or price is null or price not between 1 and game_private.setting('max_unit_price') then raise exception 'Check the quantity and price limits.'; end if;
  if not exists(select 1 from public.game_goods where id=p_payload->>'good_id') then raise exception 'Unknown goods.'; end if;
  if (select count(*) from public.game_district_buy_orders where season_id=s and buyer_id=auth.uid() and status='open')>=game_private.setting('listing_limit') then raise exception 'Your open order limit has been reached.'; end if;
  total:=qty::bigint*price;
  perform game_private.district_wallet(auth.uid(),-total,'Fund district buy order');
  insert into public.game_district_buy_orders(season_id,district_id,buyer_id,good_id,quantity,unit_price,escrow)
  values(s,d,auth.uid(),p_payload->>'good_id',qty,price,total);
 when 'fill' then
  if o.buyer_id=auth.uid() then raise exception 'You cannot fill your own buy order.'; end if;
  total:=o.quantity::bigint*o.unit_price;fee:=ceil(total*game_private.setting('market_fee_percent')::numeric/100);
  if o.escrow<>total then raise exception 'The order funding is unavailable.'; end if;
  update public.game_inventory set quantity=quantity-o.quantity where season_id=s and player_id=auth.uid() and good_id=o.good_id and quantity>=o.quantity;
  if not found then raise exception 'You do not have enough available goods to fill this order.'; end if;
  insert into public.game_inventory as inv(season_id,player_id,good_id,quantity) values(s,o.buyer_id,o.good_id,o.quantity)
  on conflict(season_id,player_id,good_id) do update set quantity=inv.quantity+excluded.quantity;
  perform game_private.district_wallet(auth.uid(),total-fee,'Supply district buy order');
  update public.game_district_buy_orders set status='filled',escrow=0,completed_at=now() where id=o.id;
  insert into public.game_district_trades(season_id,district_id,buy_order_id,good_id,quantity,unit_price,buyer_id,seller_id)
  values(s,d,o.id,o.good_id,o.quantity,o.unit_price,o.buyer_id,auth.uid());
  perform game_private.record_metric(auth.uid(),'trading',total);
  perform game_private.district_event(d,'economy','market_transaction',o.quantity||' '||o.good_id||' supplied for $'||total,null,null,null,jsonb_build_object('buy_order_id',o.id,'quantity',o.quantity,'good_id',o.good_id));
 when 'cancel' then
  if o.buyer_id<>auth.uid() then raise exception 'This is not your buy order.'; end if;
  perform game_private.district_wallet(auth.uid(),o.escrow,'Refund district buy order');
  update public.game_district_buy_orders set status='cancelled',escrow=0,completed_at=now() where id=o.id;
 else raise exception 'Unknown market order action.';
 end case;
 return jsonb_build_object('message',case p_action when 'create' then 'Buy order funded and posted.' when 'fill' then 'Goods supplied. Payment received.' else 'Buy order cancelled. Funds returned.' end);
 exception when others then
  if SQLSTATE='P0001' then return jsonb_build_object('error',SQLERRM); end if;
  raise log 'district order failure code=%',SQLSTATE;return jsonb_build_object('error','The order could not be completed. Refresh and check your values.');
 end;
end $$;
create function public.district_market_order(p_action text,p_payload jsonb) returns jsonb language sql security invoker set search_path='' as $$ select game_private.district_market_order(p_action,p_payload) $$;
revoke all on function public.district_market_order(text,jsonb),game_private.district_market_order(text,jsonb) from public,anon,authenticated;
grant execute on function public.district_market_order(text,jsonb),game_private.district_market_order(text,jsonb) to authenticated;

create or replace function game_private.district_state(p_slug text default null,p_before bigint default null) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare s uuid; d public.game_districts; result jsonb; manage boolean;
begin
 perform game_private.require_active();
 if not game_private.rate('district_read',120) then raise exception 'Wait a moment before refreshing.'; end if;
 if not exists(select 1 from public.game_players where id=auth.uid()) then perform game_private.state(); end if;
 s:=game_private.season_guard(false);
 perform game_private.ensure_districts(s);
 manage:=game_private.has_permission('districts.manage');
 if p_slug is not null then
  select * into d from public.game_districts where (slug=p_slug or id::text=p_slug) and (archived_at is null or manage);
  if d.id is null then raise exception 'District not found'; end if;
 end if;
 select jsonb_build_object(
 'districts',coalesce((select jsonb_agg(to_jsonb(x)||jsonb_build_object(
  'controller',game_private.district_owner_name('gang',t.controller_gang_id),
  'runtime_status',coalesce(t.status,x.status),
  'available_plots',(select count(*) from public.game_district_plots p where p.season_id=s and p.district_id=x.id and p.status='available' and p.archived_at is null),
  'active_businesses',(select count(*) from public.game_district_businesses b where b.season_id=s and b.district_id=x.id and b.status='open' and b.archived_at is null)) order by x.name)
  from public.game_districts x left join public.game_district_territory t on t.district_id=x.id and t.season_id=s where x.archived_at is null),'[]'::jsonb),
 'district',to_jsonb(d),'season',(select jsonb_build_object('id',id,'name',name,'status',status) from public.game_seasons where id=s),
 'player_id',auth.uid(),'cash',(select cash from public.game_players where id=auth.uid()),
 'gang_id',(select gang_id from public.game_season_gang_members where season_id=s and player_id=auth.uid()),
 'gangs',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'recruiting',g.data->>'recruitment'='open','founder',g.data->>'owner_id'=auth.uid()::text)) from public.game_season_gangs g where g.season_id=s),'[]'::jsonb),
 'can_manage',manage,'server_time',now(),
 'plots',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object(
  'owner_name',game_private.district_owner_name(p.owner_type,p.owner_id),
  'price',coalesce(p.asking_price,ceil(p.base_price*d.property_value_index/100)),
  'tax',coalesce(p.tax_rate,d.tax_rate),
  'watched',exists(select 1 from public.game_plot_watchlists w where w.plot_id=p.id and w.player_id=auth.uid())) order by p.code)
 from public.game_district_plots p where p.district_id=d.id and p.season_id=s and p.archived_at is null),'[]'::jsonb),
 'buildings',coalesce((select jsonb_agg(b) from public.game_district_buildings b join public.game_district_plots p on p.id=b.plot_id where p.district_id=d.id and b.season_id=s and b.archived_at is null),'[]'::jsonb),
 'businesses',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('owner_name',game_private.district_owner_name(b.owner_type,b.owner_id)) order by b.name) from public.game_district_businesses b where b.district_id=d.id and b.season_id=s and b.archived_at is null),'[]'::jsonb),
 'sites',coalesce((select jsonb_agg(x order by x.name) from public.game_district_sites x where x.district_id=d.id and x.season_id=s and x.archived_at is null),'[]'::jsonb),
 'events',coalesce((select jsonb_agg(e order by e.id desc) from (
  select e.*,game_private.district_owner_name('player',e.actor_id) as actor_name from public.game_district_events e
  left join public.game_district_event_visibility v on v.event_id=e.id
  where e.season_id=s and (d.id is null or e.district_id=d.id) and (p_before is null or e.id<p_before) and (not coalesce(v.hidden,false) or manage)
  order by e.id desc limit 100) e),'[]'::jsonb),
 'territory',coalesce((select to_jsonb(t)||jsonb_build_object('controller_name',case when t.controller_gang_id is null then 'Neutral' else game_private.district_owner_name('gang',t.controller_gang_id) end)
 from public.game_district_territory t where t.season_id=s and t.district_id=d.id),'{}'::jsonb),
 'influence',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('name',g.name) order by c.influence desc) from public.game_district_gang_control c join public.game_season_gangs g on g.id=c.gang_id where c.season_id=s and c.district_id=d.id),'[]'::jsonb),
 'wars',coalesce((select jsonb_agg(to_jsonb(w)||jsonb_build_object(
 'parties',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('name',g.name)) from public.game_district_war_parties p join public.game_season_gangs g on g.id=p.gang_id where p.war_id=w.id),'[]'::jsonb),
 'operations',coalesce((select jsonb_agg(o order by o.created_at desc) from public.game_district_operations o where o.war_id=w.id),'[]'::jsonb))) from public.game_district_wars w where w.season_id=s and w.district_id=d.id and w.status<>'finished'),'[]'::jsonb),
 'auctions',coalesce((select jsonb_agg(a) from public.game_plot_auctions a join public.game_district_plots p on p.id=a.plot_id where p.district_id=d.id and p.season_id=s and a.status='open'),'[]'::jsonb),
 'offers',coalesce((select jsonb_agg(o) from public.game_plot_offers o join public.game_district_plots p on p.id=o.plot_id where p.district_id=d.id and p.season_id=s and o.status='open' and (o.buyer_id=auth.uid() or o.seller_id=auth.uid())),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(x order by x.created_at desc) from (select ps.* from public.game_property_sales ps join public.game_district_plots p on p.id=ps.plot_id where p.district_id=d.id and ps.season_id=s order by ps.created_at desc limit 50) x),'[]'::jsonb),
 'market',coalesce((select jsonb_agg(l order by l.created_at desc) from public.game_listings l where l.district_id=d.id and l.season_id=s and l.status='active'),'[]'::jsonb),
 'trades',coalesce((select jsonb_agg(x order by x.created_at desc) from (select * from public.game_district_trades where district_id=d.id and season_id=s order by created_at desc limit 100) x),'[]'::jsonb),
 'buy_orders',coalesce((select jsonb_agg(to_jsonb(o)||jsonb_build_object('buyer_name',game_private.district_owner_name('player',o.buyer_id)) order by o.created_at desc) from public.game_district_buy_orders o where o.season_id=s and (d.id is null or o.district_id=d.id) and o.status='open'),'[]'::jsonb),
 'price_comparisons',coalesce((select jsonb_agg(jsonb_build_object('good_id',g.id,'local', (select avg(l.unit_price) from public.game_listings l where l.good_id=g.id and l.season_id=s and l.district_id=d.id and l.status='active'),'city',(select avg(l.unit_price) from public.game_listings l where l.good_id=g.id and l.season_id=s and l.status='active'))) from public.game_goods g),'[]'::jsonb),
 'market_volume',coalesce((select sum(quantity*unit_price) from public.game_district_trades where district_id=d.id and season_id=s),0),
 'building_types',(select coalesce(jsonb_agg(b order by b.cost),'[]'::jsonb) from public.game_building_types b where b.active),
 'zoning',(select coalesce(jsonb_agg(z),'[]'::jsonb) from public.game_zoning z),
 'goods',(select jsonb_agg(g) from public.game_goods g),
 'jobs',coalesce((select jsonb_agg(j) from public.game_jobs j join public.game_district_jobs dj on dj.job_id=j.id where dj.district_id=d.id),'[]'::jsonb),
 'job_ready_at',(select job_ready_at from public.game_players where id=auth.uid()),
 'settings',(select jsonb_object_agg(key,value) from public.game_settings where key like 'district_%'),
 'management',case when manage then jsonb_build_object(
  'districts',(select coalesce(jsonb_agg(x order by name),'[]'::jsonb) from public.game_districts x),
  'templates',(select coalesce(jsonb_agg(x order by code),'[]'::jsonb) from public.game_plot_templates x where d.id is null or x.district_id=d.id),
  'site_templates',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.game_district_site_templates x where d.id is null or x.district_id=d.id),
  'entities',(select coalesce(jsonb_agg(x),'[]'::jsonb) from public.game_district_entities x),
  'gangs',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name)),'[]'::jsonb) from public.game_season_gangs where season_id=s)) else null end
 ) into result;
 return result;
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
 +coalesce((select sum(o.escrow::numeric) from public.game_plot_offers o join public.game_district_plots p on p.id=o.plot_id where p.season_id=p_season and o.buyer_id=sp.player_id and o.status='open'),0) +coalesce((select sum(o.escrow::numeric) from public.game_district_buy_orders o where o.season_id=p_season and o.buyer_id=sp.player_id and o.status='open'),0) as asset_value,
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
create trigger retain_buy_orders before delete on public.game_district_buy_orders for each row execute function game_private.district_immutable();
create trigger retain_buy_orders_table before truncate on public.game_district_buy_orders for each statement execute function game_private.district_immutable();
create trigger retain_auctions before delete on public.game_plot_auctions for each row execute function game_private.district_immutable();
create trigger retain_auctions_table before truncate on public.game_plot_auctions for each statement execute function game_private.district_immutable();
create trigger retain_offers before delete on public.game_plot_offers for each row execute function game_private.district_immutable();
create trigger retain_offers_table before truncate on public.game_plot_offers for each statement execute function game_private.district_immutable();
