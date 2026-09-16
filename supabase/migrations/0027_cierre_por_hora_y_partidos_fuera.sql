-- La jornada se cierra sola a la hora del primer partido, y se pueden sacar
-- partidos de una jornada.
--
-- ── Por qué el cierre por hora ──────────────────────────────────────────────
--
-- Hasta ahora la jornada se cerraba con un botón, así que alguien tenía que
-- estar delante el viernes por la noche. Si se le olvidaba, se podía alinear
-- con los partidos ya empezados, que es la única forma de hacer trampa en
-- este juego.
--
-- Ahora la hora la pone el calendario: el primer partido de la jornada. Si el
-- primero es el viernes a las 21:00, a las 21:00 se cierra la edición y se
-- destapan todos los onces. La organización puede fijar otra hora si quiere,
-- y el botón de cerrar a mano sigue estando para adelantarlo.
--
-- Lo comprueba la base de datos, no el navegador. Si lo mirara el móvil,
-- bastaría con cambiar la hora del teléfono para seguir alineando.
--
-- ── Por qué sacar partidos de una jornada ───────────────────────────────────
--
-- Dos casos reales, y el segundo es el que rompe el juego:
--
--   · Aplazado: se juega semanas después. Si la jornada esperase, la liga se
--     congela. No espera: esos clubes no puntúan, que es la regla que ya
--     estaba escrita —«si el club real no juega, ese jugador no puntúa».
--
--   · Adelantado: se juega ANTES de que la gente alinee. Quien ponga a un
--     jugador de ese partido ya sabe lo que hizo. Eso no es apostar, es
--     cobrar.
--
-- Sacando el partido de la jornada se arreglan los dos: esos clubes no
-- puntúan y, además, el cierre se recalcula con los partidos que quedan. Sin
-- esto, un partido adelantado al miércoles arrastraría el cierre al miércoles
-- y fastidiaría a los doce.

-- ── la hora de comienzo, que hasta ahora se tiraba ──────────────────────────
-- El calendario guardaba `left(date, 10)`, o sea solo el día. La API manda la
-- hora completa en UTC; aquí se guarda entera y se compara con `now()`, así
-- que el cambio de hora de octubre se resuelve solo.

alter table hl_matches add column if not exists comienza timestamptz;

comment on column hl_matches.comienza is
  'Hora de comienzo con zona horaria. De aquí sale el cierre de la jornada.';

create or replace function app.refrescar_calendario(p_league int default 119924, p_season int default 2026)
returns int
language plpgsql security definer set search_path = extensions, public, pg_temp as $$
declare off int; j jsonb; total int := 0;
begin
  foreach off in array array[0,100,200,300] loop
    j := app.highlightly('/matches?leagueId=' || p_league || '&season=' || p_season
                          || '&limit=100&offset=' || off);
    insert into hl_matches (match_id, ronda, fecha, comienza, estado,
                            home_team_id, away_team_id,
                            home_nombre, away_nombre, home_goles, away_goles, actualizado)
    select (m ->> 'id')::bigint,
           m ->> 'round',
           (left(m ->> 'date', 10))::date,
           (m ->> 'date')::timestamptz,
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
      set estado = excluded.estado, fecha = excluded.fecha,
          comienza = excluded.comienza, ronda = excluded.ronda,
          home_goles = excluded.home_goles, away_goles = excluded.away_goles,
          actualizado = now();
    total := total + jsonb_array_length(coalesce(j -> 'data', j));
  end loop;
  return total;
end $$;

revoke all on function app.refrescar_calendario(int, int) from anon, authenticated;

-- ── partidos fuera de una jornada ───────────────────────────────────────────
-- Va por liga porque el reparto jornada→ronda ya es por liga: dos ligas
-- podrían empezar en rondas distintas y no tienen por qué tomar la misma
-- decisión sobre un adelantado.

create table if not exists jornada_excluidos (
  league_id uuid not null references leagues(id) on delete cascade,
  jornada   int  not null,
  match_id  bigint not null,
  motivo    text,
  creado_en timestamptz not null default now(),
  primary key (league_id, jornada, match_id)
);

alter table jornada_excluidos enable row level security;
grant select on jornada_excluidos to anon, authenticated;

-- Todo el mundo tiene que poder verlos: la pantalla de alineación necesita
-- saber qué clubes están bloqueados esta jornada y por qué.
drop policy if exists excluidos_read on jornada_excluidos;
create policy excluidos_read on jornada_excluidos for select to anon, authenticated using (true);
drop policy if exists excluidos_admin on jornada_excluidos;
create policy excluidos_admin on jornada_excluidos for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- Hora de cierre puesta a mano, para una jornada concreta. Null = la calcula
-- el calendario.
alter table jornada_rondas add column if not exists cierre timestamptz;

comment on column jornada_rondas.cierre is
  'Cierre fijado a mano. Si es null lo marca el primer partido no excluido de la ronda.';

-- ── cuándo cierra ───────────────────────────────────────────────────────────

create or replace function app.cierre_de_jornada(p_league uuid, p_jornada int)
returns timestamptz
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    jr.cierre,
    (select min(m.comienza) from hl_matches m
      where m.ronda = jr.ronda
        and m.comienza is not null
        and not exists (select 1 from jornada_excluidos x
                         where x.league_id = p_league and x.jornada = p_jornada
                           and x.match_id = m.match_id)))
  from jornada_rondas jr
  where jr.league_id = p_league and jr.jornada = p_jornada
