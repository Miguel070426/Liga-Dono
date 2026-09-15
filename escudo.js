// El escudo de cada manager.
//
// No se guarda una imagen: se guarda la receta para dibujarla, unos 30
// caracteres como `esp|bandas|1f7a4d|f4f1e6|balon|NC`. El navegador la lee y
// pinta un SVG. Así el escudo no ocupa espacio ni gasta tráfico, se ve nítido
// igual de pequeño en una fila de la tabla que grande en la portada, y nadie
// puede subir una imagen que luego haya que moderar.
//
// Todo lo que se puede elegir está en este fichero. Lo que no esté aquí no se
// puede dibujar, y eso es a propósito: la paleta está cerrada para que ninguna
// combinación quede fea, y `leer()` descarta cualquier cosa que no reconozca
// en vez de fiarse de lo que venga de la base de datos.

// ── lo que se puede elegir ──────────────────────────────────────────────────

export const FORMAS = {
  esp: { n:'Español',  d:'M6,4 H94 V64 C94,96 72,112 50,118 C28,112 6,96 6,64 Z' },
  ing: { n:'Inglés',   d:'M6,4 H94 V70 L50,118 L6,70 Z' },
  red: { n:'Redondo',  d:'M50,10 A51,51 0 1,1 49.9,10 Z' },
  rom: { n:'Rombo',    d:'M50,2 L96,61 L50,120 L4,61 Z' },
  ita: { n:'Italiano', d:'M6,22 C6,9 20,4 50,4 C80,4 94,9 94,22 V64 C94,96 72,112 50,118 C28,112 6,96 6,64 Z' }
};

// Cada diseño devuelve lo que va DENTRO del escudo con el color secundario.
// Se dibuja recortado por la silueta, por eso las formas se salen del marco:
// así no quedan costuras en el borde.
export const PATRONES = {
  liso:    { n:'Liso',     f:()  => '' },
  vert:    { n:'Mitades',  f:(b) => `<rect x="50" y="-5" width="57" height="136" fill="${b}"/>` },
  horiz:   { n:'Franjas',  f:(b) => `<rect x="-5" y="-5" width="112" height="45" fill="${b}"/><rect x="-5" y="82" width="112" height="49" fill="${b}"/>` },
  bandas:  { n:'Bandas',   f:(b) => `<rect x="17" y="-5" width="17" height="136" fill="${b}"/><rect x="51" y="-5" width="17" height="136" fill="${b}"/><rect x="85" y="-5" width="17" height="136" fill="${b}"/>` },
  diag:    { n:'Banda',    f:(b) => `<path d="M-30,52 L58,-36 L104,10 L16,98 Z" fill="${b}"/>` },
  aspa:    { n:'Aspa',     f:(b) => `<path d="M-20,2 L10,-28 L120,82 L90,112 Z" fill="${b}"/><path d="M90,-28 L120,2 L10,112 L-20,82 Z" fill="${b}"/>` },
  cuartos: { n:'Cuartos',  f:(b) => `<rect x="50" y="-5" width="57" height="67" fill="${b}"/><rect x="-5" y="62" width="55" height="69" fill="${b}"/>` },
  galon:   { n:'Galón',    f:(b) => `<path d="M50,20 L102,74 L102,131 L50,70 L-2,131 L-2,74 Z" fill="${b}"/>` },
  jefe:    { n:'Jefe',     f:(b) => `<rect x="-5" y="-5" width="112" height="39" fill="${b}"/>` },
  palo:    { n:'Palo',     f:(b) => `<rect x="36" y="-5" width="28" height="136" fill="${b}"/>` }
};

