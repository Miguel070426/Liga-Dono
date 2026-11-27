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
formas. Y cada uno puede cambiarse la suya desde **Mi cuenta**, para no quedarse
con una que le puso otro.

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

## Tres arreglos para el móvil, medidos

Salieron de mirar el ensayo en un móvil de 390 px. Los tres eran de verdad y
los tres se comprobaron con números, no con opinión.

**1 · La clasificación no cabía.** La tabla medía 540 px dentro de una caja de
312: había que **arrastrarla 228 px de lado**, y lo que quedaba escondido eran
los **puntos**, que es lo primero que quiere ver cualquiera. Se veían G, E y P
—lo accesorio— y no se veía Pts.

Ahora en el móvil se esconden PJ, G, E, P, SF y SC, y sus números salen en una
línea pequeña debajo del nombre del club (`1 PJ · 1G 0E 0P · 6-3`), **siempre
visible**. Nada que pulsar: un dato detrás de un gesto es un dato que la mitad
de la gente no ve nunca. Quedan #, escudo, club, Dif, Pts y la racha. En el
ordenador no cambia nada, que allí sobra sitio. Medido después: **0 px de
arrastre**.

PJ se esconde porque en esta liga los doce juegan siempre las mismas: era una
columna diciendo lo mismo doce veces.

**2 · En Mi Plantilla había que bajar pantalla y media antes de poder alinear.**
Los partidos de Primera ocupaban 670 px y estaban encima, así que el primer
hueco empezaba en el **píxel 1.252** de una pantalla de 844. Abrías la pantalla
de alinear y lo primero que veías no era tu alineación. Ahora los partidos van
**debajo**: el primer hueco queda en el **píxel 528**, dentro de la primera
pantalla. La ayuda va detrás de la tarea.

**3 · La pestaña Jornada medía 2.274 px**, casi tres pantallas. Ahí los partidos
van ahora **plegados**: en esa pestaña ya no se decide nada, se mira lo que
pasó. Quedó en **1.721 px**. En Mi Plantilla siguen abiertos, porque allí sí se
decide.

Se valoró quitarlos de una de las dos pestañas y **se descartó**: hacen cosas
distintas. En Mi Plantilla están antes de jugarse, para elegir; en Jornada están
después, con el resultado y con los 22 dentro. Quitarlos de Jornada se llevaría
por delante «el partido real desglosado».

Todo esto lo vigila `t-movil.mjs`, que mide en vez de mirar.

## Mi cuenta: lo tuyo, fuera del juego

Inicio llevaba una tarjeta con el escudo, el nombre del club y la contraseña.
Son tres cosas que se tocan **una vez** y luego no vuelven a tocarse, y estaban
ocupando sitio en la pantalla que se abre cada día. Ahora viven en su propia
pantalla, a la que se entra **pulsando tu escudo de la cabecera**, que ya estaba
ahí arriba y no hacía nada.

- El escudo de la cabecera es un `<button>` de verdad, con `aria-label="Mi
  cuenta"` para quien navega a oídas, y se queda marcado mientras estás dentro.
- «Volver» te devuelve **a la pantalla donde estabas**, no a Inicio.
- El selector de escudo viene **plegado y sin montar**: sus 66.000
  combinaciones no se dibujan hasta que se piden.
- Inicio se quedó en menos de 1.200 px y ya no habla de contraseñas.

De paso salió a la luz un fallo que llevaba desde el principio: **nadie podía
cambiarse el nombre del club**. El permiso estaba dado —RLS deja escribir en tu
propia fila y el `grant` de columnas solo abre `club_name`, `owner_name` y
`escudo`— y `renameOwnClub` estaba escrito en `db.js`… y **el juego no lo
llamaba desde ningún sitio**. Un camino entero construido sin puerta. Ahora Mi
cuenta tiene los dos campos —club y tu nombre— y la cabecera se actualiza al
guardar. Si la base rechaza el cambio, el juego lo dice en vez de fingir que se
guardó: `renameOwnClub` devuelve `blocked` cuando no vuelve ninguna fila.

Y un aviso que casi se rompe: `pintarCuenta()` lleva un cortocircuito que **no
repinta mientras el selector de escudo está abierto**. Lo quité pensando que la
pantalla propia no se repintaba sola; se repinta, porque `refrescarEnVivo()`
llama a `renderAll()` sobre la vista que tengas delante. Sin ese cortocircuito,
que otro de la liga guardara su once te **borraba el escudo a medio elegir**.
Está vigilado por `t-micuenta.mjs`, que elige un escudo, provoca un refresco en
vivo y comprueba que el dibujo sigue siendo el mismo.

## El ensayo de una jornada completa

Hecho **sobre la base de datos real**, con datos reales de Primera, y deshecho
después restaurando una copia. No prueba las pantallas —eso lo hacen las 19
baterías del navegador— sino **los números**: que la cadena entera desde el acta
de un partido hasta la clasificación da lo que debe.

Cómo se montó: copia de seguridad, la jornada 1 apuntando temporalmente a la
**ronda 5** (jugada entera, 11–14 de septiembre), los 10 partidos cargados de la
API de verdad, los datos de club cerrados y los 12 onces rellenados con el
simulador. Coste: **10 llamadas** a la API.

Qué salió:

