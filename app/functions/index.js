const {onSchedule} = require('firebase-functions/v2/scheduler');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');

initializeApp();
const db = getFirestore();

// Colombia no observa horario de verano, así que el offset es siempre
// fijo — más simple y confiable que depender del huso horario del
// contenedor de la función (que corre en UTC salvo que se configure lo
// contrario, y esa configuración no afecta los cálculos con `Date` del
// código, solo cuándo dispara el cron).
const OFFSET_BOGOTA_HORAS = 5;

/**
 * El rango [inicio, fin) del "día de hoy" en hora de Bogotá, expresado
 * como instantes UTC — para que la consulta a Firestore compare
 * correctamente contra `fechaMovimiento` sin importar en qué huso
 * horario esté corriendo el proceso de la función.
 */
function rangoDeHoyBogota(ahora) {
  const bogota = new Date(ahora.getTime() - OFFSET_BOGOTA_HORAS * 3600 * 1000);
  const inicioBogotaComoUtc = Date.UTC(
    bogota.getUTCFullYear(),
    bogota.getUTCMonth(),
    bogota.getUTCDate(),
  );
  const inicio = new Date(inicioBogotaComoUtc + OFFSET_BOGOTA_HORAS * 3600 * 1000);
  const fin = new Date(inicio.getTime() + 24 * 3600 * 1000);
  return {inicio, fin};
}

/**
 * Mismo criterio de "presente ahora" que usa la app (ver
 * `ninos_presentes_screen.dart` → `_calcularPresentes`): para un niño
 * registrado, su movimiento más reciente de hoy debe ser "Entrada"; para
 * un visitante, CADA entrada de hoy cuenta (esta fase no tiene forma de
 * registrarle una salida manual).
 */
function calcularPresentes(registros) {
  const ultimoPorNino = new Map();
  const visitantesPresentes = [];
  for (const r of registros) {
    if (!r.fkIdNino) {
      if (r.tipoMovimiento === 'Entrada') visitantesPresentes.push(r);
      continue;
    }
    ultimoPorNino.set(r.fkIdNino, r);
  }
  const presentesRegistrados = Array.from(ultimoPorNino.values()).filter(
    (r) => r.tipoMovimiento === 'Entrada',
  );
  return [...presentesRegistrados, ...visitantesPresentes];
}

/**
 * Cierra (da Salida) a todos los niños presentes ahora mismo. Copia
 * quién lo retira desde su propia entrada — mismo criterio que el swipe
 * manual en la app ("se entrega a la misma persona que lo recibió") — y
 * deja constancia en `observacion` de que fue un cierre automático, para
 * distinguirlo de una salida real registrada por un servidor.
 */
async function cerrarPresentesDeHoy(motivo) {
  const ahora = new Date();
  const {inicio, fin} = rangoDeHoyBogota(ahora);

  const snap = await db
    .collection('registros')
    .where('fechaMovimiento', '>=', Timestamp.fromDate(inicio))
    .where('fechaMovimiento', '<', Timestamp.fromDate(fin))
    .orderBy('fechaMovimiento')
    .get();

  const registros = snap.docs.map((doc) => doc.data());
  const presentes = calcularPresentes(registros);

  if (presentes.length === 0) {
    console.log(`Cierre automático (${motivo}): nadie presente, nada que cerrar.`);
    return 0;
  }

  const ahoraTimestamp = Timestamp.fromDate(ahora);
  const batch = db.batch();
  for (const r of presentes) {
    const ref = db.collection('registros').doc();
    batch.set(ref, {
      fkIdNino: r.fkIdNino || '',
      nombreNinoVisitante: r.nombreNinoVisitante || '',
      tipoMovimiento: 'Salida',
      fechaMovimiento: ahoraTimestamp,
      numeroManilla: r.numeroManilla || '',
      fkIdServidor: 'sistema',
      nombreServidor: 'Cierre automático del sistema',
      fkIdAcudienteContacto: r.fkIdAcudienteContacto || '',
      nombreAcudienteContacto: r.nombreAcudienteContacto || '',
      tipoIdentificacionVisitante: r.tipoIdentificacionVisitante || '',
      documentoNinoVisitante: r.documentoNinoVisitante || '',
      telefonoAcudienteVisitante: r.telefonoAcudienteVisitante || '',
      alertaMedicaVisitante: r.alertaMedicaVisitante || false,
      condicionMedicaVisitante: r.condicionMedicaVisitante || '',
      modalidadRegistro: 'Automático',
      servicio: r.servicio || '',
      grupoEdad: r.grupoEdad || '',
      observacion: `Salida automática (${motivo}) — no se registró salida manual.`,
    });
    // Limpia el flag de presencia (ver ninoYaPresente() en
    // firestore.rules) para que el niño pueda volver a recibir una
    // Entrada después — si no se limpiara, quedaría bloqueado para
    // siempre aunque ya se le haya dado salida.
    if (r.fkIdNino) {
      batch.update(db.collection('ninos').doc(r.fkIdNino), {presente: false});
    }
  }
  await batch.commit();
  console.log(`Cierre automático (${motivo}): ${presentes.length} niños cerrados.`);
  return presentes.length;
}

// Domingo 10:30am hora de Bogotá: cierra a quien se haya quedado del
// primer servicio antes de que arranque el segundo — pedido explícito
// de Rafael.
exports.cierreAutomaticoDomingoMediodia = onSchedule(
  {schedule: '30 10 * * 0', timeZone: 'America/Bogota'},
  async () => {
    await cerrarPresentesDeHoy('domingo 10:30am');
  },
);

// Todos los días, al finalizar el día (11:55pm hora de Bogotá): cierra a
// cualquiera que haya quedado presente, sea cual sea el servicio.
exports.cierreAutomaticoFinDeDia = onSchedule(
  {schedule: '55 23 * * *', timeZone: 'America/Bogota'},
  async () => {
    await cerrarPresentesDeHoy('fin de día');
  },
);
