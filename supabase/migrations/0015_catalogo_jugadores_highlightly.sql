-- Highlightly no tiene endpoint de plantilla por equipo: /players solo busca por
-- nombre y /teams/{id} devuelve solo el escudo. Los jugadores se cosechan de los
-- box score, que traen las dos plantillas completas de cada partido.
create table if not exists hl_players (
  hid       bigint primary key,
  name      text   not null,
  position  text,
  hteam_id  bigint,
  visto_en  timestamptz not null default now()
);
create index if not exists idx_hl_players_team on hl_players(hteam_id);

alter table hl_players enable row level security;
revoke all on hl_players from anon, authenticated;

-- Guarda los jugadores de un partido en el catálogo. Devuelve cuántos son nuevos.
create or replace function app.cosechar_box_score(p_match_id bigint)
returns int
language plpgsql security definer set search_path = extensions, public, pg_temp as $$
declare j jsonb; nuevos int;
begin
  j := app.highlightly('/box-score/' || p_match_id);
  with entradas as (
    select (p ->> 'id')::bigint           as hid,
           p ->> 'name'                   as name,
           p ->> 'position'               as position,
           (t -> 'team' ->> 'id')::bigint as hteam_id
    from jsonb_array_elements(j) t, jsonb_array_elements(t -> 'players') p
    where p ->> 'id' is not null
  ), ins as (
    insert into hl_players (hid, name, position, hteam_id)
    select hid, name, position, hteam_id from entradas
    on conflict (hid) do update
      set name = excluded.name, position = excluded.position, hteam_id = excluded.hteam_id
    returning (xmax = 0) as era_nuevo
  )
  select count(*) filter (where era_nuevo) into nuevos from ins;
  return nuevos;
end $$;

revoke all on function app.cosechar_box_score(bigint) from anon, authenticated;
