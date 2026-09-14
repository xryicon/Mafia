-- Mining skill XP is calculated from the authoritative extraction ledger.
-- Every ore delivered during the current season earns configurable Mining skill XP.

select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Add per-ore mining skill progression',true);

insert into public.game_settings(key,value,minimum,maximum)
values('mining_skill_xp_per_ore',1,0,1000000)
on conflict(key) do nothing;

alter table public.game_mining_yields
  add column if not exists xp_awarded bigint not null default 0
  check(xp_awarded>=0);

alter table public.game_skill_definitions
  drop constraint if exists game_skill_definitions_id_check;
alter table public.game_skill_definitions
  add constraint game_skill_definitions_id_check
  check(id in ('crafting','sharpshooting','lockpicking','mining'));

insert into public.game_skill_definitions(id,name,description,display_order)
values('mining','Mining','Work public seams or run an extraction site. Every ore delivered earns Mining XP.',4)
on conflict(id) do nothing;

create or replace function game_private.mining_yield_skill_snapshot()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.xp_awarded:=greatest(0,new.quantity::bigint*game_private.setting('mining_skill_xp_per_ore')::bigint);
  return new;
end $$;

create or replace function game_private.mining_skill_award()
returns trigger language plpgsql security definer set search_path='' as $$
declare resource_name text;
begin
  if new.xp_awarded>0 then
    select name into resource_name from public.game_goods where id=new.good_id;
    insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
    values(new.season_id,new.player_id,'mining',gen_random_uuid(),new.xp_awarded,
      'Mined '||new.quantity||' '||coalesce(resource_name,new.good_id),new.created_at);
  end if;
  return new;
end $$;

drop trigger if exists mining_yield_skill_snapshot on public.game_mining_yields;
create trigger mining_yield_skill_snapshot
before insert on public.game_mining_yields
for each row execute function game_private.mining_yield_skill_snapshot();

drop trigger if exists mining_skill_award on public.game_mining_yields;
create trigger mining_skill_award
after insert on public.game_mining_yields
for each row execute function game_private.mining_skill_award();

-- Existing history predates the mining skill. Import it once without changing
-- player balances, general power, resource ownership, or the source ledger.
insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
select y.season_id,y.player_id,'mining',gen_random_uuid(),
  y.quantity::bigint*game_private.setting('mining_skill_xp_per_ore')::bigint,
  'Mined '||y.quantity||' '||coalesce(g.name,y.good_id),y.created_at
from public.game_mining_yields y
left join public.game_goods g on g.id=y.good_id
where y.quantity>0
  and not exists(
    select 1 from game_private.skill_xp_ledger l
    where l.skill_id='mining' and l.season_id=y.season_id and l.player_id=y.player_id
      and l.description='Mined '||y.quantity||' '||coalesce(g.name,y.good_id)
      and l.created_at=y.created_at
  );

create or replace function game_private.mining_state(p_slug text default 'mines-and-quarries')
returns jsonb language plpgsql security definer set search_path='' as $$
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
 'mining_skill_xp',coalesce((select sum(delta) from game_private.skill_xp_ledger where season_id=s and player_id=auth.uid() and skill_id='mining'),0),
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

revoke all on function game_private.mining_yield_skill_snapshot(),game_private.mining_skill_award() from public,anon,authenticated;
notify pgrst,'reload schema';
