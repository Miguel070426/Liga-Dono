-- Mantenimiento automático de las plantillas.
--
-- Las plantillas se mueven durante la temporada: fichajes, canteranos que
-- suben y gente que se va. Hasta aquí el catálogo era una foto del día que se
-- pegó a mano. Esto lo mantiene solo a partir de dos fuentes de Highlightly:
--
--   1. Los box score de cada jornada, que traen las dos plantillas enteras.
--      De ahí salen los que aparecen por primera vez y los que han cambiado
--      de club dentro de la liga.
--   2. El resumen de jugador (/players/{id}), que dice en `profile.club.current`
--      a qué club pertenece hoy. De ahí sale quién ya no está.
--
-- Sobre dar de baja: la primera versión daba de baja automáticamente a quien
-- no cuadrase con ningún club de la liga, y los cuatro primeros casos fueron
-- los cuatro falsos positivos. El resumen de jugador usa nombres distintos de
-- los de la clasificación ("Deportivo A Coruña" frente a "Deportivo de La
-- Coruña", "Athletic Bilbao" frente a "Athletic Club"). Ahora el emparejado de
-- clubes va por nombre, por alias y por parecido con margen, y cuando aun así
-- no cuadra **no se da de baja a nadie**: se marca para revisión. Borrar a un
-- jugador que sí está tiene mucho peor arreglo que dejar uno de más.

-- ── columnas ────────────────────────────────────────────────────────────────

alter table clubs
  add column if not exists aliases text[] not null default '{}';

comment on column clubs.aliases is
  'Otros nombres con los que las fuentes externas llaman a este club.';

alter table club_players
  add column if not exists activo boolean not null default true,
  add column if not exists ultima_aparicion date,
  add column if not exists ultima_ronda text,
  add column if not exists origen text not null default 'manual',
  add column if not exists club_segun_api text,
  add column if not exists verificado_en timestamptz,
  add column if not exists motivo_baja text,
  add column if not exists revisar boolean not null default false,
  add column if not exists motivo_revision text;

create index if not exists club_players_activo_idx on club_players (club_id) where activo;

-- ── normalización de nombres de club ────────────────────────────────────────
-- Se añade "a" a las partículas que se descartan, para que "Deportivo A
-- Coruña" y "Deportivo de La Coruña" queden en el mismo sitio.

create or replace function app.norm_club(t text) returns text
language sql immutable
set search_path = extensions, public, pg_temp
as $$
  select trim(regexp_replace(
           regexp_replace(app.norm_nombre(t),
             '\y(fc|cf|cd|ud|sd|ad|ac|ca|rc|rcd|sad|afc|club|de|del|la|el|los|las|a)\y', ' ', 'g'),
           '\s+', ' ', 'g'))
$$;

-- ── a qué club nuestro corresponde un nombre de fuera ───────────────────────
-- Tres pasadas, de más segura a menos: nombre normalizado, alias, y parecido
-- de trigramas. El parecido solo vale si además saca ventaja clara al segundo
-- candidato; los 20 clubes de la liga no se parecen entre sí más de 0.33, así
-- que un ganador por encima de 0.45 y con 0.15 de ventaja es inequívoco.

create or replace function app.club_por_nombre(
  p_league uuid, p_nombre text,
  out club_id uuid, out via text, out certeza real)
language plpgsql stable
set search_path = extensions, public, pg_temp
as $$
declare n text; id1 uuid; s1 real; s2 real;
begin
  n := app.norm_club(p_nombre);
  if n is null or n = '' then return; end if;

  select c.id into club_id from clubs c
   where c.league_id = p_league and app.norm_club(c.name) = n
   limit 1;
  if club_id is not null then via := 'nombre'; certeza := 1; return; end if;

  select c.id into club_id from clubs c
   where c.league_id = p_league
     and exists (select 1 from unnest(c.aliases) a where app.norm_club(a) = n)
   limit 1;
  if club_id is not null then via := 'alias'; certeza := 1; return; end if;

  with p as (
    select c.id,
           greatest(similarity(app.norm_club(c.name), n),
                    coalesce((select max(similarity(app.norm_club(a), n))
                                from unnest(c.aliases) a), 0)) as s
      from clubs c where c.league_id = p_league
  ), r as (select id, s, row_number() over (order by s desc) rn from p)
  select (array_agg(id) filter (where rn = 1))[1], max(s) filter (where rn = 1),
         max(s) filter (where rn = 2)
    into id1, s1, s2
    from r;

  if s1 >= 0.45 and s1 - coalesce(s2, 0) >= 0.15 then
    club_id := id1; via := 'parecido'; certeza := s1;
  end if;
end $$;

-- ── alias conocidos ─────────────────────────────────────────────────────────

update clubs c set aliases = v.aliases
from (values
  ('Alavés',                 array['Deportivo Alavés','Alaves']),
  ('Athletic Club',          array['Athletic Bilbao','Athletic Club Bilbao']),
  ('Atlético de Madrid',     array['Atlético Madrid','Atletico Madrid','Club Atlético de Madrid']),
  ('Celta de Vigo',          array['Celta Vigo','RC Celta','RC Celta de Vigo']),
  ('Deportivo de La Coruña', array['Deportivo A Coruña','Deportivo La Coruña','RC Deportivo','RC Deportivo de La Coruña','Depor']),
  ('Elche',                  array['Elche CF']),
  ('Espanyol',               array['RCD Espanyol','RCD Espanyol de Barcelona','Espanyol Barcelona']),
  ('FC Barcelona',           array['Barcelona','Barça']),
  ('Getafe',                 array['Getafe CF']),
  ('Levante',                array['Levante UD']),
  ('Málaga',                 array['Málaga CF','Malaga CF']),
  ('Osasuna',                array['CA Osasuna','Club Atlético Osasuna']),
  ('Racing de Santander',    array['Racing Santander','Real Racing Club','Real Racing Club de Santander']),
  ('Rayo Vallecano',         array['Rayo']),
  ('Real Betis',             array['Betis','Real Betis Balompié']),
  ('Real Madrid',            array['Real Madrid CF']),
  ('Real Sociedad',          array['Real Sociedad de Fútbol','La Real']),
  ('Sevilla',                array['Sevilla FC']),
  ('Valencia',               array['Valencia CF']),
  ('Villarreal',             array['Villarreal CF'])
) as v(name, aliases)
where c.name = v.name;

-- ── cosecha de un box score, con mantenimiento ──────────────────────────────
-- Además de guardar el box score: enlaza a quien aún no lo estaba, mueve al
-- que ha cambiado de club, da de alta al que no teníamos y apunta la fecha en
-- que se le vio por última vez. Ver a alguien jugar es prueba de que está.

create or replace function app.sincronizar_box_score(p_match_id bigint)
returns table(nuevos int, movidos int, enlazados int, vistos int)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare j jsonb; f date; ronda text;
begin
  select fecha, hl_matches.ronda into f, ronda from hl_matches where match_id = p_match_id;
  j := app.highlightly('/box-score/' || p_match_id);

  drop table if exists _bs;
  create temp table _bs as
  select (p ->> 'id')::bigint            as hid,
         p ->> 'name'                    as hname,
         app.pos_desde_highlightly(p ->> 'position') as hpos,
         (t -> 'team' ->> 'id')::bigint  as hteam
  from jsonb_array_elements(j) t, jsonb_array_elements(t -> 'players') p
  where p ->> 'id' is not null;

  insert into hl_players (hid, name, position, hteam_id)
  select hid, hname, hpos::text, hteam from _bs
  on conflict (hid) do update
    set name = excluded.name, position = excluded.position, hteam_id = excluded.hteam_id;

  -- enlazar por nombre exacto dentro del mismo club, solo si es único por los dos lados
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
     set ultima_aparicion = greatest(coalesce(cp.ultima_aparicion, f), f),
         ultima_ronda = case when cp.ultima_aparicion is null or cp.ultima_aparicion <= f
                             then ronda else cp.ultima_ronda end,
         activo = true, motivo_baja = null,
         revisar = false, motivo_revision = null
  from _bs b where cp.highlightly_id = b.hid;
  get diagnostics vistos = row_count;

  drop table if exists _bs;
  return next;
end $$;

-- ── verificación contra el club oficial del jugador ─────────────────────────

create or replace function app.verificar_jugador(p_cp_id uuid) returns text
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare cp club_players; j jsonb; actual text; m record; lg uuid;
begin
  select * into cp from club_players where id = p_cp_id;
  if not found then return 'no existe'; end if;
  if cp.highlightly_id is null then return 'sin enlazar'; end if;

  j := app.highlightly('/players/' || cp.highlightly_id);
  actual := nullif(btrim(coalesce(j -> 0 -> 'profile' -> 'club' ->> 'current', '')), '');

  update club_players set verificado_en = now(), club_segun_api = actual where id = cp.id;
  if actual is null then return 'la API no dice club'; end if;

  select league_id into lg from clubs where id = cp.club_id;
  select * into m from app.club_por_nombre(lg, actual);

  if m.club_id is null then
    -- No cuadra con ninguno de los 20. Puede ser una baja de verdad o un
    -- nombre que no sabemos leer, así que se marca y lo mira una persona.
    update club_players
       set revisar = true,
           motivo_revision = 'la API lo pone en «' || actual || '»'
     where id = cp.id;
    return 'a revisar: ' || actual;
  elsif m.club_id <> cp.club_id then
    update club_players
       set club_id = m.club_id, activo = true, motivo_baja = null,
           revisar = false, motivo_revision = null
     where id = cp.id;
    return 'traspaso a ' || actual;
  else
    update club_players
       set activo = true, motivo_baja = null, revisar = false, motivo_revision = null
     where id = cp.id;
    return 'confirmado';
  end if;
end $$;

-- Por tandas, porque el plan gratuito son 100 llamadas al día y además limita
-- por segundo. La pausa evita el 429; si aun así corta, lo hecho queda hecho.
drop function if exists app.verificar_plantillas(int);

create or replace function app.verificar_plantillas(p_limite int default 40, p_pausa real default 1.2)
returns table(accion text, cuantos int)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare r record; res text; primero boolean := true;
begin
  drop table if exists _ver;
  create temp table _ver (accion text);
  for r in
    select id from club_players
     where highlightly_id is not null
     order by verificado_en nulls first, id
     limit p_limite
  loop
    if not primero then perform pg_sleep(p_pausa); end if;
    primero := false;
    begin
      res := app.verificar_jugador(r.id);
      insert into _ver values (split_part(res, ':', 1));
    exception when others then
      insert into _ver values ('cortado: ' || left(sqlerrm, 60));
      exit;
    end;
  end loop;
  return query select v.accion, count(*)::int from _ver v group by v.accion order by 2 desc;
  drop table if exists _ver;
end $$;

-- Dar de baja es siempre un acto deliberado de la organización, nunca del
-- automatismo: esto aplica las bajas que una persona ya ha mirado.
create or replace function app.aplicar_bajas_revisadas(p_ids uuid[]) returns int
language sql security definer
set search_path = extensions, public, pg_temp
as $$
  with hecho as (
    update club_players
       set activo = false, revisar = false,
           motivo_baja = coalesce(motivo_revision, 'baja confirmada a mano'),
           motivo_revision = null
     where id = any(p_ids) and revisar
    returning 1)
  select count(*)::int from hecho;
$$;

-- ── qué mirar ───────────────────────────────────────────────────────────────

drop view if exists jugadores_a_revisar;
create view jugadores_a_revisar
with (security_invoker = true) as
select cp.id, cp.name as jugador, c.name as club_nuestro,
       cp.club_segun_api, cp.motivo_revision, cp.verificado_en,
       cp.ultima_aparicion, cp.ultima_ronda
from club_players cp join clubs c on c.id = cp.club_id
where cp.revisar
order by c.name, cp.name;

drop view if exists jugadores_sin_aparecer;
create view jugadores_sin_aparecer
with (security_invoker = true) as
select cp.id, cp.name as jugador, c.name as club, cp.pos,
       cp.ultima_aparicion, cp.activo, cp.highlightly_id is not null as enlazado
from club_players cp join clubs c on c.id = cp.club_id
where cp.ultima_aparicion is null
order by c.name, cp.name;
