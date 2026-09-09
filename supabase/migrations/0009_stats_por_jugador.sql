-- Las estadísticas se guardaban por hueco de alineación, así que un jugador
-- elegido por varios managers había que introducirlo una vez por cada uno. Dos
-- problemas: el trabajo se multiplicaba, y un dedazo en una de las copias daba
-- resultados distintos para el mismo jugador en cruces distintos.
--
-- Los goles de un jugador en una jornada son una propiedad del jugador, no de
-- quién lo eligió. Se guardan una sola vez y valen para todos.
--
-- Es además el paso previo para poder automatizar la carga desde una API: una
-- API devuelve datos por jugador, no por hueco de alineación.

-- El hueco pasa a apuntar a la ficha real del jugador. player_name se queda como
-- copia para poder seguir mostrando el nombre si la ficha desaparece.
alter table lineup_slots
  add column if not exists club_player_id uuid references club_players(id) on delete set null;

create index if not exists idx_slots_player on lineup_slots(club_player_id);

create table if not exists player_jornada_stats (
  league_id      uuid not null references leagues(id) on delete cascade,
  jornada        int  not null check (jornada between 1 and 11),
  club_player_id uuid not null references club_players(id) on delete cascade,
  goals          int not null default 0 check (goals         >= 0),
  assists        int not null default 0 check (assists       >= 0),
  yellow         int not null default 0 check (yellow        between 0 and 1),
  second_yellow  int not null default 0 check (second_yellow between 0 and 1),
  red            int not null default 0 check (red           between 0 and 1),
  fouls          int not null default 0 check (fouls         >= 0),
  shots          int not null default 0 check (shots         >= 0),
  updated_at     timestamptz not null default now(),
  primary key (league_id, jornada, club_player_id)
);
comment on table player_jornada_stats is 'lo que hizo un jugador real en una jornada; se introduce una vez y vale para todos los managers que lo eligieron';

alter table player_jornada_stats enable row level security;
revoke all on player_jornada_stats from anon;

create policy pjs_read  on player_jornada_stats for select to authenticated using (true);
create policy pjs_admin on player_jornada_stats for all    to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- La puntuación pasa a leer del jugador en vez del hueco. El resto de la vista
-- no cambia, así que fixture_results y standings siguen funcionando igual.
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
  (y + 3*y2 + 5*r) * act                                                   as tarjetas,
  tp * act                                                                 as pts_equipo,
  (case when cse then (case pos when 'GK' then 3 when 'DF' then 2 else 1 end)
        else 0 end) * act                                                  as porteria0,
  f * act                                                                  as faltas,
  co * act                                                                 as corners,
  sh * (case pos when 'GK' then 3 when 'DF' then 3 when 'MF' then 2 else 1 end) * act as tiros
from base;

-- La tabla vieja ya no la usa nadie.
drop table if exists player_stats;

-- Quién ha sido elegido en una jornada y por cuántos managers. Es la lista de
-- trabajo del panel: una fila por jugador, no una por hueco.
create or replace view picked_players with (security_invoker = true) as
select l.league_id, l.jornada, ls.club_player_id,
       cp.name as player_name, cp.pos, c.id as club_id, c.name as club_name,
       count(distinct l.manager_id)::int as elegido_por
from lineups l
join lineup_slots ls on ls.lineup_id = l.id
join club_players cp on cp.id = ls.club_player_id
join clubs c         on c.id  = cp.club_id
group by l.league_id, l.jornada, ls.club_player_id, cp.name, cp.pos, c.id, c.name;

grant select on picked_players to authenticated;
revoke all  on picked_players from anon;