| Comprobación | Resultado |
|---|---|
| Partidos cargados | 10 de 10 · 456 fichas de jugador · 20 filas de club |
| **Goles por jugador contra los marcadores** | **29 y 29** · cuadran exactamente |
| Minutos totales | 19.922, contra los ≈19.800 de 20 equipos × 990 (la diferencia es el descuento) |
| Jugadores con minutos | 316 en 20 equipos, unos 16 por club: los 11 y los cambios |
| **Las 8 categorías de los 12 managers** | recalculadas a mano desde los datos crudos y comparadas con `manager_jornada_totals`: **12 de 12 cuadran** |
| Reparto de puntos de los 6 cruces | 6 de 6 correctos (3 al que gana, 1 y 1 si empatan) |
| Invariante de subpuntos | los 6 cumplen `total = 8 + categorías empatadas`, que es la regla del empate reparte uno a cada uno |
| Clasificación | 12 filas, 17 puntos repartidos = 5 victorias + 1 empate, y el desempate por diferencia de subpuntos bien aplicado |
| El ciclo | cerró la jornada 1, guardó su copia (425 kB con los 12 onces y los 456 datos dentro) y abrió la jornada 2 él solo |
| Restauración | las **13 tablas volvieron idénticas** a la copia previa |

Un detalle que el ensayo dejó a la vista: al usar una ronda jugada una semana
antes de que la jornada «se abriera», el ciclo marcó los 10 partidos como
adelantados. En la temporada de verdad no pasa, porque la jornada se abre antes
de que empiece su ronda. Pero enseña qué haría si el ciclo se retrasara y una
jornada naciera con partidos ya jugados: avisarlos uno por uno, y calcular el
cierre con el primer partido que quede por jugar en vez de con uno ya disputado.

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

## Los escudos de los veinte clubes

Salieron de una revisión de un amigo de Miguel que sabe de interfaces. Pedía
imágenes: escudos y fotos de jugador. Los escudos **sí**; las fotos **no**, y
conviene dejar escrito por qué.

**Los escudos no cuestan nada.** La dirección se construye con el
`highlightly_id` que ya guardábamos de cada club:

```
https://highlightly.net/soccer/images/teams/{highlightly_id}.png
```

Cero llamadas a la API, cero bytes en el repositorio, y la cuota diaria
intacta. Comprobados los veinte, uno a uno: los veinte responden 200. El
cliente ya los pide en `bootstrap` —`highlightly_id` estaba en el `grant` de
`authenticated` desde el principio— así que no hizo falta ni una migración.

Van en las filas de partido, en el partido desglosado, en la fila del once y
en el detalle de cada cruce. Detalles que importan:

- **Son decoración**, con `alt` vacío y `aria-hidden`. El nombre del club está
  al lado en todos los sitios: quien navega a oídas no tiene que oírlo dos
  veces.
- **El hueco se reserva** aunque no haya escudo, para que la fila no pegue un
  salto cuando la imagen llega tarde.
- **Si una imagen falla se esconde** y queda el nombre, que nunca se quitó. Lo
  hace un solo `addEventListener('error', …, true)` para toda la página: el
  evento `error` no burbujea, así que se escucha en captura, y así no hay un
  `onerror` por escudo.
- **Con los partidos plegados no se descarga ninguno.** `loading="lazy"` más
  el pliegue de la pestaña Jornada: veinte peticiones que la mayoría de las
  visitas no llegan a necesitar. Medido: 0 peticiones plegado, 20 al abrir.

### Por qué no hay fotos de jugador

La API que usamos **no las tiene**: `/players/{id}` devuelve el campo de
imagen vacío, y no es que falten los suplentes — también está vacío el de
Mbappé. Pedir la imagen por dirección directa da 404.

Se investigó **TheSportsDB**, que sí tiene fotos y hasta recortes con fondo
transparente. Se descartó, y no por prudencia sino por lo que dicen ellos
mismos. Sus condiciones, actualizadas el 17/09/2026: «la mayoría de nuestras
imágenes las crean nuestros usuarios», y cada jugador lleva un campo
`strCreativeCommons` cuyo valor `No` significa literalmente «no trates la
imagen como apta para reutilizar», con la instrucción de no usarlas
públicamente, webs incluidas.

**Medido en 50 jugadores de La Liga: 41 marcados `No`, 9 marcados `Yes`.** El
82% de las fotos las marca como no autorizadas quien las aloja. Pagar sus 9 $
al mes no lo cambia: sus propias condiciones dicen que la suscripción «no
otorga derechos sobre imágenes de terceros».

Aparte, su clave gratuita corta las plantillas a 10 jugadores, y sus datos de
plantilla son colaborativos y flojos: devuelve a Gordon y a Livaković como
jugadores del Barça.

La conclusión de diseño es que las fotos no hacían falta. Lo que pedía esa
revisión era **reconocer en vez de recordar** —que no haya que acordarse de
dónde juega Laporte— y eso lo resuelve el escudo. La cara era el adorno.

## La cabecera, medida en cinco anchos

Venía de un aviso de que «en el móvil hay botones que se solapan». Buscado a
ojo no aparecía, y una vez llegué a decir que no existía. Existía, y la forma
de encontrarlo fue medir en vez de mirar:

- `header.top h1` tenía `white-space:nowrap` y **ningún recorte**, así que se
  salía de su caja y se colaba por debajo de la píldora de la jornada. No
  llegaba a taparla, pero de un vistazo en un móvil son dos cosas montadas.
- El subtítulo —**tu club y tu puesto, lo único de la cabecera que cambia**—
  salía cortado en «Dono FC · 2º co…», mientras el nombre de la liga, que es
  siempre el mismo, se quedaba entero.

