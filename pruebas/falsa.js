// ============================================================
// Capa de datos falsa · para las pruebas del navegador
// ============================================================
// Sustituye a db.js entero. app.js no sabe que Supabase existe, así que con
// esto se prueba el juego completo sin red y sin tocar la base de verdad.
//
// Vive EN EL REPOSITORIO a propósito. La versión anterior estaba en una
// carpeta temporal y se perdió entera cuando se recicló la máquina: las
// diecinueve baterías, la semilla y el sitio de pruebas, todo. Las pruebas
// son parte del proyecto; si no están versionadas, no existen.
(function(){
  'use strict';

  const ahora = () => new Date();
  const enHoras = h => new Date(Date.now() + h * 3600000).toISOString();
  const copia = x => JSON.parse(JSON.stringify(x));

  // ---------------------------------------------------------- los veinte clubes
  // Con su identificador de verdad, que es lo que construye la dirección del
  // escudo. Si estos números se inventaran, la prueba del escudo no probaría
  // nada: pasaría igual con una dirección que en producción da 404.
  const CLUBES = [
    ['Alavés', 462026], ['Athletic Club', 452665], ['Atlético de Madrid', 451814],
    ['Celta de Vigo', 458622], ['Deportivo de La Coruña', 463728], ['Elche', 679031],
    ['Espanyol', 460324], ['FC Barcelona', 450963], ['Getafe', 465430],
    ['Levante', 459473], ['Málaga', 456069], ['Osasuna', 619461],
    ['Racing de Santander', 3970699], ['Rayo Vallecano', 620312], ['Real Betis', 462877],
    ['Real Madrid', 461175], ['Real Sociedad', 467132], ['Sevilla', 456920],
    ['Valencia', 453516], ['Villarreal', 454367]
  ].map(([name, hl], i) => ({ id: 'c' + (i + 1), name, highlightly_id: hl }));

  const POS = ['GK', 'DF', 'MF', 'FW'];
  const PLANTILLA = { GK: 2, DF: 5, MF: 5, FW: 3 };

  function jugadoresDe(club, n){
    const out = [];
    for(const pos of POS){
      for(let k = 1; k <= PLANTILLA[pos]; k++){
        out.push({
          id: `p${n}-${pos}${k}`, club_id: club.id,
          name: `${pos}${k} del ${club.name}`, pos,
          activo: true, revisar: false, club_segun_api: null, motivo_baja: null
        });
      }
    }
    return out;
  }

  function semilla(){
    const clubs = copia(CLUBES);
    const players = clubs.flatMap((c, i) => jugadoresDe(c, i + 1));
    const managers = Array.from({length: 12}, (_, i) => ({
      id: 'm' + (i + 1), slot: i + 1,
      club_name: i === 0 ? 'Null City' : 'Club ' + (i + 1),
      owner_name: 'Dueño ' + (i + 1),
      usuario: 'user' + (i + 1), user_id: null, is_admin: false,
      escudo: null
    }));

    // Diez partidos de Primera: los veinte clubes emparejados de dos en dos.
    // El primero marca la hora de cierre, y hay uno en otro mes a propósito
    // para que se vea si una fecha se escribe sin mes.
    const base = new Date(Date.now() + 26 * 3600000);
    const partidos = [];
    for(let i = 0; i < 10; i++){
      const local = clubs[i * 2], visitante = clubs[i * 2 + 1];
      const cuando = new Date(base.getTime() + i * 26 * 3600000);
      partidos.push({
        match_id: 'x' + (i + 1), jornada: 1,
        local: local.name, visitante: visitante.name,
        local_club: local.id, visitante_club: visitante.id,
        comienza: cuando.toISOString(), fecha: cuando.toISOString().slice(0, 10),
        estado: 'Scheduled', goles_local: null, goles_visitante: null,
        cargado: false, excluido: false
      });
    }

    return {
      league: { id: 'lg1', name: 'Liga Dono', current_jornada: 1,
                lineups_locked: false, admin_user_id: null },
      managers, clubs, players, partidos,
      lineups: [], standings: [], form: [], results: [],
      playerStats: [], clubStats: [], picked: [],
      session: null, usuarios: {}, latidos: [], temporada: [],
      jornadaCerrada: false, clubesFuera: [], cierre: partidos[0].comienza,
      joinCode: 'DONO-2026'
    };
  }

  let D = semilla();

  // --------------------------------------------------------------- utilidades
  const esperar = v => Promise.resolve(copia(v));
  const yo = () => D.managers.find(m => m.user_id && m.user_id === D.session) || null;

  function huecosDe(formacion){
    const n = { '1-4-4-2': {DF:4, MF:4, FW:2}, '1-4-3-3': {DF:4, MF:3, FW:3} }[formacion]
           || {DF:4, MF:4, FW:2};
    const slots = [{slot: 1, pos: 'GK'}];
    let s = 2;
    for(const pos of ['DF', 'MF', 'FW']){
      for(let k = 0; k < n[pos]; k++) slots.push({slot: s++, pos});
    }
    return slots.map(x => ({...x, id: 'ls' + x.slot, club_id: null,
                            club_player_id: null, player_name: ''}));
  }

  const FALSA = {
    // Lo que las pruebas manipulan directamente para montar un escenario.
    get __D(){ return D; },
    __reset(){ D = semilla(); },

    // ------------------------------------------------------------ sesión
    async session(){ return D.session; },
    async freeSlots(){
      return D.managers.filter(m => !m.user_id).map(m => ({slot: m.slot, club_name: m.club_name}));
    },
    async claim(slot, club, owner, usuario, clave, joinCode, escudo){
      if(joinCode !== D.joinCode) throw new Error('El código de la liga no es correcto');
      const m = D.managers.find(x => x.slot === +slot);
      if(!m || m.user_id) throw new Error('Esa plaza ya está cogida');
      if(D.usuarios[usuario]) throw new Error('Ese usuario ya existe');
      m.user_id = 'u' + slot; m.club_name = club; m.owner_name = owner;
      m.usuario = usuario; if(escudo) m.escudo = escudo;
      D.usuarios[usuario] = {clave, user_id: m.user_id};
      D.session = m.user_id;
      return m;
    },
    async signIn(usuario, clave){
      const u = D.usuarios[usuario];
      if(!u || u.clave !== clave) throw new Error('Usuario o contraseña incorrectos');
      D.session = u.user_id;
    },
    async signOut(){ D.session = null; },
    async changePassword(nueva){
      const m = yo(); if(!m) return;
      const par = Object.values(D.usuarios).find(u => u.user_id === m.user_id);
      if(par) par.clave = nueva;
    },
    async resetPassword(){ },
    async claimAdmin(code){
      const m = yo();
      if(!m || code !== 'ADMIN-2026') return false;
      m.is_admin = true; return true;
    },

    // ------------------------------------------------------------ carga
    async bootstrap(){
      const me = yo();
      return copia({
        league: D.league, managers: D.managers, clubs: D.clubs, players: D.players,
        me, isAdmin: !!(me && me.is_admin)
      });
    },
    async standings(){ return esperar(D.standings); },
    async form(){ return esperar(D.form); },
    async results(j){ return esperar(D.results.filter(r => r.jornada === j)); },
    async lineups(j){ return esperar(D.lineups.filter(l => l.jornada === j)); },
    async playerStats(j){ return esperar(D.playerStats.filter(r => r.jornada === j)); },
    async pickedPlayers(j){ return esperar(D.picked.filter(r => r.jornada === j)); },
    async clubStats(j){ return esperar(D.clubStats.filter(r => r.jornada === j)); },
    async matchesOfJornada(j){ return esperar(D.partidos.filter(p => p.jornada === j)); },
    async jornadaEstado(j){
      return copia({
        jornada: j, cerrada: D.jornadaCerrada, cierre: D.cierre,
        clubes_fuera: D.clubesFuera
      });
    },
    async onceReferencia(){ return {limite: null, jornada_ref: null, jugadores: []}; },

    // Lo que lleva cada jugador en la temporada. Por defecto vacío, como está
    // la liga de verdad hasta octubre; `__conTemporada()` lo rellena para
    // poder probar la lista con números y sin ellos.
    async seasonStats(){ return esperar(D.temporada); },

    // ------------------------------------------------------------ alineación
    async saveLineup(leagueId, jornada, managerId, formation, slots){
      let l = D.lineups.find(x => x.jornada === jornada && x.manager_id === managerId);
      if(!l){
        l = {id: 'l' + D.lineups.length, jornada, manager_id: managerId,
             formation, confirmed: false, simulada: false, lineup_slots: []};
        D.lineups.push(l);
      }
      l.formation = formation;
      l.lineup_slots = copia(slots);
      return {blocked: false};
    },
    async setConfirmed(id, confirmed){
      const l = D.lineups.find(x => x.id === id); if(l) l.confirmed = confirmed;
      return {blocked: false};
    },
    async saveEscudo(receta){
      const m = yo(); if(m) m.escudo = receta;
      return {blocked: false};
    },
    // Existía en db.js desde el principio y el juego no la llamaba: nadie
    // podía cambiarse el nombre de su club. Aquí se imita la regla de la
    // base — solo tu fila, o cualquiera si diriges.
    async renameOwnClub(managerId, club, owner){
      const m = yo();
      if(!m || (m.id !== managerId && !m.is_admin)) return {blocked: true};
      const obj = D.managers.find(x => x.id === managerId);
      if(!obj) return {blocked: true};
      obj.club_name = club; obj.owner_name = owner;
      return {blocked: false};
    },

    // ------------------------------------------------------------ en vivo
    onChange(handler){
      let visto = D.latidos.length;
      const t = setInterval(() => {
        if(D.latidos.length !== visto){ visto = D.latidos.length; handler('alineación'); }
      }, 400);
      return () => clearInterval(t);
    },

    // ------------------- lo que solo toca la organización, en esqueleto ------
    async loadMatch(){ return {}; },
    async closeClubData(){ return {}; },
    async refreshFixtures(){ return {}; },
    async simulate(){ return {}; },
    async simulatedCount(){ return 0; },
    async checkJornada(){ return {ok: true}; },
    async clearSimulation(){ return {}; },
    async playoffs(){ return []; },
    async excludeMatch(){ return {}; },
    async includeMatch(){ return {}; },
    async setDeadline(j, cuando){ D.cierre = cuando; return {}; },
    async cicloEstado(){ return {}; },
    async cicloAhora(){ return {}; },
    async backups(){ return []; },
    async backupNow(){ return {}; },
    async backupJson(){ return {}; },
    async restoreBackup(){ return {}; },
    async searchPlayer(){ return []; },
    async lookCandidate(){ return {}; },
    async addSigning(){ return {}; },
    async setLeague(){ return {}; },
    async upsertClubStats(){ return {}; },
    async upsertPlayerStats(){ return {}; },
    async addClub(){ return {}; },
    async renameClub(){ return {}; },
    async deleteClub(){ return {}; },
    async addPlayers(){ return 0; },
    async setPlayerStatus(){ return {}; },
    async deletePlayer(){ return {}; },
    async adminSetManager(){ return {}; },
    async freeSlot(){ return {}; },
    async generateBrackets(){ return {}; },
    async saveGame(){ return {}; }
  };

  // Reparte estadísticas de temporada de mentira, pero verosímiles: unos
  // titulares con muchos minutos, unos suplentes con pocos y unos cuantos sin
  // jugar. Sin esa mezcla no se puede comprobar que la lista ordene por quien
  // juega, que es de lo que sirve el orden.
  FALSA.__conTemporada = function(){
    D.temporada = D.players.map((p, i) => {
      if(i % 7 === 0) return null;                    // uno de cada siete no juega
      const titular = i % 3 !== 0;
      const partidos = titular ? 3 + (i % 3) : 1 + (i % 2);
      return {
        club_player_id: p.id,
        goals:   p.pos === 'FW' ? (i % 4) : (i % 9 === 0 ? 1 : 0),
        assists: i % 5 === 0 ? 1 : 0,
        yellow:  i % 6 === 0 ? 1 : 0,
        red:     i % 47 === 0 ? 1 : 0,
        shots:   i % 3,
        minutes: partidos * (titular ? 85 : 22),
        partidos
      };
    }).filter(Boolean);
    return D.temporada.length;
  };

  // Ayudas para montar escenarios desde las pruebas.
  FALSA.__huecosDe = huecosDe;
  FALSA.__enHoras = enHoras;

  window.__LIGA_FAKE_DB__ = FALSA;
})();
