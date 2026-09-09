-- `hl_matches.cosechado` significaba "de este partido ya hemos sacado los
-- jugadores", y la carga de resultados lo reutilizó para decir "de este
-- partido ya tenemos las estadísticas". Son dos cosas distintas, y al
-- solaparlas la jornada 2 aparecía como cargada: sus partidos se habían
-- cosechado en su día para sacar las plantillas, pero no tenían ni un dato
-- de jugador. El panel la habría dado por hecha.
--
-- Cada cosa con su marca.

alter table hl_matches
  add column if not exists stats_cargadas boolean not null default false;

comment on column hl_matches.cosechado is
  'De este partido se han sacado los jugadores al catálogo.';
comment on column hl_matches.stats_cargadas is
  'De este partido se han guardado las estadísticas de la jornada.';

-- Lo ya cargado de verdad: los partidos de las rondas que tienen datos por
-- jugador. Ahora mismo, solo la jornada 1.
update hl_matches m
   set stats_cargadas = true
 where exists (
   select 1 from jornada_rondas jr
    where jr.ronda = m.ronda
      and exists (select 1 from player_jornada_stats s
                   where s.league_id = jr.league_id and s.jornada = jr.jornada));

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

  insert into hl_players (hid, name, position, hteam_id)
  select hid, hname, hpos::text, hteam from _bs
  on conflict (hid) do update
    set name = excluded.name, position = excluded.position, hteam_id = excluded.hteam_id;

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

  update hl_matches
     set cosechado = true, stats_cargadas = true, actualizado = now()
   where match_id = p_match_id;
  drop table if exists _bs;
  return next;
end $$;

-- El panel pregunta por las estadísticas, no por el catálogo.
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
         m.stats_cargadas
  from hl_matches m
  join jornada_rondas jr on jr.ronda = m.ronda
  where jr.jornada = p_jornada
    and jr.league_id = (select id from leagues limit 1)
  order by m.fecha, m.match_id;
$$;
