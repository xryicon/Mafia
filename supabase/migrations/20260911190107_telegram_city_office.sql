-- Permanent singleton; private messages are never copied into economic or general audit logs.
create table public.game_telegram_office (
 id boolean primary key default true check(id), template_id uuid not null unique references public.game_plot_templates(id),
 season_id uuid references public.game_seasons(id), plot_id uuid references public.game_district_plots(id),
 building_id uuid references public.game_district_buildings(id), business_id uuid references public.game_district_businesses(id),
 minimum_fee integer not null default 0 check(minimum_fee>=0), maximum_fee integer not null default 500 check(maximum_fee>=minimum_fee),
 default_fee integer not null default 25, available boolean not null default true,
 reset_sale_price bigint not null default 15000 check(reset_sale_price>0),
 updated_at timestamptz not null default now(), check(default_fee between minimum_fee and maximum_fee)
);
insert into public.game_telegram_office(template_id) select id from public.game_plot_templates where building_type='telegram' and archived_at is null;
update public.game_plot_templates set business_name='Blackwater Telegram Office',strategic_type='Unique Telegram Office' where building_type='telegram';
update public.game_district_plots set strategic_type='Unique Telegram Office' where template_id=(select template_id from public.game_telegram_office);
update public.game_district_businesses set name='Blackwater Telegram Office' where telegram_fee is not null;
update public.game_building_types set active=false where id='telegram';
update public.game_zoning set allowed_buildings=array_remove(allowed_buildings,'telegram');
alter table public.game_building_types add constraint unique_telegram_type check(telegram_fee is null or id='telegram');
create unique index telegram_one_template on public.game_plot_templates((true)) where building_type='telegram' and archived_at is null;
create unique index telegram_one_building on public.game_district_buildings((true)) where building_type='telegram' and archived_at is null;
create unique index telegram_one_business on public.game_district_businesses((true)) where telegram_fee is not null and archived_at is null;
insert into public.game_permissions(id,owner_only) values('telegrams.manage',true) on conflict do nothing;
insert into public.game_settings(key,value,minimum,maximum) values
 ('telegram_send_rate',30,1,120),('telegram_subject_limit',160,1,160),('telegram_body_limit',4000,1,4000) on conflict do nothing;
