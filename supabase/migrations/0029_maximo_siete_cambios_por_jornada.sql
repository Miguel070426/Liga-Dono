-- Máximo 7 cambios por jornada: te obliga a quedarte con 4 de la anterior.
--
-- ── La regla ────────────────────────────────────────────────────────────────
--
-- De una jornada a la siguiente puedes cambiar como mucho 7 jugadores, así que
-- al menos 4 repiten. La idea es que elegir sea decidir a quién te atas, no
-- rehacer el once entero cada semana.
--
-- Se cuenta contra **el último once que pusiste de verdad**, no contra la
-- jornada inmediatamente anterior. La diferencia importa: si fuera «la
-- anterior», saltarse una jornada valdría como reseteo gratis del once. Así,
-- saltártela no te libera de nada.
--
-- Quien no ha alineado nunca —jornada 1, o alguien que acaba de fichar plaza—
-- entra libre, porque no hay nada con lo que comparar.
--
-- Un jugador que se va de Primera **no da derecho a cambio gratis**: o gastas
-- uno de tus 7 en sustituirlo, o lo dejas en el once sabiendo que no puntúa.
-- Decisión tomada a propósito, incluido el caso de que se vayan tantos que no
-- puedas repetir 4: entonces juegas con muertos en el once. Es duro y es
-- simple, y las reglas duras y simples se discuten menos.
--
-- ── Por qué esto obliga a cambiar cómo se guarda ────────────────────────────
--
-- Hasta ahora guardar el once eran varias escrituras sueltas desde el
-- navegador: crear la alineación, borrar los 11 huecos, insertarlos otra vez.
-- Una regla que mira el once entero no se puede comprobar así, porque entre el
-- borrado y la inserción el once no existe.
--
-- Pasa a ser una sola llamada que hace todo de golpe. De regalo se arregla un
-- fallo que ya estaba ahí: si el borrado salía bien y la inserción fallaba
-- —se cae la red a media operación— te quedabas con la alineación vacía y sin
-- enterarte.

alter table leagues add column if not exists max_cambios int not null default 7;

comment on column leagues.max_cambios is
  'Cuántos jugadores puedes cambiar de una jornada a la siguiente. Vale igual en playoffs.';

-- ── el once con el que se compara ───────────────────────────────────────────
-- El último con jugadores de verdad, de una jornada anterior a la que se está
-- guardando. Los onces vacíos no cuentan: no son un once, son un hueco.

create or replace function app.once_referencia(p_manager uuid, p_jornada int)
returns table(jornada int, club_player_id uuid)
language sql stable security definer set search_path = public, pg_temp as $$
  with ultimo as (
    select l.jornada
    from lineups l
    join lineup_slots s on s.lineup_id = l.id
    where l.manager_id = p_manager
      and l.jornada < p_jornada
      and s.club_player_id is not null
    group by l.jornada
    order by l.jornada desc
    limit 1
  )
  select u.jornada, s.club_player_id
  from ultimo u
  join lineups l on l.manager_id = p_manager and l.jornada = u.jornada
  join lineup_slots s on s.lineup_id = l.id
  where s.club_player_id is not null
$$;

-- Lo que necesita la pantalla para ir contando mientras editas: contra qué
-- once se compara y cuántos cambios caben. El recuento en vivo lo hace el
-- navegador con esta lista; el de verdad lo rehace el servidor al guardar.
create or replace function once_referencia(p_jornada int)
returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'limite', (select max_cambios from leagues order by created_at limit 1),
    'jornada_ref', (select min(r.jornada) from app.once_referencia(app.my_manager_id(), p_jornada) r),
    'jugadores', coalesce((select jsonb_agg(r.club_player_id)
                             from app.once_referencia(app.my_manager_id(), p_jornada) r), '[]'::jsonb))
$$;

revoke execute on function once_referencia(int) from public, anon;
grant  execute on function once_referencia(int) to authenticated;

-- ── guardar el once, de una vez y con la regla aplicada ─────────────────────

create or replace function guardar_alineacion(p_jornada int, p_formacion text, p_slots jsonb)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  lg leagues; mid uuid; lid uuid;
  ref_j int; n_ref int; cambios int; limite int;
  nuevos uuid[];
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  select * into lg from leagues order by created_at limit 1;
  mid := app.my_manager_id();
  if mid is null then
    raise exception 'No tienes plaza en esta liga';
  end if;

  -- La hora manda igual que antes: la organización sí puede tocar fuera de
  -- plazo, porque alguien tiene que poder arreglar un desastre.
  if not app.is_admin() and not app.lineup_editable(lg.id, p_jornada) then
    raise exception 'La jornada % está cerrada: ya no se puede cambiar el once', p_jornada
      using errcode = 'P0001';
  end if;

  select array_agg(distinct (e ->> 'club_player_id')::uuid)
    into nuevos
    from jsonb_array_elements(p_slots) e
   where nullif(e ->> 'club_player_id', '') is not null;
  nuevos := coalesce(nuevos, '{}');

  -- ¿cuántos de los nuevos no estaban en el once de referencia?
  select r.jornada, count(*) into ref_j, n_ref
    from app.once_referencia(mid, p_jornada) r group by r.jornada;

  limite := lg.max_cambios;
  if ref_j is not null and not app.is_admin() then
    select count(*) into cambios
      from unnest(nuevos) n
     where not exists (select 1 from app.once_referencia(mid, p_jornada) r
                        where r.club_player_id = n);
    if cambios > limite then
      raise exception
        'Solo puedes cambiar % jugadores por jornada y estás cambiando %. Tienes que repetir al menos % de tu once de la jornada %.',
        limite, cambios, 11 - limite, ref_j
        using errcode = 'P0001';
    end if;
  else
    cambios := array_length(nuevos, 1);
  end if;

  -- ── escritura, ya en una sola pieza ──────────────────────────────────────
  select id into lid from lineups where manager_id = mid and jornada = p_jornada;
  if lid is null then
    insert into lineups (league_id, manager_id, jornada, formation)
    values (lg.id, mid, p_jornada, p_formacion) returning id into lid;
  else
    update lineups set formation = p_formacion, simulada = false, updated_at = now()
     where id = lid;
  end if;

  delete from lineup_slots where lineup_id = lid;
  insert into lineup_slots (lineup_id, slot, pos, club_id, club_player_id, player_name)
  select lid,
         (e.ord)::int,
         (e.v ->> 'pos')::pos_t,
         nullif(e.v ->> 'club_id','')::uuid,
         nullif(e.v ->> 'club_player_id','')::uuid,
         coalesce(e.v ->> 'player_name','')
  from jsonb_array_elements(p_slots) with ordinality e(v, ord);

  return jsonb_build_object(
    'guardado', true,
    'cambios', coalesce(cambios, 0),
    'limite', limite,
    'jornada_ref', ref_j);
end $$;

revoke execute on function guardar_alineacion(int, text, jsonb) from public, anon;
grant  execute on function guardar_alineacion(int, text, jsonb) to authenticated;
