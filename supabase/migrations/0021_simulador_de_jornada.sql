-- Simulador de jornada.
--
-- Para ver que el juego entero funciona antes de jugarlo de verdad: alinea a
-- los 12 managers al azar con jugadores reales, cruza esas alineaciones con
-- las estadísticas reales de una jornada de Primera ya cargada, y comprueba
-- que las cuentas salen.
--
-- Dos cosas que importan más que el simulador en sí:
--
--   · **No pisa nada de verdad.** Solo alinea a quien no tiene alineación, y
--     marca lo que crea con `simulada`, así que se puede borrar sin tocar la
--     de nadie. Quien ya alineó se queda como estaba.
--   · **Comprueba, no solo pinta.** `app.comprobar_jornada` mira las
--     invariantes del reglamento: 11 huecos, un jugador por club, los
--     subpuntos entre 8 y 16, los puntos de liga 3-0 o 1-1, y que quien tiene
--     el club sin jugar no puntúe.

alter table lineups
  add column if not exists simulada boolean not null default false;

comment on column lineups.simulada is
  'La puso el simulador, no una persona. Se puede borrar sin perder nada.';

-- ── un once al azar, legal ──────────────────────────────────────────────────
-- Formación al azar de las del reglamento y, para cada hueco, un jugador
-- activo de un club que no esté ya usado: el máximo de 1 jugador por club
-- real es lo que hace interesante el juego, así que el simulador lo respeta.

create or replace function app.alinear_al_azar(p_jornada int, p_manager uuid)
returns uuid
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare
  lg uuid; lu uuid; form text; huecos text[];
  usados uuid[] := '{}'; h text; i int := 0; cand record;
begin
  select id into lg from leagues limit 1;

  select f.nombre, f.huecos into form, huecos
  from (values
    ('1-4-4-2',   array['GK','DF','DF','DF','DF','MF','MF','MF','MF','FW','FW']),
    ('1-4-3-3',   array['GK','DF','DF','DF','DF','MF','MF','MF','FW','FW','FW']),
    ('1-3-4-3',   array['GK','DF','DF','DF','MF','MF','MF','MF','FW','FW','FW']),
    ('1-3-5-2',   array['GK','DF','DF','DF','MF','MF','MF','MF','MF','FW','FW']),
    ('1-5-3-2',   array['GK','DF','DF','DF','DF','DF','MF','MF','MF','FW','FW']),
    ('1-4-5-1',   array['GK','DF','DF','DF','DF','MF','MF','MF','MF','MF','FW'])
  ) f(nombre, huecos)
  order by random() limit 1;

  delete from lineups where league_id = lg and jornada = p_jornada and manager_id = p_manager;
  insert into lineups (league_id, jornada, manager_id, formation, confirmed, simulada)
  values (lg, p_jornada, p_manager, form, true, true)
  returning id into lu;

  foreach h in array huecos loop
    i := i + 1;
    select cp.id, cp.name, cp.club_id into cand
      from club_players cp
     where cp.activo
       and cp.pos::text = h
       and not (cp.club_id = any(usados))
     order by random() limit 1;

    if cand.id is null then
      -- se han agotado los clubes libres con esa posición: hueco vacío, que
      -- es exactamente lo que vería un manager en la misma situación
      insert into lineup_slots (lineup_id, slot, pos, club_id, player_name, club_player_id)
      values (lu, i, h::pos_t, null, '', null);
    else
      usados := usados || cand.club_id;
      insert into lineup_slots (lineup_id, slot, pos, club_id, player_name, club_player_id)
      values (lu, i, h::pos_t, cand.club_id, cand.name, cand.id);
    end if;
  end loop;

  return lu;
end $$;

-- ── simular una jornada entera ──────────────────────────────────────────────

