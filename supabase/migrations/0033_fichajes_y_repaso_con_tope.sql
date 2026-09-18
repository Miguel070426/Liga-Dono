-- El mercado no se cierra para el juego: los clubes siguen fichando a gente sin
-- contrato durante el año, y los fichajes de este verano no estaban puestos.
--
-- Lo primero que se investigó fue si la API tiene una forma barata de pedir «la
-- plantilla del Betis». **No la tiene.** Probado contra la API de verdad:
--
--   /teams/{id}          200, pero solo devuelve id, logo, nombre y tipo
--   /teams/{id}/squad    404
--   /squads?teamId=      404
--   /squad?teamId=       404
--   /players?teamId=     400
--   /team-statistics/    404
--
-- Lo que sí hay es `/players?name=…`, que busca por nombre y es preciso
-- («Mbappe» devuelve exactamente dos), y `/players/{id}`, que dice el club
-- actual y la posición. Así que un fichaje se añade con DOS llamadas, y no hay
-- forma de descubrirlos en bloque sin gastar una llamada por jugador.
--
-- De ahí salen las tres vías, por orden de lo que cuestan:
--
--   1. GRATIS · El que juega entra solo. El box score de cada partido trae las
--      dos plantillas enteras, así que un fichaje aparece en el catálogo la
--      primera vez que juega, sin gastar ni una llamada de más. Ya funcionaba.
--   2. DOS LLAMADAS · El que aún no ha jugado se añade a mano desde el panel:
--      se busca por nombre y se añade. Para el «lo han fichado y quiero que
--      esté ya».
--   3. UNA POR JUGADOR · El repaso de los que ya tenemos, que detecta traspasos
--      y salidas. Este es el caro, y es el que llevaba el miedo de quedarse sin
--      llamadas, así que va con tope y con los resultados por delante.
--
-- EL TOPE. El reparto de las 100 llamadas del día queda así:
--
--   · Los resultados van SIEMPRE primero. El ciclo carga partidos antes de
--     mirar plantillas y, si carga alguno, ese turno termina ahí.
--   · El repaso no empieza si el día lleva ya 40 llamadas, y no pasa de 20
--     jugadores al día.
--   · El ciclo entero no pasa de 80, así que a la organización le quedan 20
--     libres para lo que quiera hacer a mano.
--
-- Peor día posible: 4 de calendario + 10 de una jornada + 20 de repaso = 34.
-- Nunca puede pasar que falte una llamada para cargar un resultado por haberla
-- gastado en repasar plantillas.

-- ── traducir la posición del perfil ─────────────────────────────────────────
-- `app.pos_desde_highlightly` sirve para el box score, que dice «Goalkeeper» o
-- «Defender». El perfil del jugador habla otro idioma: «Centre-Back», «Left
-- Winger», «Attacking Midfield». Si se leyera con el otro traductor, un
-- delantero entraría como centrocampista y puntuaría con otros multiplicadores.

create or replace function app.pos_desde_perfil(t text) returns pos_t
language sql immutable set search_path = public, pg_temp as $$
  select case
    when t is null or btrim(t) = ''            then 'MF'
    when lower(t) like '%keeper%'              then 'GK'
    when lower(t) like '%back%'                then 'DF'
    when lower(t) like '%defender%'            then 'DF'
    when lower(t) like '%midfield%'            then 'MF'
    when lower(t) like '%winger%'              then 'FW'
    when lower(t) like '%forward%'             then 'FW'
    when lower(t) like '%striker%'             then 'FW'
    else 'MF' end::pos_t
$$;

-- ── escapar el nombre para la URL ───────────────────────────────────────────
-- Los nombres traen acentos y espacios. Va carácter a carácter y en bytes UTF-8,
-- que es lo único que aguanta una «ñ» o una tilde dentro de una query string.

create or replace function app.urlenc(t text) returns text
language sql immutable set search_path = public, pg_temp as $$
  select coalesce(string_agg(
    case when s.ch ~ '^[A-Za-z0-9_.~-]$' then s.ch
         else (select string_agg('%' || upper(to_hex(get_byte(convert_to(s.ch, 'UTF8'), g))), '')
                 from generate_series(0, octet_length(convert_to(s.ch, 'UTF8')) - 1) g)
    end, '' order by s.n), '')
  from regexp_split_to_table(coalesce(t, ''), '') with ordinality as s(ch, n)
$$;

-- ── buscar un fichaje por nombre ────────────────────────────────────────────
-- Una llamada. Devuelve los candidatos con su identificador, y dice cuáles ya
-- están en el catálogo para no añadir dos veces al mismo.

