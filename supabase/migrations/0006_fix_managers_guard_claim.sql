-- El guardián de managers impedía la propia operación de reclamar plaza:
-- quien la reclama aún no es admin, y el disparador veía un cambio de user_id.
--
-- Se permite únicamente la transición legítima (plaza libre -> tu propia
-- cuenta). No se puede abusar por la vía directa: la política managers_own
-- solo deja actualizar la fila que ya es tuya, así que a una plaza libre solo
-- se llega a través de claim_slot.
create or replace function app.managers_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if app.is_admin() then return new; end if;

  -- reclamar una plaza libre para uno mismo
  if old.user_id is null and new.user_id = auth.uid()
     and new.slot = old.slot and new.league_id = old.league_id
     and new.is_admin = old.is_admin then
    return new;
  end if;

  if new.slot <> old.slot or new.league_id <> old.league_id
     or coalesce(new.user_id::text,'') <> coalesce(old.user_id::text,'')
     or new.is_admin <> old.is_admin then
    raise exception 'Solo la organización puede cambiar la plaza, la cuenta o el rol';
  end if;
  return new;
end $$;
