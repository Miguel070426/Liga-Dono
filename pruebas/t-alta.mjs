// El alta, en dos pasos.
//
// Antes eran siete campos de golpe, el escudo entre ellos, y el nombre de
// usuario se pedía aparte: un dato más que inventarse justo cuando ya te
// estás inventando el del club. Ahora el paso 1 es lo imprescindible, con el
// usuario propuesto a partir de tu nombre, y el paso 2 es la parte divertida.
//
// Lo que más se vigila aquí: que el código de la liga se compruebe ANTES de
// que nadie se ponga a elegir escudo. Decirle a alguien que el código está
// mal después del trabajo bonito es la peor forma de dar un error.
import pkg from '/opt/node22/lib/node_modules/playwright/index.js';
const { chromium } = pkg;
const URL = 'http://127.0.0.1:8791/prueba.html';
const errores = [];
const check = (q, ok, extra = '') => {
  console.log(`${ok ? '✅' : '❌'} ${q}${extra ? ' · ' + extra : ''}`);
  if(!ok) errores.push(q);
};
const nueva = async b => {
  const p = await b.newPage({ viewport: { width: 390, height: 844 } });
  p.on('pageerror', e => errores.push('JS: ' + e.message));
  p.on('console', m => { if(m.type() === 'error') errores.push('CONSOLA: ' + m.text()); });
  await p.route('**://highlightly.net/**', r => r.abort());
  await p.goto(URL);
  await p.waitForSelector('#stepWelcome:not(.hidden)');
  await p.click('#goClaim');
  await p.waitForSelector('#stepClaim:not(.hidden)');
  await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
  return p;
};

const b = await chromium.launch();
let p = await nueva(b);

// ── EL PASO 1 PIDE MENOS ──────────────────────────────────────────────────
const paso1 = await p.evaluate(() => {
  const v = document.getElementById('stepClaim');
  return {
    campos: v.querySelectorAll('input:not(.hidden), select').length,
    hayClub: !!v.querySelector('#claimClub'),
    hayEscudo: !!v.querySelector('#claimEscudo'),
    alto: v.scrollHeight,
    pista: document.getElementById('claimPass').getAttribute('placeholder')
  };
});
check('el paso 1 pide cuatro cosas, no siete', paso1.campos === 4, paso1.campos + ' campos');
check('el club no está en el paso 1', !paso1.hayClub);
check('el escudo tampoco', !paso1.hayEscudo);
check('cabe sin scroll eterno', paso1.alto < 700, paso1.alto + ' px');
check('la contraseña pide 6, no 8', /6/.test(paso1.pista), paso1.pista);

// ── EL USUARIO SE PROPONE SOLO ────────────────────────────────────────────
await p.fill('#claimOwner', 'Miguel Ángel');
await p.waitForTimeout(250);
const sug = await p.evaluate(() => ({
  vista: document.getElementById('claimUserVista').textContent.trim(),
  valor: document.getElementById('claimUser').value,
  campoOculto: document.getElementById('claimUser').classList.contains('hidden')
}));
check('el usuario sale de tu nombre, sin tildes', sug.valor === 'miguelangel', sug.valor);
check('y se te enseña con cuál vas a entrar', sug.vista === 'miguelangel', sug.vista);
check('sin ocupar un campo de formulario', sug.campoOculto);

// Pero se puede cambiar, y entonces deja de pisarse.
await p.click('#claimUserCambiar');
await p.fill('#claimUser', 'migue');
await p.fill('#claimOwner', 'Miguel Ángel García');
await p.waitForTimeout(250);
check('si lo cambias a mano, deja de reescribirse',
  await p.inputValue('#claimUser') === 'migue', await p.inputValue('#claimUser'));

