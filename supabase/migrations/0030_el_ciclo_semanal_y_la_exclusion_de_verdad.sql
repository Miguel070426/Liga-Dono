-- El ciclo semanal solo, y dos agujeros que se veían al montarlo.
--
-- Lo que se pidió es que la liga vaya sola: que cargue los partidos y pase de
-- jornada sin que la organización entre a darle a botones. Al escribirlo
-- aparecieron dos cosas que había que arreglar antes, porque una automatización
-- encima de una regla mal aplicada solo hace que el error se repita puntual.
--
-- AGUJERO 1 · sacar un partido de la jornada no lo sacaba de la cuenta.
--   `jornada_excluidos` movía la hora de cierre y bloqueaba elegir a esos
--   jugadores, pero `slot_contrib` nunca miraba la tabla. El cartel de la
--   pantalla decía «sus jugadores no puntúan» y sí puntuaban: quien ya los
--   tuviera puestos de antes seguía sumando con ellos. Aquí se cumple.
--
-- AGUJERO 2 · un partido adelantado abría la jornada ya cerrada.
--   El cierre era el primer partido de la ronda. Si uno se adelanta a la
--   semana anterior, ese pasa a ser «el primero» y la jornada nace con la hora
--   de cierre ya pasada: doce personas sin poder alinear. Ahora el cierre lo
--   marca el primer partido que quede POR JUGAR cuando la jornada se abre.
--
-- El ciclo no va por calendario («los martes»), va por estado. Es lo único que
-- aguanta una jornada intersemanal que acaba un jueves y encadena con otra el
-- viernes: en cuanto la ronda está entera y cargada, se pasa de jornada, sea
-- lunes o sea jueves por la noche.

-- ════════════════════════════════════════════════════════════════════════════
-- 1 · CUÁNDO SE ABRIÓ LA JORNADA
-- ════════════════════════════════════════════════════════════════════════════
-- Hace falta para el agujero 2. Se apunta con un disparador y no a mano, para
-- que valga igual si la jornada la pasa el ciclo o la pasa la organización
-- desde el panel.

alter table leagues add column if not exists jornada_desde timestamptz;

comment on column leagues.jornada_desde is
  'Cuándo se abrió la jornada en curso. El cierre lo marca el primer partido que empiece después de esta hora.';

update leagues set jornada_desde = coalesce(jornada_desde, now());

create or replace function app.marcar_apertura_de_jornada()
returns trigger language plpgsql as $$
begin
  if new.current_jornada is distinct from old.current_jornada then
    new.jornada_desde := now();
  end if;
  return new;
end $$;

drop trigger if exists leagues_apertura_de_jornada on leagues;
create trigger leagues_apertura_de_jornada
  before update on leagues
  for each row execute function app.marcar_apertura_de_jornada();

-- ════════════════════════════════════════════════════════════════════════════
-- 2 · EL CIERRE LO MARCA EL PRIMER PARTIDO QUE QUEDE POR JUGAR
-- ════════════════════════════════════════════════════════════════════════════
-- Si no queda ninguno posterior a la apertura —caso raro: ronda entera
-- adelantada— se vuelve al primero de la ronda. Es peor no tener hora que
-- tener una discutible.

create or replace function app.cierre_de_jornada(p_league uuid, p_jornada int)
returns timestamptz
language sql stable security definer set search_path = public, pg_temp as $$
  with abierta as (
    select coalesce(lg.jornada_desde, '-infinity'::timestamptz) as desde
    from leagues lg where lg.id = p_league
  ),
  candidatos as (
    select m.comienza
    from jornada_rondas jr
    join hl_matches m on m.ronda = jr.ronda
    where jr.league_id = p_league and jr.jornada = p_jornada
      and m.comienza is not null
      and not exists (select 1 from jornada_excluidos x
                       where x.league_id = p_league and x.jornada = p_jornada
                         and x.match_id = m.match_id)
  )
  select coalesce(
    (select jr.cierre from jornada_rondas jr
      where jr.league_id = p_league and jr.jornada = p_jornada),
    (select min(c.comienza) from candidatos c, abierta a where c.comienza > a.desde),
    (select min(c.comienza) from candidatos c))
$$;

-- ════════════════════════════════════════════════════════════════════════════
-- 3 · UN PARTIDO FUERA DE LA JORNADA NO PUNTÚA
-- ════════════════════════════════════════════════════════════════════════════
-- Se anula en la cuenta, no se borra el dato: así volver a meter el partido es
-- un clic y no una recarga desde la API.

