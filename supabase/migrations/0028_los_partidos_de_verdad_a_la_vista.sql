-- Los partidos reales de la jornada, visibles para los doce.
--
-- Para decidir a quién alineas necesitas saber contra quién juega cada club,
-- en casa o fuera, y a qué hora. Hasta ahora eso obligaba a salir de la
-- aplicación y mirarlo en otro sitio, que es un fallo de diseño: la decisión
-- se toma en la pantalla de alineación y el dato estaba en otra parte.
--
-- Los 200 partidos ya estaban en `hl_matches` y `jornada_partidos` ya la podía
-- llamar cualquier jugador. Solo faltaba devolver tres cosas más y enseñarlo:
--
--   · `comienza`, la hora, que se añadió con el cierre por hora. Sin ella no
--     se puede saber si el partido es antes o después de que cierre.
--   · los identificadores de club, para que el juego pueda marcar «aquí juega
--     uno de los tuyos» sin tener que adivinarlo por el nombre.
--   · si el partido está fuera de la jornada, que ya se podía consultar aparte
--     pero obligaba a una segunda llamada para pintar una sola tabla.
--
-- Lo que NO se devuelve, a propósito: cuántos managers tienen jugadores de
-- cada partido. Eso delataría las alineaciones antes del cierre y se cargaría
-- el «alinear a ciegas», que es la base del juego. Cada uno solo puede marcar
-- los suyos, que ya conoce.

drop function if exists jornada_partidos(int);

create or replace function jornada_partidos(p_jornada int)
returns table(
  match_id bigint, fecha date, comienza timestamptz, estado text,
  local text, visitante text,
  local_club uuid, visitante_club uuid,
  goles_local int, goles_visitante int,
  cargado boolean, excluido boolean)
language sql stable security definer
set search_path = extensions, public, pg_temp as $$
  select m.match_id, m.fecha, m.comienza, m.estado,
         m.home_nombre, m.away_nombre,
         cl.id, cv.id,
         m.home_goles, m.away_goles,
         m.stats_cargadas,
         exists (select 1 from jornada_excluidos x
                  where x.league_id = jr.league_id
                    and x.jornada = jr.jornada
                    and x.match_id = m.match_id)
  from hl_matches m
  join jornada_rondas jr on jr.ronda = m.ronda
  left join clubs cl on cl.highlightly_id = m.home_team_id
  left join clubs cv on cv.highlightly_id = m.away_team_id
  where jr.jornada = p_jornada
    and jr.league_id = (select id from leagues order by created_at limit 1)
  order by m.comienza nulls last, m.fecha, m.match_id;
$$;

revoke execute on function jornada_partidos(int) from public, anon;
grant  execute on function jornada_partidos(int) to authenticated;
