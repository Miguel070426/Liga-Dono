// Elegir jugador sin tener que elegir club antes.
//
// La regla de interfaz detrás de esto: no obligues a nadie a acordarse de algo
// que puedes enseñarle. El diseño anterior pedía el club primero, o sea pedía
// acordarse de dónde juega cada futbolista. Sabes que quieres a Laporte; no
// sabes que juega en el Athletic.
//
// Lo que se vigila es justo eso: que se pueda llegar a un jugador escribiendo
// su nombre y nada más, sin tocar el filtro de club.
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
import { fichar } from './alta.mjs';
const URL = 'http://127.0.0.1:8791/prueba.html';
const errores = [];
const check = (q, ok, extra = '') => {
  console.log(`${ok ? '✅' : '❌'} ${q}${extra ? ' · ' + extra : ''}`);
  if(!ok) errores.push(q);
};

const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 390, height: 844 } });
p.on('pageerror', e => errores.push('JS: ' + e.message));
p.on('console', m => {
  if(m.type() === 'error' && !/Failed to load resource/.test(m.text())) errores.push('CONSOLA: ' + m.text());
});
await p.route('**://highlightly.net/**', r => r.abort());   // sin red, da igual

await p.goto(URL);
// Las estadísticas se siembran antes de entrar: el juego las lee al cargar,
// así que hacerlo después no llegaría a tiempo.
await p.evaluate(() => window.__LIGA_FAKE_DB__.__conTemporada());
await fichar(p, { slot: '1', owner: 'Miguel', club: 'Deportivo Siuuu FC',
                  user: 'miguel', pass: 'contrasena1', join: 'DONO-2026' });
await p.click('nav.tabs button[data-view="plantilla"]');
await p.waitForSelector('.lineup-row', { timeout: 8000 });
await p.waitForTimeout(500);

// ── YA NO HAY QUE ELEGIR CLUB ─────────────────────────────────────────────
const antes = await p.evaluate(() => ({
  selectoresClub: document.querySelectorAll('.slotClub').length,
  selectoresJugador: document.querySelectorAll('.slotPlayer').length,
  botones: document.querySelectorAll('.slotPick').length,
  huecos: document.querySelectorAll('.lineup-row').length
}));
check('los dos desplegables encadenados ya no están',
  antes.selectoresClub === 0 && antes.selectoresJugador === 0,
  `${antes.selectoresClub} de club, ${antes.selectoresJugador} de jugador`);
check('cada hueco es un botón que abre la lista',
  antes.botones === antes.huecos && antes.huecos === 11,
  `${antes.botones} botones en ${antes.huecos} huecos`);
check('el botón es bastante grande para el dedo',
  await p.$eval('.slotPick', n => Math.round(n.getBoundingClientRect().height)) >= 44,
  await p.$eval('.slotPick', n => Math.round(n.getBoundingClientRect().height)) + ' px');
await p.screenshot({ path: 'pruebas/salida/elegir-1-huecos.png', fullPage: false });

// ── SE LLEGA A UN JUGADOR SOLO CON SU NOMBRE ──────────────────────────────
// Se busca un delantero cualquiera y se apunta su club, para comprobar
// después que se ha podido llegar a él sin haber tocado el filtro de club.
const objetivo = await p.evaluate(() => {
  const D = window.__LIGA_FAKE_DB__.__D;
  const j = D.players.find(x => x.pos === 'FW' && x.club_id === D.clubs[13].id);
  return { nombre: j.name, club: D.clubs.find(c => c.id === j.club_id).name };
});

const hueco = await p.evaluate(() => {
  const filas = [...document.querySelectorAll('.lineup-row')];
  return filas.findIndex(f => f.querySelector('.pos-tag').textContent.trim() === 'FW');
});
await p.click(`.slotPick[data-i="${hueco}"]`);
await p.waitForSelector('#selector:not(.hidden)', { timeout: 8000 });
await p.waitForTimeout(400);