-- Esta va con los permisos del dueño y NO con los de quien pregunta, al revés
-- que el resto: `authenticated` no puede leer hl_matches (es catálogo de la
-- API, no de la liga) y una vista de invocador dejaría a los doce sin poder
-- leer la clasificación entera. No destapa nada: qué partidos están fuera ya
-- es público en jornada_excluidos.
create or replace view clubes_excluidos as
select distinct x.league_id, x.jornada, c.id as club_id
from jornada_excluidos x
join hl_matches m on m.match_id = x.match_id
join clubs c on c.league_id = x.league_id
            and c.highlightly_id in (m.home_team_id, m.away_team_id);

comment on view clubes_excluidos is
  'Clubes que juegan un partido sacado de esa jornada. Sus jugadores no aportan nada.';

grant select on clubes_excluidos to anon, authenticated;

-- Misma vista que dejó la 0011 (amarilla 1, roja 3) con una condición más en
-- `act`: el club está fuera si no jugó O si su partido se sacó de la jornada.
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
         case when ls.club_id is not null
                   and (coalesce(cs.played,true) = false
                        or exists (select 1 from clubes_excluidos ce
                                    where ce.league_id = l.league_id
                                      and ce.jornada   = l.jornada
                                      and ce.club_id   = ls.club_id))
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

-- ════════════════════════════════════════════════════════════════════════════
-- 4 · LOS DATOS DE CLUB, TAMBIÉN SIN LOS PARTIDOS EXCLUIDOS
-- ════════════════════════════════════════════════════════════════════════════
-- El cuerpo pasa a `app` para que lo pueda llamar el ciclo, que no es nadie
-- con sesión y por tanto no pasa el `is_admin()`.

create or replace function app.cerrar_datos_de_club(p_jornada int)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare lg uuid; r text; n int;
begin
  select id into lg from leagues limit 1;
  select jr.ronda into r from jornada_rondas jr where jr.league_id = lg and jr.jornada = p_jornada;
  if r is null then
    raise exception 'La jornada % no tiene asignada ninguna ronda real', p_jornada;
  end if;

  insert into club_stats (league_id, jornada, club_id, team_points, clean_sheet, played)
  with cuentan as (
    select * from hl_matches m
     where m.ronda = r and m.estado = 'Finished'
       and not exists (select 1 from jornada_excluidos x
                        where x.league_id = lg and x.jornada = p_jornada
                          and x.match_id = m.match_id)
  ), lados as (
    select home_team_id as ht, home_goles as gf, away_goles as gc from cuentan
    union all
    select away_team_id,       away_goles,       home_goles      from cuentan
  )
  select lg, p_jornada, c.id,
         case when l.gf > l.gc then 3 when l.gf = l.gc then 1 else 0 end,
         l.gc = 0, true
  from lados l join clubs c on c.highlightly_id = l.ht
  where c.league_id = lg
  on conflict (league_id, jornada, club_id) do update
    set team_points = excluded.team_points,
        clean_sheet = excluded.clean_sheet,
        played      = excluded.played;
  get diagnostics n = row_count;

  -- El club que no jugó —o cuyo partido se sacó de la jornada— se deja dicho
  -- por dato y no por ausencia de fila, para que la regla se aplique sola.
  insert into club_stats (league_id, jornada, club_id, team_points, clean_sheet, played)
  select lg, p_jornada, c.id, 0, false, false
  from clubs c
  where c.league_id = lg
    and not exists (
      select 1 from hl_matches m
       where m.ronda = r and m.estado = 'Finished'
         and c.highlightly_id in (m.home_team_id, m.away_team_id)
         and not exists (select 1 from jornada_excluidos x
                          where x.league_id = lg and x.jornada = p_jornada
                            and x.match_id = m.match_id))
  on conflict (league_id, jornada, club_id) do update
    set team_points = 0, clean_sheet = false, played = false;

  return n;
end $$;

revoke all on function app.cerrar_datos_de_club(int) from anon, authenticated;

create or replace function cerrar_datos_de_club(p_jornada int)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede cargar resultados';
  end if;
  return app.cerrar_datos_de_club(p_jornada);
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 5 · LA CUOTA DE LA API, CONTADA
-- ════════════════════════════════════════════════════════════════════════════
-- Son 100 llamadas al día en el plan gratis. Un ciclo que se pasara de la
-- cuota dejaría a la organización sin poder hacer nada a mano ese día, así que
-- se cuenta en el único sitio por el que pasan todas: la llamada.

