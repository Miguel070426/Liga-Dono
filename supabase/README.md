# Liga Fantasy · base de datos

Proyecto Supabase: **`liga-fantasy`** (`kcrxekmsltxtavbujmwq`, eu-west-3)

Las migraciones de `migrations/` están ya aplicadas. La liga arranca sembrada:
12 plazas libres, 20 clubes de Primera sin plantillas, calendario de 11 jornadas
y la jornada 1 abierta.

## Cómo entra la gente

**Usuario y contraseña, elegidos por cada uno.** Al fichar plaza se eligen, se
crea la cuenta y se entra directo: no hay nada que apuntar. Sigue sin haber
correos de verdad —Supabase Auth necesita uno, así que se deriva del usuario
(`upepe@ligadono.app`)—, pero la parte memorable la elige la persona.

Antes esto era un código generado que hacía de usuario y de contraseña a la
vez, y la idea era buena en el papel: nada que recordar y sirve en cualquier
dispositivo. En la práctica falló en todo lo que importaba:

- Nadie se acuerda de `LD-VZMW-UWX4`, así que hay que guardarlo y se pierde.
- **Teclearlo en un móvil falla.** Un manager con su plaza fichada no conseguía
  entrar. Comprobado hasta el fondo: el código era el correcto —verificado
  contra el cifrado de su propia cuenta—, la cuenta estaba sana, una llamada
  directa al servicio de acceso con ese código devolvía 200 y un token, y el
  sitio publicado era la versión actual. En los registros, sus intentos desde
  el iPhone salían como `invalid_credentials`. Lo teclado no era el código.
- Al ser también el usuario, **un carácter cambiado no se distingue de «esa
  persona no se ha registrado»**: el juego no puede decir cuál de las dos cosas
  pasa, y el aviso acabó mandando a fichar otra vez a quien ya tenía plaza.
- El gestor de contraseñas del navegador no podía ayudar, porque no había un
  campo de contraseña que guardar.

El precio del cambio, asumido a la vista: **sin correo no hay «he olvidado mi
contraseña» automático**. La repone la organización desde su panel
(`reponer_contrasena`), que para doce amigos es quien va a estar de todas
formas. Y cada uno puede cambiarse la suya desde Inicio, para no quedarse con
una que le puso otro.

El usuario no distingue mayúsculas ni espacios de más, y es único por liga. Al
fichar se comprueba que esté libre **antes** de crear la cuenta: si no, cada
intento con un usuario ya cogido dejaría una cuenta huérfana en Auth.

Cuando el acceso falla no se dice cuál de las dos cosas está mal. Decir «ese
usuario no existe» dejaría probar nombres hasta dar con los de la liga.

Para fichar hace falta además el **código de la liga**, que es la puerta de
entrada: sin él, cualquiera que encontrase la URL pública podría ocupar una
plaza libre. Se reparte entre los 12. Ese sí sigue siendo un código, pero se
teclea una vez en la vida y con él delante.

Quien organiza usa el **código de dirección**, que convierte su cuenta en
administradora.

> **Los códigos no se escriben aquí.** Este repositorio es público, y el
> historial de Git también, así que un código escrito en el README queda
> expuesto para siempre aunque se borre después. Viven solo en la base de datos.

Para consultarlos o cambiarlos, desde el editor SQL de Supabase:

```sql
select join_code, admin_claim_code from leagues;
update leagues set join_code = '...', admin_claim_code = '...';
```

El código de dirección solo funciona mientras la liga no tenga administrador
asignado, o para quien ya lo sea. Una vez reclamado, no le sirve a nadie más.

## Quién puede hacer qué

Lo decide Postgres, no el navegador. El PIN de la versión local dejó de ser una
cortina de cliente.

| | Jugador | Organización |
|---|---|---|
| Ver clasificación, cruces, clubes, plantillas | sí | sí |
| Editar su alineación | solo la suya, y solo con la jornada abierta | cualquiera |
| Ver la alineación de un rival | solo si la jornada está cerrada o ya pasó | siempre |
| Cargar estadísticas | no | sí |
| Mover o cerrar la jornada | no | sí |
| Cambiar plazas, cuentas o roles | no | sí |
| Cambiar su nombre de club y su escudo | solo los suyos | cualquiera |

De `managers`, alguien con sesión solo puede escribir `club_name`, `owner_name`
y `escudo`, y solo en su fila. El resto de columnas —`is_admin`, `user_id`,
`slot`, `usuario`— no se tocan desde el navegador: las escriben funciones
`security definer`. Esto no era así hasta la migración 0026; ver más abajo.

El flujo de una jornada es: abierta (cada uno alinea a ciegas) → la organización
la cierra (`lineups_locked = true`, y ahí se destapan los onces) → carga las
estadísticas → pasa a la jornada siguiente.

**Detalle importante para el cliente:** cuando alguien intenta guardar con la
jornada cerrada, RLS no devuelve error, devuelve **cero filas afectadas**. Hay
que comprobar las filas y avisar, en vez de dar por bueno un guardado que no
ocurrió.

## Cómo se carga una jornada

Se aprieta un botón en el panel y baja todo de Highlightly. De dónde sale cada
categoría del reglamento:

| Categoría | Campo del box score |
|---|---|
| Goles | `statistics.goalsScored` |
| Asistencias | `statistics.assists` |
| Amarillas | `statistics.cardsYellow` |
| Rojas | `statistics.cardsRed` |
| Faltas | `statistics.fouledOthers` (las que comete, no las que recibe) |
| Tiros a puerta | `statistics.shotsOnTarget` |
| Minutos | `minutesPlayed` — **fuera** de `statistics`, al nivel del jugador |

Los puntos por equipo y la portería a cero no vienen por jugador: se sacan del
marcador, que ya está en `hl_matches`.

`app.cargar_partido(match_id)` hace las dos cosas de una sola llamada a la API:
guarda las estadísticas y mantiene las dos plantillas (enlaza, mueve, da de
alta, apunta que se le ha visto jugar). Separarlas costaría el doble de cuota.
`app.cargar_jornada(jornada, pausa)` recorre los 10 partidos desde SQL.

Desde el navegador la carga va **partido a partido**, no de golpe: una jornada
entera es un minuto largo entre llamadas y pausas, y PostgREST corta mucho
antes. Partido a partido cada uno son un par de segundos, y el panel puede ir
contando por dónde va.

Qué ronda real alimenta cada jornada nuestra lo dice `jornada_rondas`: nuestra
liga son 11 jornadas y la de verdad 38. Arranca en la primera ronda que estaba
entera por jugar —la 7— y va de la 7 a la 17, del 18 de septiembre al 20 de
diciembre. Apuntaba a la 1, jugada en agosto, lo que habría hecho empezar con
una jornada ya decidida antes de que nadie alineara.

