// ============================================================
// Liga Fantasy · juego
// ============================================================
// No sabe que Supabase existe: todo pasa por DB, que se puede sustituir por
// una capa falsa en las pruebas (window.__LIGA_FAKE_DB__).
// La importación es perezosa a propósito: si hay una capa falsa inyectada, db.js
// no se carga, y con él tampoco el Supabase del CDN. Así se puede probar el
// juego entero sin red.
const DB = window.__LIGA_FAKE_DB__ || (await import('./db.js')).default;

const N_JORNADAS = 11;
const FORMATIONS = {
  '1-4-4-2':{DF:4,MF:4,FW:2}, '1-4-3-3':{DF:4,MF:3,FW:3}, '1-3-4-3':{DF:3,MF:4,FW:3},
  '1-3-5-2':{DF:3,MF:5,FW:2}, '1-5-3-2':{DF:5,MF:3,FW:2}, '1-5-4-1':{DF:5,MF:4,FW:1},
  '1-4-5-1':{DF:4,MF:5,FW:1}, '1-4-2-3-1':{DF:4,MF:5,FW:1},
  '1-3-4-2-1':{DF:3,MF:6,FW:1}, '1-4-1-4-1':{DF:4,MF:5,FW:1}
};
const CATS = [
  {key:'goles',       label:'Goles',             icon:'⚽', h:'hg', a:'ag'},
  {key:'asistencias', label:'Asistencias',       icon:'🎯', h:'ha', a:'aa'},
  {key:'tarjetas',    label:'Tarjetas',          icon:'🟨', h:'ht', a:'at2'},
  {key:'ptsEquipo',   label:'Puntos por equipo', icon:'🏆', h:'hp', a:'ap'},
  {key:'porteria0',   label:'Portería a 0',      icon:'🧤', h:'h0', a:'a0'},
  {key:'faltas',      label:'Faltas',            icon:'⚠️', h:'hf', a:'af'},
  {key:'corners',     label:'Córners',           icon:'🚩', h:'hc', a:'ac'},
  {key:'tiros',       label:'Tiros a puerta',    icon:'🥅', h:'hs', a:'as2'}
];
const POS_LABEL = {GK:'Portero', DF:'Defensas', MF:'Centro del campo', FW:'Delanteros'};
const POS_ORDER = {GK:0, DF:1, MF:2, FW:3};
const CLUB_NOISE = new Set(['fc','cf','cd','ud','sd','ad','ac','ca','rc','rcd','sad','afc','club','de','del','la','el','los','las']);

const S = {
  league:null, managers:[], clubs:[], players:[], me:null, isAdmin:false,
  standings:[], form:{}, playoffs:null,
  view:'inicio', viewJornada:1, plantillaJornada:1,
  cache:{}, draft:null, busy:false
};

/* ---------------------------------------------------------------- utilidades */
const $ = id => document.getElementById(id);
function esc(s){
  if(s === undefined || s === null) return '';
  return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}
function initials(name){
  const raw = String(name||'').trim().split(/\s+/).filter(Boolean);
  const words = raw.filter(w => !CLUB_NOISE.has(w.toLowerCase()));
  const use = words.length ? words : raw;
  if(!use.length) return '??';
  if(use.length === 1) return use[0].slice(0,2).toUpperCase();
  return (use[0][0] + use[1][0]).toUpperCase();
}
const mgr       = id => S.managers.find(m => m.id === id) || {club_name:'—', owner_name:'', slot:0};
const clubName  = id => (S.clubs.find(c => c.id === id) || {}).name || '';
const clamp     = j => Math.max(1, Math.min(N_JORNADAS, j|0));
const isMine    = id => S.me && id === S.me.id;
const jornadaOpen = () => S.league && !S.league.lineups_locked;

function playersOf(clubId, pos){
  return S.players.filter(p => p.club_id === clubId && p.pos === pos)
                  .sort((a,b) => a.name.localeCompare(b.name));
}

// Cada render asíncrono coge un número. Si mientras esperaba a la red han
// pedido otro render, el viejo se calla en vez de pisar la pantalla.
let renderSeq = 0;
const newRender = () => ++renderSeq;
const stale = seq => seq !== renderSeq;

let toastTimer = null;
function toast(msg, kind){
  const old = document.querySelector('.toast');
  if(old) old.remove();
  const el = document.createElement('div');
  el.className = 'toast ' + (kind || '');
  el.textContent = msg;
  document.body.appendChild(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 4200);
}
function loadingHtml(txt){
  return `<div class="loading"><div class="spinner"></div>${esc(txt || 'Cargando…')}</div>`;
}
async function guard(fn, label){
  if(S.busy) return;
  S.busy = true;
  try{ await fn(); }
  catch(err){ console.error(err); toast(err.message || (label || 'Algo ha fallado'), 'bad'); }
  finally{ S.busy = false; }
}

/* ---------------------------------------------------------------- acceso */
function showStep(id){
  document.querySelectorAll('.auth-step').forEach(s => s.classList.toggle('hidden', s.id !== id));
  $('authOverlay').classList.remove('hidden');
}
function hideAuth(){ $('authOverlay').classList.add('hidden'); }
function stepErr(id, msg){
  const el = $(id);
  el.textContent = msg;
  el.classList.toggle('hidden', !msg);
}

async function fillFreeSlots(){
  const sel = $('claimSlot');
  sel.innerHTML = '<option value="">Cargando…</option>';
  try{
    const slots = await DB.freeSlots();
    const free = slots.filter(s => !s.taken);
    sel.innerHTML = free.length
      ? free.map(s => `<option value="${s.slot}">Plaza ${s.slot}</option>`).join('')
      : '<option value="">— no quedan plazas libres —</option>';
    $('doClaim').disabled = free.length === 0;
    if(!free.length) stepErr('claimErr', 'La liga está completa. Si ya eres manager, entra con tu código.');
  }catch(err){
    sel.innerHTML = '<option value="">— error —</option>';
    stepErr('claimErr', err.message);
  }
}

function wireAuth(){
  $('goClaim').addEventListener('click', () => { stepErr('claimErr',''); showStep('stepClaim'); fillFreeSlots(); });
  $('goSignIn').addEventListener('click', () => { stepErr('signInErr',''); showStep('stepSignIn'); });
  $('goAdmin').addEventListener('click', () => { stepErr('adminErr',''); showStep('stepAdmin'); });
  document.querySelectorAll('.backWelcome').forEach(b => b.addEventListener('click', () => showStep('stepWelcome')));

  $('doClaim').addEventListener('click', () => guard(async () => {
    const slot  = +$('claimSlot').value;
    const owner = $('claimOwner').value.trim();
    const club  = $('claimClub').value.trim();
    const join  = $('claimJoin').value.trim();
    stepErr('claimErr','');
    if(!slot){ stepErr('claimErr','Elige una plaza.'); return; }
    if(!owner || !club){ stepErr('claimErr','Hacen falta tu nombre y el de tu club.'); return; }
    if(!join){ stepErr('claimErr','Falta el código de la liga. Pídeselo a la organización.'); return; }
    $('doClaim').disabled = true;
    try{
      const code = await DB.claim(slot, club, owner, join);
      $('codeValue').textContent = code;
      showStep('stepCode');
    }catch(err){
      stepErr('claimErr', err.message);
      await fillFreeSlots();
    }finally{ $('doClaim').disabled = false; }
  }));

  $('copyCode').addEventListener('click', async () => {
    try{
      await navigator.clipboard.writeText($('codeValue').textContent);
      toast('Código copiado', 'good');
    }catch{ toast('Cópialo a mano, el navegador no ha dejado', 'bad'); }
  });

  $('codeDone').addEventListener('click', () => guard(async () => { hideAuth(); await boot(); }));

  $('doSignIn').addEventListener('click', () => guard(async () => {
    const code = $('signInCode').value.trim();
    stepErr('signInErr','');
    if(!code){ stepErr('signInErr','Escribe tu código.'); return; }
    $('doSignIn').disabled = true;
    try{
      await DB.signIn(code);
      hideAuth();
      await boot();
    }catch(err){ stepErr('signInErr', err.message); }
    finally{ $('doSignIn').disabled = false; }
  }));

  $('doAdmin').addEventListener('click', () => guard(async () => {
    stepErr('adminErr','');
    if(!(await DB.session())){
      stepErr('adminErr','Entra primero con tu código de manager.');
      return;
    }
    const ok = await DB.claimAdmin($('adminCode').value.trim());
    if(!ok){ stepErr('adminErr','Ese código de dirección no es válido.'); return; }
    toast('Panel de dirección activado', 'good');
    hideAuth();
    await boot();
  }));

  $('gearBtn').addEventListener('click', () => {
    if(S.isAdmin){ switchView('panel'); return; }
    stepErr('adminErr','');
    showStep('stepAdmin');
  });
}