// `CC` se sustituye por la tinta que toque. Ninguno lleva color propio: el
// contraste lo decide `dibujar()` mirando los dos colores elegidos.
export const SIMBOLOS = {
  nada:  { n:'Ninguno',  d:'' },
  balon: { n:'Balón',    d:'<g fill="none" stroke="CC" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"><circle cx="50" cy="52" r="20"/><path d="M50,42 L58.6,48.2 L55.3,58.4 L44.7,58.4 L41.4,48.2 Z"/><path d="M50,42 L50,32"/><path d="M58.6,48.2 L68.1,45.1"/><path d="M55.3,58.4 L61.2,66.5"/><path d="M44.7,58.4 L38.8,66.5"/><path d="M41.4,48.2 L31.9,45.1"/></g>' },
  estr:  { n:'Estrella', d:'<path d="M50,28 L55.9,43.9 L72.8,44.6 L59.5,55.1 L64.1,71.4 L50,62 L35.9,71.4 L40.5,55.1 L27.2,44.6 L44.1,43.9 Z" fill="CC"/>' },
  rayo:  { n:'Rayo',     d:'<path d="M58,26 L34,56 L47,56 L42,78 L66,46 L53,46 Z" fill="CC"/>' },
  corona:{ n:'Corona',   d:'<path d="M26,68 L26,38 L38,50 L50,32 L62,50 L74,38 L74,68 Z" fill="CC"/><rect x="26" y="72" width="48" height="6" fill="CC"/>' },
  torre: { n:'Torre',    d:'<path d="M30,74 L30,38 L37,38 L37,45 L44,45 L44,38 L56,38 L56,45 L63,45 L63,38 L70,38 L70,74 Z" fill="CC"/>' },
  ancla: { n:'Ancla',    d:'<g fill="none" stroke="CC" stroke-width="5" stroke-linecap="round"><circle cx="50" cy="32" r="6"/><path d="M50,38 L50,76"/><path d="M34,50 L66,50"/><path d="M28,60 A22,22 0 0,0 72,60"/></g>' },
  toro:  { n:'Toro',     d:'<path d="M33,52 C20,44 17,29 26,21 C27,32 31,42 40,47 Z" fill="CC"/><path d="M67,52 C80,44 83,29 74,21 C73,32 69,42 60,47 Z" fill="CC"/><circle cx="50" cy="58" r="16" fill="CC"/>' },
  alas:  { n:'Alas',     d:'<path d="M50,42 C40,30 24,32 15,45 C28,45 38,51 50,60 Z" fill="CC"/><path d="M50,42 C60,30 76,32 85,45 C72,45 62,51 50,60 Z" fill="CC"/>' },
  espada:{ n:'Espada',   d:'<path d="M50,20 L57,35 L57,64 L43,64 L43,35 Z" fill="CC"/><rect x="31" y="64" width="38" height="7" rx="3" fill="CC"/><rect x="46" y="71" width="8" height="15" rx="3" fill="CC"/>' }
};

// Paleta cerrada. Con un selector de color libre cualquiera se monta un fucsia
// sobre naranja; con estos doce, cualquier pareja queda decente.
export const PALETA = [
  { h:'c1443a', n:'Rojo' },      { h:'7a2233', n:'Granate' },
  { h:'e07b28', n:'Naranja' },   { h:'e8b84b', n:'Dorado' },
  { h:'1f7a4d', n:'Verde' },     { h:'2f5d9e', n:'Azul' },
  { h:'5aa9e6', n:'Celeste' },   { h:'5b3a8c', n:'Morado' },
  { h:'d96a9a', n:'Rosa' },      { h:'8a9a92', n:'Gris' },
  { h:'14231c', n:'Negro' },     { h:'f4f1e6', n:'Blanco' }
];

export const POR_DEFECTO = { forma:'esp', patron:'bandas', c1:'1f7a4d', c2:'f4f1e6',
                             simbolo:'balon', ini:'' };

// ── leer y escribir la receta ───────────────────────────────────────────────

const hex = s => /^[0-9a-f]{6}$/.test(s) ? s : null;

