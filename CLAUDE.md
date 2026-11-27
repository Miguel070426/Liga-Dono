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
- **No publicar con la jornada en juego.** Desde la mañana del viernes en que
  se cierra la jornada hasta que termina de resolverse, no se sube nada a
  `main`. Quien tenga el juego abierto se queda con la versión vieja hasta que
  recargue. Entre semana, con la jornada abierta pero sin partidos, se publica
  sin problema: lo que se evita es tocar el juego con gente dentro mirando
  resultados.
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
jornadas), con playoff al que pasan los 4 primeros**. Total 16 jornadas, de la
14 de Primera a la 30 más o menos.

| Fase | Quién juega | Jornadas |
|---|---|---|
| Liga regular | los 6, ida y vuelta | 10 |
| Ronda 1 | 1º-4º · 2º-3º · 5º-6º | 3 |
| Ronda 2 | Final (ganadores) · 3º y 4º puesto (perdedores) | 3 |

Reglas que decidió él el 27/11, y que no se tocan sin preguntarle:

- **La ventaja de campo en el playoff son dos cosas, y se quedan las dos:** el
  local recibe el plus en cada categoría (+1 gol, +1 asist, +2 tarjetas,
  +3 pts equipo, +2 portería a 0, +3 faltas, +45 min, +2 tiros), **y** si aun
  así los subpuntos quedan empatados, el partido lo gana el local. Como los
  partidos 1 y 3 son en casa del mejor clasificado, quedar primero premia. Con
  esto ninguna serie puede quedarse sin ganador.
- En la **liga regular** el 4-4 sigue siendo empate, con su punto para cada uno.
- **Los tres partidos de cada serie se juegan siempre**, aunque vaya 2-0. Así
  cada ronda son 3 jornadas fijas y el calendario no depende de resultados.
- El 5º y el 6º terminan tres jornadas antes: juegan su cruce durante las
  semifinales y ahí acaba su temporada.

**La liga arranca el viernes 4 de diciembre a las 21:00.** El 27/11 solo
había 2 de 6 plazas fichadas, así que Miguel decidió retrasarla una semana
para hacerlo con tiempo. La jornada 1 se movió de la ronda 14 a la 15 y el
resto corrió una posición. No se perdió nada: los 30 partidos siguen igual y
el once que ya había guardado un manager sigue valiendo.

**El calendario de la liga regular ya está construido y verificado** (30
partidos, 10 jornadas, rondas 15-22, 24 y 25 de Primera). Lo hacen `app.rueda(n)`
—pura, sin tablas, probada con 4/6/8/10/12— y `public.generar_calendario()`,
que **borra el calendario entero** y por eso se niega si hay una sola jornada
jugada.

**El playoff sigue siendo el de doce** y no se ha tocado: `generate_brackets()`
busca al 7º y al 8º. Ahora avisa en cristiano en vez de reventar, pero hay que
generalizarlo antes de febrero. Los subpuntos del playoff se cargan a mano
desde el panel; nadie los calcula solo.

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
2. **El ciclo se cree que la última jornada es la 11** (`if j >= 11` en
   `app.ciclo`), de cuando la liga era de doce. Ahora la última es la 10. No
   rompe nada, pero al acabar la liga regular se quedaría enseñando una
   jornada 11 vacía. Se arregla junto con el playoff.
3. **Una alineación de relleno.** Miguel lo preguntó el 27/11 y quedó en
   estudio: un botón «rellénamelo» que el jugador pulsa y puede retocar (sí),
   y como respaldo automático repetir el once de la jornada anterior en vez de
   sortear uno (mejor que el azar: no inventa equipo, premia a quien se
   molestó una vez y no gasta cambios). El azar, si se hace, de verdad al
   azar: si el botón monta el mejor once posible, quien se lo curra sale
   perdiendo frente a quien pulsa un botón.
4. Pendientes suyos en Supabase: borrar las dos cuentas de prueba sueltas
   (`uprueba@` y `zz-prueba-longitud@`) y activar la protección de contraseñas
   filtradas (*Authentication → Sign In / Providers*, no *Database → Policies*).