/* ---------------------------------------------------------------- arranque */
async function boot(){
  $('hdrSub').textContent = 'Cargando…';
  const snap = await DB.bootstrap();
  Object.assign(S, snap);
  S.cache = {};
  S.viewJornada = clamp(S.league.current_jornada);
  S.plantillaJornada = clamp(S.league.current_jornada);
  S.draft = null;

  const [st, fm] = await Promise.all([DB.standings(), DB.form()]);
  S.standings = st;
  S.form = {};
  fm.forEach(r => { (S.form[r.manager_id] = S.form[r.manager_id] || []).push(r.res); });

  $('panelTab').classList.toggle('hidden', !S.isAdmin);
  $('gearBtn').classList.toggle('on', S.isAdmin);
  renderAll();
}

async function jornadaData(j){
  if(S.cache[j]) return S.cache[j];
  const [results, lineups, clubStats] = await Promise.all([
    DB.results(j), DB.lineups(j), DB.clubStats(j)
  ]);
  S.cache[j] = { results, lineups, clubStats };
  return S.cache[j];
}
function invalidate(j){ if(j === undefined) S.cache = {}; else delete S.cache[j]; }

/* ---------------------------------------------------------------- navegación */
function switchView(name){
  S.view = name;
  document.querySelectorAll('nav.tabs button').forEach(b => b.classList.toggle('active', b.dataset.view === name));
  document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
  const el = $('view-' + name);
  if(el) el.classList.add('active');
  window.scrollTo({top:0, behavior:'smooth'});
  renderAll();
}

function renderHeader(){
  const j = clamp(S.league.current_jornada);
  $('hdrJornada').textContent = `Jornada ${j}` + (S.league.lineups_locked ? ' · cerrada' : '');
  const st = S.me ? S.standings.find(s => s.manager_id === S.me.id) : null;
  $('hdrSub').textContent = S.me
    ? `${S.me.club_name} · ${st && st.pj ? st.rank + 'º con ' + st.pts + ' pts' : 'sin jugar todavía'}`
    : '12 managers · 11 jornadas · playoffs';
  $('footNote').textContent = S.isAdmin ? 'Modo dirección activo' : 'Liga Fantasy';

  const b = $('globalBanner');
  if(S.league.lineups_locked){
    b.innerHTML = `<div class="banner locked">🔒 <span><strong>Jornada ${j} cerrada.</strong>
      Las alineaciones ya no se pueden cambiar y se han destapado todos los onces.</span></div>`;
  }else{
    b.innerHTML = `<div class="banner locked">✍️ <span><strong>Jornada ${j} abierta.</strong>
      Cada uno alinea a ciegas: el once de tu rival no se ve hasta que la organización cierre la jornada.</span></div>`;
  }
}

function renderAll(){
  if(!S.league) return;
  renderHeader();
  switch(S.view){
    case 'inicio':        renderInicio(); break;
    case 'plantilla':     renderPlantilla(); break;
    case 'jornada':       renderJornada(); break;
    case 'clasificacion': renderClasificacion(); break;
    case 'playoffs':      renderPlayoffs(); break;
    case 'panel':         renderPanel(); break;
  }
}

/* ============================================================
   BLOQUES DE MARCADOR
   ============================================================ */
function catsFrom(fr){
  return CATS.map(c => {
    const va = fr[c.h] || 0, vb = fr[c.a] || 0;
    return { ...c, va, vb, winner: va > vb ? 'a' : (vb > va ? 'b' : 'tie') };
  });
}
function sideHtml(id, winner){
  const m = mgr(id);
  return `<div class="bs-side${winner ? ' winner' : ''}">
    <div class="crest-sm">${esc(initials(m.club_name))}</div>
    <div class="bs-name">${esc(m.club_name)}</div>
    <div class="bs-owner">${esc(m.owner_name || '—')}</div>
  </div>`;
}
function bigScoreHtml(fr){
  const live = fr.has_data;
  const aWin = live && fr.sub_home > fr.sub_away, bWin = live && fr.sub_away > fr.sub_home;
  const nums = live
    ? `<span class="${aWin?'hi':(bWin?'lo':'eq')}">${fr.sub_home}</span><span class="sep">–</span>`
      + `<span class="${bWin?'hi':(aWin?'lo':'eq')}">${fr.sub_away}</span>`
    : `<span class="lo">–</span><span class="sep">·</span><span class="lo">–</span>`;
  return `<div class="bigscore">
    ${sideHtml(fr.home_id, aWin)}
    <div class="bs-mid">
      <div class="bs-nums">${nums}</div>
      <div class="bs-caption">Subpuntos · Jornada ${fr.jornada}</div>
      <div class="bs-pts">${live ? `${fr.pts_home} — ${fr.pts_away} puntos de liga` : 'Pendiente de disputarse'}</div>
    </div>
    ${sideHtml(fr.away_id, bWin)}
  </div>`;
}
function catboxHtml(fr){
  const live = fr.has_data;
  const ia = initials(mgr(fr.home_id).club_name), ib = initials(mgr(fr.away_id).club_name);
  const rows = catsFrom(fr).map(c => {
    const total = c.va + c.vb;
    let pa = 50;
    if(total > 0) pa = Math.max(6, Math.min(94, Math.round(c.va / total * 100)));
    const clsA = !live ? '' : (c.winner === 'a' ? 'wa' : (c.winner === 'tie' ? 't' : ''));
    const clsB = !live ? '' : (c.winner === 'b' ? 'wb' : (c.winner === 'tie' ? 't' : ''));
    let badge = '<span class="cat-pt">— · —</span>';
    if(live){
      if(c.winner === 'a')      badge = `<span class="cat-pt a">+1 ${esc(ia)}</span>`;
      else if(c.winner === 'b') badge = `<span class="cat-pt b">+1 ${esc(ib)}</span>`;
      else                      badge = `<span class="cat-pt t">+1 / +1</span>`;
    }
    return `<div class="cat">
      <div class="cat-val ${clsA}">${c.va}</div>
      <div class="cat-core">
        <div class="cat-head"><span class="cat-name"><span class="ic">${c.icon}</span>${esc(c.label)}</span>${badge}</div>
        <div class="cat-bar" style="${total > 0 ? '' : 'opacity:.35;'}">
          <div class="fa" style="width:${pa}%;"></div><div class="fb" style="width:${100-pa}%;"></div>
        </div>
      </div>
      <div class="cat-val ${clsB}">${c.vb}</div>
    </div>`;
  }).join('');
  const verdict = !live
    ? 'Aún sin datos cargados: cada categoría repartirá 1 subpunto.'
    : (fr.sub_home > fr.sub_away ? esc(mgr(fr.home_id).club_name) + ' gana el cruce'
      : (fr.sub_away > fr.sub_home ? esc(mgr(fr.away_id).club_name) + ' gana el cruce'
      : 'Empate a subpuntos: 1 punto para cada uno'));
  return `<div class="catbox">
    <div class="catbox-title">De dónde salen los subpuntos · 8 categorías</div>
    ${rows}
    <div class="cat-legend">
      <span><span class="sw sa"></span>${esc(mgr(fr.home_id).club_name)}</span>
      <span style="color:var(--gold-dim);text-align:center;">${verdict}</span>
      <span><span class="sw sb"></span>${esc(mgr(fr.away_id).club_name)}</span>
    </div>
  </div>`;
}
function lineupsHtml(fr, lineups){
  function one(id){
    const lu = lineups.find(l => l.manager_id === id);
    const m = mgr(id);
    if(!lu){
      return `<div><h3>${esc(m.club_name)}</h3><p class="empty" style="padding:14px;">${
        jornadaOpen() && !isMine(id)
          ? 'Oculta hasta que se cierre la jornada.'
          : 'Sin alineación.'}</p></div>`;
    }
    const slots = [...(lu.lineup_slots || [])].sort((a,b) => a.slot - b.slot);
    const rows = slots.map(s => {
      const ps = (s.player_stats && (Array.isArray(s.player_stats) ? s.player_stats[0] : s.player_stats)) || {};
      const cs = (S.cache[fr.jornada]?.clubStats || []).find(c => c.club_id === s.club_id);
      const out = s.club_id && cs && cs.played === false;
      const bits = [];
      if(ps.goals)         bits.push(`${ps.goals}⚽`);
      if(ps.assists)       bits.push(`${ps.assists}🎯`);
      if(ps.yellow)        bits.push('🟨');
      if(ps.second_yellow) bits.push('🟨🟥');
      if(ps.red)           bits.push('🟥');
      if(ps.shots)         bits.push(`${ps.shots}🥅`);
      return `<tr${out ? ' style="opacity:.45;"' : ''}>
        <td><span class="pos-tag pos-${s.pos}">${s.pos}</span></td>
        <td>${esc(s.player_name || '—')}<br><span class="club-tag">${esc(clubName(s.club_id) || 'sin club')}${out ? ' · no jugó' : ''}</span></td>
        <td style="text-align:right;white-space:nowrap;">${bits.join(' ') || '<span class="club-tag">—</span>'}</td>
      </tr>`;
    }).join('');
    return `<div><h3>${esc(m.club_name)} <span class="club-tag">· ${esc(lu.formation)}</span></h3><table>${rows}</table></div>`;
  }
  return `<div class="lineups-grid">${one(fr.home_id)}${one(fr.away_id)}</div>`;
}
function wireLineups(root, fr, lineups){
  const btn = root.querySelector('.lineupsBtn');
  if(!btn) return;
  btn.addEventListener('click', e => {
    e.stopPropagation();
    const holder = root.querySelector('.lineupsHolder');
    if(holder.innerHTML){ holder.innerHTML = ''; btn.textContent = 'Ver las dos alineaciones'; }
    else { holder.innerHTML = lineupsHtml(fr, lineups); btn.textContent = 'Ocultar alineaciones'; }
  });
}

