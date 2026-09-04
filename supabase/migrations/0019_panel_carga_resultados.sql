-- Los tres botones que necesita el panel de dirección para cargar una jornada
-- sin escribir SQL.
--
-- La carga va partido a partido, no de golpe. Una jornada son 10 llamadas a la
-- API con su pausa entre medias: eso es un minuto largo, y PostgREST corta las
-- peticiones mucho antes. Partido a partido cada llamada dura un par de
-- segundos, cabe de sobra, y además el panel puede ir enseñando por dónde va
-- en vez de quedarse en blanco.

-- Qué partidos reales alimentan una jornada nuestra, y cuáles están ya
-- cargados. Es dato público de fútbol, así que lo puede ver cualquiera.
create or replace function jornada_partidos(p_jornada int)
returns table(match_id bigint, fecha date, estado text,
              local text, visitante text,
              goles_local int, goles_visitante int,
              cargado boolean)
language sql stable security definer
set search_path = extensions, public, pg_temp
as $$
  select m.match_id, m.fecha, m.estado,
         m.home_nombre, m.away_nombre,
         m.home_goles, m.away_goles,
         coalesce(m.cosechado, false)
  from hl_matches m
  join jornada_rondas jr on jr.ronda = m.ronda
  where jr.jornada = p_jornada
    and jr.league_id = (select id from leagues limit 1)
  order by m.fecha, m.match_id;
$$;

-- Cargar un partido: estadísticas de sus 22 jugadores y mantenimiento de las
-- dos plantillas, de una sola llamada a la API.
create or replace function cargar_resultado_partido(p_match_id bigint)
returns table(guardados int, sin_enlazar int, nuevos int, movidos int, enlazados int)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede cargar resultados';
  end if;
  return query select * from app.cargar_partido(p_match_id);
end $$;

-- Cerrar la jornada: los puntos de liga de cada club y la portería a cero, que
-- no salen del box score sino del marcador. Se hace una vez, al final, cuando
-- ya están todos los partidos cargados.
create or replace function cerrar_datos_de_club(p_jornada int)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare lg uuid; r text; n int;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede cargar resultados';
  end if;
  select id into lg from leagues limit 1;
  select jr.ronda into r from jornada_rondas jr where jr.league_id = lg and jr.jornada = p_jornada;
  if r is null then
    raise exception 'La jornada % no tiene asignada ninguna ronda real', p_jornada;
  end if;

  insert into club_stats (league_id, jornada, club_id, team_points, clean_sheet, played)
  with lados as (
    select home_team_id as ht, home_goles as gf, away_goles as gc
      from hl_matches where ronda = r and estado = 'Finished'
    union all
    select away_team_id, away_goles, home_goles
      from hl_matches where ronda = r and estado = 'Finished'
  )
  select lg, p_jornada, c.id,
         case when l.gf > l.gc then 3 when l.gf = l.gc then 1 else 0 end,
         l.gc = 0, true
  from lados l join clubs c on c.highlightly_id = l.ht
  where c.league_id = lg
  on conflict (league_id, jornada, club_id) do update
    set team_points = excluded.team_points,
        clean_sheet = excluded.clean_sheet,
        played      = excluded.played;
  get diagnostics n = row_count;

  -- El club que no jugó: se deja dicho, para que la regla de "si tu club no
  -- jugó no puntúas" se aplique por dato y no por ausencia de fila.
  insert into club_stats (league_id, jornada, club_id, team_points, clean_sheet, played)
  select lg, p_jornada, c.id, 0, false, false
  from clubs c
  where c.league_id = lg
    and not exists (
      select 1 from hl_matches m
       where m.ronda = r and m.estado = 'Finished'
         and c.highlightly_id in (m.home_team_id, m.away_team_id))
  on conflict (league_id, jornada, club_id) do update
    set team_points = 0, clean_sheet = false, played = false;

  return n;
end $$;

-- Volver a bajar el calendario, para que aparezcan los marcadores de los
-- partidos que se han jugado desde la última vez.
create or replace function refrescar_calendario_real()
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede refrescar el calendario';
  end if;
  return app.refrescar_calendario(119924, 2026);
end $$;

revoke all on function jornada_partidos(int)            from anon;
revoke all on function cargar_resultado_partido(bigint) from anon;
revoke all on function cerrar_datos_de_club(int)        from anon;
revoke all on function refrescar_calendario_real()      from anon;