create table if not exists app_api_uso (
  dia      date primary key,
  llamadas int  not null default 0
);

alter table app_api_uso enable row level security;
grant select on app_api_uso to authenticated;
drop policy if exists api_uso_read on app_api_uso;
create policy api_uso_read on app_api_uso for select to authenticated using (true);

create or replace function app.highlightly(p_path text)
returns jsonb
language plpgsql
security definer
set search_path = extensions, public, pg_temp
as $$
declare k text; r extensions.http_response;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'highlightly_key';
  if k is null then raise exception 'No hay clave de Highlightly en el baúl'; end if;

  -- Se apunta antes de llamar: RapidAPI cobra también las que salen mal.
  insert into app_api_uso (dia, llamadas) values (current_date, 1)
  on conflict (dia) do update set llamadas = app_api_uso.llamadas + 1;

  select * into r from extensions.http((
    'GET',
    'https://football-highlights-api.p.rapidapi.com' || p_path,
    array[
      extensions.http_header('x-rapidapi-host','football-highlights-api.p.rapidapi.com'),
      extensions.http_header('x-rapidapi-key', k)
    ],
    null, null
  )::extensions.http_request);

  if r.status <> 200 then
    raise exception 'Highlightly devolvió % en %: %', r.status, p_path, left(r.content, 300);
  end if;
  return r.content::jsonb;
end $$;

revoke all on function app.highlightly(text) from anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6 · EL PARTE DE LO QUE HACE SOLO
-- ════════════════════════════════════════════════════════════════════════════
-- Una automatización que no deja rastro es una automatización en la que no se
-- puede confiar: cuando alguien pregunte por qué su jugador no puntuó, la
-- respuesta tiene que estar escrita en algún sitio.

create table if not exists app_avisos (
  id        bigserial primary key,
  league_id uuid not null references leagues(id) on delete cascade,
  cuando    timestamptz not null default now(),
  clase     text not null check (clase in ('carga','avance','exclusion','aviso','fallo')),
  jornada   int,
  texto     text not null
);

create index if not exists app_avisos_orden on app_avisos (league_id, cuando desc);

alter table app_avisos enable row level security;
grant select on app_avisos to authenticated;
drop policy if exists avisos_read on app_avisos;
create policy avisos_read on app_avisos for select to authenticated using (true);
-- Nadie escribe desde el navegador: solo las funciones del ciclo.

alter table leagues add column if not exists automatico boolean not null default true;
alter table leagues add column if not exists ultimo_ciclo timestamptz;
alter table leagues add column if not exists ultimo_calendario timestamptz;

comment on column leagues.automatico is
  'Si está en false el ciclo no toca nada: queda todo a mano desde el panel.';

-- La organización puede apagarlo y encenderlo; nadie más.
revoke update on leagues from authenticated;
grant  update (current_jornada, lineups_locked, automatico) on leagues to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 7 · EL CICLO
-- ════════════════════════════════════════════════════════════════════════════
-- Corre cada hora y decide por estado, no por fecha:
--
--   1. refresca el calendario real cada 6 h — es lo que trae los aplazamientos
--   2. carga los partidos terminados de la jornada en curso y de la anterior
--   3. cierra los datos de club de lo que haya cargado
--   4. saca de la jornada lo que se ha aplazado más allá de la siguiente, que
--      es lo único que la dejaría congelada para siempre
--   5. avisa de los adelantados, que son decisión de la organización
--   6. pasa de jornada cuando la ronda está jugada y cargada
--
-- Todo lo que hace queda escrito en app_avisos, y todo es reversible desde el
-- panel.