/* ============================================================
   INICIO
   ============================================================ */
async function renderInicio(){
  const seq = newRender();
  const hero = $('inicioHero'), last = $('inicioLast'), top = $('inicioTop');
  if(!S.me){
    hero.innerHTML = `<div class="hero"><div class="hero-top">
      <div class="crest-big">⚙</div>
      <div class="hero-id"><div class="hero-eyebrow">Modo dirección</div>
      <div class="hero-team">Sin club asignado</div>
      <div class="hero-owner">Esta cuenta no tiene plaza de manager en la liga.</div></div></div></div>`;
    last.innerHTML = '<p class="empty">Sin cruces propios.</p>';
  }else{
    hero.innerHTML = loadingHtml();
    last.innerHTML = loadingHtml();
    const j = clamp(S.league.current_jornada);
    const st = S.standings.find(s => s.manager_id === S.me.id) || {rank:'—', pts:0, pj:0, g:0, e:0, p:0, sub_f:0, sub_c:0};
    const data = await jornadaData(j);
  if(stale(seq)) return;
    const fr = data.results.find(r => r.home_id === S.me.id || r.away_id === S.me.id);
    const myLu = data.lineups.find(l => l.manager_id === S.me.id);
    const filled = myLu && (myLu.lineup_slots || []).some(s => s.club_id || s.player_name);

    const form = (S.form[S.me.id] || []).slice(-5);
    const dots = form.map(f => `<span class="dot ${f}">${f}</span>`).join('')
      + Array.from({length: Math.max(0, 5 - form.length)}, () => '<span class="dot none">·</span>').join('');

    let next = `<div class="next-strip"><span class="vs">Jornada ${j}</span><div class="rival">Descansas esta jornada</div></div>`;
    if(fr){
      const rivalId = fr.home_id === S.me.id ? fr.away_id : fr.home_id;
      const rst = S.standings.find(s => s.manager_id === rivalId) || {rank:'—', pts:0};
      let cta;
      if(!jornadaOpen())        cta = '<span class="badge soft">Jornada cerrada</span>';
      else if(!filled)          cta = '<button class="btn" id="heroLineup">Alinear mi once</button>';
      else if(!myLu.confirmed)  cta = '<span class="badge draw">Sin confirmar</span> <button class="btn ghost small" id="heroLineup">Revisar</button>';
      else                      cta = '<span class="badge win">Confirmada</span> <button class="btn ghost small" id="heroLineup">Ver</button>';
      next = `<div class="next-strip">
        <span class="vs">Jornada ${j} · te enfrentas a</span>
        <div class="rival">${esc(mgr(rivalId).club_name)}
          <small>${esc(mgr(rivalId).owner_name || 'plaza libre')} · ${rst.rank}º con ${rst.pts} pts</small></div>
        <div class="cta">${cta}</div></div>`;
    }

    hero.innerHTML = `<div class="hero">
      <div class="hero-top">
        <div class="crest-big">${esc(initials(S.me.club_name))}</div>
        <div class="hero-id">
          <div class="hero-eyebrow">Tu club</div>
          <div class="hero-team">${esc(S.me.club_name)}</div>
          <div class="hero-owner">Manager: ${esc(S.me.owner_name || '—')}</div>
        </div>
        <div class="hero-rank"><div class="pos">${st.rank}º</div>
          <div class="lbl">${st.pj ? 'en la tabla' : 'de salida'}</div></div>
      </div>
      ${next}
      <div class="tiles">
        <div class="tile"><div class="v">${st.pts}</div><div class="k">Puntos</div></div>
        <div class="tile"><div class="v">${st.g}-${st.e}-${st.p}</div><div class="k">G · E · P</div></div>
        <div class="tile"><div class="v">${st.sub_f}<span style="font-size:14px;color:var(--chalk-dim);">:${st.sub_c}</span></div><div class="k">Subpuntos F : C</div></div>
        <div class="tile"><div class="v" style="font-size:14px;">Racha</div><div class="dots">${dots}</div></div>
      </div></div>`;
    const hb = $('heroLineup');
    if(hb) hb.addEventListener('click', () => { S.plantillaJornada = j; switchView('plantilla'); });

    // último cruce con datos
    let found = null;
    for(let jj = j; jj >= 1 && !found; jj--){
      const d = await jornadaData(jj);
      if(stale(seq)) return;
      const r = d.results.find(x => (x.home_id === S.me.id || x.away_id === S.me.id) && x.has_data);
      if(r) found = r;
    }
    if(!found){
      last.innerHTML = '<p class="empty">Todavía no has disputado ningún cruce con datos cargados.</p>';
    }else{
      const home = found.home_id === S.me.id;
      const mine = home ? found.sub_home : found.sub_away;
      const his  = home ? found.sub_away : found.sub_home;
      const rival = home ? found.away_id : found.home_id;
      const badge = mine > his ? '<span class="badge win">Victoria</span>'
                  : (his > mine ? '<span class="badge lose">Derrota</span>' : '<span class="badge draw">Empate</span>');
      last.innerHTML = `
        <div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:10px;">
          ${badge}<span class="club-tag">Jornada ${found.jornada} vs ${esc(mgr(rival).club_name)}</span></div>
        <div style="font-size:38px;font-weight:bold;color:var(--gold);font-variant-numeric:tabular-nums;">
          ${mine} <span style="color:var(--chalk-dim);font-size:24px;">–</span> ${his}</div>
        <div class="club-tag" style="margin-bottom:12px;">subpuntos</div>
        <button class="btn ghost small" id="lastDetail">Ver desglose por categorías</button>`;
      $('lastDetail').addEventListener('click', () => { S.viewJornada = found.jornada; switchView('jornada'); });
    }
  }

  const shown = S.standings.slice(0,5);
  if(S.me && !shown.some(s => s.manager_id === S.me.id)){
    const mineRow = S.standings.find(s => s.manager_id === S.me.id);
    if(mineRow) shown.push(mineRow);
  }
  top.innerHTML = `<table>
    <tr><th>#</th><th>Club</th><th>PJ</th><th>Pts</th></tr>
    ${shown.map(s => `<tr class="${isMine(s.manager_id) ? 'me' : ''}">
      <td><span class="zone ${s.rank <= 8 ? 'zone-top' : 'zone-low'}"></span>${s.rank}</td>
      <td>${esc(s.club_name)}</td><td>${s.pj}</td>
      <td><strong style="color:var(--gold);">${s.pts}</strong></td></tr>`).join('')}
  </table>
  <div style="margin-top:12px;"><button class="btn ghost small" id="toStandings">Ver clasificación completa</button></div>`;
  $('toStandings').addEventListener('click', () => switchView('clasificacion'));
}

/* ============================================================
   MI PLANTILLA
   ============================================================ */
