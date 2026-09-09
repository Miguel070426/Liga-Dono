-- Carga automática de una jornada.
--
-- Hasta aquí los 8 datos de cada jugador se metían a mano desde el panel:
-- 22 jugadores por partido, 10 partidos por jornada. Esto los baja del box
-- score de Highlightly, que trae las dos plantillas enteras con sus números.
--
-- De dónde sale cada categoría del reglamento:
--
--   goles       ← statistics.goalsScored
--   asistencias ← statistics.assists
--   amarillas   ← statistics.cardsYellow
--   rojas       ← statistics.cardsRed
--   faltas      ← statistics.fouledOthers   (las que comete, no las que recibe)
--   tiros       ← statistics.shotsOnTarget
--   minutos     ← minutesPlayed             (fuera de statistics, ojo)
--
-- Los puntos por equipo y la portería a cero no vienen por jugador: se sacan
-- del marcador del partido, que ya está en hl_matches.
--
-- No se lee `cardsSecondYellow`: es una copia de `cardsYellow`, no un dato.
-- En este mismo Sevilla 2-1 Rayo da 4 amarillas y 4 dobles amarillas en cada
-- equipo, sin un solo caso en que difieran. Por eso el reglamento funde la
-- doble amarilla con la roja.

-- ── qué jornada nuestra es cada jornada real ────────────────────────────────
-- Nuestra liga son 11 jornadas y la de verdad 38, así que hace falta decir
-- cuál alimenta a cuál. Por defecto la 1 con la 1, pero se puede cambiar: si
-- la liga arranca en octubre, la jornada 1 será otra ronda.

create table if not exists jornada_rondas (
  league_id uuid not null references leagues(id) on delete cascade,
  jornada   int  not null check (jornada between 1 and 11),
  ronda     text not null,
  primary key (league_id, jornada)
);

alter table jornada_rondas enable row level security;

drop policy if exists jornada_rondas_read  on jornada_rondas;
drop policy if exists jornada_rondas_admin on jornada_rondas;
create policy jornada_rondas_read  on jornada_rondas for select using (true);
create policy jornada_rondas_admin on jornada_rondas for all
  using (app.is_admin()) with check (app.is_admin());

insert into jornada_rondas (league_id, jornada, ronda)
select l.id, n, 'Regular Season - ' || n
from leagues l, generate_series(1, 11) n
on conflict (league_id, jornada) do nothing;

-- ── un partido ──────────────────────────────────────────────────────────────
-- Una sola llamada al box score sirve para las dos cosas: mantener la
-- plantilla (enlazar, mover, dar de alta, apuntar que se le ha visto jugar) y
-- guardar las estadísticas de la jornada. Separarlas costaría el doble de
-- cuota, y son 100 llamadas al día.