// ── EL CÓDIGO SE COMPRUEBA ANTES DEL ESCUDO ───────────────────────────────
await p.selectOption('#claimSlot', '1');
await p.fill('#claimPass', 'secreto');
await p.fill('#claimJoin', 'CODIGO-MALO');
await p.click('#doClaimNext');
await p.waitForTimeout(600);
const malCodigo = await p.evaluate(() => ({
  sigueEnPaso1: !document.getElementById('stepClaim').classList.contains('hidden'),
  error: document.getElementById('claimErr').textContent.trim(),
  cuentas: Object.keys(window.__LIGA_FAKE_DB__.__D.usuarios).length
}));
check('con el código mal no te deja pasar al escudo', malCodigo.sigueEnPaso1);
check('y lo dice claro', /código/i.test(malCodigo.error), malCodigo.error);
check('sin haber creado ninguna cuenta', malCodigo.cuentas === 0);

// Contraseña corta: también se para aquí.
await p.fill('#claimJoin', 'DONO-2026');
await p.fill('#claimPass', 'abc');
await p.click('#doClaimNext');
await p.waitForTimeout(400);
check('una contraseña de 3 no pasa',
  !(await p.evaluate(() => document.getElementById('stepClaim').classList.contains('hidden'))),
  await p.textContent('#claimErr'));

// El aviso se va en cuanto corriges, sin esperar a volver a pulsar.
await p.fill('#claimPass', 'abc123');
await p.waitForTimeout(200);
check('el aviso en rojo se va al corregir',
  await p.evaluate(() => document.getElementById('claimErr').classList.contains('hidden')));

await p.waitForTimeout(200);
await p.screenshot({ path: 'pruebas/salida/alta-1-entrar.png' });
await p.click('#doClaimNext');
await p.waitForSelector('#stepClub:not(.hidden)', { timeout: 8000 });
check('con seis pasa al paso 2', true);

// ── EL PASO 2 ES SOLO EL CLUB ─────────────────────────────────────────────
const paso2 = await p.evaluate(() => {
  const v = document.getElementById('stepClub');
  return { hayClub: !!v.querySelector('#claimClub'),
           hayEscudo: !!v.querySelector('#claimEscudo'),
           texto: v.innerText,
           cuentas: Object.keys(window.__LIGA_FAKE_DB__.__D.usuarios).length };
});
check('el paso 2 lleva el club y el escudo', paso2.hayClub && paso2.hayEscudo);
check('y no vuelve a pedir contraseña ni código',
  !/contraseña|código/i.test(paso2.texto));
check('todavía no se ha creado nada', paso2.cuentas === 0);

await p.waitForSelector('#claimEscudo [data-azar]', { timeout: 8000 });
await p.fill('#claimClub', 'Deportivo Siuuu FC');
await p.waitForTimeout(400);
await p.screenshot({ path: 'pruebas/salida/alta-2-club.png', fullPage: true });

// Sin nombre de club no deja.
await p.fill('#claimClub', '   ');
await p.click('#doClaim');
await p.waitForTimeout(400);
check('sin nombre de club no deja terminar',
  /nombre/i.test(await p.textContent('#clubErr')), await p.textContent('#clubErr'));

// ── Y AL TERMINAR, DENTRO ─────────────────────────────────────────────────
await p.fill('#claimClub', 'Deportivo Siuuu FC');
await p.click('#doClaim');
await p.waitForSelector('.hero-team', { timeout: 10000 });
const dentro = await p.evaluate(() => {
  const m = window.__LIGA_FAKE_DB__.__D.managers[0];
  return { club: m.club_name, dueno: m.owner_name, usuario: m.usuario,
           escudo: !!m.escudo, cabecera: document.getElementById('hdrSub').textContent };
});
check('entra con su club puesto', dentro.club === 'Deportivo Siuuu FC', dentro.club);
check('con su nombre', dentro.dueno === 'Miguel Ángel García', dentro.dueno);
check('con el usuario que eligió', dentro.usuario === 'migue', dentro.usuario);
check('y con su escudo guardado', dentro.escudo);

