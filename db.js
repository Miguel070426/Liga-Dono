// ============================================================
// Capa de datos · lo único que habla con Supabase
// ============================================================
// Se mantiene fina a propósito: todas las llamadas de red viven aquí y nada
// más. app.js no sabe que Supabase existe, así que se puede probar entero
// inyectando un DB falso en window.__LIGA_FAKE_DB__.
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

export const CFG = Object.assign({
  url: 'https://kcrxekmsltxtavbujmwq.supabase.co',
  key: 'sb_publishable_tSdp7IALjAg3Kl4e9c4Jpw_WBSIEJ6a',
  // Los correos no se envían nunca: se derivan del usuario y este dominio solo
  // existe para darle a la cuenta un identificador con formato válido.
  mailDomain: 'ligadono.app'
}, window.LIGA_CONFIG || {});

const sb = createClient(CFG.url, CFG.key, {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: 'liga-fantasy-auth' }
});

// Cada uno elige su usuario y su contraseña. Antes había un código generado
// que hacía de las dos cosas, y falló donde importaba: nadie se acuerda de
// `LD-VZMW-UWX4`, teclearlo en un móvil se falla, y al ser también el usuario
// un carácter cambiado no se distingue de «no te has registrado».
//
// Sigue sin haber correos de verdad: Supabase Auth necesita uno, así que se
// deriva del usuario. Lo que cambia es que la parte memorable la elige la
// persona.
export function canonicalUser(u){
  return String(u || '').trim().toLowerCase().replace(/[^a-z0-9._-]/g, '');
}
export function emailForUser(usuario){
  return 'u' + canonicalUser(usuario) + '@' + CFG.mailDomain;
}
export const MIN_USUARIO = 3;
export const MIN_CLAVE = 8;

// Lo que se puede decir de un usuario y una contraseña antes de tocar la red.
export function revisaUsuario(usuario){
  const u = canonicalUser(usuario);
  if(u.length < MIN_USUARIO){
    return 'El usuario necesita al menos ' + MIN_USUARIO + ' caracteres, y solo '
      + 'letras, números, puntos, guiones o rayas.';
  }
  return null;
}
export function revisaClave(clave){
  if(String(clave || '').length < MIN_CLAVE){
    return 'La contraseña necesita al menos ' + MIN_CLAVE + ' caracteres.';
  }
  return null;
}

function fail(error, fallback){
  const msg = error?.message || fallback;
  const e = new Error(msg);
  e.cause = error;
  return e;
}

