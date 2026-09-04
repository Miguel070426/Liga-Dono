-- Liga Fantasy · esquema base
-- Una liga de 12 managers, 11 jornadas y playoffs, con los datos compartidos
-- en Supabase en lugar del localStorage de cada navegador.

create extension if not exists pgcrypto;

do $$ begin
  create type pos_t as enum ('GK','DF','MF','FW');
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------- LIGA
create table if not exists leagues (
  id               uuid primary key default gen_random_uuid(),
  name             text        not null,
  current_jornada  int         not null default 1 check (current_jornada between 1 and 11),
  lineups_locked   boolean     not null default false,
  admin_user_id    uuid        references auth.users(id) on delete set null,
  admin_claim_code text        not null,
  created_at       timestamptz not null default now()
);
comment on column leagues.lineups_locked is 'true = jornada cerrada: nadie puede tocar su alineación';
comment on column leagues.admin_claim_code is 'código de un solo uso para que la organización reclame el panel de dirección';

-- ------------------------------------------------------------ MANAGERS
create table if not exists managers (
  id            uuid primary key default gen_random_uuid(),
  league_id     uuid not null references leagues(id) on delete cascade,
  slot          int  not null check (slot between 1 and 12),
  club_name     text not null,
  owner_name    text not null default '',
  user_id       uuid unique references auth.users(id) on delete set null,
  is_admin      boolean not null default false,
  claimed_at    timestamptz,
  unique (league_id, slot)
);
comment on column managers.user_id is 'cuenta que controla esta plaza; null = plaza libre';

-- --------------------------------------------------------------- CLUBES
create table if not exists clubs (
  id        uuid primary key default gen_random_uuid(),
  league_id uuid not null references leagues(id) on delete cascade,
  name      text not null,
  unique (league_id, name)
);

create table if not exists club_players (
  id      uuid primary key default gen_random_uuid(),
  club_id uuid  not null references clubs(id) on delete cascade,
  name    text  not null,
  pos     pos_t not null,
  unique (club_id, name)
);

-- ------------------------------------------------------------ CALENDARIO
create table if not exists fixtures (
  id         uuid primary key default gen_random_uuid(),
  league_id  uuid not null references leagues(id) on delete cascade,
  jornada    int  not null check (jornada between 1 and 11),
  home_id    uuid not null references managers(id) on delete cascade,
  away_id    uuid not null references managers(id) on delete cascade,
  unique (league_id, jornada, home_id),
  unique (league_id, jornada, away_id),
  check (home_id <> away_id)
);

-- ----------------------------------------------------------- ALINEACIONES
create table if not exists lineups (
  id         uuid primary key default gen_random_uuid(),
  league_id  uuid not null references leagues(id) on delete cascade,
  jornada    int  not null check (jornada between 1 and 11),
  manager_id uuid not null references managers(id) on delete cascade,
  formation  text not null default '1-4-4-2',
  confirmed  boolean not null default false,
  updated_at timestamptz not null default now(),
  unique (league_id, jornada, manager_id)
);

create table if not exists lineup_slots (
  id          uuid primary key default gen_random_uuid(),
  lineup_id   uuid  not null references lineups(id) on delete cascade,
  slot        int   not null check (slot between 1 and 11),
  pos         pos_t not null,
  club_id     uuid  references clubs(id) on delete set null,
  player_name text  not null default '',
  unique (lineup_id, slot)
);
-- máximo 1 jugador por club real dentro de una misma alineación
create unique index if not exists lineup_slots_one_club_per_lineup
  on lineup_slots (lineup_id, club_id) where club_id is not null;

-- ------------------------------------------------------------ ESTADÍSTICAS
create table if not exists club_stats (
  league_id   uuid not null references leagues(id) on delete cascade,
  jornada     int  not null check (jornada between 1 and 11),
  club_id     uuid not null references clubs(id) on delete cascade,
  team_points int  not null default 0 check (team_points between 0 and 3),
  corners     int  not null default 0 check (corners >= 0),
  clean_sheet boolean not null default false,
  played      boolean not null default true,
  primary key (league_id, jornada, club_id)
);
comment on column club_stats.played is 'false = el club real no jugó esa jornada, sus jugadores no puntúan';

create table if not exists player_stats (
  lineup_slot_id uuid primary key references lineup_slots(id) on delete cascade,
  goals          int not null default 0 check (goals        >= 0),
  assists        int not null default 0 check (assists      >= 0),
  yellow         int not null default 0 check (yellow       between 0 and 1),
  second_yellow  int not null default 0 check (second_yellow between 0 and 1),
  red            int not null default 0 check (red          between 0 and 1),
  fouls          int not null default 0 check (fouls        >= 0),
  shots          int not null default 0 check (shots        >= 0)
);

-- --------------------------------------------------------------- PLAYOFFS
create table if not exists playoff_series (
  id          uuid primary key default gen_random_uuid(),
  league_id   uuid not null references leagues(id) on delete cascade,
  bracket     text not null check (bracket in ('top','bottom')),
  position    int  not null,
  high_id     uuid not null references managers(id) on delete cascade,
  low_id      uuid not null references managers(id) on delete cascade,
  winner_id   uuid references managers(id) on delete set null,
  unique (league_id, bracket, position)
);

create table if not exists playoff_games (
  id         uuid primary key default gen_random_uuid(),
  series_id  uuid not null references playoff_series(id) on delete cascade,
  game_no    int  not null check (game_no between 1 and 3),
  home_id    uuid not null references managers(id) on delete cascade,
  home_sub   int,
  away_sub   int,
  unique (series_id, game_no)
);
comment on column playoff_games.home_id is 'quien tiene factor cancha en ese partido de la serie';

create index if not exists idx_managers_league   on managers(league_id);
create index if not exists idx_clubs_league      on clubs(league_id);
create index if not exists idx_players_club      on club_players(club_id);
create index if not exists idx_fixtures_jornada  on fixtures(league_id, jornada);
create index if not exists idx_lineups_jornada   on lineups(league_id, jornada);
create index if not exists idx_slots_lineup      on lineup_slots(lineup_id);
create index if not exists idx_clubstats_jornada on club_stats(league_id, jornada);