Ahora el título se recorta en su sitio, y por debajo de 520px encoge y tu
línea se parte en dos en vez de cortarse.

A **320px** no había arreglo por tamaño de letra: al texto le quedaban 72px
porque la píldora y los dos botones se llevaban la mitad del ancho. Se quitó
**la píldora de la jornada**, que es lo que menos aporta de los cuatro —el
número sale además en el aviso, en el selector y en la propia pestaña—. Se
pierde su destello al refrescar en vivo; a cambio caben el título y tu club.

`t-cabecera.mjs` lo vigila en 320, 360, 390, 430 y 1100px, y lo hace con el
club llamado «Deportivo Siuuu FC»: con «Null City» no habría fallado nunca.

## El mes en las fechas

El juego escribía «el viernes 9 a las 21:00» y «vie 9 · 21:00», sin mes en
ningún sitio. Con la liga empezando en octubre, nadie sabía si ese 9 era de
este mes o del siguiente.

Ahora el mes va siempre. «Hoy» y «mañana» se quedan sin fecha, que ahí no hay
nada que confundir. En las filas de partido el día y la hora van en **dos
líneas**: en una sola, con el mes dentro, la columna necesitaba veinte píxeles
más y se los quitaba a los nombres, que salían como «Atlético de …». Y el
nombre del club ahora **se parte en dos líneas antes que cortarse**, porque un
club leído a medias no se reconoce, que es justo para lo que está el escudo.

Ni siquiera valía deducir el mes del primer partido: una jornada puede caer a
caballo entre dos meses, y la jornada de pruebas lo hace a propósito.

## El límite de cambios no estaba en el reglamento

Lo encontró Miguel leyendo las reglas antes de mandárselas a sus amigos.

La regla existe y **rechaza el guardado**: `guardar_alineacion` levanta una
excepción si te pasas. No es un aviso, es un no. Y no se contaba en ninguna
parte: te enterabas al intentar guardar, con el once ya montado. La peor forma
posible de descubrir una regla.

Lo que dice ahora el reglamento, sacado de la función, no de la memoria:

- **7 cambios como mucho** por jornada, o sea **al menos 4 repiten**.
- Se compara con **el último once que pusiste de verdad**, no con la jornada
  anterior sin más: saltarse una jornada no sirve para empezar de cero.
- **La primera jornada no tiene límite**, que es cuando montas el once de
  partida.

El 7 va escrito a mano en `index.html` y eso es deuda conocida:
`leagues.max_cambios` **no es legible desde el navegador** —no está en el
`grant` de columnas de `authenticated`— y solo llega dentro de
`once_referencia`, que se pide cuando ya estás alineando, no cuando lees las
reglas. Si ese número cambia en la base, hay que cambiarlo también en el
texto. Queda anotado en un comentario junto a él.

## Ausencia no es traspaso

Al reiniciar la liga salió una lista incómoda: **55 jugadores activos que no
habían jugado ni un minuto** en las cuatro jornadas reales que llegaron a
cargarse. El automático no los quita porque su regla es «si dejas de aparecer,
te doy de baja», y estos **nunca llegaron a aparecer**: no hay desde dónde
empezar a contar.

La tentación era darlos de baja a los 55, con el argumento de que la baja se
deshace sola —`cargar_partido` vuelve a poner `activo = true` a cualquiera que
salga en un acta—. **Miguel paró eso, y tenía razón:** en esa lista estaban
Rodrygo, Ferland Mendy y Marcão, que no se han ido a ninguna parte.

La regla correcta no es «lleva cuatro jornadas sin jugar» sino «ya no está en
el club». Y eso sí se puede preguntar: `/players/{id}` devuelve
`profile.club.current`.

El reparto que funcionó:

- **Él repasó los 55** y marcó 19 como idos, con el club de destino.
- **La API resolvió los 12 que dudaba**, a dos llamadas cada uno (una para
  encontrar el id por nombre, otra para el club actual).
- **Dos se salvaron por dudar en vez de decidir**: Raúl de Tomás y Sergi
  Canós figuraban «sin dorsal» y la API los pone en su club. Si se hubieran
  dado por idos, se habrían perdido dos fichajes buenos.

Total: **28 bajas, cada una con su `motivo_baja`**, y ningún club se quedó
corto en ninguna posición.

### Aarón Ochoa era Aarón Otxoa

El hallazgo del día, y no lo encontró ninguna comprobación automática.

No se había ido a ningún sitio: **lo teníamos mal escrito**. La API lo llama
*Otxoa*, con equis. Al no coincidir el nombre, el día que jugara se habría
creado un duplicado y nuestra ficha se habría quedado a cero para siempre —
exactamente el fallo de la migración 0037, pero por una variante que
`app.clave_corta` no cubre: no es una inicial abreviada, es otra ortografía.

Se corrigió el nombre en nuestra lista. Y queda la lección: **la regla de la
inicial tapa un caso, no la familia entera**. Contra las ortografías distintas
no hay más remedio que un par de ojos que sepan de fútbol.

## El escudo con el fondo pegado

Diecinueve de los veinte escudos llegan recortados y quedan flotando sobre el
verde. El del **Racing de Santander** llega dentro de un cuadrado blanco. En
una lista de veinte, canta muchísimo: parece que se ha roto algo.

No se arregla en origen, así que se disimula: se redondea, se le deja el
blanco a propósito y se le da un poco de aire dentro, para que se lea como una
chapa y no como un fallo.