**Comprobado contra los datos reales.** Jornada 1: 453 fichas, 28 goles por
jugador y 28 en los marcadores, 19.749 minutos (≈20 equipos × 990), 20 filas de
club y 28 puntos repartidos, que es lo que dan 8 partidos decididos y 2
empates. Jornada 2: 455 fichas y 22 goles por los dos lados. En el Sevilla 2-1
Rayo, los totales por club salen clavados a los del JSON crudo.

`cardsSecondYellow` no se lee: en ese mismo partido da 4 amarillas y 4 dobles
amarillas por equipo, sin un solo caso en que difieran. Es una copia, no un
dato, y por eso el reglamento funde la doble amarilla con la roja.

`hl_matches` lleva dos marcas y no una: `cosechado` es "de aquí hemos sacado
los jugadores" y `stats_cargadas` es "de aquí tenemos las estadísticas". Al
principio compartían una, y la jornada 2 aparecía como cargada porque sus
partidos se habían cosechado en su día para montar las plantillas, cuando no
tenía ni un dato de jugador.

## Cómo se cargan las estadísticas

Por **jugador y jornada** (`player_jornada_stats`), no por hueco de alineación:
los goles de un jugador son una propiedad del jugador, no de quién lo eligió. Se
introducen una vez y cuentan para todos los managers que lo tengan. Antes se
guardaban por hueco, lo que multiplicaba el trabajo y permitía que un dedazo
diera números distintos para el mismo jugador en cruces distintos.

La vista `picked_players` da la lista de trabajo de cada jornada: a quién han
elegido y por cuántos managers.

Es además el requisito para automatizar la carga desde una API de datos, porque
las APIs devuelven estadísticas por jugador.

## Puntuación

Los pesos del reglamento viven en SQL (`slot_contrib`), así que no se pueden
tocar desde el navegador:

- Goles: portero y defensa 2, medio y delantero 1
- Tiros: portero y defensa 3, medio 2, delantero 1
- Portería a 0: portero 3, defensa 2, medio y delantero 1
- Tarjetas: amarilla 1, roja 3. La doble amarilla cuenta como roja
- Minutos jugados: 1 por minuto, todas las posiciones
- Asistencias, faltas y puntos de club: tal cual
- Si el club real de un jugador no jugó esa jornada, ese jugador no puntúa en nada

La octava categoría fue córners hasta la migración 0010. Los córners eran un dato
del club, así que los 11 jugadores de una alineación aportaban los de sus clubes
y la categoría medía más la suerte del sorteo de clubes que las decisiones del
manager. Los minutos son un dato del jugador y premian acertar con los titulares.

Un subpunto por categoría, y empate reparte uno a cada uno. Los subpuntos de un
lado son, por tanto, el número de categorías en las que va igual o por delante.
Más subpuntos = 3 puntos de liga; empate a subpuntos = 1 para cada uno.

## De dónde sale cada número

Debajo de cada alineación destapada hay un desplegable, **«Ver de dónde sale cada
número»**, con los 11 jugadores en filas y las 8 categorías en columnas: lo que
aporta cada uno, y el total abajo. Viene plegado para no estorbar a quien solo
quiere ver el resultado.

La pregunta que genera discusiones en un juego así es «¿por qué he sacado eso en
minutos?». No se resuelve discutiendo: se enseña la cuenta y se acaba.

El cálculo lo hace el navegador (`aporteDe` en `app.js`), porque los datos por
jugador ya están descargados y así no cuesta ninguna consulta más. Eso duplica
los pesos del reglamento fuera de SQL, con el riesgo de que un día dejen de
coincidir — así que **el desglose se comprueba a sí mismo**: suma sus 11 filas
por categoría y las compara con el resultado oficial que manda la base de datos.
Si no cuadran, avisa en rojo en vez de enseñar una cuenta falsa. El oficial
siempre manda.

Los pesos del navegador tienen que seguir a la vista `slot_contrib` tal y como la
dejó la migración 0011. Si algún día se cambia el reglamento en SQL, hay que
tocar también `MULT` y `aporteDe` en `app.js`.

### El partido real, abierto

En la lista de partidos de Primera, uno ya cargado se abre y enseña a los
jugadores de los dos equipos con sus minutos, goles, asistencias, tarjetas,
tiros y faltas. Está tanto en la pestaña Jornada como en Mi Plantilla, que es
donde se decide a quién alinear.

No cuesta ninguna consulta más: son los mismos datos que ya alimentan el
resultado, y la plantilla de cada club ya viene en el arranque. El contenido se
rellena al abrir cada partido, no antes, porque en Mi Plantilla la mayoría no se
abren nunca. Los partidos sin cargar no se pueden abrir: uno que se abriera para
no enseñar nada sería peor que uno que no se abre.

**Solo se marcan los jugadores propios.** Marcar los del rival destaparía su once
desde una pantalla que no está protegida por las reglas de la jornada, así que
hay una prueba dedicada a ello (`t-partido.mjs`).

## La liga va sola (migraciones 0030 y 0031)

Cada hora, `pg_cron` llama a `app.ciclo()` dentro de la propia base de datos. No
hace falta ningún servidor: la clave de la API está en el baúl y las llamadas
salen de Postgres con la extensión `http`.

Lo que hace, en este orden:

1. **Refresca el calendario real** cada 6 h. Es lo que trae los aplazamientos y
   los cambios de hora, así que va primero.
2. **Carga los partidos terminados** de la jornada en curso y de la anterior —la
   anterior por si alguno acabó después de pasar de jornada—. Máximo 4 por
   pasada, para no comerse la cuota.
3. **Cierra los datos de club** de lo que acaba de cargar, en la misma pasada. Si
   se dejara para después, el desglose de la pantalla no cuadraría con el
   resultado oficial mientras tanto y saldría el aviso de descuadre.
4. **Saca de la jornada lo aplazado más allá de la jornada siguiente.** Es el
   único caso que dejaría la liga congelada un mes. Por reglamento no se
   recalcula hacia atrás, así que ese partido no cuenta. Reversible con un clic.
5. **Avisa de los adelantados** —un partido jugado antes de abrirse la jornada—
   pero no los saca: eso es decisión de la organización, no del robot.
6. **Pasa de jornada** cuando la ronda está entera jugada y cargada.

**No va por calendario, va por estado.** Nada de «los martes»: es lo único que
aguanta una jornada intersemanal que acaba un jueves y encadena con otra el
viernes. En cuanto la ronda está completa, se pasa de jornada, sea lunes o sea
jueves por la noche.

Todo lo que hace queda escrito en `app_avisos` y se ve en el panel, en
**Dirección → Automático**, con un botón para adelantar la pasada y otro para
apagarlo. Una automatización sin parte de lo que ha hecho es una automatización
en la que no se puede confiar: cuando alguien pregunte por qué su jugador no
puntuó, la respuesta tiene que estar escrita.

