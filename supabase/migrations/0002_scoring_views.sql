-- Liga Fantasy · puntuación en SQL
-- Los pesos del reglamento viven aquí y no en el cliente, así que nadie puede
-- alterar un resultado desde la consola del navegador.
--
-- security_invoker = true es imprescindible: sin él las vistas se ejecutarían
-- con los permisos del propietario y se saltarían las políticas RLS.

-- Aportación de cada hueco de la alineación a las 8 categorías.
create or replace view slot_contrib with (security_invoker = true) as
with base as (
  select l.league_id, l.jornada, l.manager_id, ls.id as slot_id, ls.pos,
         coalesce(ps.goals,0)         as g,
         coalesce(ps.assists,0)       as a,
         coalesce(ps.yellow,0)        as y,
         coalesce(ps.second_yellow,0) as y2,
         coalesce(ps.red,0)           as r,
         coalesce(ps.fouls,0)         as f,
         coalesce(ps.shots,0)         as sh,
         coalesce(cs.team_points,0)   as tp,
         coalesce(cs.corners,0)       as co,
         coalesce(cs.clean_sheet,false) as cse,
         -- si el club real no jugó esa jornada, el jugador no puntúa en nada
         case when ls.club_id is not null and coalesce(cs.played,true) = false
              then 0 else 1 end as act
  from lineups l
  join lineup_slots ls on ls.lineup_id = l.id
  left join player_stats ps on ps.lineup_slot_id = ls.id
  left join club_stats  cs on cs.league_id = l.league_id
                          and cs.jornada   = l.jornada
                          and cs.club_id   = ls.club_id
)
select league_id, jornada, manager_id, slot_id, pos,
  g * (case pos when 'GK' then 2 when 'DF' then 2 else 1 end) * act        as goles,
  a * act                                                                  as asistencias,
  (y + 3*y2 + 5*r) * act                                                   as tarjetas,
  tp * act                                                                 as pts_equipo,
  (case when cse then (case pos when 'GK' then 3 when 'DF' then 2 else 1 end)
        else 0 end) * act                                                  as porteria0,
  f * act                                                                  as faltas,
  co * act                                                                 as corners,
  sh * (case pos when 'GK' then 3 when 'DF' then 3 when 'MF' then 2 else 1 end) * act as tiros
from base;

-- Totales de un manager en una jornada.
create or replace view manager_jornada_totals with (security_invoker = true) as
select l.league_id, l.jornada, l.manager_id, l.id as lineup_id, l.confirmed,
  coalesce(bool_or(ls.club_id is not null or ls.player_name <> ''), false) as filled,
  coalesce(sum(sc.goles),      0)::int as goles,
  coalesce(sum(sc.asistencias),0)::int as asistencias,
  coalesce(sum(sc.tarjetas),   0)::int as tarjetas,
  coalesce(sum(sc.pts_equipo), 0)::int as pts_equipo,
  coalesce(sum(sc.porteria0),  0)::int as porteria0,
  coalesce(sum(sc.faltas),     0)::int as faltas,
  coalesce(sum(sc.corners),    0)::int as corners,
  coalesce(sum(sc.tiros),      0)::int as tiros
from lineups l
left join lineup_slots ls on ls.lineup_id = l.id
left join slot_contrib sc on sc.slot_id   = ls.id
group by l.league_id, l.jornada, l.manager_id, l.id, l.confirmed;