function buildSlots(formation){
  const f = FORMATIONS[formation];
  const list = ['GK'];
  for(let i=0;i<f.DF;i++) list.push('DF');
  for(let i=0;i<f.MF;i++) list.push('MF');
  for(let i=0;i<f.FW;i++) list.push('FW');
  return list.map(pos => ({pos, club_id:null, player_name:''}));
}
function validate(slots){
  const errors = [], used = {};
  let noClub = 0, noName = 0;
  slots.forEach(s => {
    if(!s.club_id) noClub++;
    if(!s.player_name) noName++;
    if(s.club_id) used[s.club_id] = (used[s.club_id]||0) + 1;
  });
  if(noClub) errors.push(`Faltan ${noClub} club(es) por asignar.`);
  if(noName) errors.push(`Faltan ${noName} jugador(es) por elegir.`);
  Object.entries(used).forEach(([id,n]) => {
    if(n > 1) errors.push(`"${clubName(id)}" aparece ${n} veces — máximo 1 jugador por club.`);
  });
  return { valid: errors.length === 0, errors };
}
async function ensureDraft(){
  const j = S.plantillaJornada;
  if(S.draft && S.draft.jornada === j) return S.draft;
  const d = await jornadaData(j);
  const lu = d.lineups.find(l => l.manager_id === S.me.id);
  if(lu){
    const slots = [...(lu.lineup_slots || [])].sort((a,b) => a.slot - b.slot)
      .map(s => ({pos:s.pos, club_id:s.club_id, player_name:s.player_name}));
    S.draft = { jornada:j, formation:lu.formation, slots: slots.length ? slots : buildSlots(lu.formation),
                lineupId:lu.id, confirmed:lu.confirmed, dirty:false };
  }else{
    S.draft = { jornada:j, formation:'1-4-4-2', slots:buildSlots('1-4-4-2'),
                lineupId:null, confirmed:false, dirty:false };
  }
  return S.draft;
}

async function renderPlantilla(){
  const seq = newRender();
  const head = $('plantillaHead'), el = $('plantillaEditor');
  if(!S.me){
    head.innerHTML = '<div class="card"><p class="empty">Esta cuenta no tiene plaza de manager.</p></div>';
    el.innerHTML = '';
    return;
  }
  el.innerHTML = loadingHtml();
  const j = S.plantillaJornada;
  const cur = clamp(S.league.current_jornada);
  const d = await ensureDraft();
  if(stale(seq)) return;
  const editable = j === cur && jornadaOpen();
  const v = validate(d.slots);

  const badge = d.confirmed ? '<span class="badge win">Confirmada</span>'
    : (d.slots.some(s => s.club_id) ? '<span class="badge draw">Sin confirmar</span>' : '<span class="badge soft">Vacía</span>');
  head.innerHTML = `<div class="card" style="padding:16px 18px;">
    <div class="flex-between" style="flex-wrap:wrap;">
      <div style="display:flex;align-items:center;gap:14px;min-width:0;">
        <div class="crest-sm">${esc(initials(S.me.club_name))}</div>
        <div><div style="font-size:17px;text-transform:uppercase;letter-spacing:.5px;">${esc(S.me.club_name)}</div>
          <div class="club-tag">${esc(S.me.owner_name || '—')} · ${
            editable ? 'jornada abierta' : (j === cur ? 'jornada cerrada' : 'jornada ya pasada')}</div></div>
      </div>
      <div style="display:flex;align-items:center;gap:12px;">${badge}
        <div class="jnav">
          <button id="pPrev" ${j<=1?'disabled':''}>‹</button>
          <span class="lbl">Jornada ${j}</span>
          <button id="pNext" ${j>=N_JORNADAS?'disabled':''}>›</button>
        </div></div>
    </div></div>`;
  $('pPrev').addEventListener('click', () => { S.plantillaJornada = clamp(j-1); S.draft = null; renderPlantilla(); });
  $('pNext').addEventListener('click', () => { S.plantillaJornada = clamp(j+1); S.draft = null; renderPlantilla(); });

  if(!editable && !d.slots.some(s => s.club_id)){
    el.innerHTML = `<p class="empty">No alineaste en esta jornada.</p>`;
    return;
  }

  const used = {};
  d.slots.forEach(s => { if(s.club_id) used[s.club_id] = true; });

  const clubOpts = sel => `<option value="">— club —</option>` + S.clubs.map(c => {
    const clash = used[c.id] && c.id !== sel;
    return `<option value="${c.id}" ${c.id===sel?'selected':''}${clash?' disabled':''}>${esc(c.name)}${clash?' · ya usado':''}</option>`;
  }).join('');
  const playerOpts = (clubId, pos, sel) => {
    const list = playersOf(clubId, pos);
    let o = `<option value="">— jugador —</option>`
      + list.map(p => `<option value="${esc(p.name)}" ${p.name===sel?'selected':''}>${esc(p.name)}</option>`).join('');
    if(sel && !list.some(p => p.name === sel)) o += `<option value="${esc(sel)}" selected>${esc(sel)}</option>`;
    return o;
  };

  let blocks = '', lastPos = null;
  d.slots.forEach((s, i) => {
    if(s.pos !== lastPos){
      if(lastPos !== null) blocks += '</div>';
      blocks += `<div class="lineup-block"><div class="lineup-block-h">${POS_LABEL[s.pos]}</div>`;
      lastPos = s.pos;
    }
    const empty = s.club_id && playersOf(s.club_id, s.pos).length === 0;
    blocks += `<div class="lineup-row">
      <div class="slot-num">${i+1}</div>
      <span class="pos-tag pos-${s.pos}">${s.pos}</span>
      <select class="slotClub" data-i="${i}" ${editable?'':'disabled'}>${clubOpts(s.club_id)}</select>
      <select class="slotPlayer pn" data-i="${i}" ${(!s.club_id || !editable)?'disabled':''}>${playerOpts(s.club_id, s.pos, s.player_name)}</select>
    </div>${empty ? `<div class="club-tag" style="margin:-4px 0 6px 84px;">No hay ${s.pos} cargados para ${esc(clubName(s.club_id))}. La organización tiene que subir esa plantilla.</div>` : ''}`;
  });
  if(lastPos !== null) blocks += '</div>';

  el.innerHTML = `
    ${editable ? '' : '<div class="banner locked">🔒 Esta jornada no se puede editar. Solo consulta.</div>'}
    <div class="toolbar">
      <label style="margin:0;">Formación</label>
      <select id="formSel" style="max-width:150px;" ${editable?'':'disabled'}>
        ${Object.keys(FORMATIONS).map(f => `<option value="${f}" ${f===d.formation?'selected':''}>${f}</option>`).join('')}
      </select>
      <span class="pill">${Object.keys(used).length}/11 clubes</span>
      <span class="club-tag">Máximo 1 jugador por club real</span>
    </div>
    ${blocks}
    <div style="margin-top:10px;">${v.valid
      ? '<span class="ok">Once completo y legal ✓</span>'
      : `<span class="warn">${v.errors.join('<br>')}</span>`}</div>
    ${editable ? `<div style="margin-top:16px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
      <button class="btn" id="saveLineup" ${d.dirty?'':'disabled'}>Guardar cambios</button>
      <button class="btn ghost" id="confirmLineup" ${(!v.valid && !d.confirmed)?'disabled':''}>${d.confirmed?'Quitar confirmación':'Confirmar alineación'}</button>
      <span class="save-state" id="saveState">${d.dirty?'Cambios sin guardar':'Todo guardado'}</span>
    </div>
    <p class="club-tag" style="margin-top:12px;">Guarda antes de salir. Confirmar es lo que le dice a la organización que tu once es el definitivo.</p>` : ''}`;

  if(!editable) return;

  $('formSel').addEventListener('change', e => {
    const nf = e.target.value;
    const byPos = {GK:[],DF:[],MF:[],FW:[]};
    d.slots.forEach(s => byPos[s.pos].push(s));
    const ns = buildSlots(nf);
    ns.forEach(s => { const pool = byPos[s.pos]; if(pool && pool.length){ const o = pool.shift(); s.club_id = o.club_id; s.player_name = o.player_name; } });
    d.formation = nf; d.slots = ns; d.dirty = true;
    renderPlantilla();
  });
  el.querySelectorAll('.slotClub').forEach(sel => sel.addEventListener('change', () => {
    const i = +sel.dataset.i;
    d.slots[i].club_id = sel.value || null;
    d.slots[i].player_name = '';
    d.dirty = true;
    renderPlantilla();
  }));
  el.querySelectorAll('.slotPlayer').forEach(sel => sel.addEventListener('change', () => {
    d.slots[+sel.dataset.i].player_name = sel.value;
    d.dirty = true;
    renderPlantilla();
  }));

  $('saveLineup').addEventListener('click', () => guard(async () => {
    const ss = $('saveState');
    ss.textContent = 'Guardando…'; ss.className = 'save-state saving';
    const res = await DB.saveLineup(S.league.id, j, S.me.id, d.formation, d.slots);
    if(res.blocked){
      ss.textContent = 'No se ha guardado'; ss.className = 'save-state failed';
      toast('La jornada se ha cerrado mientras editabas: no se ha guardado nada.', 'bad');
      await boot();
      return;
    }
    d.lineupId = res.lineupId || d.lineupId;
    d.dirty = false;
    invalidate(j);
    toast('Alineación guardada', 'good');
    renderPlantilla();
  }));

  $('confirmLineup').addEventListener('click', () => guard(async () => {
    if(d.dirty){ toast('Guarda los cambios antes de confirmar.', 'bad'); return; }
    if(!d.lineupId){ toast('Guarda la alineación primero.', 'bad'); return; }
    const res = await DB.setConfirmed(d.lineupId, !d.confirmed);
    if(res.blocked){ toast('La jornada está cerrada.', 'bad'); await boot(); return; }
    d.confirmed = !d.confirmed;
    invalidate(j);
    toast(d.confirmed ? 'Alineación confirmada' : 'Confirmación retirada', 'good');
    renderPlantilla();
  }));
}

