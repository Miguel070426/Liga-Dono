// Capturas para enseñar. No comprueba nada: solo retrata.
//
// Desde aquí no hay salida a internet, así que los escudos de verdad no
// cargan. Se sirve en su lugar un escudo gris de relleno, distinto por club,
// para que se vea la maquetación sin fingir que son los escudos reales: en un
// móvil de verdad ahí van los de Highlightly.
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
const URL = 'http://127.0.0.1:8791/prueba.html';

const escudoRelleno = id => Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 44" width="40" height="44">
     <path d="M20 1 38 7v17c0 10-8 16-18 19C10 40 2 34 2 24V7Z"
           fill="hsl(${(id * 47) % 360} 34% 42%)" stroke="#0a1712" stroke-width="2"/>
     <path d="M20 8 31 12v11c0 6-5 10-11 12-6-2-11-6-11-12V12Z" fill="hsl(${(id * 47) % 360} 30% 62%)"/>
   </svg>`);

const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
await p.route('**://highlightly.net/**', r => {
  const id = parseInt((r.request().url().match(/(\d+)\.png/) || [0, '1'])[1], 10);
  r.fulfill({ status: 200, contentType: 'image/svg+xml', body: escudoRelleno(id) });
});

await p.goto(URL);
await p.evaluate(() => window.__LIGA_FAKE_DB__.__conTemporada());
await p.waitForSelector('#stepWelcome:not(.hidden)');
await p.click('#goClaim');
await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
await p.selectOption('#claimSlot', '1');
await p.fill('#claimOwner', 'Miguel'); await p.fill('#claimClub', 'Deportivo Siuuu FC');
await p.fill('#claimUser', 'miguel'); await p.fill('#claimPass', 'contrasena1');
await p.fill('#claimJoin', 'DONO-2026');
await p.click('#doClaim');
await p.waitForSelector('.hero-team', { timeout: 10000 });
await p.waitForTimeout(600);

await p.click('nav.tabs button[data-view="plantilla"]');
await p.waitForSelector('.lineup-row');
await p.waitForTimeout(700);
await p.screenshot({ path: 'pruebas/salida/foto-1-once-vacio.png' });

// Se rellenan unos cuantos huecos para que se vea puesto.
const eleccion = [0, 1, 2, 5, 8];
for(const i of eleccion){
  await p.click(`.slotPick[data-i="${i}"]`);
  await p.waitForSelector('#selector:not(.hidden)');
  await p.waitForTimeout(250);
  await p.click('.pick-fila:not([disabled])');
  await p.waitForTimeout(350);
}
await p.screenshot({ path: 'pruebas/salida/foto-2-once-puesto.png' });

// La lista abierta, con escudos y estadísticas.
await p.click('.slotPick[data-i="3"]');
await p.waitForSelector('#selector:not(.hidden)');
await p.waitForTimeout(500);
await p.screenshot({ path: 'pruebas/salida/foto-3-lista.png' });

// Buscando por nombre: el caso Laporte.
await p.fill('#pickBuscar', 'Real');
await p.waitForTimeout(400);
await p.screenshot({ path: 'pruebas/salida/foto-4-buscando.png' });
await p.keyboard.press('Escape');
await p.waitForTimeout(300);

// Y la jornada con los escudos.
await p.click('nav.tabs button[data-view="jornada"]');
await p.waitForTimeout(400);
await p.click('#partidosPliegue > summary');
await p.waitForTimeout(900);
await p.screenshot({ path: 'pruebas/salida/foto-5-jornada.png' });

await b.close();
console.log('capturas hechas');
