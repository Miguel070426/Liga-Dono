-- Liga Fantasy · funciones de acceso y siembra de la liga

-- Lo único que puede consultar alguien sin sesión: qué plazas quedan libres.
create or replace function public_slots()
returns table (slot int, club_name text, owner_name text, taken boolean)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.slot, m.club_name, m.owner_name, (m.user_id is not null)
  from managers m
  join leagues l on l.id = m.league_id
  order by m.slot
$$;
grant execute on function public_slots() to anon, authenticated;

-- Reclamar plaza. La cuenta ya existe (el código es la credencial); esto solo
-- ata esa cuenta a una plaza libre.
create or replace function claim_slot(p_slot int, p_club text, p_owner text)
returns managers
language plpgsql security definer set search_path = public, pg_temp as $$
declare m managers; lg_id uuid;
begin
  if auth.uid() is null then
    raise exception 'No hay sesión activa';
  end if;
  if coalesce(trim(p_club),'') = '' or coalesce(trim(p_owner),'') = '' then
    raise exception 'Hacen falta tu nombre y el nombre del club';
  end if;

  select id into lg_id from leagues order by created_at limit 1;

  -- ya tenía plaza: solo renombra
  select * into m from managers where user_id = auth.uid();
  if m.id is not null then
    update managers set club_name = trim(p_club), owner_name = trim(p_owner)
     where id = m.id returning * into m;
    return m;
  end if;

  update managers
     set user_id = auth.uid(), club_name = trim(p_club),
         owner_name = trim(p_owner), claimed_at = now()
   where league_id = lg_id and slot = p_slot and user_id is null
  returning * into m;

  if m.id is null then
    raise exception 'Esa plaza ya está ocupada, elige otra';
  end if;
  return m;
end $$;
grant execute on function claim_slot(int, text, text) to authenticated;

-- Reclamar el panel de dirección con el código de organización.
create or replace function claim_admin(p_code text)
returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg_id uuid;
begin
  if auth.uid() is null then raise exception 'No hay sesión activa'; end if;
  select id into lg_id from leagues
   where admin_claim_code = trim(p_code)
     and (admin_user_id is null or admin_user_id = auth.uid());
  if lg_id is null then return false; end if;
  update leagues set admin_user_id = auth.uid() where id = lg_id;
  update managers set is_admin = true where user_id = auth.uid();
  return true;
end $$;
grant execute on function claim_admin(text) to authenticated;

-- Estado de las series de playoff, calculado (no se guarda a mano).
create or replace view playoff_series_state with (security_invoker = true) as
select s.id as series_id, s.league_id, s.bracket, s.position, s.high_id, s.low_id,
  count(*) filter (where g.home_sub is not null and g.away_sub is not null
        and ((g.home_id = s.high_id and g.home_sub > g.away_sub)
          or (g.home_id = s.low_id  and g.away_sub > g.home_sub)))::int as wins_high,
  count(*) filter (where g.home_sub is not null and g.away_sub is not null
        and ((g.home_id = s.low_id  and g.home_sub > g.away_sub)
          or (g.home_id = s.high_id and g.away_sub > g.home_sub)))::int as wins_low
from playoff_series s
left join playoff_games g on g.series_id = s.id
group by s.id, s.league_id, s.bracket, s.position, s.high_id, s.low_id;

grant select on playoff_series_state to authenticated;
revoke all  on playoff_series_state from anon;

-- Generar los brackets a partir de la clasificación. Solo la organización.
create or replace function generate_brackets()
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare lg_id uuid; r record; hi uuid; lo uuid; sid uuid;
begin
  if not is_admin() then raise exception 'Solo la organización'; end if;
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
    -- factor cancha: P1 y P3 para el mejor clasificado, P2 para el peor
    insert into playoff_games (series_id, game_no, home_id) values
      (sid, 1, r.high_id), (sid, 2, r.low_id), (sid, 3, r.high_id);
  end loop;
end $$;
grant execute on function generate_brackets() to authenticated;

-- ------------------------------------------------------------------ SIEMBRA
do $$
declare lg_id uuid; club text;
begin
  if exists (select 1 from leagues) then return; end if;

  insert into leagues (name, current_jornada, admin_claim_code)
  values ('Liga Dono', 1, 'LD-DIR-4Q7M-2X9')
  returning id into lg_id;

  insert into managers (league_id, slot, club_name)
  select lg_id, i, 'Plaza ' || i from generate_series(1,12) i;

  foreach club in array array[
    'Real Madrid','FC Barcelona','Atlético de Madrid','Athletic Club','Real Sociedad',
    'Real Betis','Villarreal','Valencia','Sevilla','Celta de Vigo','Elche',
    'Espanyol','Getafe','Levante','Osasuna','Rayo Vallecano','Alavés',
    'Racing de Santander','Deportivo de La Coruña','Málaga']
  loop
    insert into clubs (league_id, name) values (lg_id, club);
  end loop;

  -- calendario round-robin de 11 jornadas (método del círculo)
  insert into fixtures (league_id, jornada, home_id, away_id)
  select lg_id, v.j, h.id, a.id
  from (values
    (1,1,12),(1,2,11),(1,3,10),(1,4,9),(1,5,8),(1,6,7),
    (2,1,2),(2,3,12),(2,4,11),(2,5,10),(2,6,9),(2,7,8),
    (3,1,3),(3,4,2),(3,5,12),(3,6,11),(3,7,10),(3,8,9),
    (4,1,4),(4,5,3),(4,6,2),(4,7,12),(4,8,11),(4,9,10),
    (5,1,5),(5,6,4),(5,7,3),(5,8,2),(5,9,12),(5,10,11),
    (6,1,6),(6,7,5),(6,8,4),(6,9,3),(6,10,2),(6,11,12),
    (7,1,7),(7,8,6),(7,9,5),(7,10,4),(7,11,3),(7,12,2),
    (8,1,8),(8,9,7),(8,10,6),(8,11,5),(8,12,4),(8,2,3),
    (9,1,9),(9,10,8),(9,11,7),(9,12,6),(9,2,5),(9,3,4),
    (10,1,10),(10,11,9),(10,12,8),(10,2,7),(10,3,6),(10,4,5),
    (11,1,11),(11,12,10),(11,2,9),(11,3,8),(11,4,7),(11,5,6)
  ) as v(j, hs, as_)
  join managers h on h.league_id = lg_id and h.slot = v.hs
  join managers a on a.league_id = lg_id and a.slot = v.as_;
end $$;
