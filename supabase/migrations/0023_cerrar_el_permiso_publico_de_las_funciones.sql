-- Revisión de seguridad hecha a propósito, no de rebote.
--
-- La fuga de los códigos apareció por casualidad mientras montaba el aviso en
-- vivo. Con 22 migraciones encima y doce personas entrando por una URL
-- pública, toca mirar el resto a conciencia. El linter de Supabase señaló 25
-- avisos; esto arregla los que son de verdad.
--
-- ── Lo que NO era un agujero ────────────────────────────────────────────────
--
-- Comprobado llamando a las once funciones del esquema público con la
-- identidad de `anon`, sin sesión: las seis de organización se rechazan solas
-- («Solo la organización…»), `claim_slot` y `claim_admin` piden sesión incluso
-- con el código correcto, y las dos que pasan —`public_slots` y
-- `jornada_partidos`— pasan a propósito: una pinta las plazas libres antes de
-- entrar y la otra son partidos de Primera, que no es ningún secreto.
--
-- ── Lo que sí estaba mal ────────────────────────────────────────────────────
--
-- En Postgres, crear una función le da EXECUTE a **PUBLIC**. En las
-- migraciones 0019 y 0021 puse `revoke all ... from anon` creyendo cerrarlas,
-- y no cerré nada: quitaba el permiso explícito de anon, pero anon seguía
-- entrando por el de PUBLIC. El ACL lo decía y no lo leí: `=X/postgres`, con
-- el hueco delante, es PUBLIC.
--
-- No hubo consecuencia porque cada función se defiende sola, pero eso es
-- suerte, no diseño: la primera función que alguien añada sin ese control
-- queda abierta a internet el día que se cree. Así que el permiso se pone
-- donde debe estar, y además se cambia el valor por defecto para que las
-- próximas no nazcan abiertas.
--
-- El esquema `app` se queda como está, a propósito: las políticas RLS llaman a
-- `app.is_admin()` **como el usuario que consulta**, así que tocarle los
-- permisos ahí rompería la lectura para todo el mundo. PostgREST no publica
-- ese esquema, que es lo que lo mantiene fuera de la API.

-- ── el permiso, donde debe estar ────────────────────────────────────────────

revoke execute on function
  public_slots(),
  claim_slot(int, text, text, text),
  claim_admin(text),
  generate_brackets(),
  jornada_partidos(int),
  cargar_resultado_partido(bigint),
  cerrar_datos_de_club(int),
  refrescar_calendario_real(),
  simular_jornada(int),
  comprobar_jornada(int),
  borrar_simulacion(int)
from public, anon, authenticated;

-- Lo único que se llama antes de tener sesión: la lista de plazas libres.
grant execute on function public_slots() to anon, authenticated;

-- El resto necesita sesión. Quién puede hacer qué lo sigue decidiendo el
-- cuerpo de cada función; esto solo evita que se pueda ni llamar.
grant execute on function
  claim_slot(int, text, text, text),
  claim_admin(text),
  generate_brackets(),
  jornada_partidos(int),
  cargar_resultado_partido(bigint),
  cerrar_datos_de_club(int),
  refrescar_calendario_real(),
  simular_jornada(int),
  comprobar_jornada(int),
  borrar_simulacion(int)
to authenticated;

-- Y que las próximas no nazcan abiertas.
alter default privileges in schema public revoke execute on functions from public;

-- ── search_path fijo ───────────────────────────────────────────────────────
-- Una función sin search_path fijo resuelve los nombres según el que traiga
-- quien la llama. Aquí solo traduce una posición, pero es la única que
-- quedaba suelta y cerrarla cuesta una línea.

create or replace function app.pos_desde_highlightly(t text) returns pos_t
language sql immutable
set search_path = extensions, public, pg_temp
as $$
  select case lower(coalesce(t,''))
           when 'goalkeeper' then 'GK'
           when 'defender'   then 'DF'
           when 'midfielder' then 'MF'
           when 'forward'    then 'FW'
           else 'MF' end::pos_t
$$;

-- ── las tablas de Highlightly, cerradas a propósito ────────────────────────
-- `hl_matches` y `hl_players` tienen RLS puesto y ninguna política, así que
-- por la API no se leen. El linter lo marca como despiste y aquí es
-- deliberado: son la materia prima de la que salen las plantillas y el
-- calendario, y el panel las consulta por `jornada_partidos()`, que decide qué
-- se ve. Denegar por defecto es la postura correcta para una tabla de trabajo.

comment on table hl_matches is
  'Calendario crudo de Highlightly. RLS sin políticas a propósito: no se lee por la API, se sirve por jornada_partidos().';
comment on table hl_players is
  'Catálogo crudo de jugadores de Highlightly. RLS sin políticas a propósito: materia prima interna.';
