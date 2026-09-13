-- Cover prison sentence foreign keys reported by the Supabase performance advisor.
create index game_prison_sentences_player_id_idx on public.game_prison_sentences(player_id);
create index game_prison_sentences_actor_id_idx on public.game_prison_sentences(actor_id) where actor_id is not null;
