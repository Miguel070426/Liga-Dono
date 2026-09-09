-- Liga Fantasy · permisos
-- Regla de oro: el navegador nunca decide quién puede escribir qué. Lo decide
-- Postgres. El "PIN" del panel deja de ser una cortina de cliente.

-- ------------------------------------------------------------- AYUDANTES
-- security definer para que puedan consultarse desde dentro de las propias
-- políticas sin recursión infinita.

create or replace function my_manager_id() returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select id from managers where user_id = auth.uid() limit 1
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    exists (select 1 from managers where user_id = auth.uid() and is_admin)
    or exists (select 1 from leagues  where admin_user_id = auth.uid()), false)
$$;

-- ¿puede este usuario tocar su alineación ahora mismo?
create or replace function lineup_editable(p_league uuid, p_jornada int) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from leagues lg
    where lg.id = p_league
      and lg.lineups_locked = false
      and lg.current_jornada = p_jornada
  )
$$;

create or replace function can_edit_lineup(p_lineup uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from lineups l
    where l.id = p_lineup
      and ( is_admin()
            or ( l.manager_id = my_manager_id()
                 and lineup_editable(l.league_id, l.jornada) ) )
  )
$$;

-- ------------------------------------------------------------------ RLS
alter table leagues        enable row level security;
alter table managers       enable row level security;
alter table clubs          enable row level security;
alter table club_players   enable row level security;
alter table fixtures       enable row level security;
alter table lineups        enable row level security;
alter table lineup_slots   enable row level security;
alter table club_stats     enable row level security;
alter table player_stats   enable row level security;
alter table playoff_series enable row level security;
alter table playoff_games  enable row level security;

-- Nadie sin sesión toca las tablas. Lo que necesita la pantalla de acceso se
-- sirve por RPC (ver más abajo).
revoke all on leagues, managers, clubs, club_players, fixtures, lineups,
              lineup_slots, club_stats, player_stats, playoff_series, playoff_games
  from anon;

-- Lectura general para los que están dentro de la liga.
create policy leagues_read   on leagues        for select to authenticated using (true);
create policy managers_read  on managers       for select to authenticated using (true);
create policy clubs_read     on clubs          for select to authenticated using (true);
create policy players_read   on club_players   for select to authenticated using (true);
create policy fixtures_read  on fixtures       for select to authenticated using (true);
create policy clubstats_read on club_stats     for select to authenticated using (true);
create policy series_read    on playoff_series for select to authenticated using (true);
create policy games_read     on playoff_games  for select to authenticated using (true);

-- Escritura de la organización.
create policy leagues_admin  on leagues        for update to authenticated using (is_admin()) with check (is_admin());
create policy clubs_admin    on clubs          for all to authenticated using (is_admin()) with check (is_admin());
create policy players_admin  on club_players   for all to authenticated using (is_admin()) with check (is_admin());
create policy fixtures_admin on fixtures       for all to authenticated using (is_admin()) with check (is_admin());
create policy clubstats_adm  on club_stats     for all to authenticated using (is_admin()) with check (is_admin());
create policy pstats_admin   on player_stats   for all to authenticated using (is_admin()) with check (is_admin());
create policy series_admin   on playoff_series for all to authenticated using (is_admin()) with check (is_admin());
create policy games_admin    on playoff_games  for all to authenticated using (is_admin()) with check (is_admin());
create policy managers_admin on managers       for all to authenticated using (is_admin()) with check (is_admin());

-- Cada uno retoca el nombre de su club; el guardián de abajo impide que se
-- toque la plaza, la cuenta o el rol.
create policy managers_own on managers for update to authenticated
  using (id = my_manager_id()) with check (id = my_manager_id());

create or replace function managers_guard() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if is_admin() then return new; end if;
  if new.slot <> old.slot or new.league_id <> old.league_id
     or coalesce(new.user_id::text,'') <> coalesce(old.user_id::text,'')
     or new.is_admin <> old.is_admin then
    raise exception 'Solo la organización puede cambiar la plaza, la cuenta o el rol';
  end if;
  return new;
end $$;

drop trigger if exists managers_guard_trg on managers;
create trigger managers_guard_trg before update on managers
  for each row execute function managers_guard();

-- ALINEACIONES: la propia siempre; las de los rivales solo cuando la jornada
-- se cierra o ya ha pasado. Así nadie copia el once del contrario.
create policy lineups_read on lineups for select to authenticated using (
  manager_id = my_manager_id()
  or is_admin()
  or exists (select 1 from leagues lg
             where lg.id = lineups.league_id
               and (lg.lineups_locked or lineups.jornada < lg.current_jornada))
);
create policy lineups_mine_ins on lineups for insert to authenticated
  with check (manager_id = my_manager_id() and lineup_editable(league_id, jornada));
create policy lineups_mine_upd on lineups for update to authenticated
  using      (manager_id = my_manager_id() and lineup_editable(league_id, jornada))
  with check (manager_id = my_manager_id() and lineup_editable(league_id, jornada));
create policy lineups_mine_del on lineups for delete to authenticated
  using      (manager_id = my_manager_id() and lineup_editable(league_id, jornada));
create policy lineups_admin on lineups for all to authenticated
  using (is_admin()) with check (is_admin());

-- Los huecos heredan la visibilidad de su alineación.
create policy slots_read on lineup_slots for select to authenticated using (
  exists (select 1 from lineups l where l.id = lineup_slots.lineup_id)
);
create policy slots_write on lineup_slots for all to authenticated
  using      (can_edit_lineup(lineup_id))
  with check (can_edit_lineup(lineup_id));

-- Las estadísticas de jugador se ven si se ve su alineación.
create policy pstats_read on player_stats for select to authenticated using (
  exists (select 1 from lineup_slots ls where ls.id = player_stats.lineup_slot_id)
);

grant select on slot_contrib, manager_jornada_totals, fixture_results,
                standings, manager_form to authenticated;
revoke all on slot_contrib, manager_jornada_totals, fixture_results,
              standings, manager_form from anon;
