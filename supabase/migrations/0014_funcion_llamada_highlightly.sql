-- Llama a Highlightly leyendo la clave del baúl cifrado de Supabase. La clave no
-- aparece nunca en el repositorio, que es público, ni en las consultas sueltas.
--
-- Para guardarla o cambiarla:
--   select vault.create_secret('LA-CLAVE', 'highlightly_key', 'RapidAPI');
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