La cuota se cuenta en `app_api_uso`, dentro de `app.highlightly()`, que es el
único sitio por el que pasan todas las llamadas. El ciclo se para solo al llegar
a 80 de las 100 diarias, para que a la organización le queden 20 por si tiene que
hacer algo a mano.

Para pararlo o mirarlo desde SQL:

```sql
select cron.unschedule('liga-dono-ciclo');
select * from cron.job_run_details order by start_time desc limit 20;
```

### Dos fallos que salieron al montarlo

**Sacar un partido de la jornada no lo sacaba de la cuenta.** `jornada_excluidos`
movía la hora de cierre y bloqueaba elegir a esos jugadores, pero `slot_contrib`
no miraba la tabla. El cartel de la pantalla decía «sus jugadores no puntúan» y
sí puntuaban: quien ya los tuviera puestos de antes seguía sumando con ellos.
Ahora la vista `clubes_excluidos` entra en `slot_contrib` y anula la aportación,
y `cerrar_datos_de_club` tampoco cuenta esos partidos. El dato no se borra, se
anula: volver a meter el partido es un clic y no una recarga desde la API.

**Un partido adelantado abría la jornada ya cerrada.** El cierre era el primer
partido de la ronda. Si uno se adelantaba a la semana anterior, ese pasaba a ser
«el primero» y la jornada nacía con la hora de cierre ya pasada: doce personas
sin poder alinear. Ahora se apunta en `leagues.jornada_desde` cuándo se abrió la
jornada —con un disparador, para que valga igual si la pasa el ciclo o la
organización— y el cierre lo marca el primer partido que quede **por jugar**.

### Y un tercero: los `revoke` no revocaban (migración 0032)

Al comprobar que un jugador normal no pudiera lanzar el ciclo salió que **sí
podía**. Por todas las migraciones hay líneas como esta:

```sql
revoke all on function app.highlightly(text) from anon, authenticated;
```

y ninguna hacía nada. En Postgres, EXECUTE sobre una función se concede por
defecto a **PUBLIC**, y quitárselo a `anon` y a `authenticated` no toca esa
concesión: los dos roles la siguen heredando por ser miembros de PUBLIC. Las 29
funciones de `app` eran ejecutables por los dos.

¿Estaba abierto de verdad? **No.** Se preguntó a la API pública con la clave
pública y contesta `PGRST106 · Only the following schemas are exposed: public,
graphql_public`. Desde el navegador no se llegaba al esquema `app` de ninguna
forma. No era un agujero: era un cierre que no cerraba. Bastaría exponer el
esquema una vez por error para que `app.highlightly` —que lleva la clave de la
API dentro— quedara al alcance de cualquiera.

Arreglado revocando de PUBLIC, más `alter default privileges` para que no vuelva
a pasar con lo que se cree en adelante. No se tocan las funciones que usan las
políticas de RLS (`app.is_admin()` y compañía): una política se evalúa con los
permisos de quien pregunta, y dejarlas sin EXECUTE cerraría el juego entero.
Comprobado por suplantación: un jugador ya no puede llamar a `app.ciclo()`,
`app.highlightly()` ni `app.cargar_partido()`, y sigue pudiendo leer la
clasificación, los resultados, los partidos y guardar su alineación.

## De dónde pueden salir los datos

Investigado y probado contra las APIs reales, no leído de su publicidad:

| Fuente | Veredicto |
|---|---|
| **Highlightly** (RapidAPI) | Sirve. Plan gratis 100/día, temporada en curso disponible, `/box-score/{matchId}` da minutos, goles, asistencias, faltas (`fouledOthers`), tiros a puerta y tarjetas por jugador |
| API-Football | Free solo llega a las temporadas 2022-2024. La actual la rechaza. Los datos por jugador sí están, pero del año que no nos sirve |
| FBref | 403 con desafío de Cloudflare: bloquean el acceso automático |
| Understat | `robots.txt` con `Disallow: /`: prohíben el rastreo |
| football-data.org | Sin datos por jugador en el plan gratuito |
| TheSportsDB | Temporada en curso gratis, pero estadísticas por equipo. Por jugador solo goles, asistencias y tarjetas vía timeline |

**Cuidado con `cardsSecondYellow` de Highlightly:** es una copia de `cardsYellow`, no
un dato real. En el Sevilla 2-1 Rayo de la jornada 1 daba 8 amarillas y 8 dobles
amarillas, con cero casos en los que los dos campos difirieran. Por eso el
reglamento funde la doble amarilla con la roja: ninguna fuente gratuita la
distingue de forma fiable.

## Enlace con Highlightly

Las estadísticas vienen de Highlightly, así que cada club y cada jugador nuestro
necesita saber su identificador allí (`clubs.highlightly_id`,
`club_players.highlightly_id`).

La clave de la API vive en el **baúl cifrado de Supabase**, nunca en el
repositorio. `app.highlightly(ruta)` la lee de ahí y hace la llamada.

```sql
select vault.create_secret('LA-CLAVE', 'highlightly_key', 'RapidAPI');
select app.highlightly('/standings?leagueId=119924&season=2026');
```

Highlightly no tiene endpoint de plantilla por equipo: `/players` solo busca por
nombre y `/teams/{id}` devuelve el escudo y poco más. Los jugadores se cosechan
de los box score de los partidos, que traen las dos plantillas enteras:
`app.refrescar_calendario()` baja el calendario y `app.cosechar_box_score(id)`
guarda los jugadores de un partido en `hl_players`.

El casado de nombres se hace en dos pasadas. Primero coincidencia exacta del
nombre normalizado dentro del mismo club, que resuelve la gran mayoría. Después
tres reglas para el resto: un nombre contenido en el otro (*Pathé Ciss* dentro de
*Pathé Ismaël Ciss*), mismo apellido con el nombre de pila abreviado (*Javi* y
*Javier*), o parecido de trigramas por encima de 0.55. Solo se aplica cuando hay
un único candidato y nadie más lo reclama.

Lo que quede sin enlazar suele ser gente que aún no ha jugado: no está en los box
score, así que no hay con qué casarlo. Se enlazan solos según vayan apareciendo.

**Identificadores de la liga real:** `leagueId=119924` es Primera; la temporada
en curso es 2026.

## Cómo se mantienen las plantillas

Las plantillas se mueven durante la temporada. El catálogo se mantiene solo a
partir de dos sitios:

- **Los box score de cada jornada**, que traen las dos plantillas enteras.
  `app.sincronizar_box_score(match_id)` enlaza al que aún no lo estaba, mueve al
  que ha cambiado de club dentro de la liga, da de alta al que no teníamos y
  apunta la fecha en que se le vio jugar. Ver jugar a alguien es prueba de que
  está.
