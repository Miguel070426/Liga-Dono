-- Copia de seguridad.
--
-- El plan gratuito de Supabase no da copias que se puedan restaurar, así que
-- hasta aquí no había ninguna red. Y el riesgo de verdad no es que Supabase
-- pierda la base de datos —eso no pasa— sino que **algo borre datos**: un
-- fallo, una pulsación en el panel, un `delete` sin `where`. Probando el ciclo
-- de hoy quedaron en la base real una alineación fantasma y un jugador de
-- prueba; se vieron y se quitaron, pero esa es exactamente la forma en la que
-- se pierde una clasificación en la jornada 8.
--
-- Hay dos formas de perder los datos y hacen falta dos remedios:
--
--   · Algo los borra y el proyecto sigue vivo → se restaura de una copia
--     guardada dentro de la propia base. Un clic.
--   · Se pierde el proyecto entero → una copia dentro de la base no sirve de
--     nada. Para eso está el botón de descargar, que se lleva un .json al
--     ordenador. Ese es el único respaldo que sobrevive al proyecto.
--
-- Qué se guarda: lo que no se puede volver a bajar. Las alineaciones son
-- irrecuperables —son decisiones de doce personas, no un dato que esté en
-- ningún sitio— y lo mismo las plazas, los escudos, los nombres de club y las
-- decisiones sobre jornadas. Las estadísticas sí se podrían volver a bajar de
-- la API, pero a una llamada por partido, así que se guardan igual: ocupan
-- poco y ahorran 110 llamadas.
--
-- Qué NO se guarda: `hl_matches` y `hl_players`, que son la copia local del
-- calendario y se rehacen con 4 llamadas; y `latidos`, `app_avisos` y
-- `app_api_uso`, que son registros de funcionamiento, no la liga.
--
-- Toda la base ocupa hoy menos de dos megas, así que una copia entera es
-- barata y no hay que elegir.

-- ── donde viven ─────────────────────────────────────────────────────────────

create table if not exists app_copias (
  id       bigserial primary key,
  cuando   timestamptz not null default now(),
  motivo   text not null,
  jornada  int,
  bytes    int,
  datos    jsonb not null
);

create index if not exists app_copias_orden on app_copias (cuando desc);

alter table app_copias enable row level security;
-- Nadie la lee desde el navegador directamente: se pasa por las funciones, que
-- comprueban quién pregunta. Una copia lleva dentro TODO, incluidos los dos
-- códigos de la liga, así que no puede quedar al alcance de los doce.
revoke all on app_copias from anon, authenticated;

comment on table app_copias is
  'Copias de seguridad de la liga. Contienen los códigos: solo la organización.';

-- ── las tablas, en orden de dependencia ─────────────────────────────────────
-- Los padres primero para insertar, y al revés para borrar. `leagues` no se
-- borra nunca: al borrarla se llevaría por delante en cascada cosas que no son
-- de la liga (los avisos, los latidos), así que esa se actualiza en el sitio.

create or replace function app.tablas_de_copia() returns text[]
language sql immutable as $$
  select array[
    'clubs', 'managers', 'club_players', 'fixtures',
    'jornada_rondas', 'jornada_excluidos',
    'lineups', 'lineup_slots',
    'club_stats', 'player_jornada_stats',
    'playoff_series', 'playoff_games'
  ]
$$;

-- ── hacer la copia ──────────────────────────────────────────────────────────

create or replace function app.copia_de_seguridad(p_motivo text default 'a mano')
returns bigint
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare d jsonb := '{}'::jsonb; t text; filas jsonb; nueva bigint; j int;
begin
  select current_jornada into j from leagues limit 1;

  -- la liga aparte, porque no entra en el bucle de borrado
  select coalesce(jsonb_agg(to_jsonb(l)), '[]'::jsonb) into filas from leagues l;
  d := jsonb_set(d, array['leagues'], filas, true);

  foreach t in array app.tablas_de_copia() loop
    execute format('select coalesce(jsonb_agg(to_jsonb(x)), ''[]''::jsonb) from %I x', t)
      into filas;
    d := jsonb_set(d, array[t], filas, true);
  end loop;

  insert into app_copias (motivo, jornada, bytes, datos)
  values (p_motivo, j, octet_length(d::text), d)
  returning id into nueva;

  -- Se guardan las 25 últimas. Con una por jornada y una diaria, eso es más de
  -- un mes de historia, y la que de verdad importa es siempre la de antes de
  -- que algo se rompiera.
  delete from app_copias
   where id not in (select id from app_copias order by cuando desc limit 25);

  return nueva;
end $$;

revoke execute on function app.copia_de_seguridad(text) from public, anon, authenticated;
revoke execute on function app.tablas_de_copia()        from public, anon, authenticated;

-- ── restaurar ───────────────────────────────────────────────────────────────
-- Lo primero que hace es otra copia. Una restauración equivocada tiene que
-- poder deshacerse, o el remedio es peor que la enfermedad.
--
-- Aviso que la pantalla repite: restaurar devuelve la liga a como estaba
-- ENTERA. Si alguien fichó plaza después de esa copia, se queda sin plaza (su
-- cuenta sigue existiendo, pero tendría que volver a fichar).

