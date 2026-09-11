
-- Mining catalog persists; titles, equipment, reserves and work runs are seasonal.
insert into public.game_permissions(id,owner_only) values ('mines.manage',true) on conflict do nothing;
insert into public.game_settings(key,value,minimum,maximum) values
 ('mining_pickaxe_cost',100,1,1000000),('mining_pickaxe_durability',100,1,10000),
 ('mining_respect_per_shift',2,0,1000),('mining_offline_cycles',24,1,1000),
 ('mining_auction_default_minutes',1440,5,43200),('mining_auction_min_minutes',5,1,10080),('mining_auction_max_minutes',10080,5,43200)
 on conflict do nothing;
alter table public.game_goods add column business_available boolean not null default true;
-- A raw resource may be traded, but its extraction rights cannot be bought as a generic factory.
create function game_private.mining_business_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if exists(select 1 from public.game_goods where id=new.good_id and not business_available) then
  raise exception 'This resource is gathered in Mines & Quarries. Acquire a mine or use a public site.';
 end if;
 return new;
end $$;
create trigger mining_business_guard before insert or update of good_id on public.game_businesses for each row execute function game_private.mining_business_guard();

alter table public.game_plot_auctions alter column seller_id drop not null;
alter table public.game_plot_auctions add column city_sale boolean not null default false;
alter table public.game_plot_auctions add constraint plot_auction_seller check((seller_id is not null and not city_sale) or (seller_id is null and city_sale));

create table public.game_mine_definitions(
 id uuid primary key default gen_random_uuid(),plot_template_id uuid not null unique references public.game_plot_templates(id),
 name text not null check(length(name) between 3 and 80),description text not null default '' check(length(description)<=2000),
 good_id text not null references public.game_goods(id),image_url text not null default '/art/mining/mine.webp',
 map_x integer not null check(map_x between 90 and 1110),map_y integer not null check(map_y between 80 and 560),
 initial_status text not null default 'closed' check(initial_status in ('open','closed','reserved')),
 initial_access text not null default 'private' check(initial_access in ('public','private')),
 initial_reserve bigint not null check(initial_reserve between 0 and 100000000),
 hand_yield integer not null check(hand_yield between 1 and 1000),
 hand_seconds integer not null check(hand_seconds between 5 and 86400),
 tool_wear integer not null default 1 check(tool_wear between 1 and 10000),
 operation_yield integer not null check(operation_yield between 1 and 10000),
 operation_seconds integer not null check(operation_seconds between 30 and 86400),
 transport text not null default 'Rail + road' check(length(transport)<=80),
 survey_status text not null default 'Surveyed' check(length(survey_status)<=80),
 archived_at timestamptz,
 check(image_url ~ '^/art/[a-zA-Z0-9._/-]+$')
);
create index mine_definition_good on public.game_mine_definitions(good_id);
create table public.game_mines(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 definition_id uuid not null references public.game_mine_definitions(id),plot_id uuid not null unique,
 status text not null check(status in ('open','closed','reserved')),access_mode text not null check(access_mode in ('public','private')),
 remaining bigint not null check(remaining between 0 and 100000000),operated_at timestamptz not null default now(),
 unique(season_id,definition_id),unique(season_id,id),
 foreign key(season_id,plot_id) references public.game_district_plots(season_id,id)
);
create table public.game_mining_tools(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 durability integer not null check(durability between 0 and 10000),primary key(season_id,player_id)
);
create index mining_tools_player on public.game_mining_tools(player_id);
create table public.game_mining_runs(
 id uuid primary key default gen_random_uuid(),season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),mine_id uuid not null,
 good_id text not null references public.game_goods(id),quantity integer not null check(quantity between 1 and 1000),
 respect integer not null check(respect between 0 and 1000),wear integer not null check(wear between 1 and 10000),
 started_at timestamptz not null default now(),ready_at timestamptz not null,
 status text not null default 'working' check(status in ('working','claimed','cancelled')),
 completed_at timestamptz,
 foreign key(season_id,mine_id) references public.game_mines(season_id,id)
);
create unique index mining_one_shift on public.game_mining_runs(season_id,player_id) where status='working';
create index mining_runs_site on public.game_mining_runs(mine_id,status);
create index mining_runs_history on public.game_mining_runs(season_id,player_id,started_at desc);
create table public.game_mining_yields(
 id bigint generated always as identity primary key,season_id uuid not null references public.game_seasons(id),
 player_id uuid not null references public.game_players(id),mine_id uuid not null references public.game_mines(id),
 good_id text not null references public.game_goods(id),quantity integer not null check(quantity>0),
 source text not null check(source in ('hand_mining','operation')),run_id uuid unique references public.game_mining_runs(id),
 created_at timestamptz not null default now()
);
create index mining_yields_site on public.game_mining_yields(mine_id,created_at desc);
create index mining_yields_player on public.game_mining_yields(season_id,player_id,created_at desc);
create table public.game_mine_reserve_ledger(
 id bigint generated always as identity primary key,mine_id uuid not null references public.game_mines(id),
 delta bigint not null,remaining bigint not null,actor_id uuid references public.game_players(id),
 reason text not null,created_at timestamptz not null default now()
);
create index mining_reserve_history on public.game_mine_reserve_ledger(mine_id,id desc);
create table game_private.mining_requests(
 season_id uuid not null references public.game_seasons(id),player_id uuid not null references public.game_players(id),
 request_id uuid not null,action text not null,payload jsonb not null,result jsonb not null,created_at timestamptz not null default now(),
 primary key(season_id,player_id,request_id)
);
create function game_private.mine_reserve_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' or new.remaining<>old.remaining then
  insert into public.game_mine_reserve_ledger(mine_id,delta,remaining,actor_id,reason)
  values(new.id,new.remaining-case when TG_OP='INSERT' then 0 else old.remaining end,new.remaining,auth.uid(),coalesce(nullif(current_setting('game.reason',true),''),'Mining reserve change'));
 end if;
 return new;