- **El resumen de jugador** (`/players/{id}`), que dice en `profile.club.current`
  a qué club pertenece hoy. `app.verificar_jugador(id)` lo consulta y
  `app.verificar_plantillas(limite, pausa)` lo hace por tandas, con pausa entre
  llamadas porque el plan gratuito limita también por segundo.

### Los fichajes que aún no han jugado (migración 0033)

El mercado se cierra pero los clubes siguen fichando a gente sin contrato todo
el año, así que el catálogo se queda corto. Lo primero que se buscó fue una
forma barata de pedir «la plantilla del Betis». **La API no la tiene.** Probado
contra la API de verdad, no leído de su documentación:

| Ruta | Respuesta |
|---|---|
| `/teams/{id}` | 200, pero solo `id`, `logo`, `name` y `type` |
| `/teams/{id}/squad` | 404 |
| `/squads?teamId=` | 404 |
| `/squad?teamId=` | 404 |
| `/team-statistics/{id}` | 404 |
| `/players?teamId=` | 400 · *property teamId should not exist* |
| `/players?name=X&leagueId=` | 400 · *property leagueId should not exist* |

`/players` solo acepta `name`. Así que hay tres vías, por lo que cuestan:

1. **Gratis, pero tarde.** El que juega entra solo: el acta del partido trae las
   dos plantillas enteras, así que un fichaje aparece la primera vez que juega
   sin gastar ni una llamada. Ya funcionaba.
2. **Gratis, y ahora.** Escribir el nombre a mano en *Equipos y jugadores*. La
   ficha nace sin enlazar y se enlaza sola por nombre normalizado la primera vez
   que el jugador sale en un acta.
3. **Dos llamadas.** Buscarlo en la API desde *Fichajes*. Deja la ficha enlazada
   desde el primer día, con el nombre y el puesto tal y como los dice la API.

La tercera necesita una pantalla con cuidado: buscar «Vinicius» devuelve diez
homónimos de medio mundo y **la búsqueda no dice el club**. Por eso el club de
cada candidato se pide de uno en uno (`mirar_candidato`), lo pide el navegador a
su ritmo —cada petición es corta, y el rol `authenticated` corta a los 8
segundos— y el botón de añadir **está desactivado hasta que se ha visto el
club**. Si el club no es uno de los 20, no se puede añadir y se dice en qué club
está. El club lo decide la API y no la organización, así que no se puede meter a
alguien en el equipo equivocado por error de dedo.

`app.pos_desde_perfil` es un traductor aparte de `app.pos_desde_highlightly`: el
acta dice «Goalkeeper» o «Defender», pero el perfil habla otro idioma
(«Centre-Back», «Left Winger», «Attacking Midfield»). Leer el perfil con el
traductor del acta metía a todo el mundo de centrocampista, y eso cambia los
multiplicadores con los que puntúa.

### El repaso, con los resultados por delante

El repaso del catálogo (traspasos y salidas) cuesta **una llamada por jugador**,
y es el que daba miedo: quedarse sin llamadas justo cuando hay que cargar una
jornada. El reparto de las 100 del día queda así:

- Los resultados van **siempre primero**. El ciclo carga partidos antes de mirar
  plantillas y, si carga alguno, ese turno termina ahí.
- El repaso **no empieza** si el día lleva ya 40 llamadas, y no pasa de **20
  fichas al día** (`app.repasar_plantillas`).
- El ciclo entero no pasa de 80, así que quedan 20 libres para lo que haga falta
  a mano.

Peor día posible: 4 de calendario + 10 de una jornada + 20 de repaso = **34 de
100**. Nunca puede faltar una llamada para cargar un resultado por haberla
gastado en repasar plantillas. Todo esto se ve en *Dirección → Automático*.

**Nadie se da de baja solo.** La primera versión sí lo hacía, y los cuatro
primeros casos fueron cuatro falsos positivos: el resumen de jugador usa nombres
distintos de los de la clasificación —«Deportivo A Coruña» frente a «Deportivo de
La Coruña», «Athletic Bilbao» frente a «Athletic Club»— y el comparador los daba
por clubes ajenos. Borrar a un jugador que sí está tiene mucho peor arreglo que
dejar uno de más, así que ahora:

1. `app.club_por_nombre(liga, nombre)` empareja por nombre normalizado, por
   `clubs.aliases`, y en último término por parecido de trigramas, exigiendo
   0.45 de parecido y 0.15 de ventaja sobre el segundo. Los 20 clubes no se
   parecen entre sí más de 0.33, así que un ganador con esa ventaja es
   inequívoco. Probado: los 19 nombres que la API ya nos había dado cuadran
   todos, y ninguno de los clubes de fuera (Girona, Cádiz, Real Valladolid,
   Sporting, Como, Bayern…) cuadra con nada.
2. Si aun así no cuadra, el jugador se marca `revisar` y **sigue disponible para
   alinear**. Sale en la vista `jugadores_a_revisar` y en el panel de dirección,
   con el club que dice la API, para que una persona decida.

`app.norm_club` descarta las partículas y sufijos de club (`fc`, `cf`, `cd`,
`ud`, `de`, `la`, `a`…), que es lo que hace que «Deportivo A Coruña» y
«Deportivo de La Coruña» acaben en el mismo sitio.

Un jugador de baja deja de ofrecerse en los desplegables, pero su ficha no se
borra: las alineaciones de jornadas ya jugadas siguen enseñándolo, con el motivo.

## Máximo 7 cambios por jornada

De una jornada a la siguiente se pueden cambiar 7 jugadores como mucho, así que
al menos 4 repiten. `leagues.max_cambios`, por si algún día se quiere otro
número. Vale igual en playoffs.

Se cuenta contra **el último once puesto de verdad**, no contra la jornada
inmediatamente anterior. La diferencia importa: si fuera «la anterior»,
saltarse una jornada valdría como reseteo gratis del once. Quien no ha alineado
nunca entra libre, porque no hay con qué comparar.

Un jugador que se va de Primera **no da derecho a cambio gratis**: o gastas uno
de los 7 en sustituirlo, o lo dejas en el once sabiendo que no puntúa. Incluido
el caso de que se vayan tantos que no puedas repetir 4: entonces juegas con
muertos en el once. Decisión tomada a propósito — dura y simple, y las reglas
duras y simples se discuten menos.

**Esto obligó a cambiar cómo se guarda el once.** Eran varias escrituras
sueltas desde el navegador —crear la alineación, borrar los 11 huecos,
insertarlos otra vez— y una regla que mira el once entero no se puede comprobar
así: entre el borrado y la inserción el once no existe. Ahora es una sola
llamada, `guardar_alineacion(jornada, formacion, slots)`, que valida y escribe
de golpe.