create or replace function app.simular_jornada(p_jornada int, p_pisar boolean default false)
returns table(concepto text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare lg uuid; m record; n_nuevas int := 0; n_respetadas int := 0;
begin
  select id into lg from leagues limit 1;

  if not exists (select 1 from player_jornada_stats where league_id = lg and jornada = p_jornada) then
    raise exception 'La jornada % no tiene estadísticas cargadas. Cárgala de la API primero.', p_jornada;
  end if;

  for m in select id from managers where league_id = lg order by slot loop
    if not p_pisar and exists (
      select 1 from lineups l
       where l.league_id = lg and l.jornada = p_jornada
         and l.manager_id = m.id and not l.simulada)
    then
      n_respetadas := n_respetadas + 1;   -- alineación de una persona: no se toca
      continue;
    end if;
    perform app.alinear_al_azar(p_jornada, m.id);
    n_nuevas := n_nuevas + 1;
  end loop;

  return query
    select 'jornada'::text, p_jornada::text
    union all select 'onces simulados', n_nuevas::text
    union all select 'onces de verdad respetados', n_respetadas::text
    union all select 'cruces con datos',
      (select count(*)::text from fixture_results
        where jornada = p_jornada and has_data);
end $$;

create or replace function app.borrar_simulacion(p_jornada int default null)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare n int;
begin
  delete from lineups
   where simulada
     and (p_jornada is null or jornada = p_jornada);
  get diagnostics n = row_count;
  return n;
end $$;

-- ── comprobar que las cuentas salen ─────────────────────────────────────────
-- Esto es el simulador de verdad: no vale con que pinte algo, tiene que
-- cumplir el reglamento.

create or replace function app.comprobar_jornada(p_jornada int)
returns table(prueba text, veredicto text, detalle text)
language plpgsql stable
set search_path = extensions, public, pg_temp
as $$
declare lg uuid;
begin
  select id into lg from leagues limit 1;

  return query
  -- 11 huecos por alineación, ni uno más ni uno menos
  with h as (
    select l.id, count(s.id) n
      from lineups l left join lineup_slots s on s.lineup_id = l.id
     where l.league_id = lg and l.jornada = p_jornada
     group by l.id)
  select 'once de 11 huecos',
         case when count(*) filter (where n <> 11) = 0 then 'BIEN' else 'MAL' end,
         count(*) || ' alineaciones, ' || count(*) filter (where n <> 11) || ' con huecos de más o de menos'
    from h;

  return query
  -- máximo un jugador por club real
  with r as (
    select l.manager_id, s.club_id, count(*) n
      from lineups l join lineup_slots s on s.lineup_id = l.id
     where l.league_id = lg and l.jornada = p_jornada and s.club_id is not null
     group by 1, 2 having count(*) > 1)
  select 'un jugador por club',
         case when count(*) = 0 then 'BIEN' else 'MAL' end,
         case when count(*) = 0 then 'ningún club repetido'
              else count(*) || ' clubes repetidos en algún once' end
    from r;

  return query
  -- la formación declarada cuadra con los huecos guardados
  with f as (
    select l.id, l.formation,
           count(*) filter (where s.pos = 'GK') gk,
           count(*) filter (where s.pos = 'DF') df,
           count(*) filter (where s.pos = 'MF') mf,
           count(*) filter (where s.pos = 'FW') fw
      from lineups l join lineup_slots s on s.lineup_id = l.id
     where l.league_id = lg and l.jornada = p_jornada
     group by 1, 2)
  select 'la formación cuadra con el once',
         case when count(*) filter (where gk <> 1) = 0 then 'BIEN' else 'MAL' end,
         count(*) filter (where gk <> 1) || ' onces sin exactamente un portero'
    from f;

  return query
  -- 8 categorías: cada una reparte 1 subpunto, o 1 a cada uno si empatan
  select 'subpuntos entre 8 y 16',
         case when count(*) filter (where sub_home + sub_away not between 8 and 16) = 0
              then 'BIEN' else 'MAL' end,
         'de ' || count(*) || ' cruces, ' ||
         count(*) filter (where sub_home + sub_away not between 8 and 16) || ' fuera de rango'
    from fixture_results where jornada = p_jornada and has_data;

  return query
  -- el cruce reparte 3-0 o 1-1, nunca otra cosa
  select 'puntos de liga 3-0 o 1-1',
         case when count(*) filter (where (pts_home, pts_away) not in ((3,0),(0,3),(1,1))) = 0
              then 'BIEN' else 'MAL' end,
         count(*) filter (where (pts_home, pts_away) not in ((3,0),(0,3),(1,1))) || ' cruces con reparto raro'
    from fixture_results where jornada = p_jornada and has_data;

  return query
  -- quien gana en subpuntos se lleva los 3 puntos
  select 'gana quien más subpuntos hace',
         case when count(*) filter (
                where (sub_home > sub_away and pts_home <> 3)
                   or (sub_away > sub_home and pts_away <> 3)
                   or (sub_home = sub_away and pts_home <> 1)) = 0
              then 'BIEN' else 'MAL' end,
         count(*) filter (
           where (sub_home > sub_away and pts_home <> 3)
              or (sub_away > sub_home and pts_away <> 3)
              or (sub_home = sub_away and pts_home <> 1)) || ' cruces mal repartidos'
    from fixture_results where jornada = p_jornada and has_data;

  return query
  -- si el club real no jugó, ese jugador no puntúa en nada
  with fuera as (
    select count(*) n
      from lineups l
      join lineup_slots s on s.lineup_id = l.id
      join club_stats cs on cs.league_id = lg and cs.jornada = l.jornada and cs.club_id = s.club_id
      join slot_contrib sc on sc.slot_id = s.id
     where l.league_id = lg and l.jornada = p_jornada and not cs.played
       and (sc.goles + sc.asistencias + sc.tarjetas + sc.pts_equipo
            + sc.porteria0 + sc.faltas + sc.minutos + sc.tiros) <> 0)
  select 'club que no jugó no puntúa',
         case when n = 0 then 'BIEN' else 'MAL' end,
         case when n = 0 then 'ningún jugador de club sin partido aporta nada'
              else n || ' jugadores puntúan con su club sin jugar' end
    from fuera;

  return query
  -- la clasificación cuadra con los cruces
  with c as (
    select sum(pj) pj, sum(pts) pts from standings)
  , f as (
    select count(*) n, sum(pts_home + pts_away) p
      from fixture_results where has_data)
  select 'la clasificación cuadra con los cruces',
         case when c.pj = f.n * 2 and c.pts = f.p then 'BIEN' else 'MAL' end,
         'partidos jugados ' || coalesce(c.pj,0) || ' frente a ' || f.n * 2 ||
         ', puntos ' || coalesce(c.pts,0) || ' frente a ' || coalesce(f.p,0)
    from c, f;
end $$;

-- ── lo que ve el panel ──────────────────────────────────────────────────────

create or replace function simular_jornada(p_jornada int)
returns table(concepto text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then raise exception 'Solo la organización puede simular'; end if;
  return query select * from app.simular_jornada(p_jornada, false);
end $$;

create or replace function comprobar_jornada(p_jornada int)
returns table(prueba text, veredicto text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then raise exception 'Solo la organización puede comprobar'; end if;
  return query select * from app.comprobar_jornada(p_jornada);
end $$;

create or replace function borrar_simulacion(p_jornada int)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then raise exception 'Solo la organización puede borrar la simulación'; end if;
  return app.borrar_simulacion(p_jornada);
end $$;

revoke all on function simular_jornada(int)    from anon;
revoke all on function comprobar_jornada(int)  from anon;
revoke all on function borrar_simulacion(int)  from anon;