Se valoró ponerle pastilla blanca **a los veinte**, que es lo que hacen
Biwenger y FotMob, y se descartó al verlo: los otros diecinueve quedan bien
como están y habría sido estropear lo que funciona por arreglar uno.

El club se marca a mano, en `ESCUDOS_CON_FONDO`. Detectar «este PNG no tiene
transparencia» exige mirarle los píxeles, y eso el navegador no lo deja hacer
con una imagen de otro dominio. Si aparece otro igual, se añade su número.

## El jugador que nunca puntuaba (migración 0037)

El fallo más caro que ha tenido el juego, y era silencioso.

La lista de jugadores se metió a mano con los nombres completos. La API, para
algunos, usa «inicial. apellido». Al cargar un acta, `app.cargar_partido`
enlazaba por nombre normalizado, así que **«Aurélien Tchouaméni» nunca casaba
con «A. Tchouaméni»**. Lo que pasaba entonces:

1. No se reconoce al jugador que ya teníamos.
2. Se crea una ficha nueva con el nombre de la API.
3. La original se queda sin enlazar: **cero puntos, para siempre**.

Y nadie se entera. Quien la hubiera elegido vería a su jugador marcar en la
tele y un cero en el juego, con un duplicado al lado en la lista.

Eran **13 jugadores**, y no precisamente suplentes: Tchouaméni, Lo Celso,
Kumbulla, Ezzalzouli, Leandro Cabrera, Cristian Romero, Obed Vargas, Abiel
Osorio, Adrián Niño, Rockson Yeboah, Giorgi Guliashvili, Alassane Diatta y
Nathan Saliba.

### La clave corta

`app.clave_corta(text)` devuelve **inicial + último apellido**: los dos nombres
de arriba dan `a tchouameni`. Se usa como **segundo intento**, nunca como
primero, y con la misma guarda de uno a uno que ya tenía el emparejado por
nombre completo: si la clave da más de un candidato por cualquiera de los dos
lados, no se enlaza nada. Un enlace equivocado es peor que ninguno.

Una pasada de una vez arregló lo que ya estaba desemparejado: **93 fichas sin
enlazar pasaron a 67**. 25 por la clave corta y una, «Adrián Niño», a mano —
la API lo llama «Adrián Niño Heredia», que no es una inicial sino un apellido
de más, y ahí la regla no llega.

Las 67 que quedan son jugadores que no han salido todavía en ningún acta. Se
enlazarán solos cuando jueguen, y ahora con dos oportunidades en vez de una.

### El guardia va en el disparador, no en la función

El segundo intento se podría haber metido dentro de `app.cargar_partido`.
Está mejor donde está: un disparador `before insert` sobre `club_players` que
mira, **justo cuando nacería el duplicado**, si hay una ficha sin enlazar del
mismo club con la misma clave corta. Si hay exactamente una, le pone el
identificador y cancela el alta.

Así protege todos los caminos que crean jugadores, no solo la carga de actas:
también los fichajes de media temporada.

**La prueba encontró un fallo antes de que llegara a producción.** La primera
versión usaba `min(cp.id)` sobre un `uuid`, y en Postgres `min()` no existe
para ese tipo. El disparador habría reventado **en cada carga de acta**, o sea
habría roto la jornada entera. Se vio porque se probó con un alta de verdad y
su marcha atrás, no leyendo el código.

### El callejón del usuario repetido

El alta en dos pasos trajo un fallo propio. El usuario se propone a partir del
nombre, así que **dos amigos que se llamen Javier reciben los dos `javier`**.
Con diez personas entrando a la vez desde el mismo mensaje de WhatsApp, eso
pasa.

El segundo se enteraba en el **paso 2**, donde no hay campo de usuario: un
callejón sin salida. Ahora ese error devuelve al paso 1, con el aviso puesto,
el campo abierto y el cursor dentro. Lo mismo que ya se hacía cuando otro te
quita la plaza.

## El alta, en dos pasos

Era un formulario de **siete campos de golpe**, con el selector de escudo
metido entre ellos. Es la primera pantalla que ve alguien invitado a la liga,
y pedía a la vez lo aburrido y lo divertido.

Ahora son dos:

1. **Entra.** Plaza, tu nombre, contraseña y código de la liga. Cuatro cosas.
2. **Monta tu club.** Nombre y escudo, solos, sin formulario alrededor.

**La cuenta no se crea hasta el final.** Los dos pasos recogen y una sola
llamada lo hace todo al terminar. Dejarlo a medias no deja nada suelto que
arreglar después — y volver atrás no pierde lo escrito.

### El código se comprueba en el paso 1

Lo que más importa de este cambio. Antes el código de la liga se validaba al
enviar, o sea **después** de que te hubieras diseñado un escudo. Decirle a
alguien que el código está mal justo después del trabajo bonito es la peor
forma de dar un error.

Ahora el paso 1 llama a `usuario_libre`, que ya existía y comprueba las dos
cosas —código correcto y usuario libre— **sin crear nada**. Si algo falla, te
enteras antes de invertir un minuto en el escudo.

### El usuario se propone, no se pide

Era un campo más que inventarse justo cuando ya te estás inventando el del
club, y quien lo rellenaba a lo loco luego no sabía con qué entrar.

Sale de tu nombre, sin tildes: «Miguel Ángel» → `miguelangel`. Se enseña
siempre («Entrarás como **miguelangel**») para que sepas con qué entras, pero
solo se convierte en campo editable si pulsas «cambiar». Y si lo cambias a
mano, deja de reescribirse al tocar el nombre.