De regalo desaparece un fallo que ya estaba ahí: si el borrado salía bien y la
inserción fallaba —se cae la red a media operación— te quedabas con la
alineación vacía y sin enterarte.

Comprobado contra la base de datos real, como jugador que no es la
organización:

```
jornada 1 libre: guarda 11 nuevos          → guardado, sin referencia
jornada 2 cambiando 7                      → aceptado, cambios = 7
jornada 2 cambiando 8                      → RECHAZADO
jornada 4 sin haber jugado la 3            → se compara con la jornada 2
```

La organización se salta el límite, igual que se salta la hora de cierre:
alguien tiene que poder arreglar un desastre.

## Los partidos reales, a la vista de los doce

Para decidir a quién alineas hace falta saber contra quién juega cada club, en
casa o fuera, y a qué hora. Eso obligaba a salir de la aplicación, que es un
fallo de diseño: la decisión se toma en la pantalla de alineación y el dato
estaba en otro sitio.

Los 200 partidos ya estaban en `hl_matches`, y `jornada_partidos()` ya la podía
llamar cualquier jugador —no solo la organización—. Solo faltaba devolver tres
cosas más y enseñarlo: la hora de comienzo, los identificadores de club (para
marcar «aquí juega uno de los tuyos» sin adivinar por el nombre) y si el
partido está fuera de la jornada.

Se enseña en la pestaña Jornada y, sobre todo, **en Mi Plantilla**, que es
donde de verdad se decide. Ahí se marca con el borrador que tienes en pantalla,
no con lo guardado: al cambiar un club se ve al momento dónde juega.

**Lo que no se devuelve, a propósito:** cuántos managers tienen jugadores de
cada partido. Eso delataría las alineaciones antes del cierre y se cargaría el
«alinear a ciegas». Cada uno solo ve los suyos, que ya se los sabe.

## Cuándo se cierra la jornada

La marca **el primer partido de la jornada**, no un botón. Si el primero es el
viernes a las 21:00, a las 21:00 se bloquean las alineaciones y se destapan
todos los onces. Nadie tiene que estar delante.

Antes cerraba a mano, y eso dejaba abierta la única forma real de hacer trampa
en este juego: que a alguien se le olvide cerrar y otro alinee con los partidos
ya empezados.

La hora sale de `hl_matches.comienza`, que es el `date` completo de la API
—hasta ahora se recortaba a `left(date,10)` y se tiraba la hora—. Se guarda con
zona horaria y se compara con `now()`, así que el cambio de hora de octubre se
resuelve solo.

Lo aplican **dos sitios y nada más**:

- `app.lineup_editable()`, que usan las políticas de insert, update y delete
- la política `lineups_read`, que decide cuándo se ven los onces de los rivales

Ambas pasan por `app.jornada_cerrada()`, que es `lineups_locked OR now() >=
cierre`. El botón de cerrar a mano se queda, pero ahora solo sirve para
**adelantar** el cierre.

Si no hay hora conocida —calendario sin refrescar— manda solo el botón. Dejar a
doce personas sin poder alinear por un dato que falta es peor que el riesgo que
evita.

Comprobado contra la base de datos real, haciéndose pasar por un jugador que no
es la organización:

```
jornada abierta: guarda su once        → GUARDA
pasada la hora: intenta modificarlo    → BLOQUEADO, 0 filas
pasada la hora: intenta crear otro     → BLOQUEADO
pasada la hora: intenta borrarlo       → BLOQUEADO, 0 filas
la formación guardada sigue siendo     → la de antes
```

La organización sí puede editar fuera de hora, por la política `lineups_admin`.
Es a propósito: alguien tiene que poder arreglar un desastre.

## Sacar un partido de la jornada

`jornada_excluidos(league_id, jornada, match_id, motivo)`. Resuelve dos casos:

- **Aplazado**: se juega semanas después. La jornada no espera —se congelaría la
  liga— y esos clubes no puntúan, que es la regla que ya estaba escrita.
- **Adelantado**: se juega *antes* de que la gente alinee. Quien ponga a un
  jugador de ese partido ya sabe lo que hizo. Además, sin sacarlo, el cierre se
  iría al día del adelanto y fastidiaría a los doce.

Sacar el partido hace las dos cosas a la vez: sus clubes quedan fuera **y** el
cierre se recalcula con los que quedan. Verificado:

```
cierre con los 10 partidos        → viernes 18, 21:00
cierre tras sacar el del viernes  → sábado 19, 14:00
clubes bloqueados al alinear      → Elche y Espanyol, con el motivo
al devolver el partido            → viernes 18, 21:00
```

Va por liga, no global, porque el reparto jornada→ronda ya es por liga: dos
ligas pueden empezar en rondas distintas y no tienen por qué tomar la misma
decisión sobre un adelantado.

La pantalla de alineación los bloquea con el motivo a la vista, y avisa si ya
tenías elegido a alguien de esos clubes. Un once puede ser legal y aun así
llevar jugadores que no van a puntuar; decir solo «legal ✓» engañaría.

## El escudo de cada manager

En `managers.escudo`, y **no es una imagen**: es la receta para dibujarla.

```
esp|bandas|1f7a4d|f4f1e6|balon|NC
forma|diseño|color1|color2|símbolo|iniciales
```

Unos 30 caracteres. Los doce escudos de una liga ocupan menos que este párrafo.
El dibujo lo hace el navegador (`escudo.js`), así que se ve nítido a cualquier
tamaño, de 26 px en una fila de la clasificación a pantalla completa.

Guardar una imagen subida habría costado almacenamiento y tráfico —justo el
recurso que limita cuántas ligas caben a la vez en el plan gratuito— y habría
obligado a alguien a moderar lo que suben. Así no hay nada que moderar: solo se
puede elegir entre lo que el catálogo ofrece, y la paleta está cerrada a doce
colores que combinan entre sí.

El `check` de la columna es de **forma**, no de contenido: impide que ahí acabe
texto arbitrario. Que la forma y el símbolo existan de verdad lo comprueba el
navegador al dibujar, que es quien tiene el catálogo; ante algo que no reconoce
pinta el escudo por defecto en vez de fallar. Son 66.000 combinaciones.

`claim_slot` lo recibe al fichar y `guardar_escudo(text)` lo cambia después.
Quien no tiene escudo no sale en blanco: se le dibuja uno derivado del nombre
de su club, distinto para cada nombre.

## Vistas

