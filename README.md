# Liga Dono · Liga Fantasy de 12 managers

Once titulares de toda la Primera División, 8 categorías por jornada, 11
jornadas y playoffs. La liga es compartida: los datos viven en Supabase y todos
ven lo mismo.

En marcha en **https://miguel070426.github.io/Liga-Dono/**

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
