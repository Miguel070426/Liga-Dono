// La cabecera, medida en cinco anchos.
//
// Sale de un aviso de que en el móvil «hay botones que se solapan». No se
// solapaba nada: el nombre de la liga se salía de su caja y se colaba por
// debajo de la píldora de la jornada, y tu club salía cortado. Leído de un
// vistazo en un móvil, eso parece dos cosas montadas — y el que lo sufre no
// tiene por qué saber distinguirlo.
//
// Se mide en vez de mirarse, y se mide con un nombre de club largo, que es
// cuando aprieta. Con «Null City» no habría fallado nunca.
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
const URL = 'http://127.0.0.1:8791/prueba.html';
const ANCHOS = [320, 360, 390, 430, 1100];
const errores = [];
const check = (q, ok, extra = '') => {
  console.log(`${ok ? '✅' : '❌'} ${q}${extra ? ' · ' + extra : ''}`);
  if(!ok) errores.push(q);
};

const b = await chromium.launch();
for(const ancho of ANCHOS){
  const p = await b.newPage({ viewport: { width: ancho, height: 844 } });
  p.on('pageerror', e => errores.push(`JS (${ancho}px): ` + e.message));
  await p.route('**://highlightly.net/**', r => r.abort());

  await p.goto(URL);
  await p.waitForSelector('#stepWelcome:not(.hidden)');
  await p.click('#goClaim');
  await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
  await p.selectOption('#claimSlot', '1');
  await p.fill('#claimOwner', 'Miguel');
  await p.fill('#claimClub', 'Deportivo Siuuu FC');   // largo a propósito
  await p.fill('#claimUser', 'miguel'); await p.fill('#claimPass', 'contrasena1');
  await p.fill('#claimJoin', 'DONO-2026');
  await p.click('#doClaim');
  await p.waitForSelector('.hero-team', { timeout: 10000 });
  await p.waitForTimeout(400);

  const r = await p.evaluate(() => {
    const caja = s => { const e = document.querySelector(s); if(!e) return null;
      const b = e.getBoundingClientRect();
      return { l: b.left, r: b.right, t: b.top, b: b.bottom, w: b.width, h: b.height,
               visible: b.width > 0 && b.height > 0 }; };
    // Solo elementos de verdad: dentro de un SVG las piezas se superponen
    // por diseño y contarlas como solape no dice nada.
    const piezas = [...document.querySelectorAll('header.top button, header.top h1, header.top .sub, header.top .jornada-pill')]
      .filter(n => !n.closest('svg') && n.getBoundingClientRect().width > 0);
    const solapes = [];
    for(let i = 0; i < piezas.length; i++) for(let j = i + 1; j < piezas.length; j++){
      const A = piezas[i].getBoundingClientRect(), B = piezas[j].getBoundingClientRect();
      const ox = Math.min(A.right, B.right) - Math.max(A.left, B.left);
      const oy = Math.min(A.bottom, B.bottom) - Math.max(A.top, B.top);
      if(ox > 1 && oy > 1) solapes.push(
        (piezas[i].id || piezas[i].tagName) + '×' + (piezas[j].id || piezas[j].tagName));
    }
    const cortados = [...document.querySelectorAll('header.top *')]
      .filter(n => !n.closest('svg') && n.clientWidth > 0 && n.scrollWidth > n.clientWidth + 1)
      .map(n => (n.id || n.tagName) + ':"' + n.textContent.trim().slice(0, 30) + '"');
    const sub = document.getElementById('hdrSub');
    return { solapes, cortados,
             subEntero: sub.scrollHeight <= sub.clientHeight + 1,
             subTexto: sub.textContent.trim(),
             alto: Math.round(document.querySelector('header.top').getBoundingClientRect().height),
             botones: ['#hdrCrest', '#helpBtn', '#gearBtn'].map(caja) };
  });

  console.log(`\n── ${ancho}px ──`);
  check(`${ancho}px · nada se solapa en la cabecera`, r.solapes.length === 0,
    r.solapes.join(', ') || 'ninguno');
  check(`${ancho}px · nada sale cortado`, r.cortados.length === 0,
    r.cortados.join(' | ') || 'ninguno');
  check(`${ancho}px · tu club se lee entero`, r.subEntero, r.subTexto);
  check(`${ancho}px · los tres botones son pulsables con el dedo`,
    r.botones.every(c => c && c.w >= 28 && c.h >= 28),
    r.botones.map(c => c ? Math.round(c.w) + '×' + Math.round(c.h) : '—').join(' '));
  check(`${ancho}px · la cabecera no se come la pantalla`, r.alto <= 90, r.alto + ' px');

  if(ancho === 320 || ancho === 390){
    await p.screenshot({ path: `pruebas/salida/cabecera-${ancho}.png`,
                         clip: { x: 0, y: 0, width: ancho, height: 120 } });
  }
  await p.close();
}
await b.close();
console.log(errores.length ? '\nERRORES: ' + errores.join(' | ') : '\nERRORES: ninguno');
process.exit(errores.length ? 1 : 0);
