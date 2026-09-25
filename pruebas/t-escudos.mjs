// Los escudos de los clubes de Primera, y el mes en las fechas.
//
// Las imágenes vienen de fuera y desde aquí no hay salida a internet, así que
// se interceptan y se sirven en local. Además de hacer la prueba rápida y
// siempre igual, permite provocar a mano el caso que importa: que una imagen
// no llegue y el nombre del club siga ahí.
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
const URL = 'http://127.0.0.1:8791/prueba.html';
const errores = [];
const check = (q, ok, extra = '') => {
  console.log(`${ok ? '✅' : '❌'} ${q}${extra ? ' · ' + extra : ''}`);
  if(!ok) errores.push(q);
};

// Un PNG de 1×1 válido, que es cuanto hace falta para que el navegador dé la
// imagen por cargada.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64');

const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 390, height: 844 } });
p.on('pageerror', e => errores.push('JS: ' + e.message));
// El 404 del Barça lo provoca esta prueba, así que su queja en consola no
// cuenta como fallo. Cualquier otra sí.
p.on('console', m => {
  if(m.type() === 'error' && !/Failed to load resource/.test(m.text())) errores.push('CONSOLA: ' + m.text());
});

// Todos los escudos menos el del Barça, que se deja fallar a propósito.
const pedidas = [];
await p.route('**://highlightly.net/**', route => {
  const u = route.request().url();
  pedidas.push(u);
  if(u.includes('450963')) return route.fulfill({ status: 404, contentType: 'text/plain', body: 'no está' });
  route.fulfill({ status: 200, contentType: 'image/png', body: PNG });
});

await p.goto(URL);
await p.waitForSelector('#stepWelcome:not(.hidden)');
await p.click('#goClaim');
await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
await p.selectOption('#claimSlot', '1');
await p.fill('#claimOwner', 'Miguel'); await p.fill('#claimClub', 'Null City');
await p.fill('#claimUser', 'miguel'); await p.fill('#claimPass', 'contrasena1');
await p.fill('#claimJoin', 'DONO-2026');
await p.click('#doClaim');
await p.waitForSelector('.hero-team', { timeout: 10000 });
await p.waitForTimeout(600);

// ── EL MES EN LAS FECHAS ──────────────────────────────────────────────────
const MESES = 'enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre';
const aviso = await p.textContent('#globalBanner');
check('el aviso de cierre dice el mes',
  new RegExp(`(hoy|mañana|de (${MESES}))`, 'i').test(aviso),
  (aviso.match(new RegExp(`(hoy a las [\\d:]+|mañana a las [\\d:]+|\\d+ de (?:${MESES})[^.]*)`, 'i')) || ['?'])[0].trim());

