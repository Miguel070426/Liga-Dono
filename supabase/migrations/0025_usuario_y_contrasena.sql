-- Usuario y contraseña elegidos por cada uno, en lugar de un código generado.
--
-- El código hacía de usuario y de contraseña a la vez, y esa decisión salió
-- mal en la práctica:
--
--   · Nadie se acuerda de `LD-VZMW-UWX4`, así que hay que guardarlo en algún
--     sitio y al final se pierde.
--   · Teclearlo en un móvil falla. Un manager con su plaza fichada no
--     conseguía entrar: el código era correcto —verificado contra el cifrado
--     de su cuenta— y el servidor devolvía credenciales inválidas, porque lo
--     teclado no era exactamente el código.
--   · Al ser también el usuario, un carácter cambiado no se distingue de «esa
--     persona no se ha registrado»: el juego no puede decirte cuál de las dos
--     cosas pasa.
--   · El gestor de contraseñas del navegador no ayuda, porque no hay un campo
--     de contraseña que guardar.
--
-- Con usuario y contraseña propios: se acuerdan porque los eligieron, el móvil
-- los guarda solo, y equivocarse escribiendo es un fallo del que se puede
-- avisar bien.
--
-- Sigue sin haber correos: Supabase Auth necesita uno, así que se deriva del
-- usuario (`upepe@ligadono.app`). El cambio es que ahora la parte memorable la
-- elige la persona.
--
-- El precio, y hay que asumirlo: sin correo no hay «he olvidado mi
-- contraseña» automático. Se la repone la organización, que para doce amigos
-- es quien va a estar de todas formas. Para eso está `reponer_contrasena`.

alter table managers add column if not exists usuario text;

create unique index if not exists managers_usuario_unico
  on managers (league_id, lower(usuario)) where usuario is not null;

comment on column managers.usuario is
  'El nombre con el que entra. La organización lo ve para poder recordárselo a quien lo olvide; la contraseña no la ve nadie.';

-- ── fichar plaza con usuario ────────────────────────────────────────────────
-- La cuenta la crea el navegador (Supabase Auth) justo antes de llamar aquí;
-- esto ata esa cuenta a la plaza y guarda el usuario elegido.

create or replace function claim_slot(p_slot int, p_club text, p_owner text,
                                      p_usuario text, p_join_code text)
returns managers
language plpgsql security definer set search_path = public, pg_temp as $$
declare m managers; lg leagues; u text;
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  if coalesce(trim(p_club),'') = '' or coalesce(trim(p_owner),'') = '' then
    raise exception 'Hacen falta tu nombre y el nombre del club';
  end if;

  u := lower(trim(coalesce(p_usuario,'')));
  if length(u) < 3 then
    raise exception 'El usuario necesita al menos 3 caracteres';
  end if;

  select * into lg from leagues order by created_at limit 1;

  -- quien ya tiene plaza solo renombra: no necesita el código otra vez
  select * into m from managers where user_id = auth.uid();
  if m.id is not null then
    update managers set club_name = trim(p_club), owner_name = trim(p_owner)
     where id = m.id returning * into m;
    return m;
  end if;

  if upper(coalesce(trim(p_join_code),'')) <> upper(lg.join_code) then
    raise exception 'El código de la liga no es correcto';
  end if;

  if exists (select 1 from managers x
              where x.league_id = lg.id and lower(x.usuario) = u) then
    raise exception 'Ese usuario ya está cogido, elige otro';
  end if;

  update managers
     set user_id = auth.uid(), club_name = trim(p_club),
         owner_name = trim(p_owner), usuario = u, claimed_at = now()
   where league_id = lg.id and slot = p_slot and user_id is null
  returning * into m;

  if m.id is null then
    raise exception 'Esa plaza ya está ocupada, elige otra';
  end if;
  return m;
end $$;

revoke execute on function claim_slot(int, text, text, text, text) from public, anon;
grant  execute on function claim_slot(int, text, text, text, text) to authenticated;

-- La versión con código-credencial se retira, para que no quede una puerta
-- de atrás con el diseño viejo.
drop function if exists claim_slot(int, text, text, text);

-- ── ¿está cogido este usuario? ──────────────────────────────────────────────
-- Se pregunta antes de crear la cuenta: si no, quedaría una cuenta huérfana en
-- Auth cada vez que alguien elige un usuario ya usado. Solo dice sí o no, y
-- hace falta el código de la liga, así que no sirve para sacar la lista de
-- quién juega.

create or replace function usuario_libre(p_usuario text, p_join_code text)
returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg leagues;
begin
  select * into lg from leagues order by created_at limit 1;
  if upper(coalesce(trim(p_join_code),'')) <> upper(lg.join_code) then
    raise exception 'El código de la liga no es correcto';
  end if;
  return not exists (
    select 1 from managers
     where league_id = lg.id
       and lower(usuario) = lower(trim(coalesce(p_usuario,''))));
end $$;

revoke execute on function usuario_libre(text, text) from public, authenticated;
grant  execute on function usuario_libre(text, text) to anon, authenticated;

-- ── reponer una contraseña olvidada ─────────────────────────────────────────
-- Sin correo no hay recuperación automática, así que la repone la
-- organización. Es la pieza que hace que perder la contraseña no sea el fin
-- del mundo.

create or replace function reponer_contrasena(p_manager uuid, p_nueva text)
returns text
language plpgsql security definer
set search_path = extensions, public, auth, pg_temp as $$
declare uid uuid; quien text;
begin
  if not app.is_admin() then
    raise exception 'Solo la organización puede reponer una contraseña';
  end if;
  if length(coalesce(p_nueva,'')) < 8 then
    raise exception 'La contraseña necesita al menos 8 caracteres';
  end if;
  select m.user_id, coalesce(m.usuario, m.owner_name) into uid, quien
    from managers m where m.id = p_manager;
  if uid is null then
    raise exception 'Esa plaza no tiene cuenta a la que reponerle nada';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_nueva, extensions.gen_salt('bf')),
         updated_at = now()
   where id = uid;
  return quien;
end $$;

revoke execute on function reponer_contrasena(uuid, text) from public, anon;
grant  execute on function reponer_contrasena(uuid, text) to authenticated;

-- ── las tres cuentas que ya existían ────────────────────────────────────────
-- Su correo interno se derivaba del código (`mldvzmwuwx4@ligadono.app`), y el
-- acceso nuevo lo deriva del usuario, así que con el cambio no se
-- encontrarían. Se podían migrar a mano, pero eran tres, ninguna tenía
-- alineación puesta y las tres personas están a un mensaje de distancia: se
-- borran y se registran otra vez con su nombre y su contraseña. Menos piezas
-- moviéndose el día antes de empezar.
--
-- La liga se queda sin administrador a propósito: el código de dirección
-- vuelve a servir, que es justo para lo que existe.

update managers
   set user_id = null, usuario = null, claimed_at = null,
       club_name = 'Plaza ' || slot, owner_name = '', is_admin = false
 where user_id is not null;

update leagues set admin_user_id = null;

delete from auth.users
 where email like 'm%@ligadono.app';
