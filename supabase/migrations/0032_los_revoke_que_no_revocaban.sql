-- Los `revoke` del esquema privado no revocaban nada.
--
-- Por todas las migraciones hay líneas de este estilo:
--
--   revoke all on function app.highlightly(text) from anon, authenticated;
--
-- y ninguna hacía nada. En Postgres, EXECUTE sobre una función se concede por
-- defecto a PUBLIC, y quitárselo a `anon` y a `authenticated` no toca esa
-- concesión: los dos roles la siguen heredando por ser miembros de PUBLIC. Se
-- comprobó con has_function_privilege: las 29 funciones de `app` eran
-- ejecutables por los dos.
--
-- ¿Estaba abierto de verdad? No. Se preguntó a la API pública con la clave
-- pública, y contesta:
--
--   PGRST106 · Only the following schemas are exposed: public, graphql_public
--
-- Así que desde el navegador no se llegaba al esquema `app` de ninguna forma. Lo
-- que había no era un agujero, era un cierre que no cerraba: bastaría exponer el
-- esquema por error una vez para que `app.highlightly` —que lleva dentro la
-- clave de la API— quedara al alcance de cualquiera con la clave pública.
--
-- Se revoca de PUBLIC, que es a quien había que revocárselo. No se tocan las
-- que necesitan las políticas de RLS, porque una política se evalúa con los
-- permisos de quien pregunta: dejar sin EXECUTE a `app.is_admin()` cerraría el
-- juego entero.

do $$
declare
  -- Las que hacen trabajo de verdad: cargas, escrituras masivas, la API.
  pesadas text[] := array[
    'highlightly', 'refrescar_calendario', 'cargar_partido', 'cargar_jornada',
    'cosechar_box_score', 'sincronizar_box_score', 'cerrar_datos_de_club',
    'ciclo', 'simular_jornada', 'alinear_al_azar', 'borrar_simulacion',
    'aplicar_bajas_revisadas', 'verificar_jugador', 'verificar_plantillas',
    'comprobar_jornada'
  ];
  f record;
begin
  for f in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app' and p.proname = any(pesadas)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f.firma);
  end loop;
end $$;

-- Y que no vuelva a pasar con lo que se cree de aquí en adelante.
alter default privileges in schema app revoke execute on functions from public;