create or replace function app.restaurar_copia(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  c app_copias; t text; tablas text[]; i int; n int;
  sets text; antes bigint; puestas jsonb := '{}'::jsonb;
begin
  select * into c from app_copias where id = p_id;
  if not found then raise exception 'No existe la copia %', p_id; end if;

  antes := app.copia_de_seguridad('antes de restaurar la copia ' || p_id);

  tablas := app.tablas_de_copia();

  -- El disparador de apertura de jornada tiene que callarse mientras se
  -- restaura. Si no, al devolver `current_jornada` a su valor lo toma por un
  -- cambio de jornada y pisa `jornada_desde` con la hora de ahora — y esa
  -- columna es la que decide a qué hora cierra la jornada, así que restaurar
  -- movía el cierre en silencio. Lo cazó la prueba de huellas: doce tablas
  -- volvían idénticas y `leagues` no.
  alter table leagues disable trigger leagues_apertura_de_jornada;

  begin
    -- borrar de las hojas hacia la raíz
    for i in reverse array_length(tablas, 1)..1 loop
      execute format('delete from %I', tablas[i]);
    end loop;

    -- la liga, actualizada en el sitio, con todas sus columnas
    select string_agg(format('%I = excluded.%I', attname, attname), ', ')
      into sets
    from pg_attribute
    where attrelid = 'leagues'::regclass and attnum > 0 and not attisdropped
      and attname <> 'id';

    execute format(
      'insert into leagues select * from jsonb_populate_recordset(null::leagues, $1)
         on conflict (id) do update set %s', sets)
    using c.datos -> 'leagues';

    -- y el resto, de la raíz hacia las hojas
    foreach t in array tablas loop
      execute format('insert into %I select * from jsonb_populate_recordset(null::%I, $1)', t, t)
        using coalesce(c.datos -> t, '[]'::jsonb);
      execute format('select count(*) from %I', t) into n;
      puestas := jsonb_set(puestas, array[t], to_jsonb(n), true);
    end loop;
  exception when others then
    -- Se vuelve a encender aunque la restauración falle: dejarlo apagado sería
    -- peor que el problema original.
    alter table leagues enable trigger leagues_apertura_de_jornada;
    raise;
  end;

  alter table leagues enable trigger leagues_apertura_de_jornada;

  -- Probado sobre la base real: se toma huella md5 de las 13 tablas, se
  -- destroza la liga a propósito (nombres de club, plazas, jornada en curso,
  -- porteros borrados, jornadas borradas) y se restaura. Las 13 vuelven
  -- idénticas.
  return jsonb_build_object(
    'restaurada', p_id,
    'de_cuando',  c.cuando,
    'motivo',     c.motivo,
    'respaldo',   antes,
    'filas',      puestas);
end $$;

revoke execute on function app.restaurar_copia(bigint) from public, anon, authenticated;

-- ── lo que ve y toca la organización ────────────────────────────────────────

create or replace function copias()
returns table(id bigint, cuando timestamptz, motivo text, jornada int, bytes int,
              alineaciones int, huecos int, fichas int, estadisticas int)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede ver las copias';
  end if;
  return query
  select c.id, c.cuando, c.motivo, c.jornada, c.bytes,
         jsonb_array_length(coalesce(c.datos -> 'lineups', '[]'::jsonb)),
         jsonb_array_length(coalesce(c.datos -> 'lineup_slots', '[]'::jsonb)),
         jsonb_array_length(coalesce(c.datos -> 'club_players', '[]'::jsonb)),
         jsonb_array_length(coalesce(c.datos -> 'player_jornada_stats', '[]'::jsonb))
  from app_copias c order by c.cuando desc;
end $$;

create or replace function copia_ahora(p_motivo text default 'a mano')
returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede hacer copias';
  end if;
  return app.copia_de_seguridad(coalesce(nullif(btrim(p_motivo), ''), 'a mano'));
end $$;

-- Para descargarla. Lleva los códigos de la liga dentro, así que solo la
-- organización, y por eso el fichero es suyo y no se publica en ningún sitio.
create or replace function copia_json(p_id bigint)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare d jsonb;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede descargar copias';
  end if;
  select datos into d from app_copias where id = p_id;
  if d is null then raise exception 'No existe la copia %', p_id; end if;
  return d;
end $$;

-- Restaurar pide escribir la palabra a mano. Un botón de «restaurar» a un clic
-- de distancia, al lado de uno de «descargar», es un accidente esperando.
create or replace function restaurar_copia(p_id bigint, p_confirmacion text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede restaurar';
  end if;
  if upper(btrim(coalesce(p_confirmacion, ''))) <> 'RESTAURAR' then
    raise exception 'Para restaurar hay que escribir RESTAURAR';
  end if;
  return app.restaurar_copia(p_id);
end $$;

revoke execute on function copias()                       from anon;
revoke execute on function copia_ahora(text)              from anon;
revoke execute on function copia_json(bigint)             from anon;
revoke execute on function restaurar_copia(bigint, text)  from anon;