end $$;
create trigger mining_reserves after insert or update of remaining on public.game_mines for each row execute function game_private.mine_reserve_record();
do $$
declare tbl text;
begin
 foreach tbl in array array['game_mine_definitions','game_mines','game_mining_tools','game_mining_runs','game_mining_yields','game_mine_reserve_ledger'] loop
  execute format('alter table public.%I enable row level security',tbl);
  execute format('revoke all on public.%I from public,anon,authenticated',tbl);
  if tbl in ('game_mining_yields','game_mine_reserve_ledger') then
   execute format('create trigger immutable_rows before update or delete on public.%I for each row execute function game_private.district_immutable()',tbl);
   execute format('create trigger immutable_table before truncate on public.%I for each statement execute function game_private.district_immutable()',tbl);
  else
   execute format('create trigger mining_audit after insert or update or delete on public.%I for each row execute function game_private.audit_change()',tbl);
  end if;
 end loop;
end $$;
alter table game_private.mining_requests enable row level security;
revoke all on game_private.mining_requests from public,anon,authenticated;
create trigger immutable_rows before update or delete on game_private.mining_requests for each row execute function game_private.district_immutable();
create trigger immutable_table before truncate on game_private.mining_requests for each statement execute function game_private.district_immutable();

alter function game_private.ensure_districts(uuid) rename to ensure_districts_before_mining;
create function game_private.ensure_districts(s uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 perform game_private.ensure_districts_before_mining(s);
 perform set_config('game.reason','Initialize seasonal mining registry',true);
 insert into public.game_district_territory(season_id,district_id,status)
 select s,id,status from public.game_districts where archived_at is null on conflict do nothing;
 insert into public.game_mines(season_id,definition_id,plot_id,status,access_mode,remaining)
 select s,m.id,p.id,m.initial_status,m.initial_access,m.initial_reserve
 from public.game_mine_definitions m join public.game_district_plots p on p.template_id=m.plot_template_id and p.season_id=s
 where m.archived_at is null and p.archived_at is null on conflict(season_id,definition_id) do nothing;
end $$;
create function game_private.mine_title_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.owner_id is distinct from old.owner_id or new.owner_type is distinct from old.owner_type then
  update public.game_mines set operated_at=now() where plot_id=new.id;
 end if;return new;
end $$;
create trigger mine_title_change after update of owner_id,owner_type on public.game_district_plots for each row execute function game_private.mine_title_change();

-- Mine property transactions use the dedicated controls; ordinary district plots retain their current behavior.
alter function game_private.district_act(text,jsonb) rename to district_act_before_mining;
create function game_private.district_act(action text,payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.game_mines where plot_id=nullif(payload->>'plot_id','')::uuid)
 and action not in ('watch','bid','auction_finish') then raise exception 'Use the mine controls for extraction rights and auctions.';end if;
 return game_private.district_act_before_mining(action,payload);
end $$;
alter function game_private.district_manage(text,jsonb) rename to district_manage_before_mining;
create function game_private.district_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform game_private.require_active();
 if not game_private.has_permission('districts.manage') then raise exception 'District management permission required.';end if;
 perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 if p_action='archive_district' and exists(select 1 from public.game_mines m join public.game_district_plots p on p.id=m.plot_id where p.district_id=nullif(p_payload->>'id','')::uuid and (exists(select 1 from public.game_mining_runs r where r.mine_id=m.id and r.status='working') or exists(select 1 from public.game_plot_auctions a where a.plot_id=p.id and a.status='open'))) then return jsonb_build_object('error','Finish mining shifts and auctions before archiving this district.');end if;
 if (p_action='plot' and exists(select 1 from public.game_mine_definitions where plot_template_id=nullif(p_payload->>'id','')::uuid))
 or (p_action='building' and exists(select 1 from public.game_mines where plot_id=nullif(p_payload->>'plot_id','')::uuid))
 then return jsonb_build_object('error','Use Mines & Quarries controls to change mining properties.');end if;
 return game_private.district_manage_before_mining(p_action,p_payload);
end $$;
revoke all on function game_private.mining_business_guard(),game_private.mine_reserve_record(),game_private.mine_title_change(),
 game_private.ensure_districts_before_mining(uuid),game_private.ensure_districts(uuid),
 game_private.district_act_before_mining(text,jsonb),game_private.district_act(text,jsonb),
 game_private.district_manage_before_mining(text,jsonb),game_private.district_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.district_manage(text,jsonb) to authenticated;