| Vista | Para qué |
|---|---|
| `slot_contrib` | lo que aporta cada hueco de una alineación a las 8 categorías |
| `manager_jornada_totals` | totales de un manager en una jornada |
| `fixture_results` | los 16 valores brutos del cruce, subpuntos y puntos de liga |
| `standings` | clasificación con PJ, G/E/P, subpuntos y puesto |
| `manager_form` | racha, para los últimos resultados |
| `playoff_series_state` | victorias de cada serie al mejor de 3 |
| `picked_players` | a qué jugadores ha elegido alguien en una jornada, y cuántos |
| `jugadores_a_revisar` | fichas cuyo club según la API no cuadra con ninguno de la liga |
| `jugadores_sin_aparecer` | fichas que no han salido en ningún box score todavía |

## Los códigos ya no se pueden leer desde el navegador

Estaban a la vista. La política de lectura de `leagues` es `using (true)`
porque todo el mundo necesita saber en qué jornada va la liga, y los códigos
viven en esa misma tabla, así que cualquiera con sesión podía pedir:

```sql
select join_code, admin_claim_code from leagues
```

Comprobado con la identidad de un jugador real: los veía los dos. Con el código
de la liga, un jugador lo reparte y un desconocido ocupa una plaza libre, que es
justo lo que ese código existe para evitar.

RLS decide filas, no columnas, así que se arregla con permisos de columna:
`leagues` solo deja leer `id`, `name`, `current_jornada`, `lineups_locked`,
`admin_user_id` y `created_at`. `claim_slot` y `claim_admin` son SECURITY
DEFINER y siguen viendo los códigos. Y ya que estábamos, la organización puede
mover la jornada y cerrarla desde el navegador pero no cambiar los códigos:
para eso está el editor SQL.

Verificado después del cambio, con la identidad de un jugador y de la
organización: el jugador no ve ninguno de los dos códigos pero sí la jornada;
la organización cierra la jornada pero tampoco toca los códigos.

## Copia de seguridad (migración 0035)

El plan gratuito de Supabase **no da copias que se puedan restaurar**, así que
hasta aquí no había ninguna red. Y el riesgo de verdad no es que Supabase pierda
la base de datos —eso no pasa— sino que **algo borre datos**: un fallo, una
pulsación en el panel, un `delete` sin `where`. Probando el ciclo quedaron en la
base real una alineación fantasma y un jugador de prueba; se vieron y se
quitaron, pero así es como se pierde una clasificación en la jornada 8.

Hay **dos formas de perder los datos y hacen falta dos remedios**:

| Qué pasa | Qué lo arregla |
|---|---|
| Algo borra datos y el proyecto sigue vivo | Restaurar de una copia guardada en la propia base. Un clic. |
| Se pierde el proyecto entero | Solo el `.json` descargado al ordenador. Una copia que vive dentro del proyecto muere con él. |

Por eso la pantalla insiste en descargar de vez en cuando, y avisa de que **el
fichero lleva dentro los dos códigos de la liga**: es para guardarlo, no para
reenviarlo.

**Qué se guarda:** las 13 tablas que no se pueden volver a bajar —`leagues`,
`clubs`, `managers`, `club_players`, `fixtures`, `jornada_rondas`,
`jornada_excluidos`, `lineups`, `lineup_slots`, `club_stats`,
`player_jornada_stats`, `playoff_series`, `playoff_games`—. Las alineaciones son
irrecuperables: son decisiones de doce personas, no un dato que esté en ningún
sitio. Las estadísticas sí se podrían rebajar de la API, pero a una llamada por
partido, así que se guardan igual.

**Qué no:** `hl_matches` y `hl_players`, que son la copia local del calendario y
se rehacen con 4 llamadas, y `latidos`, `app_avisos` y `app_api_uso`, que son
registros de funcionamiento.

Una copia entera ocupa **243 kB**. Se guardan las 25 últimas. Se hace una al
terminar cada jornada —justo antes de pasar de jornada, que es la foto que se
querría recuperar— y una al día. **No gastan ninguna llamada a la API**, y la
copia va antes que todo lo demás en el ciclo: si un día la API falla, la copia se
hace igual.

`app_copias` no es legible desde el navegador: se pasa siempre por funciones que
comprueban quién pregunta, porque una copia lleva los códigos dentro.

### La restauración, probada

Una copia que no se sabe si restaura es una promesa falsa. Se probó **sobre la
base real**: huella md5 de las 13 tablas, se destroza la liga a propósito
(nombres de club cambiados, porteros borrados, plazas en blanco, jornada en
curso movida, jornadas y cruces borrados, un once fantasma añadido) y se
restaura.

La primera vez volvieron **12 de 13**. La que no: `leagues`. El disparador
`leagues_apertura_de_jornada` tomaba la restauración de `current_jornada` por un
cambio de jornada y pisaba `jornada_desde` con la hora de ahora — y esa columna
es la que decide **a qué hora cierra la jornada**, así que restaurar movía el
cierre en silencio. Se apaga el disparador durante la restauración y se vuelve a
encender incluso si falla. Segunda vuelta: **13 de 13 idénticas**.

Antes de restaurar se guarda otra copia de cómo está todo, así que una
restauración equivocada también se deshace. Y hay que escribir `RESTAURAR` a
mano: un botón de restaurar a un clic, al lado de uno de descargar, es un
accidente esperando.

**Restaurar devuelve la liga entera** a como estaba. Si alguien fichó plaza
después de esa copia, se queda sin ella y tendría que volver a fichar; su cuenta
sigue existiendo. La pantalla lo avisa antes.

## Repaso de seguridad del ciclo (migración 0034)

Pasado el analizador de Supabase después de los cambios de hoy. Tres cosas
reales, dos metidas ese mismo día:

1. **`ciclo_estado()` no comprobaba nada.** Es `security definer` y vive en el
   esquema público, así que PostgREST la publica y `anon` podía llamarla: sin
   sesión, con la URL y la clave públicas, se leía el estado del automático, la
   jornada, la hora de cierre, las llamadas gastadas, el catálogo y todos los
   avisos. No hay códigos ni contraseñas ahí, pero es información de la liga.
   Ahora pide ser la organización. Cuando exista el tablón de noticias tendrá su
   propia función con solo lo que deban ver los doce.
2. **El disparador `app.marcar_apertura_de_jornada` no fijaba `search_path`.**
3. **Las tres funciones de fichajes y `ciclo_ahora` las alcanzaba `anon`.** No
   era aprovechable —comprueban `is_admin()` antes de gastar ninguna llamada a
   la API— pero se ha revocado.

Comprobado por suplantación: la organización lo ve, alguien sin entrar no, y un
jugador normal de la liga tampoco.

Lo que el analizador marca y se queda como está, a propósito:

- **`clubes_excluidos` como vista con permisos del dueño.** Lo marca como ERROR
  y es deliberado: `authenticated` no puede leer `hl_matches`, y una vista de
  invocador dejaría a los doce sin poder leer la clasificación. Solo expone qué
  clubes tienen un partido fuera de una jornada, que ya es público.
