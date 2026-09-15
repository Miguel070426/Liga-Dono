-- El escudo que se dibuja cada manager, y el cierre de un agujero que se ha
-- visto al ir a añadirlo.
--
-- ── Primero el agujero, que es lo importante ────────────────────────────────
--
-- La política `managers_own` deja a cada uno escribir en SU fila, que es lo
-- que se quería: cambiar el nombre de su club. Pero los permisos de columna
-- estaban abiertos de par en par: `authenticated` tenía UPDATE sobre TODAS
-- las columnas de managers, `is_admin` incluida.
--
-- Las políticas deciden QUÉ FILAS puedes tocar; los permisos de columna
-- deciden QUÉ CAMPOS. Aquí la fila era la suya —correcto— pero el campo podía
-- ser cualquiera. Comprobado contra la base de datos real haciéndose pasar por
-- un jugador: `update managers set is_admin = true` sobre su propia fila pasa
-- sin error, y `app.is_admin()` devuelve true a continuación. Es decir,
-- cualquiera de los doce podía abrirse el panel de dirección y desde ahí
-- cargar resultados, cerrar la jornada o cambiarle la contraseña a otro.
--
-- Nadie lo ha usado: hoy solo hay una plaza fichada y es la de la
-- organización. Pero esto se cierra antes de que entren los otros once.
--
-- El arreglo es dejar a `authenticated` solo las tres columnas que una persona
-- tiene por qué cambiar de sí misma. Todo lo demás lo escriben funciones
-- `security definer` que comprueban quién llama.

-- La columna del escudo se crea aquí arriba porque el grant de abajo la
-- nombra; lo que es y por qué se guarda así está explicado más adelante.
alter table managers add column if not exists escudo text;

revoke update on managers from authenticated;
grant  update (club_name, owner_name, escudo) on managers to authenticated;

-- «Liberar plaza» del panel escribía user_id, usuario y claimed_at
-- directamente, y eso ya no se puede desde el navegador. Pasa a ser una
-- función que comprueba que quien llama es la organización.
create or replace function liberar_plaza(p_manager uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede liberar una plaza';
  end if;
  update managers
     set user_id = null, usuario = null, claimed_at = null, escudo = null,
         is_admin = false, club_name = 'Plaza ' || slot, owner_name = ''
   where id = p_manager;
  get diagnostics n = row_count;
  if n = 0 then raise exception 'Esa plaza no existe'; end if;
end $$;

revoke execute on function liberar_plaza(uuid) from public, anon;
grant  execute on function liberar_plaza(uuid) to authenticated;

-- ── El escudo ───────────────────────────────────────────────────────────────
--
-- No se guarda una imagen, se guarda la receta para dibujarla: forma, diseño,
-- los dos colores, el símbolo y las iniciales, separados por barras. Unos 30
-- caracteres. Los doce escudos de una liga ocupan menos que este comentario.
--
-- Guardar una imagen habría costado almacenamiento y tráfico —justo el
-- recurso que limita cuántas ligas caben a la vez— y habría obligado a alguien
-- a moderar lo que suben. Así no hay nada que moderar: solo se puede elegir
-- entre lo que el juego ofrece.

comment on column managers.escudo is
  'Receta del escudo: forma|diseño|color1|color2|símbolo|iniciales. No es una imagen; el navegador lo dibuja.';

-- La restricción es de forma, no de contenido: impide que en esta columna
-- acabe texto arbitrario. Que la forma y el símbolo existan de verdad lo
-- comprueba el navegador al dibujar, que es quien tiene el catálogo; ante algo
-- que no reconoce pinta el escudo por defecto en vez de fallar.
alter table managers drop constraint if exists managers_escudo_formato;
alter table managers add constraint managers_escudo_formato
  check (escudo is null or escudo ~
    '^[a-z]{2,10}\|[a-z]{2,10}\|[0-9a-f]{6}\|[0-9a-f]{6}\|[a-z0-9]{2,10}\|[A-ZÑ0-9]{0,3}$');

-- ── Fichar plaza, ahora con escudo ──────────────────────────────────────────

create or replace function claim_slot(p_slot int, p_club text, p_owner text,
                                      p_usuario text, p_join_code text,
                                      p_escudo text)
returns managers
language plpgsql security definer set search_path = public, pg_temp as $$
declare m managers; lg leagues; u text;
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  if coalesce(trim(p_club),'') = '' or coalesce(trim(p_owner),'') = '' then
    raise exception 'Hacen falta tu nombre y el nombre del club';
  end if;

  u := lower(trim(coalesce(p_usuario,'')));
  if length(u) < 3 then
    raise exception 'El usuario necesita al menos 3 caracteres';
  end if;

  select * into lg from leagues order by created_at limit 1;

  -- quien ya tiene plaza solo renombra: no necesita el código otra vez
  select * into m from managers where user_id = auth.uid();
  if m.id is not null then
    update managers
       set club_name = trim(p_club), owner_name = trim(p_owner),
           escudo = coalesce(p_escudo, escudo)
     where id = m.id returning * into m;
    return m;
  end if;

  if upper(coalesce(trim(p_join_code),'')) <> upper(lg.join_code) then
    raise exception 'El código de la liga no es correcto';
  end if;

  if exists (select 1 from managers x
              where x.league_id = lg.id and lower(x.usuario) = u) then
    raise exception 'Ese usuario ya está cogido, elige otro';
  end if;

  update managers
     set user_id = auth.uid(), club_name = trim(p_club),
         owner_name = trim(p_owner), usuario = u, escudo = p_escudo,
         claimed_at = now()
   where league_id = lg.id and slot = p_slot and user_id is null
  returning * into m;

  if m.id is null then
    raise exception 'Esa plaza ya está ocupada, elige otra';
  end if;
  return m;
end $$;

revoke execute on function claim_slot(int, text, text, text, text, text) from public, anon;
grant  execute on function claim_slot(int, text, text, text, text, text) to authenticated;

-- La versión de cinco argumentos se queda, delegando. Un móvil que siga con el
-- JavaScript de antes en la caché llama a esa; si se borrase, ficharía la
-- cuenta en Auth y luego fallaría al reclamar la plaza, que es exactamente el
-- lío de cuentas a medias que ya pasó una vez.
create or replace function claim_slot(p_slot int, p_club text, p_owner text,
                                      p_usuario text, p_join_code text)
returns managers
language sql security invoker set search_path = public, pg_temp as $$
  select claim_slot(p_slot, p_club, p_owner, p_usuario, p_join_code, null::text)
$$;

revoke execute on function claim_slot(int, text, text, text, text) from public, anon;
grant  execute on function claim_slot(int, text, text, text, text) to authenticated;

-- ── Cambiar el escudo después ───────────────────────────────────────────────
-- Para quien ya fichó antes de que esto existiera, y para el que se arrepienta
-- del color. Escribe solo en la fila de quien llama.

create or replace function guardar_escudo(p_escudo text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  update managers set escudo = p_escudo where user_id = auth.uid();
  get diagnostics n = row_count;
  if n = 0 then
    raise exception 'No tienes plaza en esta liga';
  end if;
end $$;

revoke execute on function guardar_escudo(text) from public, anon;
grant  execute on function guardar_escudo(text) to authenticated;