// ------------------------------------------------------------------ ACCESO
export const DB = {
  async session(){
    const { data } = await sb.auth.getSession();
    return data.session || null;
  },

  async freeSlots(){
    const { data, error } = await sb.rpc('public_slots');
    if(error) throw fail(error, 'No se ha podido consultar las plazas');
    return data || [];
  },

  // Crea la cuenta con el usuario y la contraseña que ha elegido, y ata esa
  // cuenta a la plaza.
  async claim(slot, club, owner, usuario, clave, joinCode){
    const malU = revisaUsuario(usuario), malC = revisaClave(clave);
    if(malU) throw new Error(malU);
    if(malC) throw new Error(malC);
    const u = canonicalUser(usuario);

    // Se pregunta antes de crear la cuenta: si el usuario está cogido y la
    // cuenta ya existe, queda una cuenta huérfana en Auth y el siguiente
    // intento con ese mismo usuario choca sin poder explicarse.
    const { data: libre, error: libreErr } = await sb.rpc('usuario_libre', {
      p_usuario: u, p_join_code: joinCode
    });
    if(libreErr) throw fail(libreErr, 'No se ha podido comprobar el usuario');
    if(libre === false){
      throw new Error('El usuario «' + u + '» ya está cogido. Elige otro.');
    }

    const { error: upErr } = await sb.auth.signUp({
      email: emailForUser(u), password: clave
    });
    if(upErr){
      if(/already|registrad/i.test(upErr.message || '')){
        throw new Error('El usuario «' + u + '» ya está cogido. Elige otro.');
      }
      throw fail(upErr, 'No se ha podido crear la cuenta');
    }

    const { data: sess } = await sb.auth.getSession();
    if(!sess.session){
      // Pasa si sigue activada la confirmación por email en el panel de Supabase.
      throw new Error('La cuenta se ha creado pero no ha iniciado sesión. '
        + 'Hay que desactivar la confirmación por email en Supabase.');
    }

    const { error: claimErr } = await sb.rpc('claim_slot', {
      p_slot: slot, p_club: club, p_owner: owner, p_usuario: u, p_join_code: joinCode
    });
    if(claimErr) throw fail(claimErr, 'No se ha podido reclamar la plaza');
    return u;
  },

  async signIn(usuario, clave){
    const u = canonicalUser(usuario);
    const mal = revisaUsuario(u);
    if(mal) throw new Error(mal);
    if(!String(clave || '')) throw new Error('Escribe tu contraseña.');

    const { error } = await sb.auth.signInWithPassword({
      email: emailForUser(u), password: String(clave)
    });
    if(!error) return;

    // Un fallo que no sea de credenciales —red caída, o que nos limiten por
    // intentar mucho— no se disfraza de contraseña equivocada.
    const esCredencial = error.status === 400
      || /invalid.*credential|credenciales/i.test(error.message || '');
    if(!esCredencial){
      throw new Error('No se ha podido comprobar tu acceso: ' +
        (error.message || 'no hay respuesta del servidor') +
        '. Vuelve a intentarlo en un momento.');
    }
    // A propósito no se dice cuál de las dos falla: si dijéramos «ese usuario
    // no existe», cualquiera podría ir probando nombres hasta dar con los de
    // la liga.
    throw new Error('El usuario o la contraseña no son correctos. Si no te '
      + 'acuerdas, la organización puede ponerte una contraseña nueva.');
  },

  // Cambiar la propia contraseña, para no quedarse con la que le puso otro.
  async changePassword(nueva){
    const mal = revisaClave(nueva);
    if(mal) throw new Error(mal);
    const { error } = await sb.auth.updateUser({ password: String(nueva) });
    if(error) throw fail(error, 'No se ha podido cambiar la contraseña');
  },

  // La organización repone la contraseña de quien la ha olvidado. Sin correos
  // no hay recuperación automática, así que esta es la red de seguridad.
  async resetPassword(managerId, nueva){
    const mal = revisaClave(nueva);
    if(mal) throw new Error(mal);
    const { data, error } = await sb.rpc('reponer_contrasena', {
      p_manager: managerId, p_nueva: String(nueva)
    });
    if(error) throw fail(error, 'No se ha podido reponer la contraseña');
    return data;
  },

  async signOut(){ await sb.auth.signOut(); },

  async claimAdmin(code){
    const { data, error } = await sb.rpc('claim_admin', { p_code: String(code).trim() });
    if(error) throw fail(error, 'No se ha podido activar la dirección');
    return data === true;
  },

  // ---------------------------------------------------------------- LECTURA
  async bootstrap(){
    const [lg, mgrs, cls, pls] = await Promise.all([
      sb.from('leagues').select('id,name,current_jornada,lineups_locked,admin_user_id').limit(1).single(),
      sb.from('managers').select('id,slot,club_name,owner_name,usuario,user_id,is_admin').order('slot'),
      sb.from('clubs').select('id,name').order('name'),
      sb.from('club_players').select('id,club_id,name,pos,activo,revisar,club_segun_api,motivo_baja')
    ]);
    for(const r of [lg, mgrs, cls, pls]){
      if(r.error) throw fail(r.error, 'No se han podido cargar los datos de la liga');
    }
    const { data: { user } } = await sb.auth.getUser();
    const me = (mgrs.data || []).find(m => m.user_id === user?.id) || null;
    return {
      league: lg.data,
      managers: mgrs.data || [],
      clubs: cls.data || [],
      players: pls.data || [],
      me,
      isAdmin: !!(me?.is_admin || (user && lg.data.admin_user_id === user.id))
    };
  },

  async standings(){
    const { data, error } = await sb.from('standings')
      .select('manager_id,slot,club_name,owner_name,pj,pts,g,e,p,sub_f,sub_c,sub_dif,rank')
      .order('rank');
    if(error) throw fail(error, 'No se ha podido cargar la clasificación');
    return data || [];
  },

  async form(){
    const { data, error } = await sb.from('manager_form')
      .select('manager_id,jornada,res').order('jornada');
    if(error) throw fail(error, 'No se ha podido cargar la racha');
    return data || [];
  },

  async results(jornada){
    const { data, error } = await sb.from('fixture_results').select('*').eq('jornada', jornada);
    if(error) throw fail(error, 'No se han podido cargar los resultados');
    return data || [];
  },

  // Alineaciones visibles de una jornada. RLS ya filtra: con la jornada
  // abierta solo llega la propia.
  async lineups(jornada){
    const { data, error } = await sb.from('lineups')
      .select('id,jornada,manager_id,formation,confirmed,simulada,'
            + 'lineup_slots(id,slot,pos,club_id,club_player_id,player_name)')
      .eq('jornada', jornada);
    if(error) throw fail(error, 'No se han podido cargar las alineaciones');
    return data || [];
  },

  // Lo que hizo cada jugador real en la jornada. Una fila por jugador, no por
  // hueco: si cinco managers eligieron al mismo, esta fila vale para los cinco.
  async playerStats(jornada){
    const { data, error } = await sb.from('player_jornada_stats')
      .select('club_player_id,goals,assists,yellow,red,fouls,shots,minutes')
      .eq('jornada', jornada);
    if(error) throw fail(error, 'No se han podido cargar las estadísticas');
    return data || [];
  },

  // La lista de trabajo de la organización: a quién han elegido esta jornada.
  async pickedPlayers(jornada){
    const { data, error } = await sb.from('picked_players')
      .select('club_player_id,player_name,pos,club_id,club_name,elegido_por')
      .eq('jornada', jornada)
      .order('club_name').order('player_name');
    if(error) throw fail(error, 'No se ha podido cargar quién ha sido elegido');
    return data || [];
  },

  async clubStats(jornada){
    const { data, error } = await sb.from('club_stats').select('*').eq('jornada', jornada);
    if(error) throw fail(error, 'No se han podido cargar los datos de los clubes');
    return data || [];
  },

  // ----------------------------------------------- CARGA DESDE LA API REAL
  // Qué partidos de Primera alimentan una jornada nuestra, y cuáles están ya
  // cargados. Se carga de uno en uno: una jornada entera son 10 llamadas a la
  // API con su pausa, y eso no cabe en una sola petición.
  async matchesOfJornada(jornada){
    const { data, error } = await sb.rpc('jornada_partidos', { p_jornada: jornada });
    if(error) throw fail(error, 'No se han podido leer los partidos de la jornada');
    return data || [];
  },
  async loadMatch(matchId){
    const { data, error } = await sb.rpc('cargar_resultado_partido', { p_match_id: matchId });
    if(error) throw fail(error, 'No se ha podido cargar ese partido');
    return (data && data[0]) || {};
  },
  // Los puntos de liga del club y la portería a cero salen del marcador, no
  // del box score, así que se hacen una vez al terminar.
  async closeClubData(jornada){
    const { data, error } = await sb.rpc('cerrar_datos_de_club', { p_jornada: jornada });
    if(error) throw fail(error, 'No se han podido cerrar los datos de los clubes');
    return data;
  },
  async refreshFixtures(){
    const { data, error } = await sb.rpc('refrescar_calendario_real');
    if(error) throw fail(error, 'No se ha podido refrescar el calendario');
    return data;
  },

  // -------------------------------------------------------------- SIMULADOR
  // Alinea al azar a quien no tenga once, para ver la jornada entera
  // funcionando con datos reales. Nunca pisa la alineación de una persona.
  async simulate(jornada){
    const { data, error } = await sb.rpc('simular_jornada', { p_jornada: jornada });
    if(error) throw fail(error, 'No se ha podido simular la jornada');
    return data || [];
  },
  async simulatedCount(jornada){
    const { count, error } = await sb.from('lineups')
      .select('id', { count: 'exact', head: true })
      .eq('jornada', jornada).eq('simulada', true);
    if(error) throw fail(error, 'No se ha podido leer qué hay simulado');
    return count || 0;
  },
  async checkJornada(jornada){
    const { data, error } = await sb.rpc('comprobar_jornada', { p_jornada: jornada });
    if(error) throw fail(error, 'No se ha podido comprobar la jornada');
    return data || [];
  },
  async clearSimulation(jornada){
    const { data, error } = await sb.rpc('borrar_simulacion', { p_jornada: jornada });
    if(error) throw fail(error, 'No se ha podido borrar la simulación');
    return data;
  },

  async playoffs(){
    const [st, gm] = await Promise.all([
      sb.from('playoff_series_state').select('*').order('bracket').order('position'),
      sb.from('playoff_games').select('*').order('game_no')
    ]);
    if(st.error) throw fail(st.error, 'No se han podido cargar los playoffs');
    if(gm.error) throw fail(gm.error, 'No se han podido cargar los playoffs');
    return { series: st.data || [], games: gm.data || [] };
  },

  // --------------------------------------------------------------- ESCRITURA
  // Devuelve {blocked:true} cuando RLS deja pasar la llamada sin tocar filas,
  // que es lo que ocurre al intentar guardar con la jornada cerrada.
  async saveLineup(leagueId, jornada, managerId, formation, slots){
    let { data: existing, error: selErr } = await sb.from('lineups')
      .select('id').eq('jornada', jornada).eq('manager_id', managerId).maybeSingle();
    if(selErr) throw fail(selErr, 'No se ha podido leer tu alineación');

    let lineupId = existing?.id;
    if(!lineupId){
      const ins = await sb.from('lineups')
        .insert({ league_id: leagueId, jornada, manager_id: managerId, formation })
        .select('id').maybeSingle();
      if(ins.error){
        if(ins.error.code === '42501') return { blocked: true };
        throw fail(ins.error, 'No se ha podido crear tu alineación');
      }
      if(!ins.data) return { blocked: true };
      lineupId = ins.data.id;
    }else{
      // Al tocarla, deja de ser del simulador y pasa a ser tuya.
      const upd = await sb.from('lineups')
        .update({ formation, simulada: false, updated_at: new Date().toISOString() })
        .eq('id', lineupId).select('id');
      if(upd.error) throw fail(upd.error, 'No se ha podido guardar la formación');
      if(!upd.data || upd.data.length === 0) return { blocked: true };
    }

    const del = await sb.from('lineup_slots').delete().eq('lineup_id', lineupId).select('id');
    if(del.error) throw fail(del.error, 'No se ha podido actualizar tu once');

    const rows = slots.map((s, i) => ({
      lineup_id: lineupId, slot: i + 1, pos: s.pos,
      club_id: s.club_id || null,
      club_player_id: s.club_player_id || null,
      player_name: s.player_name || ''
    }));
    const insSlots = await sb.from('lineup_slots').insert(rows).select('id');
    if(insSlots.error) throw fail(insSlots.error, 'No se ha podido guardar tu once');
    if(!insSlots.data || insSlots.data.length !== rows.length) return { blocked: true };
    return { lineupId };
  },

  async setConfirmed(lineupId, confirmed){
    const { data, error } = await sb.from('lineups')
      .update({ confirmed }).eq('id', lineupId).select('id');
    if(error) throw fail(error, 'No se ha podido confirmar');
    return { blocked: !data || data.length === 0 };
  },

  async renameOwnClub(managerId, club, owner){
    const { data, error } = await sb.from('managers')
      .update({ club_name: club, owner_name: owner }).eq('id', managerId).select('id');
    if(error) throw fail(error, 'No se ha podido cambiar el nombre');
    return { blocked: !data || data.length === 0 };
  },

  // ------------------------------------------------------------- DIRECCIÓN
  async setLeague(leagueId, patch){
    const { data, error } = await sb.from('leagues').update(patch).eq('id', leagueId).select('id');
    if(error) throw fail(error, 'No se ha podido guardar');
    return { blocked: !data || data.length === 0 };
  },

  async upsertClubStats(rows){
    const { error } = await sb.from('club_stats')
      .upsert(rows, { onConflict: 'league_id,jornada,club_id' });
    if(error) throw fail(error, 'No se han podido guardar los datos de los clubes');
  },

  async upsertPlayerStats(rows){
    const { error } = await sb.from('player_jornada_stats')
      .upsert(rows, { onConflict: 'league_id,jornada,club_player_id' });
    if(error) throw fail(error, 'No se han podido guardar las estadísticas');
  },

  async addClub(leagueId, name){
    const { error } = await sb.from('clubs').insert({ league_id: leagueId, name });
    if(error) throw fail(error, 'No se ha podido añadir el club');
  },
  async renameClub(id, name){
    const { error } = await sb.from('clubs').update({ name }).eq('id', id);
    if(error) throw fail(error, 'No se ha podido renombrar el club');
  },
  async deleteClub(id){
    const { error } = await sb.from('clubs').delete().eq('id', id);
    if(error) throw fail(error, 'No se ha podido borrar el club');
  },
  async addPlayers(clubId, list){
    const rows = list.map(p => ({ club_id: clubId, name: p.name, pos: p.pos }));
    const { data, error } = await sb.from('club_players')
      .upsert(rows, { onConflict: 'club_id,name', ignoreDuplicates: true }).select('id');
    if(error) throw fail(error, 'No se han podido añadir los jugadores');
    return (data || []).length;
  },
  // La organización marca a un jugador como en plantilla o de baja. Se guarda
  // el estado en vez de borrar la ficha: borrarla dejaría cojas las
  // alineaciones de jornadas ya jugadas.
  async setPlayerStatus(id, patch){
    const { data, error } = await sb.from('club_players')
      .update(patch).eq('id', id).select('id');
    if(error) throw fail(error, 'No se ha podido cambiar el estado del jugador');
    return { blocked: !(data || []).length };
  },
  async deletePlayer(id){
    const { error } = await sb.from('club_players').delete().eq('id', id);
    if(error) throw fail(error, 'No se ha podido borrar el jugador');
  },
  async adminSetManager(id, patch){
    const { error } = await sb.from('managers').update(patch).eq('id', id);
    if(error) throw fail(error, 'No se ha podido guardar el manager');
  },
  async generateBrackets(){
    const { error } = await sb.rpc('generate_brackets');
    if(error) throw fail(error, 'No se han podido generar los brackets');
  },
  async saveGame(id, homeSub, awaySub){
    const { error } = await sb.from('playoff_games')
      .update({ home_sub: homeSub, away_sub: awaySub }).eq('id', id);
    if(error) throw fail(error, 'No se ha podido guardar el partido');
  },

  // Avisa cuando otro cambia algo, para no tener que recargar a mano.
  // Aviso en vivo. No se escucha ninguna tabla con datos: Realtime manda la
  // fila entera a cada suscriptor, así que escuchar `leagues` repartiría los
  // códigos y escuchar las estadísticas serían 453 mensajes por jornada. Lo
  // que se escucha es `latidos`, una tabla sin nada dentro que los triggers
  // tocan una vez por sentencia. El aviso solo dice «algo ha cambiado»: los
  // datos se vuelven a pedir por los caminos normales, que respetan RLS, y así
  // la alineación a ciegas sigue a ciegas.
  onChange(handler){
    const ch = sb.channel('liga-latidos')
      .on('postgres_changes',
          { event: '*', schema: 'public', table: 'latidos' },
          payload => handler(payload?.new?.motivo || 'algo'))
      .subscribe();
    return { unsubscribe(){ sb.removeChannel(ch); } };
  }
};

export default DB;