No se puede quitar del todo, aunque la revisión lo pedía: **este juego no usa
correo**, así que el usuario *es* la forma de entrar. Quitarlo dejaría la
puerta sin llave.

### La contraseña baja de 8 a 6

Ocho era una cifra elegida por costumbre. Para doce amigos entrando desde el
móvil, cada carácter de más es una excusa para no entrar.

Seis, no cinco, y no por gusto: **es el mínimo que permite Supabase**.
Comprobado contra el proyecto de verdad, no de memoria — cinco devuelve
`422 weak_password: "Password should be at least 6 characters."`, seis
devuelve sesión. Las dos cuentas de usar y tirar de esa prueba se borraron.

### Detalles

- **El aviso en rojo se va al escribir.** Dejarlo puesto cuando ya has
  corregido el fallo hace dudar de si lo has corregido.
- **Si alguien te quita la plaza mientras eliges escudo**, el error te
  devuelve al paso 1, que es donde se eligen las plazas, con la lista
  recargada.
- `MIN_CLAVE`, `revisaClave` y `usuarioSugerido` viajan **dentro del objeto
  `DB`**, no solo como exportaciones sueltas: en las pruebas `app.js` recibe
  una capa falsa y `db.js` no se carga, así que lo que no esté ahí dentro no
  existe allí.

Lo vigila `t-alta.mjs`. Y el alta se hace desde `pruebas/alta.mjs`, un
ayudante común: estaba repetida en cinco baterías y este cambio las habría
roto las cinco.

## Elegir jugador: reconocer en vez de recordar (migración 0036)

Era el fallo de diseño más caro del juego y llevaba ahí desde el principio.

Para poner a alguien en tu once había que elegir **primero el club**, y solo
entonces se desbloqueaba el desplegable de jugadores de ese club. Eso obliga a
recordar dónde juega cada futbolista. Y no es así como funciona la cabeza de
nadie: sabes que quieres a Laporte, no sabes que juega en el Athletic.

La regla que se aplicó es la de **reconocer antes que recordar**: no obligues a
nadie a acordarse de algo que puedes enseñarle.

Ahora cada hueco es un botón que abre la lista completa de esa posición, con
buscador. Escribes «Laporte» y aparece, con su escudo, su club y lo que lleva
hecho. **El club sigue estando**, pero como filtro opcional dentro de la lista,
no como peaje obligatorio — y ahí tiene trabajo de verdad: «esta jornada quiero
a alguien del Betis, que juega en casa» es una forma legítima de elegir.

Lo que la lista tiene que resolver, y cómo:

- **Son muchos.** 190 defensas, 170 delanteros, 160 centrocampistas. Sin
  buscador la lista no sirve, así que va lo primero.
- **Sigue habiendo un jugador por club.** Los de clubes ya usados salen **en
  gris y a la vista**, con el motivo («ya tienes a X»), nunca escondidos. Si
  desaparecieran, buscarías a tu jugador, no lo encontrarías y pensarías que
  falta de la base en vez de entender la regla. Lo mismo para un club sacado
  de la jornada.
- **Ordenada por quien más juega.** Es lo que de verdad ayuda: un jugador con
  40 minutos en toda la liga es un suplente, y eso no se deduce de que no haya
  marcado. Sin datos cae al alfabético, que es lo correcto — cualquier otro
  orden sería una opinión disfrazada de dato.
- **El buscador no se enfoca solo en el móvil.** Levantaría el teclado encima
  de la lista antes de que hayas visto lo que hay, que es justo lo que se
  quería enseñar. En el ordenador sí.

### No hay «puntos por jugador», y no se inventan

La revisión pedía un resumen de puntos por jugador. En esta liga **eso no
existe**: los puntos son de tu club y salen de comparar tus ocho categorías con
las del rival. Un delantero no vale 12 puntos; aporta goles, que cuentan o no
según lo que haya hecho el delantero del otro.

Poner un número ahí habría sido inventarse un dato con pinta de oficial. Lo que
se enseña es lo que el jugador **hizo**, en crudo: `3⚽ 1🎯 2🟨 · 540′ en 6`.
Los minutos van siempre, porque son el dato que más salva al elegir.

La migración **0036** crea `player_season_stats`, que suma
`player_jornada_stats` por jugador. Va con `security_invoker = true` a
propósito: se lee con los permisos de quien pregunta. Aquí es seguro porque la
tabla de debajo ya es legible por `authenticated` con `using (true)` —son datos
de partidos reales, no alineaciones—. Una vista con derechos de dueño encima de
una tabla con RLS es justo la forma de colar datos que la política pretendía
filtrar, y eso ya estuvo a punto de pasar con `clubes_excluidos`.

**Hoy la vista devuelve 0 filas**, porque la liga no ha empezado. La lista lo
dice («aún no hay estadísticas») en vez de enseñar ceros, que parecerían malos
jugadores en vez de ausencia de datos.

### De paso

- **Dos avisos que decían lo mismo.** `validate` contaba por separado los
  clubes sin asignar y los jugadores sin elegir. Con dos desplegables eran dos
  pasos; ahora eliges jugador y el club viene con él, así que salían los dos
  mensajes con el mismo número. Se quedó uno.
- **`input[type=search]` no estaba en la lista de campos con estilo** y el
  buscador salía con el fondo blanco del navegador en medio de una pantalla
  oscura. También se ha estilado la cruz de limpiar.
- **`POS_LABEL` va en plural** porque encabeza un bloque del once, y para un
  hueco suelto hacía falta el singular: «Elegir defensas» para un hueco suena a
  que caben varios. Se añadió `POS_UNO`.