const abierto = await p.evaluate(() => ({
  titulo: document.getElementById('pickTitulo').textContent.trim(),
  cuenta: document.getElementById('pickCuenta').textContent.trim(),
  filas: document.querySelectorAll('.pick-fila').length,
  filtroClubVacio: document.getElementById('pickClub').value === '',
  avisoVisible: !document.getElementById('pickAviso').classList.contains('hidden')
}));
check('se abre la lista de esa posición', /DELANTERO/i.test(abierto.titulo), abierto.titulo);
check('con todos los delanteros de la liga, no los de un club',
  abierto.filas === 60, abierto.cuenta);
check('y el filtro de club empieza sin filtrar', abierto.filtroClubVacio);
check('con datos de temporada no sale el aviso de «aún no hay»', !abierto.avisoVisible);
await p.screenshot({ path: 'pruebas/salida/elegir-2-lista.png', fullPage: false });

// Cada fila dice de dónde es y qué lleva hecho: eso es lo que sustituye a
// tener que saberse la liga.
const fila = await p.evaluate(() => {
  const f = document.querySelector('.pick-fila');
  return { nombre: f.querySelector('.pick-nom').textContent.trim(),
           sub: f.querySelector('.pick-sub').textContent.replace(/\s+/g, ' ').trim() };
});
check('cada fila dice el club del jugador', fila.sub.length > 0, fila.nombre + ' — ' + fila.sub);
check('y lo que lleva en la temporada, con los minutos',
  /\d+′ en \d+/.test(fila.sub), fila.sub);

// Ordenada por quien más juega: es lo que de verdad ayuda a decidir.
const minutos = await p.$$eval('.pick-fila .pick-min', ns =>
  ns.map(n => parseInt(n.textContent, 10)));
check('la lista viene ordenada por quien más juega',
  minutos.every((m, i) => i === 0 || minutos[i-1] >= m)
  // Si todos tuvieran los mismos minutos, «está ordenada» no diría nada.
  && new Set(minutos).size >= 3,
  `${new Set(minutos).size} valores distintos · ${minutos.slice(0, 4).join(' ≥ ')}`);

// EL CASO LAPORTE: se escribe el nombre y aparece, sin tocar el club.
await p.fill('#pickBuscar', objetivo.nombre);
await p.waitForTimeout(400);
const buscado = await p.evaluate(() => ({
  filas: [...document.querySelectorAll('.pick-fila')].map(f => ({
    nombre: f.querySelector('.pick-nom').textContent.trim(),
    sub: f.querySelector('.pick-sub').textContent.trim()
  })),
  clubSinTocar: document.getElementById('pickClub').value === ''
}));
check('escribiendo solo el nombre aparece el jugador',
  buscado.filas.some(f => f.nombre === objetivo.nombre),
  `«${objetivo.nombre}» → ${buscado.filas.length} resultado(s)`);
check('sin haber tocado el filtro de club en ningún momento', buscado.clubSinTocar);
check('y la lista te dice tú dónde juega, que es lo que no recordabas',
  buscado.filas[0].sub.includes(objetivo.club), objetivo.club);

// Se elige, y el hueco queda puesto.
await p.click('.pick-fila:not([disabled])');
await p.waitForTimeout(500);
const puesto = await p.evaluate(i => {
  const f = document.querySelectorAll('.lineup-row')[i];
  return { cerrado: document.getElementById('selector').classList.contains('hidden'),
           texto: f.querySelector('.slotPick').innerText.replace(/\s+/g, ' ').trim(),
           tieneQuitar: !!f.querySelector('.slotClear') };
}, hueco);
check('al elegir se cierra la lista', puesto.cerrado);
check('y el hueco enseña jugador, club y lo suyo sin abrir nada',
  puesto.texto.includes(objetivo.nombre) && puesto.texto.includes(objetivo.club),
  puesto.texto);
check('con su botón de quitar', puesto.tieneQuitar);

