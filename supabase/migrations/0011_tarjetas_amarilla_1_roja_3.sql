-- Cambio de reglamento en la categoría de tarjetas.
--
-- Antes: amarilla 1, doble amarilla 3, roja 5.
-- Ahora: amarilla 1, roja 3. La doble amarilla se cuenta como roja.
--
-- El motivo de fundir la doble amarilla con la roja no es solo de reglamento: se
-- comprobó contra Highlightly que su campo cardsSecondYellow es una copia de
-- cardsYellow, no un dato real. En el Sevilla 2-1 Rayo de la jornada 1 daba 8
-- amarillas y 8 "dobles amarillas", con cero casos en los que los dos campos
-- difirieran. Haberlo creído habría convertido cada amarilla en 4 puntos.
--
-- Ninguna fuente gratuita distingue la doble amarilla de forma fiable, y en el
-- campo acaba en expulsión igual, así que se trata como roja.

create or replace view slot_contrib with (security_invoker = true) as
with base as (
  select l.league_id, l.jornada, l.manager_id, ls.id as slot_id, ls.pos,
         coalesce(ps.goals,0)         as g,
         coalesce(ps.assists,0)       as a,
         coalesce(ps.yellow,0)        as y,
         coalesce(ps.red,0)           as r,
         coalesce(ps.fouls,0)         as f,
         coalesce(ps.shots,0)         as sh,
         coalesce(ps.minutes,0)       as mi,
         coalesce(cs.team_points,0)   as tp,
         coalesce(cs.clean_sheet,false) as cse,
         case when ls.club_id is not null and coalesce(cs.played,true) = false
              then 0 else 1 end as act
  from lineups l
  join lineup_slots ls on ls.lineup_id = l.id
  left join player_jornada_stats ps on ps.league_id      = l.league_id
                                   and ps.jornada        = l.jornada
                                   and ps.club_player_id = ls.club_player_id
  left join club_stats cs on cs.league_id = l.league_id
                         and cs.jornada   = l.jornada
                         and cs.club_id   = ls.club_id
)
select league_id, jornada, manager_id, slot_id, pos,
  g * (case pos when 'GK' then 2 when 'DF' then 2 else 1 end) * act        as goles,
  a * act                                                                  as asistencias,
  (y + 3*r) * act                                                          as tarjetas,
  tp * act                                                                 as pts_equipo,
  (case when cse then (case pos when 'GK' then 3 when 'DF' then 2 else 1 end)
        else 0 end) * act                                                  as porteria0,
  f * act                                                                  as faltas,
  mi * act                                                                 as minutos,
  sh * (case pos when 'GK' then 3 when 'DF' then 3 when 'MF' then 2 else 1 end) * act as tiros
from base;

-- Ya no la mira ninguna vista, así que se puede quitar.
alter table player_jornada_stats drop column if exists second_yellow;
