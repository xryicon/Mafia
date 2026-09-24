-- Equipped armour backs both displayed protection and street damage absorption.
select pg_advisory_xact_lock(4704020);
select set_config('game.reason','Connect equipped armour to player vitals and damage',true);
create function game_private.equipped_armour(s uuid,u uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(floor(r.defense*least(1,greatest(0,coalesce(g.condition,r.condition_max)::numeric/r.condition_max)))),0)
 from public.game_inventory_gear g join game_private.robbery_gear_rules r on r.good_id=g.good_id
 where g.season_id=s and g.player_id=u and g.location='equipped' and g.equipment_slot='armor' and g.quantity>0;
$$;
create function game_private.absorb_armour(s uuid,u uuid,damage numeric) returns numeric language plpgsql security definer set search_path='' as $$
declare g record;available numeric;remaining numeric;used numeric;total numeric:=0;base numeric;
begin
 if damage is null or damage<=0 then return 0;end if;
 perform 1 from public.game_players where id=u and season_id=s for update;
 remaining:=least(damage,game_private.setting('armour_max'));
 for g in select e.id,e.condition,r.defense,r.condition_max from public.game_inventory_gear e join game_private.robbery_gear_rules r on r.good_id=e.good_id
 where e.season_id=s and e.player_id=u and e.location='equipped' and e.equipment_slot='armor' and e.quantity>0 and r.defense>0 for update of e loop
  available:=floor(g.defense*least(1,greatest(0,coalesce(g.condition,g.condition_max)::numeric/g.condition_max)));
  used:=least(remaining,available);
  if used>0 then
   -- Round wear upward so durability can never restore consumed protection.
   update public.game_inventory_gear set condition=greatest(0,floor((available-used)*g.condition_max/g.defense))::integer where id=g.id;
   total:=total+used;remaining:=remaining-used;
  end if;
 end loop;
 select armour into base from public.game_season_players where season_id=s and player_id=u for update;
 used:=least(remaining,coalesce(base,0));
 if used>0 then update public.game_season_players set armour=greatest(0,armour-used) where season_id=s and player_id=u;total:=total+used;end if;
 return total;
end$$;
revoke all on function game_private.equipped_armour(uuid,uuid),game_private.absorb_armour(uuid,uuid,numeric) from public,anon,authenticated;
do $$declare def text;target regprocedure;old_value text:='least(armour_limit,coalesce(v.armour,0))';begin
 select pg_get_functiondef('game_private.vitals_state()'::regprocedure) into def;
 if position(old_value in def)=0 then raise exception 'Review vitals armour integration';end if;
 execute replace(def,old_value,'least(armour_limit,coalesce(v.armour,0)+game_private.equipped_armour(s,u))');
 -- Update every retained street action implementation, including delegated ones.
 for target in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','game_private') and p.prokind='f' and p.prosrc like '%absorbed:=least((vit->>''armour'')::numeric,damage)%' loop
  def:=pg_get_functiondef(target);
  if position('armour=greatest(0,armour-absorbed)' in def)=0 then raise exception 'Review street damage integration';end if;
  def:=replace(def,'absorbed:=least((vit->>''armour'')::numeric,damage)','absorbed:=game_private.absorb_armour(s,u,damage)');
  def:=replace(def,',armour=greatest(0,armour-absorbed)','');execute def;
 end loop;
end$$;
update public.game_goods set inventory_description=case id when 'kevlar-vest' then 'A protective vest. Equip in Armour to absorb street damage and improve robbery defence. Protection falls as its condition wears.' else 'A reinforced coat. Equip in Armour to absorb street damage and improve robbery defence. Protection falls as its condition wears.' end where id in ('kevlar-vest','reinforced-jacket');
notify pgrst,'reload schema';
