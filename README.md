# Liga Dono · Liga Fantasy de 12 managers

Once titulares de toda la Primera División, 8 categorías por jornada, 11
jornadas y playoffs. Hay dos versiones del juego.

## Versión en red (la buena)

`index.html` + `app.css` + `app.js` + `db.js`, pensada para publicarse en
GitHub Pages. La liga es compartida: los datos viven en Supabase y todos ven lo
mismo.

Cada manager entra con un **código** que hace de credencial, así que sirve igual
en el ordenador y en el móvil. No hay emails ni contraseñas. Quien organiza
activa el panel de dirección con un código aparte.

El reparto de permisos lo decide Postgres, no el navegador: cada uno solo puede
escribir su alineación y solo con la jornada abierta, y las estadísticas solo la
organización. Mientras la jornada está abierta **nadie ve el once de su rival**;
se destapan al cerrarla.

El esquema, las políticas y lo que queda por hacer a mano están en
[`supabase/README.md`](supabase/README.md).

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

## Versión local

`liga-fantasy (1).html`, un único archivo que funciona sin conexión guardando en
el navegador. Cada persona tiene su propia copia y sus propios datos, así que no
sirve para jugar una liga entre varios, pero se manda por WhatsApp y funciona sin
montar nada. Se mantiene tal cual.
