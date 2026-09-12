-- Run only in isolated CI, immediately before applying the loot migration.
begin;
insert into auth.users(id) values('eeeeeeee-4000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','eeeeeeee-4000-4000-8000-000000000001',true);
select public.game_state();
insert into public.game_bin_inventory(season_id,player_id,item,quantity)
 select game_private.current_season(),'eeeeeeee-4000-4000-8000-000000000001',item,7 from unnest(array['pickaxe','pistol_blueprint','bullet_blueprint']) item;
\ir ../migrations/20260912133819_tradable_bin_loot.sql
do $$ declare blocked boolean:=false;begin
 if (select sum(quantity) from public.game_inventory where player_id='eeeeeeee-4000-4000-8000-000000000001' and good_id in ('pickaxe','pistol_blueprint','bullet_blueprint')) is distinct from 21 then raise exception 'Existing loot was not preserved';end if;
 if (public.bin_diving_state()->'inventory'->>'pickaxe')::int is distinct from 7 then raise exception 'Migrated stash is not visible';end if;
 begin update public.game_bin_inventory set quantity=8;exception when raise_exception then blocked:=true;end;
 if not blocked then raise exception 'Retired snapshot is writable';end if;
 if (select sum(quantity) from public.game_bin_inventory where player_id='eeeeeeee-4000-4000-8000-000000000001') is distinct from 21 then raise exception 'Original stash destroyed';end if;
end $$;
select 'PASS: existing finds survive the inventory upgrade and retain an immutable snapshot';
rollback;