create or replace function app.cargar_partido(p_match_id bigint)
returns table(guardados int, sin_enlazar int, nuevos int, movidos int, enlazados int)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare j jsonb; m hl_matches; lg uuid; jor int;
begin
  select * into m from hl_matches where match_id = p_match_id;
  if not found then
    raise exception 'El partido % no está en el calendario. Refresca el calendario primero.', p_match_id;
  end if;
  if m.estado is distinct from 'Finished' then
    raise exception 'El partido % no ha terminado (%). No se cargan partidos a medias.', p_match_id, coalesce(m.estado,'sin estado');
  end if;

  select id into lg from leagues limit 1;
  select jr.jornada into jor from jornada_rondas jr where jr.league_id = lg and jr.ronda = m.ronda;
  if jor is null then
    raise exception 'La ronda "%" no está asignada a ninguna jornada nuestra', m.ronda;
  end if;

  j := app.highlightly('/box-score/' || p_match_id);

  drop table if exists _bs;
  create temp table _bs as
  select (p ->> 'id')::bigint            as hid,
         p ->> 'name'                    as hname,
         app.pos_desde_highlightly(p ->> 'position') as hpos,
         (t -> 'team' ->> 'id')::bigint  as hteam,
         coalesce((p ->> 'minutesPlayed')::int, 0)                     as minutos,
         coalesce((p -> 'statistics' ->> 'goalsScored')::int, 0)       as goles,
         coalesce((p -> 'statistics' ->> 'assists')::int, 0)           as asist,
         coalesce((p -> 'statistics' ->> 'cardsYellow')::int, 0)       as amarillas,
         coalesce((p -> 'statistics' ->> 'cardsRed')::int, 0)          as rojas,
         coalesce((p -> 'statistics' ->> 'fouledOthers')::int, 0)      as faltas,
         coalesce((p -> 'statistics' ->> 'shotsOnTarget')::int, 0)     as tiros
  from jsonb_array_elements(j) t, jsonb_array_elements(t -> 'players') p
  where p ->> 'id' is not null;

  -- catálogo crudo, por si hay que casar nombres a mano después
  insert into hl_players (hid, name, position, hteam_id)
  select hid, hname, hpos::text, hteam from _bs
  on conflict (hid) do update
    set name = excluded.name, position = excluded.position, hteam_id = excluded.hteam_id;

  -- mantenimiento: enlazar por nombre exacto dentro del club, solo si es único
  -- por los dos lados
  with cand as (
    select cp.id as cp_id, b.hid,
           row_number() over (partition by cp.id  order by b.hid) rn1,
           row_number() over (partition by b.hid order by cp.id) rn2
    from _bs b
    join clubs c         on c.highlightly_id = b.hteam
    join club_players cp on cp.club_id = c.id
                        and cp.highlightly_id is null
                        and app.norm_nombre(cp.name) = app.norm_nombre(b.hname)
    where not exists (select 1 from club_players x where x.highlightly_id = b.hid)
  )
  update club_players cp set highlightly_id = cand.hid
  from cand where cp.id = cand.cp_id and cand.rn1 = 1 and cand.rn2 = 1;
  get diagnostics enlazados = row_count;

  update club_players cp
     set club_id = c.id, activo = true, motivo_baja = null,
         revisar = false, motivo_revision = null
  from _bs b join clubs c on c.highlightly_id = b.hteam
  where cp.highlightly_id = b.hid and cp.club_id <> c.id;
  get diagnostics movidos = row_count;

  insert into club_players (club_id, name, pos, highlightly_id, origen)
  select c.id, b.hname, b.hpos, b.hid, 'highlightly'
  from _bs b join clubs c on c.highlightly_id = b.hteam
  where not exists (select 1 from club_players x where x.highlightly_id = b.hid)
  on conflict do nothing;
  get diagnostics nuevos = row_count;

  update club_players cp
     set ultima_aparicion = greatest(coalesce(cp.ultima_aparicion, m.fecha), m.fecha),
         ultima_ronda = case when cp.ultima_aparicion is null or cp.ultima_aparicion <= m.fecha
                             then m.ronda else cp.ultima_ronda end,
         activo = true, motivo_baja = null,
         revisar = false, motivo_revision = null
  from _bs b where cp.highlightly_id = b.hid;

  -- las estadísticas de la jornada, por jugador
  insert into player_jornada_stats
    (league_id, jornada, club_player_id, goals, assists, yellow, red, fouls, shots, minutes)
  select lg, jor, cp.id, b.goles, b.asist, b.amarillas, b.rojas, b.faltas, b.tiros, b.minutos
  from _bs b join club_players cp on cp.highlightly_id = b.hid
  on conflict (league_id, jornada, club_player_id) do update
    set goals = excluded.goals, assists = excluded.assists,
        yellow = excluded.yellow, red = excluded.red, fouls = excluded.fouls,
        shots = excluded.shots, minutes = excluded.minutes, updated_at = now();
  get diagnostics guardados = row_count;

  select count(*)::int into sin_enlazar from _bs b
   where not exists (select 1 from club_players cp where cp.highlightly_id = b.hid);

  update hl_matches set cosechado = true, actualizado = now() where match_id = p_match_id;
  drop table if exists _bs;
  return next;
end $$;

-- ── una jornada entera ──────────────────────────────────────────────────────

create or replace function app.cargar_jornada(p_jornada int, p_pausa real default 1.2)
returns table(concepto text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare
  lg uuid; r text; f record; res record;
  n_ok int := 0; n_falla int := 0; n_pend int := 0;
  n_stats int := 0; n_suelto int := 0; corte text := null;
  primero boolean := true;
begin
  select id into lg from leagues limit 1;
  select jr.ronda into r from jornada_rondas jr where jr.league_id = lg and jr.jornada = p_jornada;
  if r is null then
    raise exception 'La jornada % no tiene asignada ninguna ronda real', p_jornada;
  end if;

  for f in select match_id, estado, home_nombre, away_nombre
             from hl_matches where ronda = r order by fecha, match_id
  loop
    if f.estado is distinct from 'Finished' then
      n_pend := n_pend + 1;
      continue;
    end if;
    if not primero then perform pg_sleep(p_pausa); end if;
    primero := false;
    begin
      select * into res from app.cargar_partido(f.match_id);
      n_ok := n_ok + 1;
      n_stats := n_stats + res.guardados;
      n_suelto := n_suelto + res.sin_enlazar;
    exception when others then
      n_falla := n_falla + 1;
      corte := coalesce(corte, f.home_nombre || ' - ' || f.away_nombre || ': ' || left(sqlerrm, 90));
    end;
  end loop;

  -- Lo que sale del marcador, no del box score: puntos de liga del club y
  -- portería a cero. Y played, que es la regla de "si tu club no jugó, no
  -- puntúas en nada".
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
         l.gc = 0,
         true
  from lados l join clubs c on c.highlightly_id = l.ht
  where c.league_id = lg
  on conflict (league_id, jornada, club_id) do update
    set team_points = excluded.team_points,
        clean_sheet = excluded.clean_sheet,
        played      = excluded.played;

  -- El club que no jugó esa ronda: se deja constancia, para que la regla se
  -- aplique de forma explícita en vez de por ausencia de fila.
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

  return query
    select 'jornada'::text,        p_jornada || ' · ' || r
    union all select 'partidos cargados', n_ok::text
    union all select 'partidos sin jugar', n_pend::text
    union all select 'partidos que fallaron', n_falla::text
    union all select 'fichas con estadísticas', n_stats::text
    union all select 'jugadores del box score sin enlazar', n_suelto::text
    union all select 'primer fallo', coalesce(corte, '—');
end $$;
