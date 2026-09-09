-- La base de datos necesita salida a internet para consultar la API de datos de
-- fútbol. Se instala en el esquema extensions y se le quitan los permisos a los
-- roles del cliente, para que la base de datos no acabe siendo un proxy abierto.
create extension if not exists http with schema extensions;

revoke all on function extensions.http(extensions.http_request) from anon, authenticated;
revoke all on function extensions.http_get(varchar) from anon, authenticated;
