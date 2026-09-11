# Liga Dono · Liga Fantasy de 12 managers

Once titulares de toda la Primera División, 8 categorías por jornada, 11
jornadas y playoffs. La liga es compartida: los datos viven en Supabase y todos
ven lo mismo.

En marcha en **https://miguel070426.github.io/Liga-Dono/**

Los resultados de cada jornada se cargan solos del box score de Highlightly:
goles, asistencias, minutos, faltas, tiros y tarjetas de los 22 jugadores de
cada partido, y del marcador los puntos de equipo y la portería a cero. Las
plantillas también se mantienen solas, con fichajes y canteranos, aunque no dan
de baja a nadie sin que una persona lo confirme.

## Cómo está montado

Una web estática (`index.html` + `app.css` + `app.js` + `db.js`) publicada en
GitHub Pages, que habla con Supabase.

Hubo antes una versión de un solo archivo que guardaba los datos en el propio
navegador. Se retiró al quedarse con un reglamento distinto: cada persona tenía
su copia y sus datos, así que no servía para jugar una liga entre varios. Sigue
en el historial de Git si alguna vez hace falta.

Cada manager entra con un **código** que hace de credencial, así que sirve igual
en el ordenador y en el móvil. No hay emails ni contraseñas. Para fichar plaza
hace falta además el código de la liga, que es lo que evita que un desconocido
que encuentre la URL ocupe un sitio. Quien organiza activa el panel de dirección
con un tercer código.

El reparto de permisos lo decide Postgres, no el navegador: cada uno solo puede
escribir su alineación y solo con la jornada abierta, y las estadísticas solo la
organización. Mientras la jornada está abierta **nadie ve el once de su rival**;
se destapan al cerrarla.

El esquema, las políticas y lo que queda por hacer a mano están en
[`supabase/README.md`](supabase/README.md).

Los códigos de acceso no se guardan en el repositorio: es público, y su historial
también. Viven solo en la base de datos (`select join_code, admin_claim_code from
leagues`).

### Que se pueda usar

Repasado contra los puntos *High* y *Critical* del checklist de
[ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill), con
una auditoría que corre en el navegador y mide lo que de verdad se pinta:

- **Contraste.** Tres colores no llegaban al 4,5:1 que necesita un texto
  normal: el rojo de los avisos de error daba 3,02 (el peor sitio para no
  leerse), la etiqueta de centrocampista 2,93 en blanco sobre ámbar, y el pie
  de página 3,28. El rojo de tarjeta se queda para rellenos y hay uno aclarado
  para texto; el ámbar mantiene su color con el texto en oscuro.
- **Foco visible.** Solo lo tenían los campos de texto. Ahora lo lleva todo lo
  que se puede accionar: comprobado tabulando por 23 controles seguidos.
- **Nombres.** Los botones que son solo un icono —la rueda de dirección, las
  flechas de jornada, las equis de borrar— no decían nada a un lector de
  pantalla. Y los desplegables del once ahora dicen «Hueco 1, portero: club».
- **Etiquetas de campo** asociadas a su campo, que es donde la gente teclea su
  código.
- **16px en el móvil.** Safari en iPhone hace zoom solo al enfocar un campo más
  pequeño, y deja la pantalla descolocada. Alinear once jugadores desde el
  móvil con eso era un suplicio.
- **24px de objetivo mínimo**: los botones pequeños se quedaban en 21.
- **Los avisos se anuncian**, no solo aparecen en una esquina.
- **Movimiento reducido**: quien lo tiene activado en su sistema no ve ninguna
  animación.

### Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | armazón y pantallas de acceso |
| `app.css` | estilos |
| `app.js` | el juego: estado, vistas y panel de dirección |
| `db.js` | lo único que habla con Supabase |
| `supabase/migrations/` | el esquema, ya aplicado |

`app.js` no sabe que Supabase existe: todo pasa por `db.js`, que se puede
sustituir por una capa falsa (`window.__LIGA_FAKE_DB__`) para probar el juego
entero sin red.