/* ============================================================
   JORNADA
   ============================================================ */
async function renderJornada(){
  const seq = newRender();
  const j = clamp(S.viewJornada);
  S.viewJornada = j;
  $('jLabel').textContent = `Jornada ${j}`;
  $('jPrev').disabled = j <= 1;
  $('jNext').disabled = j >= N_JORNADAS;

  const feat = $('jornadaFeatured'), rest = $('jornadaRest');
  feat.innerHTML = '';
  rest.innerHTML = loadingHtml();

  const d = await jornadaData(j);
  if(stale(seq)) return;
  const mine = S.me ? d.results.find(r => r.home_id === S.me.id || r.away_id === S.me.id) : null;
  const others = d.results.filter(r => r !== mine);

  if(mine){
    feat.innerHTML = `<div class="match-featured" id="featMatch">
      <div class="match-flag">Tu cruce</div>
      ${bigScoreHtml(mine)}${catboxHtml(mine)}
      <div class="lineups-toggle"><button class="lineupsBtn">Ver las dos alineaciones</button></div>
      <div class="lineupsHolder"></div></div>`;
    wireLineups($('featMatch'), mine, d.lineups);
  }
  $('restTitle').textContent = mine ? 'Resto de la jornada' : 'Cruces de la jornada';

  rest.innerHTML = others.map((fr,i) => {
    const live = fr.has_data;
    const aw = live && fr.sub_home > fr.sub_away, bw = live && fr.sub_away > fr.sub_home;
    return `<div class="mini-match" data-i="${i}">
      <div class="mini-head">
        <div class="t${aw?' w':''}">${esc(mgr(fr.home_id).club_name)}</div>
        <div class="sc">${live ? fr.sub_home+' - '+fr.sub_away : '– · –'}<small>${live?'subpuntos':'pendiente'}</small></div>
        <div class="t r${bw?' w':''}">${esc(mgr(fr.away_id).club_name)}</div>
        <div class="chev">▼</div>
      </div><div class="mini-body"></div></div>`;
  }).join('') || '<p class="empty">No hay más cruces.</p>';

  rest.querySelectorAll('.mini-match').forEach(card => {
    card.querySelector('.mini-head').addEventListener('click', () => {
      const fr = others[+card.dataset.i];
      const body = card.querySelector('.mini-body');
      if(card.classList.contains('open')){ card.classList.remove('open'); body.innerHTML = ''; }
      else{
        body.innerHTML = bigScoreHtml(fr) + catboxHtml(fr)
          + '<div class="lineups-toggle"><button class="lineupsBtn">Ver las dos alineaciones</button></div><div class="lineupsHolder"></div>';
        card.classList.add('open');
        wireLineups(card, fr, d.lineups);
      }
    });
  });
}

/* ============================================================
   CLASIFICACIÓN
   ============================================================ */
function renderClasificacion(){
  $('tablaClasificacion').innerHTML = `<div style="overflow-x:auto;"><table>
    <tr><th>#</th><th>Club</th><th>PJ</th><th>G</th><th>E</th><th>P</th><th>SF</th><th>SC</th><th>Dif</th><th>Pts</th><th>Racha</th></tr>
    ${S.standings.map(s => `<tr class="st-row ${isMine(s.manager_id)?'me':''}">
      <td><span class="zone ${s.rank<=8?'zone-top':'zone-low'}"></span>${s.rank}</td>
      <td>${esc(s.club_name)}<br><span class="club-tag">${esc(s.owner_name || '—')}</span></td>
      <td>${s.pj}</td><td>${s.g}</td><td>${s.e}</td><td>${s.p}</td>
      <td>${s.sub_f}</td><td>${s.sub_c}</td><td>${s.sub_dif > 0 ? '+' : ''}${s.sub_dif}</td>
      <td><strong style="color:var(--gold);font-size:15px;">${s.pts}</strong></td>
      <td><div class="dots">${(S.form[s.manager_id]||[]).slice(-5).map(f=>`<span class="dot ${f}">${f}</span>`).join('') || '<span class="club-tag">—</span>'}</div></td>
    </tr>`).join('')}</table></div>`;
}

/* ============================================================
   PLAYOFFS
   ============================================================ */
async function renderPlayoffs(){
  const seq = newRender();
  if(!S.playoffs) S.playoffs = await DB.playoffs();
  if(stale(seq)) return;
  const { series, games } = S.playoffs;
  function bracket(el, which, base){
    const list = series.filter(s => s.bracket === which);
    if(!list.length){ el.innerHTML = '<p class="empty">El bracket se generará al cerrar la liga regular.</p>'; return; }
    el.innerHTML = list.map(s => {
      const winner = s.wins_high >= 2 ? s.high_id : (s.wins_low >= 2 ? s.low_id : null);
      const seedH = base + s.position, seedL = base + (which === 'top' ? 9 - s.position : 5 - s.position);
      return `<div class="bracket-match clickable" data-series="${s.series_id}">
        <div class="p ${winner===s.high_id?'winner':''}"><span><span class="seed">${seedH}º</span>${esc(mgr(s.high_id).club_name)}</span><span>${s.wins_high}</span></div>
        <div class="p ${winner===s.low_id?'winner':''}"><span><span class="seed">${seedL}º</span>${esc(mgr(s.low_id).club_name)}</span><span>${s.wins_low}</span></div>
        <div class="club-tag" style="margin-top:6px;">${winner ? 'Serie decidida' : 'Al mejor de 3'} · click para ver</div>
      </div>`;
    }).join('');
    el.querySelectorAll('.bracket-match').forEach(c => c.addEventListener('click', () => showSeries(c.dataset.series)));
  }
  bracket($('bracketTop'), 'top', 0);
  bracket($('bracketBottom'), 'bottom', 8);

  function showSeries(id){
    const s = series.find(x => x.series_id === id);
    const gs = games.filter(g => g.series_id === id).sort((a,b) => a.game_no - b.game_no);
    const el = $('playoffSeriesEditor');
    el.style.display = 'block';
    el.innerHTML = `<h2>${esc(mgr(s.high_id).club_name)} ${s.wins_high} — ${s.wins_low} ${esc(mgr(s.low_id).club_name)}</h2>
      <table><tr><th>Partido</th><th>Local (factor cancha)</th><th>Visitante</th><th>Subpuntos</th></tr>
      ${gs.map(g => {
        const away = g.home_id === s.high_id ? s.low_id : s.high_id;
        return `<tr><td>P${g.game_no}</td><td>${esc(mgr(g.home_id).club_name)}</td>
          <td>${esc(mgr(away).club_name)}</td>
          <td><strong>${g.home_sub !== null && g.away_sub !== null ? g.home_sub+' - '+g.away_sub : '—'}</strong></td></tr>`;
      }).join('')}</table>`;
    el.scrollIntoView({behavior:'smooth', block:'nearest'});
  }
}

/* ============================================================
   PANEL DE DIRECCIÓN
   ============================================================ */
let panelSec = 'jornada';
let statsJornada = null, statsFixture = 0;