await p.click('nav.tabs button[data-view="jornada"]');
await p.waitForTimeout(500);
const horas = await p.$$eval('.pl-cuando', ns => ns.map(n => n.textContent.replace(/\s+/g, ' ').trim()));
check('hay partidos en la lista', horas.length === 10, horas.length + ' partidos');
const sinMes = horas.filter(h => !/\b(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\b/.test(h));
check('todas las filas de partido llevan el mes', sinMes.length === 0,
  sinMes.length ? 'sin mes: ' + sinMes.join(', ') : horas[0]);

// La jornada de prueba cruza dos meses a propósito: si el mes se dedujera de
// un solo partido, aquí se vería.
const meses = new Set(horas.map(h => (h.match(/\b(ene|feb|mar|abr|may|jun|jul|ago|sep|oct|nov|dic)\b/) || [])[1]));
check('y cada partido lleva el suyo, no el del primero', meses.size >= 2,
  [...meses].join(' y '));

// ── CON LOS PARTIDOS PLEGADOS NO SE PIDE NINGUNA IMAGEN ───────────────────
// En Jornada los partidos vienen plegados, y `loading="lazy"` hace que los
// veinte escudos no se descarguen hasta que se abren. No es un detalle: son
// veinte peticiones que la mayoría de las visitas no llegan a necesitar.
check('con los partidos plegados no se pide ni un escudo', pedidas.length === 0,
  pedidas.length + ' peticiones');

await p.click('#partidosPliegue > summary');
await p.waitForTimeout(1200);
check('al abrirlos se piden los veinte', pedidas.length === 20, pedidas.length + ' peticiones');

// ── LOS ESCUDOS EN LOS PARTIDOS ───────────────────────────────────────────
const esc = await p.$$eval('.partidos .esc-club', ns => ns.map(n => ({
  src: n.getAttribute('src'), oculto: n.classList.contains('sin-carga')
})));
check('cada partido enseña los dos escudos', esc.length === 20, esc.length + ' escudos en 10 partidos');
check('y la dirección se construye con el identificador del club',
  esc.every(e => /highlightly\.net\/soccer\/images\/teams\/\d+\.png$/.test(e.src)),
  esc[0] ? esc[0].src.split('/').pop() : '—');
check('sin repetir el mismo escudo en dos clubes',
  new Set(esc.map(e => e.src)).size === 20, new Set(esc.map(e => e.src)).size + ' distintos');

// ── SI UNA IMAGEN NO LLEGA, EL NOMBRE SIGUE ───────────────────────────────
const roto = await p.evaluate(() => {
  const img = [...document.querySelectorAll('.partidos .esc-club')].find(i => i.src.includes('450963'));
  const eq = img && img.closest('.pl-eq');
  return { escondido: img ? img.classList.contains('sin-carga') : null,
           ancho: img ? Math.round(img.getBoundingClientRect().width) : null,
           texto: eq ? eq.innerText.trim() : null };
});
check('el escudo que no carga se esconde', roto.escondido === true);
check('y no deja un hueco roto en la fila', roto.ancho === 0, roto.ancho + ' px');
check('y el nombre del club sigue estando', /Barcelona/.test(roto.texto || ''), roto.texto);

// ── EL VISITANTE, PEGADO AL MARCADOR ──────────────────────────────────────
const orden = await p.evaluate(() => {
  const f = document.querySelector('.partidos .pl-fila');
  const izq = f.querySelector('.pl-eq:not(.pl-eq-der)');
  const der = f.querySelector('.pl-eq.pl-eq-der');
  const x = n => n.getBoundingClientRect();
  return {
    izqEscudoAntes: x(izq.querySelector('.esc-club')).left < x(izq.querySelector('.pl-nom')).left,
    derEscudoDespues: x(der.querySelector('.esc-club')).left > x(der.querySelector('.pl-nom')).left
  };
});
check('en el local el escudo va delante del nombre', orden.izqEscudoAntes);
check('y en el visitante detrás, mirando al marcador', orden.derEscudoDespues);

await p.screenshot({ path: 'pruebas/salida/escudos-jornada.png', fullPage: false });

// ── EL ESCUDO EN LA FILA DEL ONCE ─────────────────────────────────────────
await p.click('nav.tabs button[data-view="plantilla"]');
await p.waitForSelector('.lineup-row', { timeout: 8000 });
await p.waitForTimeout(400);

const vacio = await p.$$eval('.lineup-row .esc-hueco', ns => ns.map(n => n.innerHTML.trim()));
check('sin jugador elegido el hueco del escudo está vacío pero reservado',
  vacio.every(v => v === ''), vacio.filter(v => v).length + ' con escudo');
const reserva = await p.$eval('.lineup-row .esc-hueco',
  n => Math.round(n.getBoundingClientRect().width));
check('y el hueco mide lo mismo que medirá el escudo', reserva >= 18, reserva + ' px');

// Se elige un jugador del Real Madrid desde la lista y su escudo tiene que
// aparecer en la fila.
await p.click('.lineup-row .slotPick');
await p.waitForSelector('#selector:not(.hidden)', { timeout: 8000 });
await p.waitForTimeout(300);
await p.fill('#pickBuscar', 'Real Madrid');
await p.waitForTimeout(400);
await p.click('.pick-fila:not([disabled])');
await p.waitForTimeout(500);
const puesto = await p.evaluate(() => {
  const img = document.querySelector('.lineup-row .esc-hueco .esc-club');
  return img ? img.getAttribute('src') : null;
});
check('al elegir jugador aparece el escudo de su club en la fila',
  !!puesto && puesto.includes('461175'), puesto ? puesto.split('/').pop() : 'ninguno');

// La fila del once es de una sola línea en todos los anchos: con el selector
// ya no hay un segundo desplegable que bajarse en el móvil.
const unaLinea = () => {
  const r = document.querySelector('.lineup-row');
  const b = r.getBoundingClientRect();
  const dentro = [...r.children].every(c => {
    const cb = c.getBoundingClientRect();
    return cb.top >= b.top - 1 && cb.bottom <= b.bottom + 1;
  });
  return { dentro, alto: Math.round(b.height) };
};
const movil = await p.evaluate(unaLinea);
check('en el móvil la fila del once cabe en una línea', movil.dentro, movil.alto + ' px');
await p.setViewportSize({ width: 1100, height: 900 });
await p.waitForTimeout(400);
const orde = await p.evaluate(unaLinea);
check('y en el ordenador también', orde.dentro, orde.alto + ' px');
await p.setViewportSize({ width: 390, height: 844 });
await p.waitForTimeout(400);

// ── NINGÚN NOMBRE DE CLUB SE CORTA ────────────────────────────────────────
await p.click('nav.tabs button[data-view="jornada"]');
await p.waitForTimeout(500);
const cortados = await p.$$eval('.partidos .pl-nom', ns => ns
  .filter(n => n.scrollWidth > n.clientWidth + 1)
  .map(n => n.textContent.trim()));
check('ningún nombre de club sale cortado', cortados.length === 0,
  cortados.length ? cortados.join(', ') : 'los 20 enteros');
const nombres = await p.$$eval('.partidos .pl-nom', ns => ns.map(n => n.textContent.trim()));
check('y se leen enteros, con su «de» y todo',
  nombres.includes('Atlético de Madrid') && nombres.includes('Racing de Santander'),
  nombres.find(n => n.startsWith('Atlético')) || '—');

const desborde = await p.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('nada desborda el móvil', desborde <= 0, desborde + ' px');
await p.screenshot({ path: 'pruebas/salida/escudos-plantilla.png', fullPage: false });

await b.close();
console.log(errores.length ? '\nERRORES: ' + errores.join(' | ') : '\nERRORES: ninguno');
process.exit(errores.length ? 1 : 0);
