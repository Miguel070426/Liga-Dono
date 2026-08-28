-- NOTA: los códigos que aparecen abajo fueron solo los valores iniciales de la
-- siembra. Se cambiaron después, porque este repositorio es público. Los códigos
-- vivos están en la base de datos: select join_code, admin_claim_code from leagues;

-- La web va en una URL pública, así que fichar plaza necesita una puerta:
-- sin código de liga, cualquiera que encuentre el enlace podía ocupar una
-- plaza libre. Leer y escribir datos ya estaba cerrado; esto cierra el alta.
alter table leagues add column if not exists join_code text not null default 'DONO-2026';
comment on column leagues.join_code is 'código que hay que meter para fichar plaza; se reparte entre los 12';

create or replace function claim_slot(p_slot int, p_club text, p_owner text, p_join_code text)
returns managers
language plpgsql security definer set search_path = public, pg_temp as $$
declare m managers; lg leagues;
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  if coalesce(trim(p_club),'') = '' or coalesce(trim(p_owner),'') = '' then
    raise exception 'Hacen falta tu nombre y el nombre del club';
  end if;

  select * into lg from leagues order by created_at limit 1;

  -- quien ya tiene plaza solo renombra: no necesita el código otra vez
  select * into m from managers where user_id = auth.uid();
  if m.id is not null then
    update managers set club_name = trim(p_club), owner_name = trim(p_owner)
     where id = m.id returning * into m;
    return m;
  end if;

  if upper(coalesce(trim(p_join_code),'')) <> upper(lg.join_code) then
    raise exception 'El código de la liga no es correcto';
  end if;

  update managers
     set user_id = auth.uid(), club_name = trim(p_club),
         owner_name = trim(p_owner), claimed_at = now()
   where league_id = lg.id and slot = p_slot and user_id is null
  returning * into m;

  if m.id is null then
    raise exception 'Esa plaza ya está ocupada, elige otra';
  end if;
  return m;
end $$;

grant execute on function claim_slot(int, text, text, text) to authenticated;
revoke execute on function claim_slot(int, text, text, text) from anon;

-- Fuera la versión sin código, para que no quede una puerta de atrás abierta.
drop function if exists claim_slot(int, text, text);