// ── LA REGLA DE UN JUGADOR POR CLUB SE VE, NO SE ADIVINA ──────────────────
const otroFW = await p.evaluate(() => {
  const filas = [...document.querySelectorAll('.lineup-row')];
  const i = filas.findIndex((f, k) => f.querySelector('.pos-tag').textContent.trim() === 'FW'
    && f.querySelector('.slotPick.vacio'));
  return i;
});
await p.click(`.slotPick[data-i="${otroFW}"]`);
await p.waitForSelector('#selector:not(.hidden)');
await p.waitForTimeout(400);
const vetos = await p.evaluate(() => {
  const vetadas = [...document.querySelectorAll('.pick-fila.vetada')];
  return { cuantas: vetadas.length,
           visibles: vetadas.every(v => v.getBoundingClientRect().height > 0),
           motivo: vetadas.length ? vetadas[0].querySelector('.pick-veto')?.textContent.trim() : null,
           desactivadas: vetadas.every(v => v.disabled) };
});
check('los del club que ya usaste salen vetados, no escondidos',
  vetos.cuantas >= 1 && vetos.visibles, vetos.cuantas + ' vetados y a la vista');
check('diciendo por qué', !!vetos.motivo && /ya tienes/.test(vetos.motivo), vetos.motivo);
check('y no se pueden pulsar', vetos.desactivadas);

// ── EL FILTRO DE CLUB SIGUE AHÍ, PARA QUIEN LO QUIERA ─────────────────────
const unClub = await p.evaluate(() => window.__LIGA_FAKE_DB__.__D.clubs[2].id);
await p.selectOption('#pickClub', unClub);
await p.waitForTimeout(400);
const filtrado = await p.evaluate(() => {
  const subs = [...document.querySelectorAll('.pick-fila .pick-sub')].map(n => n.textContent);
  return { filas: subs.length, club: window.__LIGA_FAKE_DB__.__D.clubs[2].name,
           todosDelMismo: subs.every(t => t.includes(window.__LIGA_FAKE_DB__.__D.clubs[2].name)) };
});
check('elegir club primero sigue funcionando, ahora como filtro',
  filtrado.filas > 0 && filtrado.todosDelMismo,
  `${filtrado.filas} del ${filtrado.club}`);
await p.screenshot({ path: 'pruebas/salida/elegir-3-filtrado.png', fullPage: false });

// ── SE CIERRA COMO SE ESPERA ──────────────────────────────────────────────
await p.keyboard.press('Escape');
await p.waitForTimeout(300);
check('se cierra con Escape',
  await p.evaluate(() => document.getElementById('selector').classList.contains('hidden')));

// ── SIN DATOS DE TEMPORADA (la liga de verdad, hoy mismo) ─────────────────
// Pestaña nueva y sin sembrar estadísticas, que es exactamente como está la
// liga hasta que se juegue la primera jornada. Recargar no vale: la base
// falsa vuelve a nacer y se lleva la sesión por delante.
const p2 = await b.newPage({ viewport: { width: 390, height: 844 } });
p2.on('pageerror', e => errores.push('JS (sin datos): ' + e.message));
await p2.route('**://highlightly.net/**', r => r.abort());
await p2.goto(URL);
await fichar(p2, { slot: '2', owner: 'Pask', club: 'Real Paskdrid', user: 'pask', pass: 'contrasena1', join: 'DONO-2026' });
await p2.click('nav.tabs button[data-view="plantilla"]');
await p2.waitForSelector('.lineup-row');
await p2.waitForTimeout(400);
await p2.click('.slotPick');
await p2.waitForSelector('#selector:not(.hidden)');
await p2.waitForTimeout(400);
const vacia = await p2.evaluate(() => ({
  aviso: !document.getElementById('pickAviso').classList.contains('hidden'),
  filas: document.querySelectorAll('.pick-fila').length,
  sinDatos: document.querySelectorAll('.pick-sin').length,
  primero: document.querySelector('.pick-fila .pick-nom').textContent.trim()
}));
check('sin estadísticas la lista sigue sirviendo', vacia.filas > 0, vacia.filas + ' jugadores');
check('avisa de que aún no hay números en vez de enseñar ceros', vacia.aviso);
check('y cada fila lo dice también', vacia.sinDatos === vacia.filas);