async function renderPanel(){
  const seq = newRender();
  const root = $('panelRoot');
  if(!S.isAdmin){ root.innerHTML = '<div class="card"><p class="empty">Zona de la organización.</p></div>'; return; }
  const secs = [['jornada','Jornada'],['stats','Cargar resultados'],['managers','Managers'],
                ['equipos','Equipos y jugadores'],['playoffs','Playoffs'],['cuenta','Cuenta']];
  root.innerHTML = `<div class="subtabs">${secs.map(([k,l]) =>
      `<button data-sec="${k}" class="${panelSec===k?'active':''}">${l}</button>`).join('')}</div>
    <div id="panelBody">${loadingHtml()}</div>`;
  root.querySelector('.subtabs').addEventListener('click', e => {
    const b = e.target.closest('button[data-sec]');
    if(!b) return;
    panelSec = b.dataset.sec;
    renderPanel();
  });
  const body = $('panelBody');
  if(stale(seq)) return;
  if(panelSec === 'jornada')       await panelJornada(body, seq);
  else if(panelSec === 'stats')    await panelStats(body, seq);
  else if(panelSec === 'managers') panelManagers(body);
  else if(panelSec === 'equipos')  panelEquipos(body);
  else if(panelSec === 'playoffs') await panelPlayoffs(body, seq);
  else                             panelCuenta(body);
}

async function panelJornada(body, seq){
  const cur = clamp(S.league.current_jornada);
  const locked = S.league.lineups_locked;
  const d = await jornadaData(cur);
  if(stale(seq)) return;
  body.innerHTML = `
    <div class="admin-note">El ciclo de una jornada: <strong>abierta</strong> (cada uno alinea a ciegas) →
      <strong>cerrada</strong> (se destapan los onces) → cargas los resultados → pasas a la siguiente.</div>
    <div class="card">
      <h2>Jornada en juego</h2>
      <div style="display:flex;flex-wrap:wrap;gap:8px;">${Array.from({length:N_JORNADAS},(_,i)=>i+1)
        .map(n => `<div class="jchip ${n===cur?'cur':''}" data-j="${n}">Jornada ${n}${n===cur?' ✓':''}</div>`).join('')}</div>
      <div style="margin-top:16px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;">
        <button class="btn ${locked?'ghost':''}" id="toggleLock">${locked?'Reabrir la jornada':'Cerrar la jornada'}</button>
        <span class="club-tag">${locked
          ? 'Cerrada: nadie puede editar y todos ven todos los onces.'
          : 'Abierta: cada uno puede editar y nadie ve el once del rival.'}</span>
      </div>
    </div>
    <div class="card"><h2>Estado de las alineaciones · jornada ${cur}</h2>
      <table><tr><th>#</th><th>Club</th><th>Manager</th><th>Formación</th><th>Estado</th></tr>
      ${S.managers.map(m => {
        const lu = d.lineups.find(l => l.manager_id === m.id);
        const filled = lu && (lu.lineup_slots||[]).some(s => s.club_id || s.player_name);
        const state = !filled ? '<span class="badge lose">Sin alinear</span>'
          : (lu.confirmed ? '<span class="badge win">Confirmada</span>' : '<span class="badge draw">Sin confirmar</span>');
        return `<tr><td>${m.slot}</td><td>${esc(m.club_name)}</td>
          <td>${esc(m.owner_name || '<span class="club-tag">plaza libre</span>')}</td>
          <td>${lu ? esc(lu.formation) : '—'}</td><td>${state}</td></tr>`;
      }).join('')}</table></div>`;

  body.querySelectorAll('.jchip').forEach(c => c.addEventListener('click', () => guard(async () => {
    await DB.setLeague(S.league.id, { current_jornada: +c.dataset.j });
    toast(`Jornada ${c.dataset.j} en juego`, 'good');
    await boot(); switchView('panel');
  })));
  $('toggleLock').addEventListener('click', () => guard(async () => {
    await DB.setLeague(S.league.id, { lineups_locked: !locked });
    toast(locked ? 'Jornada reabierta' : 'Jornada cerrada', 'good');
    await boot(); switchView('panel');
  }));
}

async function panelStats(body, seq){
  if(statsJornada === null) statsJornada = clamp(S.league.current_jornada);
  const d = await jornadaData(statsJornada);
  if(stale(seq)) return;
  const fr = d.results[Math.min(statsFixture, Math.max(0, d.results.length-1))];
  const jOpts = Array.from({length:N_JORNADAS},(_,i)=>i+1)
    .map(n => `<option value="${n}" ${n===statsJornada?'selected':''}>Jornada ${n}</option>`).join('');
  const fOpts = d.results.map((r,i) =>
    `<option value="${i}" ${i===statsFixture?'selected':''}>${esc(mgr(r.home_id).club_name)} vs ${esc(mgr(r.away_id).club_name)}</option>`).join('');

  let inner = '';
  if(!fr){ inner = '<div class="card"><p class="empty">Sin cruces en esta jornada.</p></div>'; }
  else{
    const luH = d.lineups.find(l => l.manager_id === fr.home_id);
    const luA = d.lineups.find(l => l.manager_id === fr.away_id);
    if(!luH || !luA){
      inner = `<div class="card"><p class="empty">Falta la alineación de ${
        esc(mgr(!luH ? fr.home_id : fr.away_id).club_name)}.</p></div>`;
    }else{
      const slots = [...(luH.lineup_slots||[]), ...(luA.lineup_slots||[])];
      const clubIds = [...new Set(slots.map(s => s.club_id).filter(Boolean))];
      const csRows = clubIds.map(id => {
        const cs = d.clubStats.find(c => c.club_id === id) || {team_points:0, corners:0, clean_sheet:false, played:true};
        return `<div class="grid cols-4" data-club="${id}" style="align-items:end;margin-bottom:10px;">
          <div><label>Club</label><strong style="font-size:13px;">${esc(clubName(id))}</strong></div>
          <div><label>Pts. de liga</label><input type="number" class="cTp" value="${cs.team_points}" min="0" max="3"></div>
          <div><label>Córners</label><input type="number" class="cCo" value="${cs.corners}" min="0"></div>
          <div><label>Portería a 0 / ¿jugó?</label>
            <select class="cCs"><option value="0" ${!cs.clean_sheet?'selected':''}>Sin portería a 0</option><option value="1" ${cs.clean_sheet?'selected':''}>Portería a 0</option></select>
            <select class="cPl" style="margin-top:4px;"><option value="1" ${cs.played!==false?'selected':''}>Jugó</option><option value="0" ${cs.played===false?'selected':''}>No jugó</option></select>
          </div></div>`;
      }).join('');
      const rows = lu => [...(lu.lineup_slots||[])].sort((a,b)=>a.slot-b.slot).map(s => {
        const ps = (Array.isArray(s.player_stats) ? s.player_stats[0] : s.player_stats) || {};
        const n = k => ps[k] || 0;
        return `<tr data-slot="${s.id}">
          <td style="min-width:150px;"><span class="pos-tag pos-${s.pos}">${s.pos}</span> ${esc(s.player_name||'—')}
            <br><span class="club-tag">${esc(clubName(s.club_id)||'sin club')}</span></td>
          <td><input type="number" class="pG"  value="${n('goals')}" min="0"></td>
          <td><input type="number" class="pA"  value="${n('assists')}" min="0"></td>
          <td><input type="number" class="pY"  value="${n('yellow')}" min="0" max="1"></td>
          <td><input type="number" class="pY2" value="${n('second_yellow')}" min="0" max="1"></td>
          <td><input type="number" class="pR"  value="${n('red')}" min="0" max="1"></td>
          <td><input type="number" class="pF"  value="${n('fouls')}" min="0"></td>
          <td><input type="number" class="pS"  value="${n('shots')}" min="0"></td></tr>`;
      }).join('');
      const head = '<tr><th>Jugador</th><th>Gol</th><th>Asist</th><th>Am</th><th>2ªAm</th><th>Roja</th><th>Faltas</th><th>Tiros</th></tr>';
      inner = `
        <div class="card"><h2>Datos de los clubes reales · jornada ${statsJornada}</h2>${csRows}
          <button class="btn small" id="saveClubStats">Guardar datos de clubes</button></div>
        <div class="card"><h2>${esc(mgr(fr.home_id).club_name)}</h2>
          <div style="overflow-x:auto;"><table>${head}${rows(luH)}</table></div></div>
        <div class="card"><h2>${esc(mgr(fr.away_id).club_name)}</h2>
          <div style="overflow-x:auto;"><table>${head}${rows(luA)}</table></div></div>
        <div style="margin-bottom:16px;"><button class="btn" id="savePlayerStats">Guardar estadísticas de jugadores</button></div>
        <div class="card" style="padding:0;overflow:hidden;">${bigScoreHtml(fr)}${catboxHtml(fr)}</div>`;
    }
  }

  body.innerHTML = `<div class="admin-note">Primero los datos del club real, después las estadísticas de cada jugador.
      El marcador de abajo se recalcula solo.</div>
    <div class="card"><div class="toolbar">
      <label style="margin:0;">Jornada</label><select id="stJ" style="max-width:150px;">${jOpts}</select>
      <label style="margin:0 0 0 12px;">Cruce</label><select id="stF" style="max-width:340px;">${fOpts}</select>
    </div></div>${inner}`;

  $('stJ').addEventListener('change', e => { statsJornada = +e.target.value; statsFixture = 0; renderPanel(); });
  $('stF').addEventListener('change', e => { statsFixture = +e.target.value; renderPanel(); });

  const scb = $('saveClubStats');
  if(scb) scb.addEventListener('click', () => guard(async () => {
    const rows = [...body.querySelectorAll('[data-club]')].map(r => ({
      league_id: S.league.id, jornada: statsJornada, club_id: r.dataset.club,
      team_points: +r.querySelector('.cTp').value || 0,
      corners:     +r.querySelector('.cCo').value || 0,
      clean_sheet: r.querySelector('.cCs').value === '1',
      played:      r.querySelector('.cPl').value === '1'
    }));
    await DB.upsertClubStats(rows);
    invalidate(statsJornada);
    toast('Datos de clubes guardados', 'good');
    await boot(); switchView('panel');
  }));

  const spb = $('savePlayerStats');
  if(spb) spb.addEventListener('click', () => guard(async () => {
    const rows = [...body.querySelectorAll('tr[data-slot]')].map(r => ({
      lineup_slot_id: r.dataset.slot,
      goals:         +r.querySelector('.pG').value || 0,
      assists:       +r.querySelector('.pA').value || 0,
      yellow:        +r.querySelector('.pY').value || 0,
      second_yellow: +r.querySelector('.pY2').value || 0,
      red:           +r.querySelector('.pR').value || 0,
      fouls:         +r.querySelector('.pF').value || 0,
      shots:         +r.querySelector('.pS').value || 0
    }));
    await DB.upsertPlayerStats(rows);
    invalidate(statsJornada);
    toast('Estadísticas guardadas', 'good');
    await boot(); switchView('panel');
  }));
}