create table game_private.telegram_threads (
 id uuid primary key default gen_random_uuid(), first_player uuid not null references public.game_players(id),
 second_player uuid not null references public.game_players(id), subject text not null check(length(subject) between 1 and 160),
 created_at timestamptz not null default now(), check(first_player<>second_player)
);
create index telegram_threads_first on game_private.telegram_threads(first_player,created_at desc);
create index telegram_threads_second on game_private.telegram_threads(second_player,created_at desc);
create table game_private.telegrams (
 id uuid primary key default gen_random_uuid(), thread_id uuid not null references game_private.telegram_threads(id),
 sender_id uuid not null references public.game_players(id), recipient_id uuid not null references public.game_players(id),
 body text not null check(length(body) between 1 and 4000), season_id uuid not null references public.game_seasons(id),
 request_id uuid not null, created_at timestamptz not null default now(), unique(sender_id,request_id), check(sender_id<>recipient_id)
);
create index telegram_thread_feed on game_private.telegrams(thread_id,created_at desc,id);
create index telegram_inbox on game_private.telegrams(recipient_id,created_at desc);
create index telegram_sent on game_private.telegrams(sender_id,created_at desc);
create table game_private.telegram_folders (
 player_id uuid not null references public.game_players(id), thread_id uuid not null references game_private.telegram_threads(id),
 archived boolean not null default false, starred boolean not null default false, read_at timestamptz, primary key(player_id,thread_id)
);
create table game_private.telegram_drafts (
 id uuid primary key default gen_random_uuid(), player_id uuid not null references public.game_players(id),
 recipient text not null default '', subject text not null default '' check(length(subject)<=160),
 body text not null default '' check(length(body)<=4000), updated_at timestamptz not null default now(), deleted_at timestamptz
);
create index telegram_drafts_player on game_private.telegram_drafts(player_id,updated_at desc) where deleted_at is null;
create table game_private.telegram_blocks (
 player_id uuid not null references public.game_players(id), blocked_id uuid not null references public.game_players(id),
 created_at timestamptz not null default now(), primary key(player_id,blocked_id),check(player_id<>blocked_id)
);
create table game_private.telegram_reports (
 case_id uuid primary key references public.game_cases(id), message_id uuid not null references game_private.telegrams(id),
 reporter_id uuid not null references public.game_players(id), created_at timestamptz not null default now(), unique(message_id,reporter_id)
);
create table game_private.telegram_receipts (
 message_id uuid primary key references game_private.telegrams(id), season_id uuid not null references public.game_seasons(id),
 business_id uuid not null references public.game_district_businesses(id), owner_type text not null, owner_id uuid not null,
 payout_player_id uuid references public.game_players(id), fee bigint not null check(fee>=0), created_at timestamptz not null default now()
);
create index telegram_receipts_season on game_private.telegram_receipts(season_id,created_at);
create table game_private.telegram_accounts (
 season_id uuid not null references public.game_seasons(id), owner_type text not null, owner_id uuid not null,
 balance bigint not null default 0 check(balance>=0), primary key(season_id,owner_type,owner_id)
);
create table game_private.telegram_account_ledger (
 id bigint generated always as identity primary key, season_id uuid not null, owner_type text not null, owner_id uuid not null,
 message_id uuid not null unique references game_private.telegrams(id), delta bigint not null check(delta>=0),
 balance_before bigint not null, balance_after bigint not null, reason text not null, created_at timestamptz not null default now(),
 foreign key(season_id,owner_type,owner_id) references game_private.telegram_accounts(season_id,owner_type,owner_id),
 check(balance_after=balance_before+delta and balance_before>=0)
);
alter table public.game_telegram_office enable row level security;
revoke all on public.game_telegram_office from public,anon,authenticated;
create trigger telegram_office_audit after insert or update or delete on public.game_telegram_office for each row execute function game_private.audit_change();
create trigger telegram_office_retain before delete on public.game_telegram_office for each row execute function game_private.no_delete();
create trigger telegram_office_retain_table before truncate on public.game_telegram_office for each statement execute function game_private.no_delete();
do $$ declare r record; begin
 for r in select tablename from pg_tables where schemaname='game_private' and (tablename like 'telegram_%' or tablename='telegrams') loop
  execute format('alter table game_private.%I enable row level security',r.tablename);
  execute format('revoke all on game_private.%I from public,anon,authenticated',r.tablename);
  if r.tablename in ('telegrams','telegram_threads','telegram_receipts','telegram_account_ledger','telegram_reports') then
   execute format('create trigger retain_rows before update or delete on game_private.%I for each row execute function game_private.immutable()',r.tablename);
   execute format('create trigger retain_table before truncate on game_private.%I for each statement execute function game_private.immutable()',r.tablename);
  end if;
 end loop;
end $$;
create function game_private.telegram_business_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare o public.game_telegram_office; b public.game_district_buildings; p public.game_district_plots;
begin
 select * into b from public.game_district_buildings where id=new.building_id;
 if (b.building_type='telegram') is distinct from (new.telegram_fee is not null) then raise exception 'Only the unique Telegram Office can charge telegram fees.'; end if;
 if new.telegram_fee is not null and new.archived_at is null then
  select * into strict o from public.game_telegram_office;
  select * into strict p from public.game_district_plots where id=new.plot_id;
  if p.template_id<>o.template_id or b.plot_id<>p.id or new.owner_id<>p.owner_id or new.owner_type<>p.owner_type then raise exception 'The Telegram Office must match its unique strategic property.'; end if;
  if new.telegram_fee not between o.minimum_fee and o.maximum_fee then raise exception 'Telegram fee must be between $% and $%.',o.minimum_fee,o.maximum_fee; end if;
 end if;
 return new;