// Nada de lo que venga de fuera se usa sin comprobar: un texto raro guardado
// en la base de datos tiene que acabar en un escudo por defecto, no en un SVG
// roto ni en algo inyectado dentro del dibujo.
export function leer(txt){
  const p = String(txt || '').split('|');
  const ini = String(p[5] || '').toUpperCase().replace(/[^A-ZÑ0-9]/g, '').slice(0, 3);
  return {
    forma:   FORMAS[p[0]]    ? p[0] : POR_DEFECTO.forma,
    patron:  PATRONES[p[1]]  ? p[1] : POR_DEFECTO.patron,
    c1:      hex(p[2])       || POR_DEFECTO.c1,
    c2:      hex(p[3])       || POR_DEFECTO.c2,
    simbolo: SIMBOLOS[p[4]]  ? p[4] : POR_DEFECTO.simbolo,
    ini
  };
}

// Se escribe pasando por `leer`, que normaliza: así lo que sale de aquí
// siempre encaja con lo que la base de datos acepta, venga de donde venga.
export function escribir(e){
  const v = leer([e.forma, e.patron, e.c1, e.c2, e.simbolo, e.ini].join('|'));
  return [v.forma, v.patron, v.c1, v.c2, v.simbolo, v.ini].join('|');
}

// Las iniciales de un nombre de club: «Deportivo Siuuu FC» → «DS».
export function inicialesDe(nombre){
  return String(nombre || '').trim().split(/\s+/)
    .filter(p => !/^(fc|cf|cd|ud|sd|ad|ac|ca|rc|de|del|la|el|los|las)$/i.test(p))
    .slice(0, 2).map(p => p[0] || '').join('')
    .toUpperCase().replace(/[^A-ZÑ0-9]/g, '');
}

// Escudo de arranque para quien aún no tiene: distinto según el nombre del
// club, para que doce plazas sin tocar no salgan las doce iguales.
export function sugerir(nombreClub){
  const t = String(nombreClub || '');
  let n = 0;
  for(let i = 0; i < t.length; i++) n = (n * 31 + t.charCodeAt(i)) >>> 0;
  const formas = Object.keys(FORMAS), patrones = Object.keys(PATRONES);
  const simbolos = Object.keys(SIMBOLOS).filter(k => k !== 'nada');
  // El desplazamiento va con `>>>` y no con `>>`: con signo, un número grande
  // se vuelve negativo y el índice se sale de la lista. Pasaba con unos
  // nombres sí y otros no, que es la peor manera de fallar.
  const c1 = PALETA[n % PALETA.length].h;
  let c2 = PALETA[(n >>> 3) % PALETA.length].h;
  if(c2 === c1) c2 = c1 === 'f4f1e6' ? '14231c' : 'f4f1e6';
  return {
    forma:   formas[(n >>> 5) % formas.length],
    patron:  patrones[(n >>> 8) % patrones.length],
    c1, c2,
    simbolo: simbolos[(n >>> 12) % simbolos.length],
    ini:     inicialesDe(nombreClub)
  };
}

// ── dibujar ─────────────────────────────────────────────────────────────────

const luz = h =>
  0.299 * parseInt(h.slice(0,2),16) +
  0.587 * parseInt(h.slice(2,4),16) +
  0.114 * parseInt(h.slice(4,6),16);

// Cada SVG define su propio recorte y su propio filtro. Si dos escudos de la
// misma página compartieran identificador, el segundo se dibujaría con el
// recorte del primero.
let n = 0;

