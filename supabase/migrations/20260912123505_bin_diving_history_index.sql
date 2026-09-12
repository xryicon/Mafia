-- Cover player-account lookups across archived seasons as reward history grows.
create index bin_dives_player on public.game_bin_dives(player_id);