-- Resultado de cada cruce. Un subpunto por categoría; empate reparte uno a cada
-- uno, así que los subpuntos de un lado son el número de categorías en las que
-- va igual o por delante.
create or replace view fixture_results with (security_invoker = true) as
with t as (
  select f.id as fixture_id, f.league_id, f.jornada, f.home_id, f.away_id,
    coalesce(h.goles,0) hg,       coalesce(a.goles,0) ag,
    coalesce(h.asistencias,0) ha, coalesce(a.asistencias,0) aa,
    coalesce(h.tarjetas,0) ht,    coalesce(a.tarjetas,0) at2,
    coalesce(h.pts_equipo,0) hp,  coalesce(a.pts_equipo,0) ap,
    coalesce(h.porteria0,0) h0,   coalesce(a.porteria0,0) a0,
    coalesce(h.faltas,0) hf,      coalesce(a.faltas,0) af,
    coalesce(h.corners,0) hc,     coalesce(a.corners,0) ac,
    coalesce(h.tiros,0) hs,       coalesce(a.tiros,0) as2,
    (coalesce(h.filled,false) and coalesce(a.filled,false)) as played
  from fixtures f
  left join manager_jornada_totals h
         on h.league_id = f.league_id and h.jornada = f.jornada and h.manager_id = f.home_id
  left join manager_jornada_totals a
         on a.league_id = f.league_id and a.jornada = f.jornada and a.manager_id = f.away_id
), s as (
  select t.*,
    (hg+ha+ht+hp+h0+hf+hc+hs + ag+aa+at2+ap+a0+af+ac+as2) > 0 as has_data,
    (case when hg>=ag then 1 else 0 end) + (case when ha>=aa then 1 else 0 end)
  + (case when ht>=at2 then 1 else 0 end)+ (case when hp>=ap then 1 else 0 end)
  + (case when h0>=a0 then 1 else 0 end) + (case when hf>=af then 1 else 0 end)
  + (case when hc>=ac then 1 else 0 end) + (case when hs>=as2 then 1 else 0 end) as sub_home,
    (case when ag>=hg then 1 else 0 end) + (case when aa>=ha then 1 else 0 end)
  + (case when at2>=ht then 1 else 0 end)+ (case when ap>=hp then 1 else 0 end)
  + (case when a0>=h0 then 1 else 0 end) + (case when af>=hf then 1 else 0 end)
  + (case when ac>=hc then 1 else 0 end) + (case when as2>=hs then 1 else 0 end) as sub_away
  from t
)
select s.*,
  case when sub_home > sub_away then 3 when sub_home = sub_away then 1 else 0 end as pts_home,
  case when sub_away > sub_home then 3 when sub_home = sub_away then 1 else 0 end as pts_away
from s;

-- Clasificación de la liga regular.
create or replace view standings with (security_invoker = true) as
with per as (
  select league_id, jornada, home_id as manager_id, sub_home as sf, sub_away as sc, pts_home as pts,
         case when sub_home > sub_away then 'W' when sub_home < sub_away then 'L' else 'D' end as res
  from fixture_results where played
  union all
  select league_id, jornada, away_id, sub_away, sub_home, pts_away,
         case when sub_away > sub_home then 'W' when sub_away < sub_home then 'L' else 'D' end
  from fixture_results where played
)
select m.league_id, m.id as manager_id, m.slot, m.club_name, m.owner_name,
  count(p.manager_id)::int                            as pj,
  coalesce(sum(p.pts),0)::int                         as pts,
  count(*) filter (where p.res = 'W')::int            as g,
  count(*) filter (where p.res = 'D')::int            as e,
  count(*) filter (where p.res = 'L')::int            as p,
  coalesce(sum(p.sf),0)::int                          as sub_f,
  coalesce(sum(p.sc),0)::int                          as sub_c,
  (coalesce(sum(p.sf),0) - coalesce(sum(p.sc),0))::int as sub_dif,
  row_number() over (
    partition by m.league_id
    order by coalesce(sum(p.pts),0) desc,
             (coalesce(sum(p.sf),0) - coalesce(sum(p.sc),0)) desc,
             coalesce(sum(p.sf),0) desc,
             m.slot
  )::int as rank
from managers m
left join per p on p.manager_id = m.id
group by m.league_id, m.id, m.slot, m.club_name, m.owner_name;

-- Racha: los últimos resultados de cada manager, más reciente primero.
create or replace view manager_form with (security_invoker = true) as
select league_id, manager_id, jornada, res from (
  select league_id, jornada, home_id as manager_id,
         case when sub_home > sub_away then 'W' when sub_home < sub_away then 'L' else 'D' end as res
  from fixture_results where played
  union all
  select league_id, jornada, away_id,
         case when sub_away > sub_home then 'W' when sub_away < sub_home then 'L' else 'D' end
  from fixture_results where played
) f;
