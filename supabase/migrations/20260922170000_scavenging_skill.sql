-- Award Scavenging XP only from authoritative, completed search results.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Add seasonal Scavenging skill progression',true);
insert into public.game_settings(key,value,minimum,maximum)
values('scavenging_skill_xp_per_search',10,0,10000) on conflict(key) do nothing;
alter table public.game_skill_definitions drop constraint game_skill_definitions_id_check;
alter table public.game_skill_definitions add constraint game_skill_definitions_id_check
 check(id in ('crafting','sharpshooting','lockpicking','mining','scavenging'));
insert into public.game_skill_definitions(id,name,description,display_order)
values('scavenging','Scavenging','Search bins and successfully open cars on the streets. Completed searches earn Scavenging XP.',5);
create function game_private.scavenging_skill_award() returns trigger
language plpgsql security definer set search_path='' as $$
declare reward bigint:=game_private.setting('scavenging_skill_xp_per_search')::bigint;
begin
 if new.opened and new.kind in ('bin','car') and reward>0 then
  insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
  values(new.season_id,new.player_id,'scavenging',new.id,reward,
   case when new.kind='bin' then 'Searched a bin' else 'Searched an opened car' end,new.created_at)
  on conflict(skill_id,source_id) do nothing;
 end if;
 return new;
end $$;
create trigger scavenging_skill_award after insert on game_private.scav_results
 for each row execute function game_private.scavenging_skill_award();
revoke all on function game_private.scavenging_skill_award() from public,anon,authenticated;
-- Credit recorded successful searches once, preserving historical season ownership.
insert into game_private.skill_xp_ledger(season_id,player_id,skill_id,source_id,delta,description,created_at)
select season_id,player_id,'scavenging',id,game_private.setting('scavenging_skill_xp_per_search')::bigint,
 case when kind='bin' then 'Searched a bin' else 'Searched an opened car' end,created_at
from game_private.scav_results where opened and kind in ('bin','car')
 and game_private.setting('scavenging_skill_xp_per_search')>0
on conflict(skill_id,source_id) do nothing;