// ── EL PARTIDO DE LA JORNADA, EN CADA FILA ────────────────────────────────
// El dato que cambia cada semana. Lo que se vigila: que esté, que diga contra
// quién —un escudo de 13 px no lo decía—, que no corte la fila, y que no se
// repita cien veces cuando ya has cab por club.
await p2.click('#pickCerrar');
await p2.waitForTimeout(200);
await p.$$eval('.slotPick', ns => ns[3].click());   // un defensa: 100 opciones
await p.waitForSelector('.pick-fila');
await p.waitForTimeout(300);
const cruce = await p.evaluate(() => {
  const filas = [...document.querySelectorAll('.pick-fila')];
  const libres = filas.filter(f => !f.disabled);
  const subs = filas.map(f => f.querySelector('.pick-sub'));
  const caja = document.querySelector('.selector-lista').getBoundingClientRect();
  return {
    libres: libres.length,
    conCruce: libres.filter(f => f.querySelector('.pick-cruce')).length,
    vetadasConCruce: filas.filter(f => f.disabled && f.querySelector('.pick-cruce')).length,
    cortadas: subs.filter(s => s.scrollWidth > s.clientWidth + 1).length,
    desborde: filas.filter(f => f.getBoundingClientRect().right > caja.right + 1).length,
    texto: libres[0].querySelector('.pick-cruce').textContent.trim(),
    nombres: [...new Set(libres.map(f =>
      f.querySelector('.pick-cruce').textContent.replace(/[^\p{L}\s.]/gu, '').trim()))]
  };
});
check('cada jugador elegible enseña contra quién juega su club',
  cruce.conCruce === cruce.libres, `${cruce.conCruce} de ${cruce.libres}`);
check('y lo dice con el nombre del rival, no solo con un escudo',
  /\p{L}{3,}/u.test(cruce.texto), '«' + cruce.texto + '»');
check('el nombre del rival viene recortado para que quepa',
  cruce.nombres.every(n => n.length <= 12), cruce.nombres.slice(0, 4).join(', '));
check('ninguna fila se corta con el rival dentro', cruce.cortadas === 0,
  cruce.cortadas + ' cortadas');
check('ninguna fila desborda la caja', cruce.desborde === 0, cruce.desborde + ' filas');
check('al vetado no se le pone rival: el hueco es para el motivo',
  cruce.vetadasConCruce === 0, cruce.vetadasConCruce + ' vetadas con rival');

// Con el club ya cab el rival sube a la cabecera y sale una sola vez.
await p.selectOption('#pickClub', { label: 'Real Betis' });
await p.waitForTimeout(300);
const cab = await p.evaluate(() => ({
  enFilas: document.querySelectorAll('.pick-cruce').length,
  cabecera: document.getElementById('pickCruce').textContent.replace(/\s+/g, ' ').trim(),
  visible: !document.getElementById('pickCruce').classList.contains('hidden')
}));
check('con un club filtrado el rival no se repite en cada fila',
  cab.enFilas === 0, cab.enFilas + ' veces');
check('sale una sola vez arriba, con el nombre entero',
  cab.visible && /casa|fuera/.test(cab.cabecera) && cab.cabecera.length > 12,
  '«' + cab.cabecera + '»');
await p.screenshot({ path: 'pruebas/salida/elegir-5-cruce.png', fullPage: false });

const desborde = await p2.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('nada desborda el móvil', desborde <= 0, desborde + ' px');
await p2.screenshot({ path: 'pruebas/salida/elegir-4-sin-datos.png', fullPage: false });

await b.close();
console.log(errores.length ? '\nERRORES: ' + errores.join(' | ') : '\nERRORES: ninguno');
process.exit(errores.length ? 1 : 0);
