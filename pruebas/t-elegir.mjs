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
await p.evaluate(() => window.__LIGA_FAKE_DB__.__conTemporada());
await p.reload();
await p.waitForSelector('#stepWelcome:not(.hidden)');
await p.evaluate(() => window.__LIGA_FAKE_DB__.__conTemporada());
await p.click('#goClaim');
await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
await p.selectOption('#claimSlot', '1');
await p.fill('#claimOwner', 'Miguel'); await p.fill('#claimClub', 'Deportivo Siuuu FC');
await p.fill('#claimUser', 'miguel'); await p.fill('#claimPass', 'contrasena1');
await p.fill('#claimJoin', 'DONO-2026');
await p.click('#doClaim');
await p.waitForSelector('.hero-team', { timeout: 10000 });
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
await p2.waitForSelector('#stepWelcome:not(.hidden)');
await p2.click('#goClaim');
await p2.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
await p2.selectOption('#claimSlot', '2');
await p2.fill('#claimOwner', 'Pask'); await p2.fill('#claimClub', 'Real Paskdrid');
await p2.fill('#claimUser', 'pask'); await p2.fill('#claimPass', 'contrasena1');
await p2.fill('#claimJoin', 'DONO-2026');
await p2.click('#doClaim');
await p2.waitForSelector('.hero-team', { timeout: 10000 });
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

const desborde = await p2.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('nada desborda el móvil', desborde <= 0, desborde + ' px');
await p2.screenshot({ path: 'pruebas/salida/elegir-4-sin-datos.png', fullPage: false });

await b.close();
console.log(errores.length ? '\nERRORES: ' + errores.join(' | ') : '\nERRORES: ninguno');
process.exit(errores.length ? 1 : 0);
