#!/bin/sh
# Monta el sitio de pruebas: el juego real con la capa falsa delante.
#
# No se copia nada: se sirve el propio repositorio, así que es imposible que
# una prueba pase contra una versión vieja del juego. La anterior sí copiaba,
# y una vez se quedó con un app.js de dos días antes sin que nadie lo notara.
set -e
RAIZ=$(cd "$(dirname "$0")/.." && pwd)

# prueba.html es index.html con la capa falsa cargada antes que app.js, y sin
# los ?v= para que el navegador no guarde nada entre pruebas.
sed -e 's|<script type="module" src="app.js?v=[0-9]*"></script>|<script src="pruebas/falsa.js"></script>\n<script type="module" src="app.js"></script>|' \
    -e 's|app.css?v=[0-9]*|app.css|' \
    "$RAIZ/index.html" > "$RAIZ/prueba.html"

grep -q 'pruebas/falsa.js' "$RAIZ/prueba.html" || { echo 'ERROR: prueba.html no carga la capa falsa'; exit 1; }
grep -q 'claimEscudo'       "$RAIZ/prueba.html" || { echo 'ERROR: prueba.html no trae el selector de escudo'; exit 1; }
echo "sitio de pruebas listo en $RAIZ/prueba.html"
