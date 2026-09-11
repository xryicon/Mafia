create or replace function game_private.district_immutable() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'District financial and event records are permanent'; end $$;
-- District catalog is permanent. Ownership, construction and economic history are seasonal.
insert into public.game_permissions(id,owner_only) values ('districts.manage',false) on conflict do nothing;
insert into public.game_settings(key,value,minimum,maximum) values
 ('district_auction_hours',24,1,168),('district_bid_increment',100,1,1000000),
 ('district_offer_hours',48,1,168),('district_influence_cost',500,1,1000000),
 ('district_influence_cooldown',300,1,86400),('district_control_threshold',60,1,100),
 ('district_offline_batches',24,1,1000)
 on conflict do nothing;

create table public.game_districts (
 id uuid primary key default gen_random_uuid(), slug text not null unique check(slug ~ '^[a-z0-9-]{2,64}$'),
 name text not null check(length(name) between 2 and 80), description text not null default '',
 tagline text not null default '', district_type text not null default 'urban',
 image_url text not null default '/art/harbor.webp', industries text[] not null default '{}',
 strategic_importance text not null default '', tax_rate numeric(5,2) not null default 3 check(tax_rate between 0 and 100),
 police_heat integer not null default 0 check(police_heat between 0 and 100),
 property_value_index numeric(9,2) not null default 100 check(property_value_index>0),
 property_trend numeric(7,2) not null default 0,
 status text not null default 'neutral' check(status in ('neutral','controlled','contested','lockdown')),
 city_polygon jsonb not null default '[[280,420],[530,370],[740,490],[450,660]]',
 map_data jsonb not null default '{}', archived_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.game_district_entities (
 id uuid primary key default gen_random_uuid(), name text not null unique, entity_type text not null check(entity_type in ('company','city')),
 payout_player_id uuid references public.game_players(id), archived_at timestamptz
);
create table public.game_building_types (
 id text primary key, name text not null, cost bigint not null check(cost>=0),
 construction_seconds integer not null check(construction_seconds>=0),
 capacity_required integer not null default 1 check(capacity_required>0),
 minimum_utility integer not null default 0 check(minimum_utility between 0 and 100),
 minimum_infrastructure integer not null default 0 check(minimum_infrastructure between 0 and 100),
 business_type text not null, good_id text references public.game_goods(id),
 batch_size integer not null default 0 check(batch_size>=0),
 cycle_seconds integer not null default 3600 check(cycle_seconds>0),
 input_good_id text references public.game_goods(id), input_quantity integer not null default 0 check(input_quantity>=0),
 telegram_fee bigint check(telegram_fee>=0), active boolean not null default true
);
create table public.game_zoning (
 id text primary key, name text not null, allowed_buildings text[] not null default '{}'
);
create table public.game_plot_templates (
 id uuid primary key default gen_random_uuid(), district_id uuid not null references public.game_districts(id),
 code text not null check(length(code) between 1 and 16), polygon jsonb not null,
 size integer not null check(size>0), zoning text not null references public.game_zoning(id),
 status text not null default 'available' check(status in ('available','owned','reserved','locked')),
 base_price bigint not null check(base_price>=0), tax_rate numeric(5,2) check(tax_rate between 0 and 100),
 utility_level integer not null default 50 check(utility_level between 0 and 100),
 infrastructure_level integer not null default 50 check(infrastructure_level between 0 and 100),
 build_capacity integer not null default 1 check(build_capacity>0), strategic_type text,
 entity_id uuid references public.game_district_entities(id), building_type text references public.game_building_types(id),
 business_name text, description text not null default '', archived_at timestamptz,
 unique(district_id,code), check(status<>'owned' or entity_id is not null)
);
create table public.game_district_plots (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 template_id uuid not null references public.game_plot_templates(id), district_id uuid not null references public.game_districts(id),
 code text not null, polygon jsonb not null, size integer not null check(size>0),
 zoning text not null references public.game_zoning(id), status text not null check(status in ('available','owned','reserved','locked')),
 owner_type text not null default 'none' check(owner_type in ('none','player','company','gang','city')),
 owner_id uuid, base_price bigint not null check(base_price>=0),
 asking_price bigint check(asking_price>0), offers_allowed boolean not null default false,
 tax_rate numeric(5,2) check(tax_rate between 0 and 100),
 utility_level integer not null check(utility_level between 0 and 100),
 infrastructure_level integer not null check(infrastructure_level between 0 and 100),
 build_capacity integer not null check(build_capacity>0), strategic_type text,
 version integer not null default 1, archived_at timestamptz,
 unique(season_id,template_id), unique(season_id,district_id,code), unique(season_id,id),
 check((owner_type='none')=(owner_id is null)), check(status<>'owned' or owner_id is not null),
 check(asking_price is null or status='owned')
);
create table public.game_district_buildings (
 id uuid primary key default gen_random_uuid(), season_id uuid not null,
 plot_id uuid not null, building_type text not null references public.game_building_types(id),
 owner_type text not null, owner_id uuid not null, level integer not null default 1 check(level>0),
 condition integer not null default 100 check(condition between 0 and 100),
 construction_status text not null check(construction_status in ('building','ready')),
 cost bigint not null check(cost>=0), ready_at timestamptz not null, built_at timestamptz,
 archived_at timestamptz, foreign key(season_id,plot_id) references public.game_district_plots(season_id,id)
);
create unique index district_one_building on public.game_district_buildings(plot_id) where archived_at is null;
create table public.game_district_businesses (
 id uuid primary key default gen_random_uuid(), season_id uuid not null,
 district_id uuid not null references public.game_districts(id), plot_id uuid not null,
 building_id uuid not null references public.game_district_buildings(id),
 owner_type text not null, owner_id uuid not null, name text not null check(length(name) between 2 and 80),
 business_type text not null, status text not null default 'open' check(status in ('open','closed')),
 description text not null default '', buys text[] not null default '{}', sells text[] not null default '{}',
 telegram_fee bigint check(telegram_fee>=0), collected_at timestamptz not null default now(),
 created_at timestamptz not null default now(), archived_at timestamptz,
 foreign key(season_id,plot_id) references public.game_district_plots(season_id,id)
);
create unique index district_one_business on public.game_district_businesses(plot_id) where archived_at is null;
create table public.game_district_site_templates (
 id uuid primary key default gen_random_uuid(), district_id uuid not null references public.game_districts(id),
 plot_template_id uuid references public.game_plot_templates(id), name text not null,
 kind text not null check(kind in ('strategic','resource')), resource_type text not null,
 data jsonb not null default '{}', archived_at timestamptz
);
create table public.game_district_sites (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 template_id uuid not null references public.game_district_site_templates(id),
 district_id uuid not null references public.game_districts(id), plot_id uuid references public.game_district_plots(id),
 name text not null, kind text not null, resource_type text not null, data jsonb not null default '{}',
 archived_at timestamptz, unique(season_id,template_id)
);
create table public.game_district_territory (
 season_id uuid not null references public.game_seasons(id), district_id uuid not null references public.game_districts(id),
 controller_gang_id uuid, neutral_influence bigint not null default 100 check(neutral_influence>=0),
 fortification integer not null default 0 check(fortification between 0 and 100),
 status text not null default 'neutral' check(status in ('neutral','controlled','contested','lockdown')),
 primary key(season_id,district_id),
 foreign key(season_id,controller_gang_id) references public.game_season_gangs(season_id,id)
);
create table public.game_district_gang_control (
 season_id uuid not null, district_id uuid not null references public.game_districts(id), gang_id uuid not null,
 influence bigint not null default 0 check(influence>=0), primary key(season_id,district_id,gang_id),
 foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create table public.game_district_wars (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 district_id uuid not null references public.game_districts(id), name text not null,
 status text not null check(status in ('preparing','active','finished')), started_at timestamptz not null default now(),
 ended_at timestamptz, objectives jsonb not null default '[]', unique(season_id,id)
);
create unique index district_one_war on public.game_district_wars(season_id,district_id) where status<>'finished';
create table public.game_district_war_parties (
 war_id uuid not null, season_id uuid not null, gang_id uuid not null,
 side text not null check(side in ('attacker','defender','independent')), supply bigint not null default 0 check(supply>=0),
 data jsonb not null default '{}', primary key(war_id,gang_id),
 foreign key(season_id,war_id) references public.game_district_wars(season_id,id),
 foreign key(season_id,gang_id) references public.game_season_gangs(season_id,id)
);
create table public.game_district_operations (
 id uuid primary key default gen_random_uuid(), war_id uuid not null references public.game_district_wars(id),
 gang_id uuid not null, kind text not null check(kind in ('operation','convoy','defense','participation','territory_change')),
 status text not null, description text not null, data jsonb not null default '{}',
 created_at timestamptz not null default now(), foreign key(war_id,gang_id) references public.game_district_war_parties(war_id,gang_id)
);
create table public.game_district_events (
 id bigint generated always as identity primary key, season_id uuid not null references public.game_seasons(id),
 district_id uuid not null references public.game_districts(id), category text not null check(category in ('property','business','economy','gang','resources','system')),
 event_type text not null, description text not null, actor_id uuid references public.game_players(id),
 plot_id uuid references public.game_district_plots(id), business_id uuid references public.game_district_businesses(id),
 gang_id uuid references public.game_season_gangs(id), metadata jsonb not null default '{}',
 created_at timestamptz not null default now()
);
create index district_events_feed on public.game_district_events(season_id,district_id,id desc);
create table public.game_district_event_visibility (
 event_id bigint primary key references public.game_district_events(id), hidden boolean not null default false, reason text not null
);
create table public.game_plot_watchlists (
 player_id uuid not null references public.game_players(id), plot_id uuid not null references public.game_district_plots(id),
 created_at timestamptz not null default now(), primary key(player_id,plot_id)
);
create table public.game_plot_auctions (
 id uuid primary key default gen_random_uuid(), plot_id uuid not null references public.game_district_plots(id),
 seller_id uuid not null references public.game_players(id), minimum_bid bigint not null check(minimum_bid>0),
 bid bigint not null default 0 check(bid>=0), bidder_id uuid references public.game_players(id),
 escrow bigint not null default 0 check(escrow>=0), tax_rate numeric(5,2) not null check(tax_rate between 0 and 100),
 ends_at timestamptz not null, status text not null default 'open' check(status in ('open','sold','expired','cancelled')),
 created_at timestamptz not null default now()
);
create unique index plot_one_auction on public.game_plot_auctions(plot_id) where status='open';
create table public.game_plot_offers (
 id uuid primary key default gen_random_uuid(), plot_id uuid not null references public.game_district_plots(id),
 buyer_id uuid not null references public.game_players(id), seller_id uuid not null references public.game_players(id),
 price bigint not null check(price>0), escrow bigint not null check(escrow>0), tax_rate numeric(5,2) not null,
 ends_at timestamptz not null, status text not null default 'open' check(status in ('open','accepted','cancelled','expired')),
 created_at timestamptz not null default now()
);
create unique index plot_one_offer on public.game_plot_offers(plot_id,buyer_id) where status='open';
create table public.game_property_sales (
 id uuid primary key default gen_random_uuid(), season_id uuid not null references public.game_seasons(id),
 plot_id uuid not null references public.game_district_plots(id), buyer_id uuid not null references public.game_players(id),
 seller_type text not null, seller_id uuid, price bigint not null check(price>=0), tax bigint not null check(tax>=0),
 method text not null, created_at timestamptz not null default now()
);
create table public.game_plot_ownership_history (
 id bigint generated always as identity primary key, plot_id uuid not null references public.game_district_plots(id),
 previous_owner jsonb not null, new_owner jsonb not null, sale_id uuid references public.game_property_sales(id),
 actor_id uuid references public.game_players(id), reason text not null, created_at timestamptz not null default now()
);
create table public.game_plot_escrow_entries (
 id bigint generated always as identity primary key, player_id uuid not null references public.game_players(id),
 plot_id uuid not null references public.game_district_plots(id), reference_id uuid not null,
 amount bigint not null, reason text not null, created_at timestamptz not null default now()
);
create table public.game_district_contributions (
 id bigint generated always as identity primary key, season_id uuid not null references public.game_seasons(id),
 district_id uuid not null references public.game_districts(id), player_id uuid not null references public.game_players(id),
 gang_id uuid not null references public.game_season_gangs(id), amount bigint not null, created_at timestamptz not null default now()
);
create index district_contribution_cooldown on public.game_district_contributions(player_id,district_id,created_at desc);
create table public.game_district_jobs (
 district_id uuid not null references public.game_districts(id), job_id text not null references public.game_jobs(id),
 primary key(district_id,job_id)
);
alter table public.game_listings add column district_id uuid references public.game_districts(id);
create index district_local_listings on public.game_listings(season_id,district_id,status);
create table public.game_district_trades (
 id bigint generated always as identity primary key, season_id uuid not null references public.game_seasons(id),
 district_id uuid not null references public.game_districts(id), listing_id uuid not null unique references public.game_listings(id),
 good_id text not null references public.game_goods(id), quantity bigint not null, unit_price bigint not null,
 buyer_id uuid not null references public.game_players(id), seller_id uuid not null references public.game_players(id),
 created_at timestamptz not null default now()
);

-- Every read and mutation is mediated by guarded RPCs. No browser table access.
do $$
declare r record;
begin
 for r in select tablename from pg_tables where schemaname='public' and
 (tablename like 'game_district%' or tablename like 'game_plot%' or tablename in ('game_property_sales','game_building_types','game_zoning')) loop
  execute format('alter table public.%I enable row level security',r.tablename);
  execute format('revoke all on public.%I from public,anon,authenticated',r.tablename);
  if r.tablename in ('game_district_events','game_property_sales','game_plot_ownership_history','game_plot_escrow_entries','game_district_contributions','game_district_trades') then
   execute format('create trigger immutable_rows before update or delete on public.%I for each row execute function game_private.district_immutable()',r.tablename);
   execute format('create trigger immutable_table before truncate on public.%I for each statement execute function game_private.district_immutable()',r.tablename);
  else
   execute format('create trigger audit_district_change after insert or update or delete on public.%I for each row execute function game_private.audit_change()',r.tablename);
  end if;
 end loop;
end $$;