- **`hl_matches` y `hl_players` con RLS y sin políticas.** Es el cierre buscado.
- **El resto de funciones `security definer` del esquema público** son los
  endpoints del juego, y cada una comprueba por dentro quién la llama.

Queda **sin activar**, y es un interruptor de 30 segundos en el panel de
Supabase si se quiere: *Leaked Password Protection* (Authentication → Policies),
que compara la contraseña elegida contra HaveIBeenPwned y evita que alguien use
una que ya se ha filtrado por ahí.

## Revisión de seguridad

Hecha a propósito, porque la fuga de los códigos salió de rebote y eso no es un
método. El linter de Supabase dio 25 avisos; esto es lo que resultó ser cada
cosa.

**Un fallo real, sin consecuencia por suerte.** En Postgres, crear una función
le da EXECUTE a **PUBLIC**. En las migraciones 0019 y 0021 escribí
`revoke all ... from anon` creyendo cerrar las funciones de organización, y no
cerré nada: quitaba el permiso explícito de `anon`, pero `anon` seguía
entrando por el de PUBLIC. El ACL lo decía —`=X/postgres`, con el hueco
delante, es PUBLIC— y no lo leí.

Comprobado llamando a las once funciones con la identidad de `anon` y sin
sesión: **ninguna dejaba hacer nada**. Las seis de organización se rechazan
solas, y `claim_slot` y `claim_admin` piden sesión incluso con el código
correcto. Es decir: no hubo agujero, pero por suerte y no por diseño. La
primera función que alguien añada sin ese control habría quedado abierta a
internet el día de crearla.

Arreglado donde debía: el permiso quitado de PUBLIC y dado a `authenticated`,
salvo `public_slots()`, que es lo único que se llama antes de entrar. Y
`alter default privileges` para que las próximas no nazcan abiertas. Los
ejecutables sin sesión pasan de once a uno.

El esquema `app` se queda como está, a propósito: las políticas RLS llaman a
`app.is_admin()` **como el usuario que consulta**, así que tocar los permisos
ahí rompería la lectura para todos. Lo que lo mantiene fuera de la API es que
PostgREST no publica ese esquema.

### Un segundo fallo real, este sí aprovechable (migración 0026)

Encontrado al ir a añadir el escudo, que necesitaba una columna nueva
escribible por cada manager.

La política `managers_own` deja a cada uno escribir en **su** fila, que es lo
que se quiere: renombrar su club. Pero los permisos de columna estaban abiertos:
`authenticated` tenía UPDATE sobre **todas** las columnas de `managers`,
`is_admin` incluida.

Las políticas deciden **qué filas** tocas; los permisos de columna, **qué
campos**. Aquí la fila era la correcta y el campo podía ser cualquiera.

Comprobado contra la base de datos real, haciéndose pasar por un jugador:

```
un jugador hace UPDATE managers SET is_admin=true sobre su propia fila
  → PASA, el UPDATE no da error
después, app.is_admin() devuelve
  → true
```

Es decir, cualquiera de los doce podía abrirse el panel de dirección y desde
ahí cargar resultados, cerrar la jornada o cambiarle la contraseña a otro. A
diferencia del anterior, este sí era explotable con una línea. No lo usó nadie
—solo había una plaza fichada, la de la organización— y se cerró antes de que
entrasen los otros once.

Arreglado dejando a `authenticated` solo las tres columnas que una persona
tiene por qué cambiar de sí misma: `club_name`, `owner_name` y `escudo`. Lo
demás lo escriben funciones `security definer`. «Liberar plaza» del panel
escribía `user_id`, `usuario` y `claimed_at` a pelo, así que pasa a ser
`liberar_plaza(uuid)`, que comprueba `app.is_admin()`.

Comprobado después, con la misma identidad de jugador:

```
se pone is_admin=true      → BLOQUEADO, permission denied for table managers
reescribe user_id          → BLOQUEADO
se cambia de plaza         → BLOQUEADO
renombra su club           → pasa, que es lo suyo
guarda su escudo           → pasa
```

La lección se repite: **una política RLS correcta no basta si los permisos de
columna están abiertos.** Al añadir una columna escribible hay que mirar el
`grant`, no solo la política.

**Lo que el linter marca y no es un problema:**

- *Once funciones ejecutables por usuarios con sesión.* Es el diseño: son la
  API del juego, y cada una decide por dentro quién puede qué. Verificado con
  la identidad de un jugador y de la organización.
- *`hl_matches` y `hl_players` con RLS y sin políticas.* Deliberado: denegar
  por defecto. Son materia prima interna y el panel las consulta por
  `jornada_partidos()`, que decide qué se ve.
- *Protección de contraseñas filtradas desactivada.* Nuestras contraseñas son
  códigos generados al azar, que nadie elige. Comprobarlos contra
  HaveIBeenPwned no aporta nada y podría rechazar un código válido.
- *Los avisos de rendimiento* —once claves ajenas sin índice, tres índices sin
  usar, políticas permisivas duplicadas— no se tocan. Las tablas tienen entre
  12 y 900 filas: poner índices ahí es ruido, no optimización. Cuando alguna
  pase de unas decenas de miles, se mira otra vez.

## El aviso en vivo

Doce personas mirando la misma jornada tienen que verla moverse sin darle a
recargar. Lo evidente sería publicar las tablas por Realtime y escuchar los
cambios, y es justo lo que no se hace, por dos razones:

1. **Realtime manda la fila entera** a cada suscriptor, y los permisos de
   columna no aplican ahí. Publicar `leagues` habría repartido los códigos que
   acabábamos de esconder.
2. Cargar una jornada escribe 453 filas de estadísticas. Con un trigger por
   fila serían 453 mensajes a cada cliente para decir una sola cosa.

Así que se publica una tabla que no tiene nada dentro: `latidos`, con la liga,
una hora y un motivo. Los triggers son **por sentencia**, no por fila, y
nuestras escrituras son de conjunto, de modo que una jornada entera son 10
latidos en lugar de 453 mensajes. Medido: una sentencia que toca las 453 filas
deja un solo latido.

El cliente no lee el contenido del aviso más que para el motivo. Solo se entera
de que algo cambió y vuelve a pedir los datos por los caminos normales, que
respetan RLS. Por eso la alineación a ciegas sigue a ciegas: nadie recibe la
alineación de un rival por el cable.

`latidos` se lee y nada más: los permisos de escritura están revocados, para que
lo único que separe a un desconocido de un `TRUNCATE` no sea una política que
falta.

**No verificado:** el websocket de punta a punta. La política de red del entorno
donde se hizo esto bloquea `*.supabase.co`, así que la configuración del lado de
la base de datos está comprobada (publicación, política, triggers por sentencia,
identidad de réplica) pero el viaje real del mensaje se sabrá con dos navegadores
de verdad.

