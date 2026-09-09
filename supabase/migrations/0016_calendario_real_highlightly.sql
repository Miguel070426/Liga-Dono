-- Calendario real de Primera según Highlightly. Sirve para saber qué partidos
-- hay que consultar en cada jornada y para cosechar jugadores de sus box score.
create table if not exists hl_matches (
  match_id     bigint primary key,
  ronda        text,
  fecha        date,
  estado       text,
  home_team_id bigint,
  away_team_id bigint,
  home_nombre  text,
  away_nombre  text,
  home_goles   int,
  away_goles   int,
  cosechado    boolean not null default false,
  actualizado  timestamptz not null default now()
);
create index if not exists idx_hl_matches_ronda on hl_matches(ronda);
create index if not exists idx_hl_matches_fecha on hl_matches(fecha);

alter table hl_matches enable row level security;
revoke all on hl_matches from anon, authenticated;

-- /matches no admite filtrar por jornada, así que se pagina la temporada entera:
-- cuatro llamadas de 100.
create or replace function app.refrescar_calendario(p_league int default 119924, p_season int default 2026)
returns int
language plpgsql security definer set search_path = extensions, public, pg_temp as $$
declare off int; j jsonb; total int := 0;
begin
  foreach off in array array[0,100,200,300] loop
    j := app.highlightly('/matches?leagueId=' || p_league || '&season=' || p_season
                          || '&limit=100&offset=' || off);
    insert into hl_matches (match_id, ronda, fecha, estado, home_team_id, away_team_id,
                            home_nombre, away_nombre, home_goles, away_goles, actualizado)
    select (m ->> 'id')::bigint,
           m ->> 'round',
           (left(m ->> 'date', 10))::date,
           m -> 'state' ->> 'description',
           (m -> 'homeTeam' ->> 'id')::bigint,
           (m -> 'awayTeam' ->> 'id')::bigint,
           m -> 'homeTeam' ->> 'name',
           m -> 'awayTeam' ->> 'name',
           nullif(split_part(m -> 'state' -> 'score' ->> 'current', ' - ', 1), '')::int,
           nullif(split_part(m -> 'state' -> 'score' ->> 'current', ' - ', 2), '')::int,
           now()
    from jsonb_array_elements(coalesce(j -> 'data', j)) m
    where m ->> 'id' is not null
    on conflict (match_id) do update
      set estado = excluded.estado, fecha = excluded.fecha, ronda = excluded.ronda,
          home_goles = excluded.home_goles, away_goles = excluded.away_goles,
          actualizado = now();
    total := total + jsonb_array_length(coalesce(j -> 'data', j));
  end loop;
  return total;
end $$;

revoke all on function app.refrescar_calendario(int, int) from anon, authenticated;