// ── VOLVER ATRÁS NO PIERDE LO ESCRITO ─────────────────────────────────────
await p.close();
p = await nueva(b);
await p.selectOption('#claimSlot', '1');
await p.fill('#claimOwner', 'Pask');
await p.fill('#claimPass', 'abc123');
await p.fill('#claimJoin', 'DONO-2026');
await p.click('#doClaimNext');
await p.waitForSelector('#stepClub:not(.hidden)');
await p.fill('#claimClub', 'Real Paskdrid');
await p.click('#clubVolver');
await p.waitForSelector('#stepClaim:not(.hidden)');
const vuelta = await p.evaluate(() => ({
  nombre: document.getElementById('claimOwner').value,
  clave: document.getElementById('claimPass').value,
  codigo: document.getElementById('claimJoin').value
}));
check('al volver atrás sigue todo escrito',
  vuelta.nombre === 'Pask' && vuelta.clave === 'abc123' && vuelta.codigo === 'DONO-2026',
  `${vuelta.nombre} / ${vuelta.clave ? 'clave puesta' : 'clave perdida'} / ${vuelta.codigo}`);
await p.click('#doClaimNext');
await p.waitForSelector('#stepClub:not(.hidden)');
check('y el club tampoco se pierde',
  await p.inputValue('#claimClub') === 'Real Paskdrid',
  await p.inputValue('#claimClub'));

// ── DOS AMIGOS QUE SE LLAMAN IGUAL ────────────────────────────────────────
// El caso del día del lanzamiento: diez personas entrando a la vez desde el
// mismo mensaje. El usuario se propone a partir del nombre, así que dos
// Javier reciben los dos «javier». El segundo se entera en el paso 2, donde
// no hay campo de usuario — y ahí se quedaba atascado.
await p.close();
p = await nueva(b);
await p.selectOption('#claimSlot', '3');
await p.fill('#claimOwner', 'Javier');
await p.fill('#claimPass', 'abc123');
await p.fill('#claimJoin', 'DONO-2026');
await p.click('#doClaimNext');
await p.waitForSelector('#stepClub:not(.hidden)');
// Mientras elige escudo, otro Javier termina antes.
await p.evaluate(() => { window.__LIGA_FAKE_DB__.__D.usuarios['javier'] = { clave:'x', user_id:'uX' }; });
await p.fill('#claimClub', 'Javi FC');
await p.click('#doClaim');
await p.waitForTimeout(800);
const pisado = await p.evaluate(() => ({
  vuelveAlPaso1: !document.getElementById('stepClaim').classList.contains('hidden'),
  aviso: document.getElementById('claimErr').textContent.trim(),
  campoAbierto: !document.getElementById('claimUser').classList.contains('hidden'),
  enfocado: document.activeElement?.id
}));
check('si otro te pisa el usuario, vuelves al paso 1', pisado.vuelveAlPaso1);
check('con el aviso puesto', /usuario/i.test(pisado.aviso), pisado.aviso);
check('y el campo abierto para cambiarlo', pisado.campoAbierto);
check('y el cursor dentro, sin tener que buscarlo', pisado.enfocado === 'claimUser', pisado.enfocado);

// Y se puede terminar cambiándolo.
await p.fill('#claimUser', 'javi2');
await p.click('#doClaimNext');
await p.waitForSelector('#stepClub:not(.hidden)', { timeout: 8000 });
await p.fill('#claimClub', 'Javi FC');
await p.click('#doClaim');
await p.waitForSelector('.hero-team', { timeout: 10000 });
check('cambiando el usuario, entra sin empezar de cero',
  await p.evaluate(() => window.__LIGA_FAKE_DB__.__D.managers[2].usuario) === 'javi2');

const desborde = await p.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('nada desborda el móvil', desborde <= 0, desborde + ' px');

await b.close();
console.log(errores.length ? '\nERRORES: ' + errores.join(' | ') : '\nERRORES: ninguno');
process.exit(errores.length ? 1 : 0);
