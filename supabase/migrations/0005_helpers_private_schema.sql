-- Liga Fantasy · esconder los ayudantes internos
-- PostgREST publica como endpoint todo lo que hay en "public". Las funciones
-- que solo existen para las políticas RLS no deben ser llamables desde fuera,
-- así que se mudan a un esquema que la API no expone.
-- Se quedan en public únicamente las que son API de verdad:
-- public_slots, claim_slot, claim_admin y generate_brackets.

create schema if not exists app;
grant usage on schema app to authenticated;
revoke all on schema app from anon;

create or replace function app.my_manager_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select id from managers where user_id = auth.uid() limit 1
$$;

create or replace function app.is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    exists (select 1 from managers where user_id = auth.uid() and is_admin)
    or exists (select 1 from leagues  where admin_user_id = auth.uid()), false)
$$;

create or replace function app.lineup_editable(p_league uuid, p_jornada int) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from leagues lg
    where lg.id = p_league and lg.lineups_locked = false and lg.current_jornada = p_jornada
  )
$$;

create or replace function app.can_edit_lineup(p_lineup uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from lineups l
    where l.id = p_lineup
      and ( app.is_admin()
            or ( l.manager_id = app.my_manager_id()
                 and app.lineup_editable(l.league_id, l.jornada) ) )
  )
$$;

create or replace function app.managers_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if app.is_admin() then return new; end if;
  if new.slot <> old.slot or new.league_id <> old.league_id
     or coalesce(new.user_id::text,'') <> coalesce(old.user_id::text,'')
     or new.is_admin <> old.is_admin then
    raise exception 'Solo la organización puede cambiar la plaza, la cuenta o el rol';
  end if;
  return new;
end $$;

-- Rehacer lo que apuntaba a las versiones públicas.
drop trigger if exists managers_guard_trg on managers;
drop policy if exists managers_own    on managers;
drop policy if exists managers_admin  on managers;
drop policy if exists leagues_admin   on leagues;
drop policy if exists clubs_admin     on clubs;
drop policy if exists players_admin   on club_players;
drop policy if exists fixtures_admin  on fixtures;
drop policy if exists clubstats_adm   on club_stats;
drop policy if exists pstats_admin    on player_stats;
drop policy if exists series_admin    on playoff_series;
drop policy if exists games_admin     on playoff_games;
drop policy if exists lineups_read     on lineups;
drop policy if exists lineups_mine_ins on lineups;
drop policy if exists lineups_mine_upd on lineups;
drop policy if exists lineups_mine_del on lineups;
drop policy if exists lineups_admin    on lineups;
drop policy if exists slots_write      on lineup_slots;

create trigger managers_guard_trg before update on managers
  for each row execute function app.managers_guard();

create policy managers_admin on managers       for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy leagues_admin  on leagues        for update to authenticated using (app.is_admin()) with check (app.is_admin());
create policy clubs_admin    on clubs          for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy players_admin  on club_players   for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy fixtures_admin on fixtures       for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy clubstats_adm  on club_stats     for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy pstats_admin   on player_stats   for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy series_admin   on playoff_series for all to authenticated using (app.is_admin()) with check (app.is_admin());
create policy games_admin    on playoff_games  for all to authenticated using (app.is_admin()) with check (app.is_admin());

create policy managers_own on managers for update to authenticated
  using (id = app.my_manager_id()) with check (id = app.my_manager_id());

create policy lineups_read on lineups for select to authenticated using (
  manager_id = app.my_manager_id()
  or app.is_admin()
  or exists (select 1 from leagues lg
             where lg.id = lineups.league_id
               and (lg.lineups_locked or lineups.jornada < lg.current_jornada))
);
create policy lineups_mine_ins on lineups for insert to authenticated
  with check (manager_id = app.my_manager_id() and app.lineup_editable(league_id, jornada));
create policy lineups_mine_upd on lineups for update to authenticated
  using      (manager_id = app.my_manager_id() and app.lineup_editable(league_id, jornada))
  with check (manager_id = app.my_manager_id() and app.lineup_editable(league_id, jornada));
create policy lineups_mine_del on lineups for delete to authenticated
  using      (manager_id = app.my_manager_id() and app.lineup_editable(league_id, jornada));
create policy lineups_admin on lineups for all to authenticated
  using (app.is_admin()) with check (app.is_admin());
create policy slots_write on lineup_slots for all to authenticated
  using      (app.can_edit_lineup(lineup_id))
  with check (app.can_edit_lineup(lineup_id));

-- generate_brackets usaba el is_admin público
create or replace function generate_brackets()
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg_id uuid; r record; sid uuid;
begin
  if not app.is_admin() then raise exception 'Solo la organización'; end if;
  select id into lg_id from leagues order by created_at limit 1;
  delete from playoff_series where league_id = lg_id;
  for r in
    select 'top' as bracket, i as position,
           (select manager_id from standings where league_id = lg_id and rank = i)     as high_id,
           (select manager_id from standings where league_id = lg_id and rank = 9 - i) as low_id
    from generate_series(1,4) i
    union all
    select 'bottom', i,
           (select manager_id from standings where league_id = lg_id and rank = 8 + i),
           (select manager_id from standings where league_id = lg_id and rank = 21 - i)
    from generate_series(1,2) i
  loop
    insert into playoff_series (league_id, bracket, position, high_id, low_id)
    values (lg_id, r.bracket, r.position, r.high_id, r.low_id)
    returning id into sid;
    insert into playoff_games (series_id, game_no, home_id) values
      (sid, 1, r.high_id), (sid, 2, r.low_id), (sid, 3, r.high_id);
  end loop;
end $$;

drop function if exists public.can_edit_lineup(uuid);
drop function if exists public.lineup_editable(uuid, int);
drop function if exists public.my_manager_id();
drop function if exists public.is_admin();
drop function if exists public.managers_guard();
