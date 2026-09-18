-- Programar el ciclo. Va en su propia migración porque `create extension
-- pg_cron` tiene que estar confirmado antes de que se pueda compilar una
-- llamada a `cron.schedule`: en la misma transacción el esquema `cron` aún no
-- existe para el planificador de consultas.
--
-- En el minuto 7 y no en punto: las horas en punto son la hora de más cola en
-- cualquier planificador compartido, y aquí da exactamente igual el minuto.
--
-- Una pasada cada hora, 24 al día. Casi todas no hacen nada y no gastan ni una
-- llamada a la API: solo miran el estado. Las que gastan son la del calendario
-- (una cada 6 h) y las cargas de partido, que son 10 por jornada.
--
-- Para pararlo:  select cron.unschedule('liga-dono-ciclo');
-- Para verlo:    select * from cron.job_run_details order by start_time desc limit 20;

create extension if not exists pg_cron;

select cron.schedule('liga-dono-ciclo', '7 * * * *', $cron$select app.ciclo()$cron$);