Lo vigila `t-elegir.mjs`, que comprueba lo que de verdad importa: que se llega
a un jugador escribiendo solo su nombre y **sin haber tocado el filtro de club
en ningún momento**.

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

## Apuntado para después de la jornada 1: datos del jugador al elegirlo

Pedido por Miguel el 25/11/2026, **a hacer entre la jornada 1 y la 2**, no
antes: faltaban dos días para el arranque y tocar la pantalla de alinear justo
cuando entran diez personas nuevas es buscarse el problema.

El porqué: la pantalla de elegir jugador es donde se juega el juego, y hoy solo
enseña un total de temporada. No contesta la pregunta que uno se hace al
elegir, que es **«¿va a jugar el domingo?»**. Y en esta liga eso pesa más que
los goles: un jugador que no juega da **cero en las ocho categorías**, no poco.

Por orden de valor:

1. **La tira de las últimas cinco jornadas.** Cinco marcas: titular (60 min o
   más), suplente que entró, no jugó. De un vistazo separas al fijo del que
   calienta banquillo. Sale de `player_jornada_stats.minutes`, sin coste de
   API.
2. **El partido que le toca esa jornada**, con casa o fuera. Es lo que más
   cambia una decisión, y alimenta dos categorías directas —puntos de equipo y
   portería a cero—. Los partidos ya están cargados en `partidosCache`.
3. **Medias por jornada en vez de totales.** Para decidir importa lo esperable
   en *una* jornada, no el acumulado: compara mal un «3 goles» de seis
   partidos con otro de dos.
4. **Avisos**: «lleva 3 jornadas sin jugar», «su club no juega esta jornada».

### Lo que NO se puede recuperar

Al reiniciar la liga se borró `player_jornada_stats`, y con ella el detalle de
minutos partido a partido de las seis rondas que llegaron a cargarse. Sobrevive
`club_players.ultima_aparicion`, así que hoy solo se puede decir «última vez
que jugó: 8 nov».

Volver a cargar esas rondas costaría unas 60 llamadas y **corrompería la liga**:
los datos entrarían etiquetados con números de jornada que ahora apuntan a
otros fines de semana. No se hace.

Conclusión: la tira de cinco empieza a decir algo **desde la jornada 2** y está
completa hacia la 5 o la 6. Por eso se hace entonces y no antes.

### La trampa de diseño

Las filas del selector **ya van justas a 390 px** — se midió al construirlo. Si
se meten cuatro datos más por fila, el remedio es peor que la enfermedad. La
tira va en puntos diminutos y el rival en letra pequeña, **midiendo el
desbordamiento**, y si no cabe se mueve a una ficha que se abre al pulsar el
nombre.

## Lo que queda por hacer a mano

1. ~~Desactivar la confirmación por email~~ · hecho (Authentication → Sign In /
   Providers → sección *User Signups* → *Confirm email* en `off`). Sin eso, crear
   la cuenta al fichar se quedaba a medias esperando un correo que nadie iba a
   recibir, porque las direcciones son internas.
2. ~~Activar GitHub Pages~~ · hecho.
3. ~~Apuntar GitHub Pages a `main`~~ · hecho y comprobado el 25/11. No hizo
   falta tocar nada: el despliegue número 46 salió de `main` con el commit
   correcto, así que ya estaba bien apuntado. Se comprobó por la API de
   GitHub (`head_branch: main`, `conclusion: success`) y no abriendo la web,
   porque el proxy del contenedor tiene bloqueado `github.io`.
4. ~~Cambiar los dos códigos~~ · hecho. Estuvieron un tiempo escritos en este
   README, que es público: se han cambiado y ya no se documentan aquí.
5. ~~Cargar las plantillas~~ · hecho. Los 20 clubes tienen plantilla y se
   mantienen solas a partir de los box score.
6. **Faltan 10 managers** por fichar su plaza (25/11). Ya están dentro Miguel
   (plaza 1, *Null City*, sin once todavía) y Vallecillos (plaza 2, *Real
   Tabardillo*, con su once puesto). Hasta que fichen el resto, sus cruces
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
11. ~~Comprobar a qué rama apunta GitHub Pages~~ · era lo mismo que el punto 3,
   y está comprobado.
12. **Borrar las dos cuentas de prueba sueltas.** Son `uprueba@ligadono.app`
   (19 sep) y `zz-prueba-longitud@ligadono.app` (9 oct). Las dos tienen cero
   plazas y cero onces, y en `public` lo único que cuelga de una cuenta es
   `managers.user_id`, así que borrarlas no toca nada del juego. Se intentó el
   25/11 y no salió: Supabase pide confirmación al dueño del proyecto antes de
   ejecutar un borrado, y la pregunta se quedó sin respuesta. Ese día el panel
   tenía además una incidencia abierta. No corre prisa.
13. **Activar la protección de contraseñas filtradas.** Sigue desactivada
   (comprobado el 25/11). Está en *Authentication → Sign In / Providers*, no
   en *Database → Policies*, que es otra cosa con el mismo nombre. La ruta
   directa es `/project/<id>/auth/providers`, y si la han movido, con Ctrl+K y
   escribir «leaked» se llega. Comprueba contra una base pública de
   contraseñas robadas; no ve la contraseña de nadie, compara una huella. No
   revisa hacia atrás, así que solo protege a quien se dé de alta después.

## No publicar con la jornada abierta