export function dibujar(escudo, opciones = {}){
  const e = typeof escudo === 'string' ? leer(escudo) : { ...POR_DEFECTO, ...escudo };
  const id = 'e' + (++n);
  const F = FORMAS[e.forma] || FORMAS[POR_DEFECTO.forma];
  const P = PATRONES[e.patron] || PATRONES[POR_DEFECTO.patron];
  const S = SIMBOLOS[e.simbolo] || SIMBOLOS[POR_DEFECTO.simbolo];
  const c1 = '#' + e.c1, c2 = '#' + e.c2;

  // El símbolo cruza los dos colores del diseño, así que la tinta se decide
  // por el brillo medio y lleva contorno del color contrario. Sin eso, un
  // balón blanco sobre bandas blancas desaparece.
  const medio = e.patron === 'liso' ? luz(e.c1) : (luz(e.c1) + luz(e.c2)) / 2;
  const tinta = medio > 140 ? '#14231c' : '#f4f1e6';
  const filo  = medio > 140 ? '#f4f1e6' : '#14231c';

  // Las formas que acaban en punta dejan menos sitio abajo: ahí el símbolo se
  // encoge y sube, y las iniciales suben con él.
  const AJUSTE = { esp:[1, 0], ita:[1, 0], ing:[0.9, -7], rom:[0.82, -10], red:[0.92, -4] };
  const ALTO   = { esp:[102, 70], ita:[102, 70], ing:[92, 64], rom:[88, 66], red:[96, 68] };
  const [escala, dy] = AJUSTE[e.forma] || AJUSTE.esp;
  const conSimbolo = !!S.d;
  const yIni  = (ALTO[e.forma] || ALTO.esp)[conSimbolo ? 0 : 1];
  const tamIni = conSimbolo ? 20 : 34;

  const marca = conSimbolo
    ? `<g transform="translate(0,${dy}) translate(50,52) scale(${escala}) translate(-50,-52)">${
        S.d.replace(/CC/g, tinta)}</g>`
    : '';
  const letras = e.ini
    ? `<text x="50" y="${yIni}" text-anchor="middle" fill="${tinta}"
         font-family="Oswald, Arial Narrow, sans-serif" font-weight="600"
         font-size="${tamIni}" letter-spacing="1.5">${e.ini}</text>`
    : '';

  return `<svg viewBox="-3 -3 106 130" class="escudo ${opciones.clase || ''}"
   role="img" aria-label="${opciones.alt || 'Escudo del equipo'}">
  <defs>
    <clipPath id="c${id}"><path d="${F.d}"/></clipPath>
    <filter id="f${id}" x="-30%" y="-30%" width="160%" height="160%">
      <feMorphology in="SourceAlpha" operator="dilate" radius="1.8" result="g"/>
      <feFlood flood-color="${filo}" result="t"/>
      <feComposite in="t" in2="g" operator="in" result="o"/>
      <feMerge><feMergeNode in="o"/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
    <linearGradient id="o${id}" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#fbeec0"/><stop offset="0.35" stop-color="#e3bc5c"/>
      <stop offset="0.62" stop-color="#9a7726"/><stop offset="1" stop-color="#e8cf87"/>
    </linearGradient>
    <linearGradient id="b${id}" x1="0.1" y1="0" x2="0.75" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity="0.26"/>
      <stop offset="0.45" stop-color="#fff" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#000" stop-opacity="0.10"/>
    </linearGradient>
    <radialGradient id="v${id}" cx="0.5" cy="0.42" r="0.78">
      <stop offset="0.45" stop-color="#000" stop-opacity="0"/>
      <stop offset="1" stop-color="#000" stop-opacity="0.42"/>
    </radialGradient>
  </defs>
  <g clip-path="url(#c${id})">
    <rect x="-5" y="-5" width="112" height="136" fill="${c1}"/>
    ${P.f(c2)}
    <g filter="url(#f${id})">${marca}${letras}</g>
    <rect x="-5" y="-5" width="112" height="136" fill="url(#b${id})"/>
    <rect x="-5" y="-5" width="112" height="136" fill="url(#v${id})"/>
    <path d="${F.d}" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="10"/>
  </g>
  <path d="${F.d}" fill="none" stroke="url(#o${id})" stroke-width="5.5"/>
  <path d="${F.d}" fill="none" stroke="#000" stroke-opacity="0.35" stroke-width="1"
        transform="translate(50,61) scale(1.055) translate(-50,-61)"/>
</svg>`;
}

// Lo que se usa en el juego: el escudo de un manager, con su nombre de club de
// respaldo para los que aún no se han hecho uno.
export function escudoDe(manager, opciones){
  const m = manager || {};
  const e = m.escudo ? leer(m.escudo) : sugerir(m.club_name);
  return dibujar(e, { alt: 'Escudo de ' + (m.club_name || 'la plaza'), ...opciones });
}
