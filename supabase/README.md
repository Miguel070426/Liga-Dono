# Liga Fantasy · base de datos

Proyecto Supabase: **`liga-fantasy`** (`kcrxekmsltxtavbujmwq`, eu-west-3)

Las migraciones de `migrations/` están ya aplicadas. La liga arranca sembrada:
12 plazas libres, 20 clubes de Primera sin plantillas, calendario de 11 jornadas
y la jornada 1 abierta.

## Cómo entra la gente

El código **es** la credencial. Al reclamar plaza, la web genera un código
(tipo `LD-7F3K-2QX9`), crea una cuenta cuya contraseña es ese código y lo
enseña una vez. Para entrar desde otro dispositivo se mete solo el código: no
hay email, ni contraseña aparte, ni plaza que recordar.

Para fichar hace falta además el **código de la liga**, que es la puerta de
entrada: sin él, cualquiera que encontrase la URL pública podría ocupar una
plaza libre. Se reparte entre los 12.

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
liga son 11 jornadas y la de verdad 38. Por defecto la 1 con la 1, pero se
puede cambiar si la liga arranca a mitad de temporada.

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

## Funciones del panel

| Función | Para qué |
|---|---|
| `jornada_partidos(jornada)` | los partidos reales de esa jornada y si están cargados |
| `cargar_resultado_partido(match_id)` | un partido: estadísticas y mantenimiento de plantillas |
| `cerrar_datos_de_club(jornada)` | puntos de liga y portería a cero, del marcador |
| `refrescar_calendario_real()` | volver a bajar el calendario para que aparezcan los marcadores nuevos |

Las cuatro comprueban `app.is_admin()`. Verificado ejecutándolas con la
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
2. **Activar GitHub Pages** en los ajustes del repo, para que todos entren por
   un enlace en lugar de repartir el archivo.
3. ~~Cambiar los dos códigos~~ · hecho. Estuvieron un tiempo escritos en este
   README, que es público: se han cambiado y ya no se documentan aquí.
4. **Cargar las plantillas** de los 20 clubes desde el panel de dirección: los
   clubes están creados pero vacíos, y hasta que tengan jugadores nadie puede
   alinear.

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
