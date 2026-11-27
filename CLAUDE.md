# Liga Dono

Liga fantasy de La Liga para doce amigos, hecha para Miguel, que no es
programador. Página estática en GitHub Pages hablando con Supabase.

- Juego: https://miguel070426.github.io/Liga-Dono/
- Proyecto Supabase: `kcrxekmsltxtavbujmwq` (`liga-fantasy`)
- El cuaderno largo, con todo el detalle y las decisiones razonadas, está en
  **`supabase/README.md`**. Léelo antes de tocar la base de datos.

## Cómo hablarle a Miguel

En español y sin jerga. Dale la recomendación, no el catálogo de opciones. Si
algo te parece mal, díselo: lo pide expresamente y le sirve. Cuando te
corrija, suele tener razón — conoce el fútbol y conoce a sus amigos.

Comprueba las cosas en vez de suponerlas. Este proyecto ha tenido ya varios
casos de algo que «debería funcionar» y no funcionaba, y se cazaron
ejecutándolo, no leyéndolo.

## Reglas que no se saltan

- **Los códigos de acceso NUNCA se escriben en el repositorio.** Es público y
  su historia es permanente. Viven solo en la base de datos (`leagues.join_code`
  y `leagues.admin_claim_code`). Si hay que decírselos a alguien, por el chat.
- **No publicar con la jornada abierta.** De viernes por la mañana hasta que
  cierre la jornada no se sube nada a `main`. Quien tenga el juego abierto se
  queda con la versión vieja hasta que recargue.
- Rama de trabajo: `claude/game-ui-gameplay-focus-k22mhu`. A `main` solo se
  fusiona para publicar.

## Dónde está cada cosa

- `app.js` — el juego entero (pantallas, panel de dirección, playoffs).
- `db.js` — todo lo que habla con Supabase.
- `pruebas/` — cuatro baterías con Playwright contra una base falsa.
  Se arranca con `bash pruebas/sitio.sh` y se pasan con `node pruebas/t-*.mjs`.
  **Pásalas todas antes de publicar.**

## Decidido el 27/11: la liga va a ser de 6

Miguel no llega a doce. La liga será de **6 managers, ida y vuelta (10
jornadas), con playoff al que pasan los 4 primeros**. Los dos últimos juegan
su propio cruce. Total estimado: 16 jornadas, de la 14 de Primera a la 30.

Nada de esto está construido todavía. Lo que hay montado es para 12.

## RECORDARLE A MIGUEL (lo pidió él)

1. **El panel de ajustes de la liga.** Lo aplazó el 27/11 pero quiere que se
   lo recuerdes. Son dos piezas:
   - *Ahora, cuando él diga:* generador de calendario para N equipos, con ida
     o ida y vuelta. Es lo que desbloquea arrancar. Media sesión. Lo caro son
     las pruebas: hay que verificar con 4, 6, 8, 10 y 12 equipos que nadie se
     enfrenta a sí mismo, que nadie juega dos veces la misma jornada, que
     todos se cruzan con todos las veces que toca y que casa/fuera está
     repartido. Un fallo aquí no se ve hasta la jornada 6.
   - *En enero:* el playoff flexible y la pantalla de ajustes. Si se hace un
     botón de regenerar calendario, va con cerrojo: se niega si hay una sola
     jornada jugada. Ese botón borra la liga.
2. **El empate en el playoff no está resuelto.** Las ocho categorías pueden
   quedar 4-4, y entonces ese partido no lo gana nadie. Una serie al mejor de
   3 puede acabar 1-1 sin ganador. Hay que decidirlo antes de febrero. La
   propuesta sobre la mesa: pasa el mejor clasificado de la liga regular.
3. Pendientes suyos en Supabase: borrar las dos cuentas de prueba sueltas
   (`uprueba@` y `zz-prueba-longitud@`) y activar la protección de contraseñas
   filtradas (*Authentication → Sign In / Providers*, no *Database → Policies*).