$$;

-- Cerrada = la organización le ha dado al botón, O ya ha llegado la hora.
-- Si no hay hora conocida —calendario sin refrescar— manda solo el botón: es
-- peor dejar a doce personas sin poder alinear por un dato que falta.
create or replace function app.jornada_cerrada(p_league uuid, p_jornada int)
returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select lg.lineups_locked from leagues lg where lg.id = p_league), false)
    or coalesce(now() >= app.cierre_de_jornada(p_league, p_jornada), false)
$$;

-- ── los dos sitios donde se aplica ──────────────────────────────────────────
-- Toda la regla vive aquí: una función para escribir y una política para leer.

create or replace function app.lineup_editable(p_league uuid, p_jornada int) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from leagues lg
    where lg.id = p_league
      and lg.current_jornada = p_jornada
      and not app.jornada_cerrada(p_league, p_jornada)
  )
$$;

-- La copia pública, que es la que usan las políticas antiguas.
create or replace function lineup_editable(p_league uuid, p_jornada int) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select app.lineup_editable(p_league, p_jornada)
$$;

revoke execute on function lineup_editable(uuid, int) from public, anon;
grant  execute on function lineup_editable(uuid, int) to authenticated;

-- Los onces de los rivales se destapan en el mismo momento en que se cierra
-- la edición, que es lo que la gente espera: si ya no puedo cambiar, ya puedo
-- mirar.
drop policy if exists lineups_read on lineups;
create policy lineups_read on lineups for select to authenticated using (
  manager_id = app.my_manager_id()
  or app.is_admin()
  or exists (select 1 from leagues lg
             where lg.id = lineups.league_id
               and (lineups.jornada < lg.current_jornada
                    or app.jornada_cerrada(lg.id, lineups.jornada)))
);

-- ── lo que usa el panel ─────────────────────────────────────────────────────

-- Sacar un partido de la jornada, o volver a meterlo.
create or replace function excluir_partido(p_jornada int, p_match bigint, p_motivo text)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg leagues;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede sacar un partido de la jornada';
  end if;
  select * into lg from leagues order by created_at limit 1;
  if not exists (select 1 from hl_matches where match_id = p_match) then
    raise exception 'Ese partido no está en el calendario';
  end if;
  insert into jornada_excluidos (league_id, jornada, match_id, motivo)
  values (lg.id, p_jornada, p_match, nullif(trim(coalesce(p_motivo,'')), ''))
  on conflict (league_id, jornada, match_id) do update set motivo = excluded.motivo;
end $$;

create or replace function incluir_partido(p_jornada int, p_match bigint)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg leagues;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede devolver un partido a la jornada';
  end if;
  select * into lg from leagues order by created_at limit 1;
  delete from jornada_excluidos
   where league_id = lg.id and jornada = p_jornada and match_id = p_match;
end $$;

-- Fijar el cierre a mano, o volver al automático pasando null.
create or replace function fijar_cierre(p_jornada int, p_cuando timestamptz)
returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg leagues;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede cambiar la hora de cierre';
  end if;
  select * into lg from leagues order by created_at limit 1;
  update jornada_rondas set cierre = p_cuando
   where league_id = lg.id and jornada = p_jornada;
  if not found then
    raise exception 'La jornada % no está asignada a ninguna ronda real', p_jornada;
  end if;
  return app.cierre_de_jornada(lg.id, p_jornada);
end $$;

-- ── lo que necesita saber el juego ──────────────────────────────────────────
-- Una sola llamada: cuándo cierra esta jornada, si ya ha cerrado, y qué
-- clubes están fuera y por qué. La pantalla de alineación los bloquea con el
-- motivo a la vista, para que nadie gaste un hueco en un jugador que no va a
-- puntuar.

create or replace function jornada_estado(p_jornada int)
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'jornada',  p_jornada,
    'cierre',   app.cierre_de_jornada(lg.id, p_jornada),
    'cerrada',  app.jornada_cerrada(lg.id, p_jornada),
    'a_mano',   coalesce((select jr.cierre is not null from jornada_rondas jr
                           where jr.league_id = lg.id and jr.jornada = p_jornada), false),
    'clubes_fuera', coalesce((
      select jsonb_agg(distinct jsonb_build_object(
               'club_id', c.id, 'club', c.name, 'motivo', x.motivo))
      from jornada_excluidos x
      join hl_matches m on m.match_id = x.match_id
      join clubs c on c.highlightly_id in (m.home_team_id, m.away_team_id)
      where x.league_id = lg.id and x.jornada = p_jornada), '[]'::jsonb))
  from leagues lg order by lg.created_at limit 1
$$;

revoke execute on function jornada_estado(int) from public, anon;
grant  execute on function jornada_estado(int) to authenticated;
revoke execute on function excluir_partido(int, bigint, text) from public, anon;
grant  execute on function excluir_partido(int, bigint, text) to authenticated;
revoke execute on function incluir_partido(int, bigint) from public, anon;
grant  execute on function incluir_partido(int, bigint) to authenticated;
revoke execute on function fijar_cierre(int, timestamptz) from public, anon;
grant  execute on function fijar_cierre(int, timestamptz) to authenticated;