create or replace function buscar_jugador(p_nombre text)
returns table(hl_id bigint, nombre text, nombre_completo text, ya_lo_tenemos boolean, club_nuestro text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare j jsonb;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede buscar jugadores';
  end if;
  if length(btrim(coalesce(p_nombre, ''))) < 3 then
    raise exception 'Escribe al menos tres letras del nombre';
  end if;

  j := app.highlightly('/players?name=' || app.urlenc(btrim(p_nombre)));

  return query
  select (p ->> 'id')::bigint,
         p ->> 'name',
         p ->> 'fullName',
         cp.id is not null,
         c.name
  from jsonb_array_elements(coalesce(j -> 'data', j)) p
  left join club_players cp on cp.highlightly_id = (p ->> 'id')::bigint
  left join clubs c on c.id = cp.club_id
  order by cp.id is not null desc, p ->> 'name'
  limit 25;
end $$;

-- ── añadir el fichaje ───────────────────────────────────────────────────────
-- Otra llamada. El club lo dice la API, no la organización: así no se puede
-- meter a un jugador en el club equivocado por error de dedo. Si el club que
-- dice la API no es uno de los 20 de Primera, no se añade y se explica por qué.

create or replace function anadir_jugador(p_hl_id bigint)
returns jsonb
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare
  j jsonb; lg uuid; club_api text; nombre text; puesto pos_t; m record;
  ya club_players; nuevo uuid;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede añadir jugadores';
  end if;
  select id into lg from leagues limit 1;

  j := app.highlightly('/players/' || p_hl_id);
  if j -> 0 is null then
    return jsonb_build_object('ok', false, 'motivo', 'La API no conoce a ese jugador');
  end if;

  nombre   := nullif(btrim(coalesce(j -> 0 ->> 'name', j -> 0 ->> 'fullName', '')), '');
  club_api := nullif(btrim(coalesce(j -> 0 -> 'profile' -> 'club' ->> 'current', '')), '');
  puesto   := app.pos_desde_perfil(j -> 0 -> 'profile' -> 'position' ->> 'main');

  if club_api is null then
    return jsonb_build_object('ok', false, 'nombre', nombre,
      'motivo', 'La API no dice en qué club está');
  end if;

  select * into m from app.club_por_nombre(lg, club_api);
  if m.club_id is null then
    return jsonb_build_object('ok', false, 'nombre', nombre, 'club_api', club_api,
      'motivo', format('La API lo pone en «%s», que no es ninguno de los 20 de Primera', club_api));
  end if;

  select * into ya from club_players where highlightly_id = p_hl_id;
  if found then
    update club_players
       set club_id = m.club_id, activo = true, motivo_baja = null,
           revisar = false, motivo_revision = null,
           club_segun_api = club_api, verificado_en = now()
     where id = ya.id;
    return jsonb_build_object('ok', true, 'nombre', coalesce(ya.name, nombre),
      'club', (select name from clubs where id = m.club_id), 'pos', ya.pos,
      'que', case when ya.club_id = m.club_id and ya.activo then 'ya estaba'
                  when ya.club_id <> m.club_id then 'movido' else 'reactivado' end);
  end if;

  insert into club_players (club_id, name, pos, highlightly_id, origen,
                            club_segun_api, verificado_en, activo)
  values (m.club_id, nombre, puesto, p_hl_id, 'fichaje a mano', club_api, now(), true)
  returning id into nuevo;

  return jsonb_build_object('ok', true, 'nombre', nombre, 'pos', puesto,
    'club', (select name from clubs where id = m.club_id), 'que', 'añadido');
end $$;

-- ── el repaso, con los resultados por delante ───────────────────────────────

create or replace function app.repasar_plantillas(
  p_por_tanda int default 5, p_tope_dia int default 20, p_reserva int default 40)
returns int
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare usadas int; hechos int; cupo int;
begin
  select coalesce((select u.llamadas from app_api_uso u where u.dia = current_date), 0) into usadas;
  -- Si el día ya va cargado, el repaso espera: una llamada gastada aquí podría
  -- ser la que faltara para cargar un resultado.
  if usadas >= p_reserva then return 0; end if;

  select count(*)::int into hechos from club_players
   where verificado_en >= current_date;
  cupo := least(p_por_tanda, p_tope_dia - hechos, p_reserva - usadas);
  if cupo <= 0 then return 0; end if;

  perform app.verificar_plantillas(cupo, 1.2);
  return cupo;
end $$;

revoke execute on function app.repasar_plantillas(int, int, int) from public, anon, authenticated;
revoke execute on function app.pos_desde_perfil(text)            from public, anon, authenticated;
revoke execute on function app.urlenc(text)                      from public, anon, authenticated;

-- ── el repaso entra en el ciclo, detrás de todo lo demás ────────────────────
-- Va después de cargar y antes de contar lo que queda por jugar, así que solo
-- corre en los turnos en los que no había nada que cargar: si el ciclo carga un
-- partido, ese turno termina ahí y el repaso ni se plantea.
--
-- `p_repaso` es cuántos jugadores como mucho por turno. El botón «Hacerlo
-- ahora» del panel lo pone a 0: el navegador corta a los 8 segundos y el
-- repaso hace una pausa de 1,2 s entre llamadas para no chocar con el límite
-- por segundo de la API.

-- La versión de dos argumentos tiene que desaparecer: con las dos presentes y
-- todos los argumentos con valor por defecto, `app.ciclo()` —que es justo como
-- lo llama el cron— quedaría ambigua y el ciclo dejaría de dispararse.
drop function if exists app.ciclo(int, int);

create or replace function app.ciclo(
  p_max_cargas int default 4, p_tope_dia int default 80, p_repaso int default 5)
returns table(accion text, detalle text)
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare
  lg uuid; j int; auto boolean; ult_cal timestamptz; desde timestamptz;
  r text; r_sig text; inicio_sig timestamptz;
  usadas int; cargados int := 0; jj int; repasados int;
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

  -- Aquí ya se sabe que no había nada que cargar en este turno.
  if p_repaso > 0 then
    repasados := app.repasar_plantillas(p_repaso);
    if repasados > 0 then
      return query select 'plantillas'::text,
        format('%s fichas repasadas contra la API', repasados)::text;
    end if;
  end if;

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

revoke execute on function app.ciclo(int, int, int) from public, anon, authenticated;

-- El botón del panel: pocas cargas y sin repaso, que el navegador corta a los
-- 8 segundos. El resto lo hace el ciclo de cada hora sin prisa.
create or replace function ciclo_ahora()
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare pasos jsonb;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede lanzar el ciclo';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('accion', c.accion, 'detalle', c.detalle)), '[]'::jsonb)
    into pasos from app.ciclo(2, 80, 0) c;
  return pasos;
end $$;

-- Y el estado enseña también cómo va el catálogo, que es lo que hay que poder
-- mirar para confiar en que las plantillas están al día.
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
    'plantillas', jsonb_build_object(
      'fichas',          (select count(*) from club_players),
      'activas',         (select count(*) from club_players where activo),
      'enlazadas',       (select count(*) from club_players where highlightly_id is not null),
      'sin_enlazar',     (select count(*) from club_players where highlightly_id is null),
      'repasadas_hoy',   (select count(*) from club_players where verificado_en >= current_date),
      'sin_repasar',     (select count(*) from club_players
                           where highlightly_id is not null and verificado_en is null),
      'mas_antigua',     (select min(verificado_en) from club_players
                           where highlightly_id is not null),
      'a_revisar',       (select count(*) from club_players where revisar)),
    'avisos', coalesce((
      select jsonb_agg(jsonb_build_object(
               'cuando', a.cuando, 'clase', a.clase, 'jornada', a.jornada, 'texto', a.texto)
             order by a.cuando desc)
      from (select * from app_avisos a2 where a2.league_id = lg.id
             order by a2.cuando desc limit 30) a), '[]'::jsonb))
  from leagues lg limit 1
