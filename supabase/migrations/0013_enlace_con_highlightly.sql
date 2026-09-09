-- Enlace entre nuestras fichas y las de Highlightly, que es de donde vendrán las
-- estadísticas. Los nombres no coinciden ("Álvaro García" frente a "Alvaro
-- Garcia", "Javi" frente a "Javier"), así que hace falta normalizarlos y medir
-- parecidos.
create extension if not exists pg_trgm  with schema extensions;
create extension if not exists unaccent with schema extensions;

alter table clubs        add column if not exists highlightly_id bigint;
alter table club_players add column if not exists highlightly_id bigint;

create unique index if not exists clubs_highlightly_uq
  on clubs(league_id, highlightly_id) where highlightly_id is not null;
create unique index if not exists players_highlightly_uq
  on club_players(highlightly_id) where highlightly_id is not null;

comment on column clubs.highlightly_id        is 'id del club en Highlightly, para traer sus estadísticas';
comment on column club_players.highlightly_id is 'id del jugador en Highlightly; null = sin enlazar, hay que casarlo a mano';

-- Nombres comparables: sin acentos, sin puntuación y en minúsculas.
create or replace function app.norm_nombre(t text) returns text
language sql immutable set search_path = extensions, public, pg_temp as $$
  select trim(regexp_replace(
           regexp_replace(
             lower(extensions.unaccent(coalesce(t,''))),
             '[^a-z0-9 ]', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

-- Para clubes, además se quitan las palabras de relleno: "Atlético de Madrid" y
-- "Atlético Madrid" tienen que verse iguales.
create or replace function app.norm_club(t text) returns text
language sql immutable set search_path = extensions, public, pg_temp as $$
  select trim(regexp_replace(
           regexp_replace(app.norm_nombre(t),
             '\y(fc|cf|cd|ud|sd|ad|ac|ca|rc|rcd|sad|afc|club|de|del|la|el|los|las)\y', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

grant execute on function app.norm_nombre(text), app.norm_club(text) to authenticated;

create index if not exists idx_players_nombre_trgm
  on club_players using gin (name extensions.gin_trgm_ops);
