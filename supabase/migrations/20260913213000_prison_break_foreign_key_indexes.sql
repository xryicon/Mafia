-- Cover the direct inmate and rescuer foreign-key lookups used during
-- sentence cleanup and player deletion.
create index if not exists prison_break_attempt_inmate_fk
  on game_private.prison_break_attempts (inmate_id);

create index if not exists prison_break_attempt_rescuer_fk
  on game_private.prison_break_attempts (rescuer_id);