$$;

-- ── mirar un candidato ──────────────────────────────────────────────────────
-- Buscar «Vinicius» devuelve diez homónimos y la búsqueda NO dice el club: se
-- comprobó que `/players` solo acepta `name` («property leagueId should not
-- exist», «property teamId should not exist»), así que no hay forma de filtrar
-- por liga ni por equipo desde el servidor.
--
-- Por eso el club de cada candidato se mira de uno en uno, una llamada cada
-- uno, y lo pide el navegador a su ritmo. Así el tope de 8 segundos por
-- petición no se toca, la pausa entre llamadas la marca el navegador, y la
-- organización ve el club de cada ficha antes de añadir nada: «Vinicius ·
-- Real Madrid» frente a «Vinicius · Grêmio» se elige sin equivocarse.
--
-- No escribe nada. Solo mira.

create or replace function mirar_candidato(p_hl_id bigint)
returns jsonb
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
declare j jsonb; lg uuid; club_api text; cid uuid;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede mirar fichas';
  end if;
  select id into lg from leagues limit 1;

  j := app.highlightly('/players/' || p_hl_id);
  if j -> 0 is null then
    return jsonb_build_object('hl_id', p_hl_id, 'club_api', null, 'de_primera', false);
  end if;

  club_api := nullif(btrim(coalesce(j -> 0 -> 'profile' -> 'club' ->> 'current', '')), '');
  -- Si la API no dice club, `cid` se queda en null y no se toca: usar un record
  -- sin asignar aquí revienta con «record m is not assigned yet». Lo cazó la
  -- primera prueba, con un candidato sin club.
  if club_api is not null then
    select club_id into cid from app.club_por_nombre(lg, club_api);
  end if;

  return jsonb_build_object(
    'hl_id',      p_hl_id,
    'nombre',     nullif(btrim(coalesce(j -> 0 ->> 'name', '')), ''),
    'completo',   nullif(btrim(coalesce(j -> 0 ->> 'fullName', '')), ''),
    'club_api',   club_api,
    'club',       (select c.name from clubs c where c.id = cid),
    'de_primera', cid is not null,
    'pos',        app.pos_desde_perfil(j -> 0 -> 'profile' -> 'position' ->> 'main'),
    'desde',      j -> 0 -> 'profile' -> 'club' ->> 'joinedAt');
end $$;