El juego es una página estática: el navegador se baja el programa al entrar y
lo deja corriendo en la pestaña. Si se publica una versión nueva mientras
alguien tiene el juego abierto, esa persona sigue con la copia vieja hasta que
cierre y vuelva a entrar. No se le rompe nada —el `?v=` del `index.html` evita
que se mezclen versiones de los archivos—, simplemente no se entera del
cambio. Miguel se lo encontró el 25/11: tuvo que salir y volver a entrar para
ver el partido de la jornada en la lista.

La regla, decidida entre los dos, es la aburrida: **de viernes por la mañana
hasta que cierre la jornada no se publica nada.** Los cambios se acumulan y
entran entre jornadas, cuando nadie está dentro. Cuesta cero y quita el
problema de en medio.

La alternativa era un aviso dentro del juego —«hay una versión nueva, recarga»—
y se descartó a propósito: es media hora de trabajo y una pieza más que puede
fallar justo la semana del estreno. Queda apuntada por si algún día hace falta
publicar de verdad con gente jugando.

Lo que sí aguanta una versión nueva es la sesión: la identificación vive en el
navegador y no depende del programa. Al recargar no te pide la contraseña otra
vez. Comprobado el 25/11.

## La liga va a ser de 6, no de 12 (27/11)

Miguel no llegó a doce amigos y decidió no esperar más. La liga será de **6
managers, ida y vuelta, con playoff al que pasan los cuatro primeros**. Los
dos últimos se cruzan entre ellos para que no se queden sin jugar.

Las cuentas: 10 jornadas de liga regular, 3 de semifinales, 3 de final. Son
16 jornadas, de la 14 de Primera a la 30 más o menos. Cabe de sobra, la Liga
llega a la 38 — el límite de 11 jornadas que figuraba antes era una elección,
no un tope.

**Nada de esto está construido.** Lo que hay montado es para 12: el calendario
son 66 cruces metidos una vez a mano (no hay función que lo regenere) y
`generate_brackets()` tiene el 8 y el 4 escritos dentro. Hace falta:

1. Un generador de calendario para N equipos, con ida o ida y vuelta.
2. Ajustar las plazas al número elegido, sin poder tocar una ya fichada.
3. Generalizar el playoff a cuántos pasan arriba y cuántos abajo.

El orden importa: el calendario desbloquea arrancar, el playoff no hace falta
hasta febrero. Montar el playoff ahora es construir en caliente una pieza que
nunca se ha ejecutado y que no se necesita en tres meses.

La regla que hay que decirle al grupo: **el número se cierra el día del
arranque**. El calendario se construye entero al empezar, así que si entra
alguien en la jornada 4 hay que rehacerlo y se pierde lo jugado.

## El playoff: al mejor de tres, y un empate sin resolver

Cómo está montado, comprobado leyendo `generate_brackets()` y la vista
`playoff_series_state`:

- Cada eliminatoria son **tres partidos y gana quien llegue a dos**.
- Los partidos 1 y 3 son en casa del mejor clasificado, el 2 en casa del peor.
  Si la serie se decide en dos, el tercero no se juega.
- Cada partido se gana por subpuntos (`playoff_games.home_sub` contra
  `away_sub`), que es quien se lleva más de las ocho categorías esa jornada.

**El agujero que tenía:** la vista solo cuenta victorias. Un partido empatado
—cuatro categorías y cuatro— no sumaba a nadie, así que una serie podía
acabar 1-1, o 0-0 con los tres empatados, y quedarse sin ganador.

**Resuelto el 27/11 por Miguel: en el playoff, un 4-4 lo gana el que juega en
casa.** Se había propuesto antes que pasara el mejor clasificado, y la suya es
mejor: aquello era un desempate de despacho y esto se decide en el campo. Y
como los partidos 1 y 3 son en casa del mejor clasificado, el empate le
favorece en dos de los tres, así que quedar primero en la liga regular pasa a
tener un premio real. Con esto todos los partidos tienen ganador y ninguna
serie puede quedarse atascada.

En la **liga regular** el 4-4 sigue siendo empate con su punto para cada uno,
que es como funciona el fútbol: en liga se empata, en eliminatoria no.

**Los tres partidos se juegan siempre**, aunque la serie ya esté decidida 2-0.
Decisión suya y con una ventaja práctica: cada ronda son 3 jornadas pase lo
que pase, así que el calendario es fijo en vez de depender de los resultados.
El coste es que el tercer partido de una serie resuelta no decide nada.

### El cuadro, con 6 equipos

| Fase | Quién juega | Jornadas |
|---|---|---|
| Liga regular | los 6, ida y vuelta | 10 |
| Ronda 1 | 1º-4º · 2º-3º · 5º-6º | 3 |
| Ronda 2 | Final (ganadores) · 3º y 4º puesto (perdedores) | 3 |

Total **16 jornadas**. El 5º y el 6º terminan tres jornadas antes que el resto:
juegan su cruce mientras los otros disputan las semifinales y ahí acaba su
temporada. Es deliberado —ponerles la serie en la ronda 2 los dejaría parados
justo al acabar la liga regular, que es peor— pero hay que avisarles.

## El calendario de 6, construido (27/11)

Dos piezas, a propósito separadas:

