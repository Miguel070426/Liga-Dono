-- Repaso de seguridad después de los cambios de hoy, con el analizador de
-- Supabase. La mayoría de lo que marca es a propósito, pero tres cosas no, y
-- dos se metieron hoy.
--
-- 1 · `ciclo_estado()` NO COMPROBABA NADA.
--     Es `security definer` y vive en el esquema público, así que PostgREST la
--     publica y el rol `anon` podía llamarla. Sin sesión, con solo la URL
--     pública y la clave pública, se leía: si el automático está encendido,
--     cuándo fue la última pasada, la jornada en curso, la hora de cierre, las
--     llamadas gastadas hoy, el estado del catálogo y TODOS los avisos, con los
--     nombres de los partidos y las decisiones tomadas. No es una catástrofe
--     —no hay códigos ni contraseñas ahí— pero es información de la liga y no
--     tiene por qué verla quien pase por delante. Ahora pide ser la
--     organización, que es la única pantalla que la usa.
--
--     Cuando exista el tablón de noticias para los doce, tendrá su propia
--     función con solo lo que deban ver, en vez de abrir esta.
--
-- 2 · `app.marcar_apertura_de_jornada()` no fijaba `search_path`.
--     Es el disparador que apunta cuándo se abre una jornada. Un disparador sin
--     `search_path` fijo se resuelve con el del rol que provoca la escritura, y
--     eso es la clase de detalle que un día se convierte en un agujero.
--
-- 3 · Las tres funciones de fichajes y `ciclo_ahora` las podía llamar `anon`.
--     No era aprovechable: lo primero que hacen es comprobar `is_admin()` y
--     ahí se cortan, ANTES de gastar ninguna llamada a la API, así que nadie
--     podía vaciar la cuota desde fuera. Pero no tienen por qué estar al
--     alcance de quien no ha entrado, y quitarlo es una línea.
--
-- Lo que el analizador marca y se queda como está, a propósito:
--
--   · `clubes_excluidos` como vista con permisos del dueño. Lo marca como
--     ERROR, y es deliberado: `authenticated` no puede leer `hl_matches` y una
--     vista de invocador dejaría a los doce sin poder leer la clasificación.
--     Solo expone qué clubes tienen un partido fuera de una jornada, que ya es
--     público en `jornada_excluidos`.
--   · `hl_matches` y `hl_players` con RLS y sin políticas. Es el cierre que se
--     quiere: solo se leen desde funciones `security definer`.
--   · El resto de funciones `security definer` del esquema público son los
--     endpoints del juego, y cada una comprueba por dentro quién la llama.

-- ── 1 · el estado del ciclo, solo para la organización ──────────────────────
-- Pasa a plpgsql porque una función en SQL puro no puede cortar con un raise.

create or replace function ciclo_estado()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare d jsonb;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede ver el estado del automático';
  end if;

  select jsonb_build_object(
    'automatico',  lg.automatico,
    'ultimo',      lg.ultimo_ciclo,
    'calendario',  lg.ultimo_calendario,
    'jornada',     lg.current_jornada,
    'abierta_desde', lg.jornada_desde,
    'cierre',      app.cierre_de_jornada(lg.id, lg.current_jornada),
    'llamadas_hoy', coalesce((select u.llamadas from app_api_uso u where u.dia = current_date), 0),
    'plantillas', jsonb_build_object(
      'fichas',          (select count(*) from club_players),
      'activas',         (select count(*) from club_players where activo),
      'enlazadas',       (select count(*) from club_players where highlightly_id is not null),
      'sin_enlazar',     (select count(*) from club_players where highlightly_id is null),
      'repasadas_hoy',   (select count(*) from club_players where verificado_en >= current_date),
      'sin_repasar',     (select count(*) from club_players
                           where highlightly_id is not null and verificado_en is null),
      'mas_antigua',     (select min(verificado_en) from club_players
                           where highlightly_id is not null),
      'a_revisar',       (select count(*) from club_players where revisar)),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'cuando', a.cuando, 'clase', a.clase, 'jornada', a.jornada, 'texto', a.texto)
             order by a.cuando desc)
      from (select * from app_avisos a2 where a2.league_id = lg.id
             order by a2.cuando desc limit 30) a), '[]'::jsonb))
  into d
  from leagues lg limit 1;

  return d;
end $$;

-- ── 2 · el disparador, con su search_path ───────────────────────────────────

create or replace function app.marcar_apertura_de_jornada()
returns trigger language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.current_jornada is distinct from old.current_jornada then
    new.jornada_desde := now();
  end if;
  return new;
end $$;

-- ── 3 · fuera del alcance de quien no ha entrado ────────────────────────────

revoke execute on function ciclo_estado()             from anon;
revoke execute on function ciclo_ahora()              from anon;
revoke execute on function buscar_jugador(text)       from anon;
revoke execute on function mirar_candidato(bigint)    from anon;
revoke execute on function anadir_jugador(bigint)     from anon;
