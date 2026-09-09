-- Dos cosas: tapar una fuga y montar el aviso en vivo. Van juntas porque la
-- segunda habría empeorado la primera.
--
-- ── La fuga ─────────────────────────────────────────────────────────────────
-- Los códigos de la liga y de dirección viven en `leagues`, y la política de
-- lectura de esa tabla es `using (true)` porque todo el mundo necesita saber
-- en qué jornada va. Resultado: cualquiera con sesión podía pedir
--
--     select join_code, admin_claim_code from leagues
--
-- y llevarse los dos. Comprobado con la identidad de un jugador real: los veía.
-- Con el código de la liga, un jugador lo reparte y un desconocido ocupa una
-- plaza libre, que es exactamente lo que ese código existe para evitar.
--
-- RLS decide filas, no columnas, así que esto se arregla con permisos de
-- columna. Las funciones que sí necesitan los códigos (`claim_slot`,
-- `claim_admin`) son SECURITY DEFINER y siguen viéndolos.

revoke select on leagues from anon, authenticated;

grant select (id, name, current_jornada, lineups_locked, admin_user_id, created_at)
  on leagues to anon, authenticated;

-- Y de paso: la organización mueve la jornada y la cierra, pero los códigos no
-- se cambian desde el navegador. Para eso está el editor SQL.
revoke update on leagues from authenticated;
grant update (current_jornada, lineups_locked) on leagues to authenticated;

-- ── El latido ───────────────────────────────────────────────────────────────
-- Doce personas mirando la misma jornada tienen que ver la tabla moverse sin
-- recargar. Lo evidente sería publicar las tablas por Realtime y escuchar los
-- cambios, pero eso tiene dos problemas:
--
--   1. Realtime manda **la fila entera** a cada suscriptor. Publicar `leagues`
--      repartiría los códigos que acabamos de esconder, y los permisos de
--      columna no aplican ahí.
--   2. Cargar una jornada escribe 453 filas de estadísticas. Con trigger por
--      fila serían 453 mensajes por cliente para decir una sola cosa.
--
-- Así que se publica una tabla sin nada dentro: un latido. Los triggers son
-- **por sentencia**, no por fila, y nuestras escrituras son de conjunto, así
-- que una jornada entera son 10 latidos en vez de 453 mensajes. El cliente no
-- lee el contenido del aviso: solo se entera de que algo cambió y vuelve a
-- pedir lo que tenga permiso para ver, que es lo que mantiene la alineación a
-- ciegas intacta.

create table if not exists latidos (
  league_id    uuid primary key references leagues(id) on delete cascade,
  actualizado  timestamptz not null default now(),
  motivo       text
);

alter table latidos enable row level security;
drop policy if exists latidos_read on latidos;
create policy latidos_read on latidos for select using (true);

insert into latidos (league_id, motivo)
select id, 'arranque' from leagues
on conflict (league_id) do nothing;

create or replace function app.latir() returns trigger
language plpgsql security definer
set search_path = extensions, public, pg_temp
as $$
begin
  insert into latidos (league_id, actualizado, motivo)
  select id, now(), tg_argv[0] from leagues
  on conflict (league_id) do update
    set actualizado = now(), motivo = excluded.motivo;
  return null;
end $$;

do $$
declare t record;
begin
  for t in select * from (values
      ('lineups','alineaciones'), ('lineup_slots','alineaciones'),
      ('player_jornada_stats','estadisticas'), ('club_stats','estadisticas'),
      ('managers','managers'), ('club_players','plantillas'),
      ('leagues','jornada'), ('playoff_games','playoffs'), ('playoff_series','playoffs')
    ) as v(tabla, motivo)
  loop
    execute format('drop trigger if exists latido_%1$s on %1$I', t.tabla);
    execute format(
      'create trigger latido_%1$s after insert or update or delete on %1$I '
      'for each statement execute function app.latir(%2$L)', t.tabla, t.motivo);
  end loop;
end $$;

-- El latido se lee y nada más. RLS ya lo impediría por no tener política de
-- escritura, pero dejar el permiso puesto significa que lo único que separa a
-- un desconocido de un TRUNCATE es una política que falta.
revoke insert, update, delete, truncate on latidos from anon, authenticated;

-- Solo el latido se publica. Ninguna tabla con datos sale por el cable.
do $$
begin
  if not exists (
    select 1 from pg_publication_rel pr
    join pg_publication p on p.oid = pr.prpubid
    join pg_class c on c.oid = pr.prrelid
    where p.pubname = 'supabase_realtime' and c.relname = 'latidos')
  then
    alter publication supabase_realtime add table latidos;
  end if;
end $$;
