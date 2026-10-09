// Fichar una plaza, para las pruebas que solo quieren estar dentro del juego.
//
// Vive aparte porque el alta cambia: era un formulario de siete campos y
// ahora son dos pasos. Con esto repartido por cinco baterías, cada cambio
// rompía cinco archivos y la batería que de verdad prueba el alta
// (`t-alta.mjs`) se perdía entre el ruido.
export async function fichar(p, opciones = {}){
  const o = Object.assign({
    slot: '1', owner: 'Miguel', club: 'Deportivo Siuuu FC',
    user: null, pass: 'contrasena1', join: 'DONO-2026'
  }, opciones);

  await p.waitForSelector('#stepWelcome:not(.hidden)');
  await p.click('#goClaim');
  await p.waitForSelector('#stepClaim:not(.hidden)');
  await p.waitForFunction(() => document.querySelector('#claimSlot option')?.value);
  await p.selectOption('#claimSlot', o.slot);
  await p.fill('#claimOwner', o.owner);
  await p.fill('#claimPass', o.pass);
  await p.fill('#claimJoin', o.join);
  // El usuario se propone a partir del nombre; solo se toca si la prueba
  // quiere uno concreto.
  if(o.user){
    await p.click('#claimUserCambiar');
    await p.fill('#claimUser', o.user);
  }
  await p.click('#doClaimNext');

  await p.waitForSelector('#stepClub:not(.hidden)', { timeout: 8000 });
  await p.fill('#claimClub', o.club);
  await p.click('#doClaim');
  await p.waitForSelector('.hero-team', { timeout: 10000 });
}