function panelManagers(body){
  body.innerHTML = `<div class="admin-note">Puedes corregir el nombre del club o del manager. Liberar una plaza la
      deja libre para que otro la fiche: el código anterior deja de dar acceso a ella.</div>
    <div class="card"><h2>Managers</h2>
    ${S.managers.map(m => `<div class="grid cols-3" style="align-items:end;margin-bottom:10px;" data-m="${m.id}">
      <div><label>Plaza ${m.slot} — club</label><input type="text" class="mClub" value="${esc(m.club_name)}"></div>
      <div><label>Manager</label><input type="text" class="mOwner" value="${esc(m.owner_name)}" placeholder="libre"></div>
      <div style="display:flex;gap:6px;">
        <button class="btn small mSave">Guardar</button>
        <button class="btn ghost small mFree">Liberar</button>
      </div></div>`).join('')}</div>`;

  body.querySelectorAll('[data-m]').forEach(row => {
    const id = row.dataset.m;
    row.querySelector('.mSave').addEventListener('click', () => guard(async () => {
      await DB.adminSetManager(id, {
        club_name: row.querySelector('.mClub').value.trim() || 'Plaza',
        owner_name: row.querySelector('.mOwner').value.trim()
      });
      toast('Manager guardado', 'good');
      await boot(); switchView('panel');
    }));
    row.querySelector('.mFree').addEventListener('click', () => guard(async () => {
      const m = mgr(id);
      if(!confirm(`¿Liberar la plaza ${m.slot}? Quien la tenía perderá el acceso a ese club.`)) return;
      await DB.adminSetManager(id, { user_id:null, club_name:'Plaza '+m.slot, owner_name:'', claimed_at:null });
      toast('Plaza liberada', 'good');
      await boot(); switchView('panel');
    }));
  });
}

const SPANISH_POS = {
  'portero':'GK','guardameta':'GK','arquero':'GK',
  'defensa':'DF','defensa central':'DF','central':'DF','lateral':'DF',
  'lateral izquierdo':'DF','lateral derecho':'DF',
  'carrilero izquierdo':'DF','carrilero derecho':'DF','carrilero':'DF',
  'medio':'MF','medio centro':'MF','mediocampista':'MF','centrocampista':'MF',
  'pivote':'MF','mediocentro':'MF','mediocentro defensivo':'MF','mediocentro ofensivo':'MF',
  'mediapunta':'MF','interior derecho':'MF','interior izquierdo':'MF','interior':'MF',
  'extremo':'FW','extremo izquierdo':'FW','extremo derecho':'FW',
  'delantero':'FW','delantero centro':'FW','segundo delantero':'FW','ariete':'FW'
};

// Reconoce tres formatos de pegado:
//   A · "Nombre - GK"                            (posición ya en clave)
//   B · "Nombre<tab>Portero" o "Nombre Portero"  (posición al final de la línea)
//   C · la posición en su propia línea y el nombre unas líneas más arriba
//       (así lo suelta el bloque de Transfermarkt)
const POS_PHRASES = Object.keys(SPANISH_POS).sort((a, b) => b.length - a.length);

// Devuelve {name, pos} si la línea termina en una posición en español. Se prueban
// las frases largas primero, para que "defensa central" gane a "defensa".
function trailingPos(line){
  const low = line.toLowerCase();
  for(const p of POS_PHRASES){
    if(low === p) return { name:'', pos:SPANISH_POS[p] };
    if(low.endsWith(p) && /[\s\t,;·|-]/.test(low[low.length - p.length - 1] || '')){
      const name = line.slice(0, line.length - p.length).replace(/[\t\s,;·|–-]+$/,'').trim();
      if(name) return { name, pos:SPANISH_POS[p] };
    }
  }
  return null;
}

function parseBulk(text){
  const lines = text.replace(/\u00a0/g, ' ').split('\n').map(l => l.trim()).filter(Boolean);
  const out = [], seen = new Set();
  const add = (name, pos) => {
    name = name.replace(/\s{2,}/g, ' ').trim();
    if(!name || name.length < 2) return;
    const k = name.toLowerCase();
    if(seen.has(k)) return;
    seen.add(k); out.push({ name, pos });
  };
  const soloPos = [];   // líneas que son solo una posición, para el formato C

  lines.forEach((l, i) => {
    const m = l.match(/^(.+?)[-–,]\s*(GK|DF|MF|FW)\s*$/i);
    if(m){ add(m[1].trim(), m[2].toUpperCase()); return; }
    const t = trailingPos(l);
    if(t && t.name){ add(t.name, t.pos); return; }
    if(t) soloPos.push(i);
  });

  soloPos.forEach(i => {
    const pos = SPANISH_POS[lines[i].toLowerCase()];
    for(let j = i - 1; j >= 0 && j >= i - 4; j--){
      const c = lines[j];
      if(/^\d+(\s|$)/.test(c)) continue;
      if(/mill\.|€|\d{1,2}\/\d{1,2}\/\d{4}/.test(c)) continue;
      if(SPANISH_POS[c.toLowerCase()]) continue;
      const n = c.split('\t')[0].trim();
      if(n.length > 1){ add(n, pos); break; }
    }
  });
  return out;
}

