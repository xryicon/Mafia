-- The public read RPC is SECURITY INVOKER, so authenticated callers need
-- EXECUTE on its guarded SECURITY DEFINER implementation after replacement.
grant execute on function game_private.bin_state() to authenticated;