create or replace function app.ciclo(p_max_cargas int default 4, p_tope_dia int default 80)
returns table(accion text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare
  lg uuid; j int; auto boolean; ult_cal timestamptz; desde timestamptz;
  r text; r_sig text; inicio_sig timestamptz;
  usadas int; cargados int := 0; jj int;
  pendientes int; sin_cargar int;
  m record;
begin
  select id, current_jornada, automatico, ultimo_calendario, jornada_desde
    into lg, j, auto, ult_cal, desde
  from leagues limit 1;
  if lg is null then
    return query select 'nada'::text, 'no hay liga'::text;
    return;
  end if;

  update leagues set ultimo_ciclo = now() where id = lg;

  if not auto then
    return query select 'apagado'::text, 'el ciclo automático está desactivado'::text;
    return;
  end if;

  select coalesce(u.llamadas, 0) into usadas from app_api_uso u where u.dia = current_date;
  usadas := coalesce(usadas, 0);
  if usadas >= p_tope_dia then
    return query select 'cuota'::text,
      format('ya van %s llamadas hoy, se espera a mañana', usadas)::text;
    return;
  end if;

  -- ── 1. el calendario ──────────────────────────────────────────────────────
  if ult_cal is null or ult_cal < now() - interval '6 hours' then
    begin
      perform app.refrescar_calendario();
      update leagues set ultimo_calendario = now() where id = lg;
      return query select 'calendario'::text, 'calendario real actualizado'::text;
    exception when others then
      insert into app_avisos (league_id, clase, jornada, texto)
        values (lg, 'fallo', j, 'No se ha podido refrescar el calendario: ' || sqlerrm);
      return query select 'fallo'::text, ('calendario: ' || sqlerrm)::text;
    end;
  end if;

  select jr.ronda into r     from jornada_rondas jr where jr.league_id = lg and jr.jornada = j;
  select jr.ronda into r_sig from jornada_rondas jr where jr.league_id = lg and jr.jornada = j + 1;
  if r is null then
    return query select 'nada'::text, format('la jornada %s no tiene ronda asignada', j)::text;
    return;
  end if;

  -- ── 2. cargar lo terminado ────────────────────────────────────────────────
  -- También la jornada anterior: un partido puede acabar después de haber
  -- pasado de jornada y sus números siguen siendo de la jornada en la que se
  -- jugó.
  for m in
    select hm.match_id, jr.jornada
    from jornada_rondas jr
    join hl_matches hm on hm.ronda = jr.ronda
    where jr.league_id = lg
      and jr.jornada between greatest(j - 1, 1) and j
      and hm.estado = 'Finished'
      and not hm.stats_cargadas
      and not exists (select 1 from jornada_excluidos x
                       where x.league_id = lg and x.jornada = jr.jornada
                         and x.match_id = hm.match_id)
    order by hm.comienza
    limit p_max_cargas
  loop
    begin
      perform app.cargar_partido(m.match_id);
      cargados := cargados + 1;
    exception when others then
      insert into app_avisos (league_id, clase, jornada, texto)
        values (lg, 'fallo', m.jornada,
                format('No se ha podido cargar el partido %s: %s', m.match_id, sqlerrm));
    end;
  end loop;

  -- ── 3. los datos de club, en el mismo paso ────────────────────────────────
  -- Si se dejaran para después, el desglose de la pantalla no cuadraría con el
  -- resultado oficial mientras tanto y saldría el aviso de descuadre.
  if cargados > 0 then
    for jj in greatest(j - 1, 1)..j loop
      begin
        perform app.cerrar_datos_de_club(jj);
      exception when others then
        insert into app_avisos (league_id, clase, jornada, texto)
          values (lg, 'fallo', jj, 'No se han podido cerrar los datos de club: ' || sqlerrm);
      end;
    end loop;
    insert into app_avisos (league_id, clase, jornada, texto)
      values (lg, 'carga', j, format('Cargados %s partidos de Primera.', cargados));
    return query select 'carga'::text, format('%s partidos cargados', cargados)::text;
  end if;

  -- ── 4. lo aplazado más allá de la jornada siguiente ───────────────────────
  -- Esperarlo dejaría la jornada abierta un mes, que es justo lo que no se
  -- quiere. Por el reglamento (no se recalcula hacia atrás) se saca.
  select min(hm.comienza) into inicio_sig from hl_matches hm where hm.ronda = r_sig;
  if inicio_sig is not null then
    for m in
      select hm.match_id, hm.home_nombre, hm.away_nombre
      from hl_matches hm
      where hm.ronda = r
        and hm.estado is distinct from 'Finished'
        and hm.comienza >= inicio_sig
        and not exists (select 1 from jornada_excluidos x
                         where x.league_id = lg and x.jornada = j
                           and x.match_id = hm.match_id)
    loop
      insert into jornada_excluidos (league_id, jornada, match_id, motivo)
        values (lg, j, m.match_id, 'aplazado más allá de la jornada siguiente')
        on conflict do nothing;
      insert into app_avisos (league_id, clase, jornada, texto)
        values (lg, 'exclusion', j, format(
          '%s – %s se ha aplazado más allá de la jornada siguiente, así que se saca de la jornada %s: '
          || 'sus jugadores no puntúan y no se pueden elegir. Si prefieres esperarlo, vuelve a meterlo desde el panel.',
          m.home_nombre, m.away_nombre, j));
      return query select 'exclusion'::text,
        format('%s – %s fuera de la jornada %s', m.home_nombre, m.away_nombre, j)::text;
    end loop;
  end if;

  -- ── 5. los adelantados: se avisa, no se decide ────────────────────────────
  -- Un partido jugado antes de abrirse la jornada se sabe al alinear, así que
  -- la organización querrá sacarlo. Pero es su decisión, no la del robot.
  for m in
    select hm.match_id, hm.home_nombre, hm.away_nombre
    from hl_matches hm
    where hm.ronda = r and hm.estado = 'Finished'
      and desde is not null and hm.comienza < desde
      and not exists (select 1 from jornada_excluidos x
                       where x.league_id = lg and x.jornada = j and x.match_id = hm.match_id)
      and not exists (select 1 from app_avisos a
                       where a.league_id = lg and a.clase = 'aviso' and a.jornada = j
                         and a.texto like '%' || hm.home_nombre || ' – ' || hm.away_nombre || '%')
  loop
    insert into app_avisos (league_id, clase, jornada, texto)
      values (lg, 'aviso', j, format(
        '%s – %s se jugó antes de abrirse la jornada %s, así que su resultado ya se conocía al alinear. '
        || 'Si quieres que no cuente, sácalo de la jornada desde el panel.',
        m.home_nombre, m.away_nombre, j));
    return query select 'aviso'::text,
      format('%s – %s se adelantó', m.home_nombre, m.away_nombre)::text;
  end loop;

  -- ── 6. pasar de jornada ───────────────────────────────────────────────────
  select count(*) into pendientes
  from hl_matches hm
  where hm.ronda = r and hm.estado is distinct from 'Finished'
    and not exists (select 1 from jornada_excluidos x
                     where x.league_id = lg and x.jornada = j and x.match_id = hm.match_id);

  select count(*) into sin_cargar
  from hl_matches hm
  where hm.ronda = r and hm.estado = 'Finished' and not hm.stats_cargadas
    and not exists (select 1 from jornada_excluidos x
                     where x.league_id = lg and x.jornada = j and x.match_id = hm.match_id);

  if pendientes > 0 or sin_cargar > 0 then
    return query select 'espera'::text, format(
      'jornada %s: %s partidos por jugar y %s por cargar', j, pendientes, sin_cargar)::text;
    return;
  end if;

  if j >= 11 then
    return query select 'final'::text,
      'la jornada 11 es la última: los playoffs se llevan a mano'::text;
    return;
  end if;

  perform app.cerrar_datos_de_club(j);
  update leagues set current_jornada = j + 1 where id = lg;
  insert into app_avisos (league_id, clase, jornada, texto)
    values (lg, 'avance', j + 1, format(
      'Jornada %s terminada y jornada %s abierta: ya se pueden poner alineaciones.', j, j + 1));
  return query select 'avance'::text, format('jornada %s → %s', j, j + 1)::text;
end $$;

revoke all on function app.ciclo(int, int) from anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 8 · LO QUE VE Y TOCA LA ORGANIZACIÓN
-- ════════════════════════════════════════════════════════════════════════════

create or replace function ciclo_estado()
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'automatico',  lg.automatico,
    'ultimo',      lg.ultimo_ciclo,
    'calendario',  lg.ultimo_calendario,
    'jornada',     lg.current_jornada,
    'abierta_desde', lg.jornada_desde,
    'cierre',      app.cierre_de_jornada(lg.id, lg.current_jornada),
    'llamadas_hoy', coalesce((select u.llamadas from app_api_uso u where u.dia = current_date), 0),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'cuando', a.cuando, 'clase', a.clase, 'jornada', a.jornada, 'texto', a.texto)
             order by a.cuando desc)
      from (select * from app_avisos a2 where a2.league_id = lg.id
             order by a2.cuando desc limit 30) a), '[]'::jsonb))
  from leagues lg limit 1
$$;

create or replace function ciclo_ahora()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare pasos jsonb;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede lanzar el ciclo';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('accion', c.accion, 'detalle', c.detalle)), '[]'::jsonb)
    into pasos from app.ciclo() c;
  return pasos;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 9 · CADA HORA
-- ════════════════════════════════════════════════════════════════════════════
-- La programación va aparte, en 0031: `create extension pg_cron` y la llamada
-- a cron.schedule no pueden ir en la misma transacción que esta migración,
-- porque el esquema `cron` no existe todavía cuando se compila.