- **`app.rueda(n)`** no toca ninguna tabla y devuelve solo números: quién
  juega contra quién a una vuelta, por el método del círculo. Vive aparte
  justo para poder probarla con 4, 6, 8, 10 y 12 equipos sin inventarse
  plazas. Se verificó que con todos ellos nadie se enfrenta a sí mismo, nadie
  juega dos veces la misma jornada, se dan todas las parejas exactamente una
  vez, y el reparto de casa y fuera es el mejor posible (con n-1 jornadas,
  que son impares, lo máximo es que difieran en uno).

  La primera versión pasaba todas esas pruebas y aun así estaba mal: dejaba al
  equipo 0 jugando las cinco jornadas de ida fuera de casa. Se vio midiendo,
  no leyendo. Ahora el local se elige sobre la marcha, el que menos veces lo
  ha sido.

- **`public.generar_calendario(ida_vuelta)`** la aplica a las plazas reales.
  **Borra el calendario entero**, así que lleva cerrojo: se niega si hay un
  solo dato de jornada jugada o una serie de playoff creada. Probado de
  verdad, fingiendo una liga en marcha: se negó y el calendario quedó intacto.

Resultado para la liga: 30 partidos en 10 jornadas, cada pareja dos veces, una
en cada campo. Las jornadas 1 a 10 van a las rondas 14 a 22 y 24 de Primera.

## Auditoría antes del estreno (27/11)

Con la liga ya de seis, se repasó qué había quedado descolgado del cambio
desde doce. Lo limpio: sin alineaciones ni huecos huérfanos, seis plazas
correlativas, cada jornada con su ronda real cargada.

Lo que estaba roto y se arregló:

1. **El pie de la clasificación anunciaba «1º-8º» y «9º-12º»** en una liga de
   seis. Lo veía cualquiera que abriese la pestaña. Ahora el número vive en
   `leagues.playoff_arriba` (que sí se puede leer, no es secreto) y la
   pantalla lo pinta: «1º-4º» y «5º-6º».
2. **`generate_brackets()` reventaba** con 6 equipos buscando al 7º y al 8º,
   con el mensaje `null value in column low_id violates not-null constraint`.
   No se generalizó —eso es trabajo de enero— pero ahora avisa en cristiano y
   no deja nada a medias. Comprobado.

Y se pasó la base de pruebas de 12 managers a 6, para que a partir de ahora
las baterías corran contra la liga de verdad. Las cuatro siguen en verde.

## La ventaja de campo en el playoff son dos cosas, no una

Decisión de Miguel el 27/11, cuando se le enseñó que el reglamento ya tenía un
plus para el local y él acababa de añadir otra regla: **se quedan las dos.**

- El local de cada partido recibe el plus en cada categoría: +1 gol,
  +1 asistencia, +2 tarjetas, +3 puntos de equipo, +2 portería a cero,
  +3 faltas, +45 minutos, +2 tiros.
- Y si aun así los subpuntos quedan empatados, **el partido lo gana el local**.

Las dos premian lo mismo: haber quedado arriba en la liga regular, porque los
partidos 1 y 3 de cada serie se juegan en casa del mejor clasificado. Ya está
escrito en el reglamento del juego.

Queda pendiente que los subpuntos del playoff se cargan **a mano** desde el
panel: nadie los calcula solo. Para febrero.

## Dos cosas que se vieron leyendo el ciclo (27/11)

**Quien no pone once no pierde: su cruce no se juega.** `fixture_results`
marca `played` solo si los DOS equipos tienen alineación, y `standings` cuenta
únicamente los `played`. Así que una plaza sin once no regala una goleada al
rival: el partido entero desaparece de la clasificación. Durante la mañana del
27 se le dijo a Miguel varias veces que se perdía 8-0, y era falso.

El daño real de empezar con plazas vacías es otro, y es peor de explicar: esos
cruces no se juegan nunca. En una liga a ida y vuelta eso deja a unas parejas
vistas dos veces y a otras una sola, y la tabla queda descuadrada para
siempre. No hay forma de recuperarlos sin rehacer el calendario.

**El ciclo se cree que la última jornada es la 11.** Lleva escrito
`if j >= 11 then ... 'la jornada 11 es la última'`, de cuando la liga era de
doce managers a una vuelta. Ahora la última es la 10. No rompe nada —al
terminar la 10 pasaría a la 11, no encontraría ronda asignada y se pararía
sola— pero la liga se quedaría enseñando una «jornada 11» vacía en vez de
anunciar que la liga regular ha terminado. Hay que arreglarlo cuando se
generalice el playoff, que es el mismo trabajo: el ciclo tiene que saber
cuándo acaba la liga regular y empezar las eliminatorias.

## La liga se retrasa una semana (27/11)

El 27 de noviembre, con la jornada 14 empezando esa misma noche, solo había
2 de 6 plazas fichadas. Miguel decidió retrasar el arranque al **viernes 4 de
diciembre a las 21:00** para hacerlo con los seis y con tiempo.

El cambio fue correr el mapeo una posición: las jornadas 1 a 10 pasaron de las
rondas 14-22 y 24 a las **15-22, 24 y 25**. Nada más. Los 30 partidos del
calendario van por número de jornada, no por ronda de Primera, así que no se
tocaron; el once que ya tenía guardado un manager para la jornada 1 siguió
valiendo; y no se había cargado ni un resultado, así que no quedó nada a
medias. Comprobado después: 0 estadísticas, 0 partidos de la ronda 14
cargados, 30 partidos en pie y las diez rondas con calendario real.

La decisión fue suya y era la buena. Lo que estaba en juego no era empezar
tarde, era empezar torcido: los tres cruces de una jornada con plazas vacías
no se juegan nunca, y en una liga a ida y vuelta eso deja a unas parejas
vistas dos veces y a otras una sola.

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
