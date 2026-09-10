-- Reference data is seeded by versioned migrations. This idempotent seed is safe to rerun.
-- Never creates Auth users, changes balances, or assigns Owner.
insert into public.game_user_roles(player_id,role_id)
select id,'player' from public.game_players on conflict do nothing;
