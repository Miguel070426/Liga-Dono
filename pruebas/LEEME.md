# Las pruebas

Baterías de navegador que ejercitan el juego de verdad —el mismo `app.js`,
`app.css` e `index.html` que se publican— con una capa de datos falsa delante.

**Viven aquí, en el repositorio, a propósito.** La versión anterior estaba en
una carpeta temporal de la máquina de trabajo y se perdió entera cuando esa
máquina se recicló: diecinueve baterías, la semilla y el sitio de pruebas. Si
no están versionadas, no existen.

## Cómo se lanzan

```sh
sh pruebas/sitio.sh                 # monta prueba.html
npx http-server -p 8791 -s .        # sirve el repositorio
node pruebas/t-escudos.mjs          # una batería
```

`prueba.html` se genera y no se versiona: es `index.html` con `pruebas/falsa.js`
cargado antes que `app.js` y sin los `?v=`. No se copia nada a otra carpeta, así
que es imposible que una prueba pase contra una versión vieja del juego — eso ya
pasó una vez y no se notó en dos días.

## Qué hay

| Archivo | Qué vigila |
|---|---|
| `falsa.js` | La capa de datos falsa. Sustituye a `db.js` entero. |
| `sitio.sh` | Monta `prueba.html`. |
| `t-escudos.mjs` | Los escudos de los clubes y el mes en las fechas. |
| `t-cabecera.mjs` | La cabecera, medida en cinco anchos. |
| `t-elegir.mjs` | Elegir jugador sin elegir club antes. |
| `capturas.mjs` | Solo retrata, no comprueba. Para enseñar cómo va quedando. |

## Cómo se escriben

- **Medir, no mirar.** «Se ve bien» no es una comprobación. `scrollWidth`
  contra `clientWidth`, píxeles de desbordamiento, rectángulos.
- **Con los datos que aprietan.** La cabecera se prueba con «Deportivo Siuuu
  FC», no con «Null City»: con un nombre corto no habría fallado nunca.
- **Los identificadores de club son los de verdad.** Si se inventaran, la
  prueba del escudo pasaría con una dirección que en producción da 404.
- **Sin red.** Aquí no hay salida a internet, así que las imágenes se
  interceptan y se sirven en local. De paso permite provocar a mano el caso
  que importa: que una imagen no llegue.