let equiposClub = null;
function panelEquipos(body){
  if(!equiposClub && S.clubs.length) equiposClub = S.clubs[0].id;
  const list = S.players.filter(p => p.club_id === equiposClub)
    .sort((a,b) => POS_ORDER[a.pos]-POS_ORDER[b.pos] || a.name.localeCompare(b.name));
  body.innerHTML = `<div class="admin-note">Esta es la base de la que los managers eligen sus jugadores. Ellos no la
      ven: solo ven los desplegables ya rellenos. Un club sin jugadores no se puede elegir.</div>
    <div class="card"><h2>Clubes de Primera</h2>
      <div class="grid cols-4">${S.clubs.map(c => `<div style="display:flex;gap:4px;align-items:center;" data-c="${c.id}">
        <input type="text" class="cName" value="${esc(c.name)}" style="flex:1;">
        <button class="btn danger small cDel">✕</button></div>`).join('')}</div>
      <div style="margin-top:12px;display:flex;gap:8px;">
        <input type="text" id="newClub" placeholder="Añadir club…" style="max-width:220px;">
        <button class="btn ghost small" id="addClub">+ Añadir</button></div></div>
    <div class="card"><h2>Plantillas reales</h2>
      <div class="toolbar"><label style="margin:0;">Club</label>
        <select id="clubSel" style="max-width:250px;">${S.clubs.map(c =>
          `<option value="${c.id}" ${c.id===equiposClub?'selected':''}>${esc(c.name)}</option>`).join('')}</select>
        <span class="pill">${list.length} jugador(es)</span></div>
      <div class="grid cols-3" style="align-items:end;">
        <div><label>Nombre</label><input type="text" id="npName" placeholder="Ej. Vinícius Jr."></div>
        <div><label>Posición</label><select id="npPos">
          <option value="GK">Portero (GK)</option><option value="DF">Defensa (DF)</option>
          <option value="MF">Centrocampista (MF)</option><option value="FW">Delantero (FW)</option></select></div>
        <div><button class="btn" id="addPlayer">+ Añadir</button></div></div>
      <h3 style="margin-top:20px;">Pegar la plantilla entera</h3>
      <p style="font-size:12px;color:var(--chalk-dim);margin-top:0;">Pega el bloque tal cual de Flashscore o
        Transfermarkt, o línea a línea como <code>Nombre - POS</code>.</p>
      <textarea id="bulk" rows="6" placeholder="Pega aquí…"></textarea>
      <div style="margin-top:10px;"><button class="btn ghost" id="addBulk">Añadir todos</button></div>
      <h3 style="margin-top:20px;">Plantilla cargada</h3>
      ${list.length ? `<table><tr><th>Jugador</th><th>Posición</th><th></th></tr>${list.map(p =>
        `<tr><td>${esc(p.name)}</td><td><span class="pos-tag pos-${p.pos}">${p.pos}</span></td>
         <td style="text-align:right;"><button class="btn danger small pDel" data-p="${p.id}">✕</button></td></tr>`).join('')}</table>`
        : '<p class="empty">Sin jugadores. Hasta que cargues alguno, nadie puede elegir de este club.</p>'}
    </div>`;

  $('clubSel').addEventListener('change', e => { equiposClub = e.target.value; renderPanel(); });
  $('addClub').addEventListener('click', () => guard(async () => {
    const v = $('newClub').value.trim();
    if(!v) return;
    await DB.addClub(S.league.id, v);
    toast('Club añadido', 'good'); await boot(); switchView('panel');
  }));
  body.querySelectorAll('[data-c]').forEach(row => {
    const id = row.dataset.c;
    row.querySelector('.cName').addEventListener('change', e => guard(async () => {
      await DB.renameClub(id, e.target.value.trim());
      toast('Club renombrado', 'good'); await boot(); switchView('panel');
    }));
    row.querySelector('.cDel').addEventListener('click', () => guard(async () => {
      if(!confirm(`¿Quitar "${clubName(id)}"? Se irán también sus jugadores.`)) return;
      await DB.deleteClub(id);
      toast('Club borrado', 'good'); equiposClub = null; await boot(); switchView('panel');
    }));
  });
  $('addPlayer').addEventListener('click', () => guard(async () => {
    const name = $('npName').value.trim();
    if(!name) return;
    await DB.addPlayers(equiposClub, [{name, pos: $('npPos').value}]);
    toast('Jugador añadido', 'good'); await boot(); switchView('panel');
  }));
  $('addBulk').addEventListener('click', () => guard(async () => {
    const parsed = parseBulk($('bulk').value);
    if(!parsed.length){ toast('No se ha reconocido ningún jugador', 'bad'); return; }
    const n = await DB.addPlayers(equiposClub, parsed);
    toast(`${n} jugador(es) añadido(s) de ${parsed.length} reconocidos`, 'good');
    await boot(); switchView('panel');
  }));
  body.querySelectorAll('.pDel').forEach(b => b.addEventListener('click', () => guard(async () => {
    await DB.deletePlayer(b.dataset.p);
    await boot(); switchView('panel');
  })));
}

async function panelPlayoffs(body, seq){
  S.playoffs = await DB.playoffs();
  if(stale(seq)) return;
  const { series, games } = S.playoffs;
  body.innerHTML = `<div class="admin-note">Genera los brackets al terminar la liga regular y carga los subpuntos de
      cada partido, con el plus de factor cancha del local ya sumado.</div>
    <div class="card"><div class="flex-between"><h2 style="border:none;margin:0;">Brackets</h2>
      <button class="btn small" id="genBrackets">Generar / Actualizar</button></div>
      <div class="bracket-wrap" style="margin-top:14px;">${series.length ? series.map(s => {
        const w = s.wins_high >= 2 ? s.high_id : (s.wins_low >= 2 ? s.low_id : null);
        return `<div class="bracket-match clickable" data-s="${s.series_id}">
          <div class="p ${w===s.high_id?'winner':''}"><span>${esc(mgr(s.high_id).club_name)}</span><span>${s.wins_high}</span></div>
          <div class="p ${w===s.low_id?'winner':''}"><span>${esc(mgr(s.low_id).club_name)}</span><span>${s.wins_low}</span></div>
          <div class="club-tag" style="margin-top:6px;">${s.bracket==='top'?'Título':'Consolación'} · click para editar</div></div>`;
      }).join('') : '<p class="empty">Sin generar.</p>'}</div></div>
    <div class="card" id="serEdit" style="display:none;"></div>`;

  $('genBrackets').addEventListener('click', () => guard(async () => {
    await DB.generateBrackets();
    toast('Brackets generados', 'good');
    renderPanel();
  }));
  body.querySelectorAll('[data-s]').forEach(c => c.addEventListener('click', () => {
    const s = series.find(x => x.series_id === c.dataset.s);
    const gs = games.filter(g => g.series_id === s.series_id).sort((a,b)=>a.game_no-b.game_no);
    const el = $('serEdit');
    el.style.display = 'block';
    el.innerHTML = `<h2>${esc(mgr(s.high_id).club_name)} vs ${esc(mgr(s.low_id).club_name)} — al mejor de 3</h2>
      ${gs.map(g => {
        const away = g.home_id === s.high_id ? s.low_id : s.high_id;
        return `<div class="grid cols-3" style="align-items:end;margin-bottom:10px;" data-g="${g.id}">
          <div><label>P${g.game_no} — local</label><strong>${esc(mgr(g.home_id).club_name)}</strong>
            <span class="club-tag">vs ${esc(mgr(away).club_name)}</span></div>
          <div><label>Subpuntos local</label><input type="number" class="gH" value="${g.home_sub ?? ''}" min="0" max="16"></div>
          <div><label>Subpuntos visitante</label><input type="number" class="gA" value="${g.away_sub ?? ''}" min="0" max="16"></div>
        </div>`;
      }).join('')}
      <button class="btn" id="saveSeries">Guardar serie</button>`;
    $('saveSeries').addEventListener('click', () => guard(async () => {
      for(const row of el.querySelectorAll('[data-g]')){
        const h = row.querySelector('.gH').value, a = row.querySelector('.gA').value;
        await DB.saveGame(row.dataset.g, h === '' ? null : +h, a === '' ? null : +a);
      }
      toast('Serie guardada', 'good');
      renderPanel();
    }));
  }));
}

function panelCuenta(body){
  body.innerHTML = `<div class="admin-note">La organización es una cuenta como las demás, con el rol activado. El
      código de dirección se cambia en la base de datos (tabla <code>leagues</code>, columna
      <code>admin_claim_code</code>).</div>
    <div class="card"><h2>Sesión</h2>
      <p style="font-size:13px;">${S.me ? 'Entras como <strong>'+esc(S.me.club_name)+'</strong> (plaza '+S.me.slot+').' : 'Sin plaza de manager.'}</p>
      <button class="btn danger" id="signOut">Cerrar sesión en este dispositivo</button>
      <p class="club-tag" style="margin-top:10px;">Para volver a entrar necesitarás tu código.</p></div>`;
  $('signOut').addEventListener('click', () => guard(async () => {
    if(!confirm('¿Cerrar sesión? Necesitarás tu código para volver.')) return;
    await DB.signOut();
    location.reload();
  }));
}

/* ============================================================
   ARRANQUE
   ============================================================ */
document.querySelectorAll('nav.tabs button').forEach(b =>
  b.addEventListener('click', () => switchView(b.dataset.view)));
$('jPrev').addEventListener('click', () => { S.viewJornada = clamp(S.viewJornada-1); renderJornada(); });
$('jNext').addEventListener('click', () => { S.viewJornada = clamp(S.viewJornada+1); renderJornada(); });
$('jNow').addEventListener('click',  () => { S.viewJornada = clamp(S.league.current_jornada); renderJornada(); });

(async function init(){
  wireAuth();
  try{
    if(await DB.session()){
      await boot();
    }else{
      showStep('stepWelcome');
      $('hdrSub').textContent = '12 managers · 11 jornadas · playoffs';
    }
  }catch(err){
    console.error(err);
    $('hdrSub').textContent = 'Error de conexión';
    $('globalBanner').innerHTML = `<div class="banner error">⚠️ <span>No se ha podido conectar con la liga:
      ${esc(err.message)}</span></div>`;
  }
})();
