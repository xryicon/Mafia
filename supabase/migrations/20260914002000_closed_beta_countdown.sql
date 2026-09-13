-- Owner-controlled launch time for the public closed-beta landing countdown.
insert into public.game_settings(key,value,minimum,maximum)
values('closed_beta_starts_at_unix',extract(epoch from timestamptz '2026-10-01 18:00:00+00')::integer,0,2147483647)
on conflict(key) do nothing;

create function public.closed_beta_state() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'starts_at',to_timestamp(value),
  'server_time',statement_timestamp()
 )
 from public.game_settings
 where key='closed_beta_starts_at_unix'
$$;

revoke all on function public.closed_beta_state() from public;
grant execute on function public.closed_beta_state() to anon,authenticated;
notify pgrst,'reload schema';