## El simulador

Para ver el juego entero funcionando antes de jugarlo de verdad. Alinea al azar
a los managers que no tengan once —formación al azar de las del reglamento y,
para cada hueco, un jugador activo de un club que no esté ya usado— y cruza
esas alineaciones con las estadísticas reales de una jornada ya cargada.

Dos cosas importan más que el simulador en sí:

- **No pisa nada de verdad.** Solo alinea a quien no tiene once, marca lo que
  crea con `lineups.simulada`, y `app.borrar_simulacion()` borra solo eso. En
  cuanto una persona toca un once simulado y lo guarda, deja de estar marcado y
  pasa a ser suyo. Y mientras lo esté, la pantalla de Mi Plantilla lo dice, para
  que nadie se encuentre un once que no puso sin saber por qué.
- **Comprueba, no solo pinta.** `app.comprobar_jornada(jornada)` mira ocho
  invariantes del reglamento: 11 huecos por once, un jugador por club, un
  portero por once, los subpuntos entre 8 y 16, los puntos de liga solo 3-0 o
  1-1, que gane quien más subpuntos hace, que quien tenga el club sin jugar no
  puntúe en nada, y que la clasificación cuadre con los cruces.

Probado con las jornadas 1 y 2 reales: las ocho pruebas en verde, 24 partidos
jugados frente a 24 y 35 puntos frente a 35.

La prueba del club que no jugó se ejercitó a mano, porque en esas dos jornadas
jugaron los 20: marcando al Real Madrid como que no jugó, seis managers pierden
puntos y desaparecen 84 minutos, y la comprobación sigue en verde. Es decir, la
regla se aplica de verdad y no por casualidad.

## Funciones del panel

| Función | Para qué |
|---|---|
| `jornada_partidos(jornada)` | los partidos reales de esa jornada y si están cargados |
| `cargar_resultado_partido(match_id)` | un partido: estadísticas y mantenimiento de plantillas |
| `cerrar_datos_de_club(jornada)` | puntos de liga y portería a cero, del marcador |
| `refrescar_calendario_real()` | volver a bajar el calendario para que aparezcan los marcadores nuevos |
| `simular_jornada(jornada)` | alinear al azar a quien no tenga once |
| `comprobar_jornada(jornada)` | las ocho invariantes del reglamento |
| `borrar_simulacion(jornada)` | borrar solo los onces simulados |

Todas comprueban `app.is_admin()`. Verificado ejecutándolas con la
identidad de un jugador: las tres de escritura le rechazan.

Todas se crean con `security_invoker = true`. Sin eso se ejecutarían con los
permisos del propietario y se saltarían las políticas RLS.

## API

Solo cuatro funciones son endpoint a propósito. Los ayudantes internos viven en
el esquema `app`, que PostgREST no publica.

| Función | Quién |
|---|---|
| `public_slots()` | sin sesión: lo único que se puede consultar, para pintar las plazas libres |
| `claim_slot(slot, club, nombre, codigo_liga)` | con sesión y con el código de la liga |
| `claim_admin(codigo)` | con sesión |
| `generate_brackets()` | organización |

## Lo que queda por hacer a mano

1. ~~Desactivar la confirmación por email~~ · hecho (Authentication → Sign In /
   Providers → sección *User Signups* → *Confirm email* en `off`). Sin eso, crear
   la cuenta al fichar se quedaba a medias esperando un correo que nadie iba a
   recibir, porque las direcciones son internas.
2. ~~Activar GitHub Pages~~ · hecho.
3. **Apuntar GitHub Pages a `main`.** Estuvo sirviendo la rama de trabajo
   `claude/game-ui-gameplay-focus-k22mhu` mientras `main` iba por detrás.
   Ahora que está fusionada, el enlace público debe salir de `main`: mientras
   apunte a una rama de trabajo, cualquier commit a medias se publica en el
   momento a los doce jugadores. Settings → Pages → *Branch* → `main` → `/`
   (root).
4. ~~Cambiar los dos códigos~~ · hecho. Estuvieron un tiempo escritos en este
   README, que es público: se han cambiado y ya no se documentan aquí.
5. ~~Cargar las plantillas~~ · hecho. Los 20 clubes tienen plantilla y se
   mantienen solas a partir de los box score.
6. **Faltan 11 managers** por fichar su plaza. Hasta que la fichen, sus cruces
   salen contra plazas vacías. Es lo único que bloquea el arranque.
7. ~~Cargar los resultados cada jornada~~ · ya no hace falta: lo hace el ciclo
   automático. Los botones del panel siguen ahí para cuando haya que forzar algo.
8. ~~Cuatro fichas de jugador esperan decisión~~ · hechas. Se dieron de baja las
   cinco que la API sitúa fuera de Primera (Rafa Romero → Sevilla Atlético,
   Carlos Martín → Hajduk Split, Moussa Diarra → Al-Wahda, Ibra Sow → Genoa,
   Carlos Álvarez → CF América). La regla queda puesta: si la API lo pone fuera
   de Primera, se da de baja. La ficha no se borra, y si el jugador llega a
   jugar un partido de Primera el acta lo reactiva solo.
9. **Los fichajes de este verano no están.** Van entrando solos a medida que
   juegan; el que se quiera tener antes de su debut se añade desde
   *Equipos y jugadores → Fichajes*.
10. **Descargar una copia de vez en cuando** desde *Dirección → Copias*. Es lo
   único que sobrevive a perder el proyecto. El fichero lleva los códigos
   dentro: guardarlo, no reenviarlo.
11. **Comprobar a qué rama apunta GitHub Pages** (Settings → Pages → Branch).
   Debe ser `main`. Mientras apunte a la rama de trabajo, cualquier commit a
   medias se publica al momento a los doce.

## Estado de la verificación

Comprobado ejecutando SQL con la identidad de un jugador y de la organización:

- Un jugador no puede cargar estadísticas, mover la jornada, hacerse
  administrador, renombrar el club de otro ni alinear en una jornada que no está
  en juego.
- Fichar plaza con un código de liga equivocado se rechaza, y la versión de
  `claim_slot` sin código ya no existe.
- Con la jornada abierta, un jugador solo ve su propia alineación; al cerrarla,
  ve las de todos.
- Los pesos por posición y la regla del club que no jugó dan los valores
  esperados.
- Un cruce de prueba con 4-5 en goles y 3-2 en asistencias da 7-7 en subpuntos y
  1-1 en puntos de liga, el mismo resultado que el cálculo del juego local.

**No verificado:** el flujo HTTP de alta y acceso. La política de red del entorno
donde se hizo esto bloquea `*.supabase.co`, así que no se pudo probar contra la
API real. Se sabrá en la primera alta de verdad, una vez desactivada la
confirmación por email.