end $$;
create trigger telegram_business_guard before insert or update on public.game_district_businesses for each row execute function game_private.telegram_business_guard();
alter function game_private.ensure_districts(uuid) rename to ensure_districts_before_telegrams;
create function game_private.ensure_districts(s uuid) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare o public.game_telegram_office; b public.game_district_businesses;
begin
 perform pg_advisory_xact_lock(4704020);
 select * into strict o from public.game_telegram_office for update;
 if o.season_id is distinct from s then
  update public.game_district_businesses set archived_at=now(),status='closed' where telegram_fee is not null and season_id<>s and archived_at is null;
  update public.game_district_buildings set archived_at=now() where building_type='telegram' and season_id<>s and archived_at is null;
  update public.game_building_types set telegram_fee=o.default_fee where id='telegram';
 end if;
 perform game_private.ensure_districts_before_telegrams(s);
 select * into strict b from public.game_district_businesses where telegram_fee is not null and season_id=s and archived_at is null;
 if o.season_id is distinct from s then
  update public.game_district_businesses set telegram_fee=o.default_fee where id=b.id;
  update public.game_district_plots set asking_price=o.reset_sale_price,offers_allowed=false where id=b.plot_id and owner_type in ('city','company');
  update public.game_telegram_office set season_id=s,plot_id=b.plot_id,building_id=b.building_id,business_id=b.id,updated_at=now();
 end if;
end $$;
select game_private.ensure_districts(game_private.current_season());
create function game_private.telegram_singleton_check() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if (select count(*) from public.game_district_businesses where telegram_fee is not null and archived_at is null)<>1
 or not exists(select 1 from public.game_telegram_office o join public.game_district_businesses b on b.id=o.business_id
 join public.game_district_buildings g on g.id=o.building_id join public.game_district_plots p on p.id=o.plot_id
 where b.archived_at is null and g.archived_at is null and g.building_type='telegram'
 and b.plot_id=p.id and g.plot_id=p.id and b.building_id=g.id and p.template_id=o.template_id
 and b.season_id=o.season_id and b.telegram_fee between o.minimum_fee and o.maximum_fee) then
  raise exception 'The city must retain exactly one Telegram Office. Use Telegram Office controls.';
 end if;
 return null;
end $$;
create constraint trigger telegram_singleton_business after insert or update or delete on public.game_district_businesses deferrable initially deferred for each row execute function game_private.telegram_singleton_check();
create constraint trigger telegram_singleton_building after insert or update or delete on public.game_district_buildings deferrable initially deferred for each row execute function game_private.telegram_singleton_check();
create constraint trigger telegram_singleton_office after insert or update or delete on public.game_telegram_office deferrable initially deferred for each row execute function game_private.telegram_singleton_check();
alter function game_private.district_manage(text,jsonb) rename to district_manage_before_telegrams;
create function game_private.district_manage(p_action text,p_payload jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.game_telegram_office;
begin
 perform game_private.require_active();
 if not game_private.has_permission('districts.manage') then raise exception 'District management permission required.'; end if;
 perform game_private.season_guard(false);perform pg_advisory_xact_lock(4704020);
 select * into strict o from public.game_telegram_office;
 if (p_action='building' and ((p_payload->>'plot_id')::uuid=o.plot_id or p_payload->>'building_type'='telegram'))
 or (p_action='building_type' and (p_payload->>'id'='telegram' or nullif(p_payload->>'telegram_fee','') is not null))
 or (p_action='plot' and nullif(p_payload->>'id','')::uuid=o.template_id)
 or (p_action='zoning' and p_payload->'allowed_buildings' ? 'telegram')
 or (p_action='archive_district' and (p_payload->>'id')::uuid=(select district_id from public.game_district_plots where id=o.plot_id)) then
  return jsonb_build_object('error','This is the unique city Telegram Office. Use its dedicated Owner controls.');
 end if;
 return game_private.district_manage_before_telegrams(p_action,p_payload);
end $$;
revoke all on function game_private.telegram_business_guard(),game_private.telegram_singleton_check(),game_private.ensure_districts_before_telegrams(uuid),game_private.ensure_districts(uuid),game_private.district_manage_before_telegrams(text,jsonb),game_private.district_manage(text,jsonb) from public,anon,authenticated;
grant execute on function game_private.district_manage(text,jsonb) to authenticated;

