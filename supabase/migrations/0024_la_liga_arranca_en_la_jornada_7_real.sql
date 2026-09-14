-- Nuestra jornada 1 apuntaba a la jornada 1 real de Primera, jugada del 15 al
-- 27 de agosto. Es decir: la liga habría arrancado con una jornada cuyo
-- resultado estaba decidido antes de que nadie alineara, lo que vacía de
-- sentido el alinear a ciegas.
--
-- Así que la liga empieza en la primera ronda real que esté **entera por
-- jugar**. A 11 de septiembre, la 5 empieza hoy y la 6 tiene un partido ya
-- adelantado, así que es la 7. Las once jornadas van de la 7 a la 17:
--
--   jornada 1  → ronda 7   18-20 sep
--   jornada 2  → ronda 8   11 oct   (parón de selecciones en medio)
--   jornada 3  → ronda 9   18 oct
--   ...
--   jornada 11 → ronda 17  20 dic
--
-- La liga regular termina antes de Navidad y los playoffs caen en enero.
--
-- Si algún día hay que volver a mover el arranque, es este mismo update con
-- otro desplazamiento; `jornada_rondas` existe justo para eso.

update jornada_rondas jr
   set ronda = 'Regular Season - ' || (jr.jornada + 6)
 where jr.league_id = (select id from leagues limit 1);

-- Las estadísticas cargadas de las rondas de agosto eran pruebas y ya no
-- corresponden a ninguna jornada nuestra. Se van: dejarlas haría que la
-- clasificación arrancase con puntos que nadie ha jugado.
delete from player_jornada_stats;
delete from club_stats;
