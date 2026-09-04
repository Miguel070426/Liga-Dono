-- El guardián de managers bloqueaba también al service_role y al superusuario,
-- es decir, cualquier mantenimiento desde el panel de Supabase o desde un
-- script de servidor. Se exceptúan esos contextos.
--
-- Es seguro: sin sesión de usuario final (auth.uid() nulo) solo se llega a esta
-- tabla desde el servidor, porque al rol anon se le revocaron todos los
-- permisos sobre managers.
create or replace function app.managers_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- contextos de servidor de confianza
  if auth.uid() is null
     or current_user in ('postgres','supabase_admin','service_role') then
    return new;
  end if;

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
