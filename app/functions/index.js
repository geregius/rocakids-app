const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall} = require('firebase-functions/v2/https');
const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const {defineSecret} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, Timestamp, FieldValue} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');
const {getMessaging} = require('firebase-admin/messaging');
const nodemailer = require('nodemailer');

initializeApp();
const db = getFirestore();

// Los correos arman su HTML por interpolación de strings (nombres de
// niños, etc. — datos que llenó un acudiente/servidor, sin validación
// de formato en `firestore.rules`). Sin escapar, un nombre con
// caracteres como `<`/`>`/`&` quedaría insertado tal cual en el HTML
// del correo (inyección de marcado). Se usa en cualquier valor que
// venga de un documento de Firestore antes de interpolarlo en una
// plantilla de correo.
const ENTIDADES_HTML = {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'};
function escapeHtml(texto) {
  return String(texto ?? '').replace(/[&<>"']/g, (c) => ENTIDADES_HTML[c]);
}

// Para valores que van en un encabezado de correo (ej. `subject`) en vez
// de en el cuerpo HTML — nodemailer ya sanitiza esto internamente, pero
// se quita cualquier salto de línea como defensa adicional (un dato sin
// validar con un `\r\n` no debería poder inyectar encabezados extra).
function sinSaltosDeLinea(texto) {
  return String(texto ?? '').replace(/[\r\n]+/g, ' ');
}

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

// ---------------------------------------------------------------------
// Correo automático de cumpleaños (2026-08-18, pedido de Rafael).
// ---------------------------------------------------------------------
//
// Cada mañana revisa qué niños "Activo" cumplen años HOY (mismo
// criterio de fecha que `cumpleEnUltimaSemana()`/`diasDesdeCumpleanos()`
// en `lib/models/nino.dart`, pero solo el día exacto) y le manda un
// correo festivo a CADA acudiente vinculado, en `rokakidsarmenia@gmail.com`
// (⚠️ con K, no "roca" — ver docs/estado-proyecto.md). Un niño sin
// ningún acudiente con correo real y válido se omite en silencio, sin
// bloquear el resto del envío.
const gmailAppPassword = defineSecret('GMAIL_APP_PASSWORD');
const EMAIL_VALIDO = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Versículos de bendición/alegría (elegido uno al azar por correo, para
// que no sea siempre el mismo) — todos en tono de gozo, bendición o
// esperanza, apropiados para una felicitación de cumpleaños.
const VERSICULOS_CUMPLEANOS = [
  {
    texto: 'El Señor te bendiga y te guarde; haga resplandecer su rostro sobre ti y te dé mucha paz.',
    referencia: 'Números 6:24-26',
  },
  {
    texto: 'Este es el día que hizo el Señor; nos gozaremos y alegraremos en él.',
    referencia: 'Salmos 118:24',
  },
  {
    texto: 'Porque yo sé los planes que tengo para ti —afirma el Señor—, planes de bienestar y no de calamidad, para darte un futuro y una esperanza.',
    referencia: 'Jeremías 29:11',
  },
  {
    texto: 'El Señor tu Dios está en medio de ti, poderoso, él salvará; se gozará sobre ti con alegría, se regocijará sobre ti con cánticos.',
    referencia: 'Sofonías 3:17',
  },
  {
    texto: 'Te alabaré, porque formidable y maravillosamente fuiste hecho; estoy maravillado, y mi alma lo sabe muy bien.',
    referencia: 'Salmos 139:14',
  },
  {
    texto: 'El gozo del Señor es tu fuerza.',
    referencia: 'Nehemías 8:10',
  },
  {
    texto: 'Por la misericordia de Jehová no hemos sido consumidos... Nuevas son cada mañana; grande es tu fidelidad.',
    referencia: 'Lamentaciones 3:22-23',
  },
  {
    texto: 'Amado, deseo que seas prosperado en todas las cosas, y que tengas salud, así como prospera tu alma.',
    referencia: '3 Juan 1:2',
  },
];

function elegirVersiculo() {
  const i = Math.floor(Math.random() * VERSICULOS_CUMPLEANOS.length);
  return VERSICULOS_CUMPLEANOS[i];
}

/** {mes, dia} de "hoy" en hora de Bogotá — mismo offset fijo que [rangoDeHoyBogota]. */
function hoyEnBogota() {
  const bogota = new Date(Date.now() - OFFSET_BOGOTA_HORAS * 3600 * 1000);
  return {mes: bogota.getUTCMonth(), dia: bogota.getUTCDate()};
}

/**
 * "MM-DD" de hoy en hora de Bogotá — mismo formato exacto que
 * `mesDiaDe()` en el lado Dart (`lib/models/nino.dart`), que es lo que
 * arma el campo `mesDiaNacimiento` guardado en cada `ninos/{id}` al
 * registrar/editar su fecha de nacimiento.
 */
function mesDiaHoyBogota() {
  const {mes, dia} = hoyEnBogota();
  return `${String(mes + 1).padStart(2, '0')}-${String(dia).padStart(2, '0')}`;
}

function plantillaCorreoCumpleanos(nombreNino, versiculo) {
  const nombreNinoSeguro = escapeHtml(nombreNino);
  return `
  <div style="background:#f2f2f2;padding:24px 12px;font-family:Verdana,Arial,sans-serif;">
    <div style="max-width:480px;margin:0 auto;background:#ffffff;border:2px solid #ffcc00;border-radius:20px;overflow:hidden;">
      <div style="background:linear-gradient(135deg,#ff5f6d,#ffb347);padding:24px 20px;text-align:center;">
        <div style="font-size:28px;line-height:1;margin-bottom:8px;">🎈🥳🎂🎁🎉</div>
        <div style="color:#ffffff;font-size:20px;font-weight:bold;letter-spacing:0.5px;">
          ¡HOY ES UN DÍA SÚPER ESPECIAL!
        </div>
      </div>
      <div style="padding:24px 24px 8px;text-align:center;">
        <p style="font-size:16px;color:#1A1A2E;margin:0 0 16px;">¡Hola campeón@!</p>
        <div style="display:inline-block;background:#2dd4bf;color:#ffffff;font-weight:bold;
                    padding:10px 20px;border-radius:999px;font-size:16px;margin-bottom:20px;">
          ⭐ ¡¡Feliz Cumpleaños ${nombreNinoSeguro}!! ⭐
        </div>
        <p style="font-size:15px;color:#1A1A2E;text-align:left;line-height:1.5;margin:0 0 14px;">
          En <b>RocaKids</b> estamos saltando de alegría 🥳🙏 porque hoy Dios te regala un
          año más de vida lleno de sonrisas, juegos, amigos y bendiciones.
        </p>
        <p style="font-size:15px;color:#1A1A2E;text-align:left;line-height:1.5;margin:0 0 18px;">
          ¡Nos encanta verte brillar, aprender y divertirte cada fin de semana! Eres una
          persona muy especial e importante para Jesús y para todos nosotros. 💫✨
        </p>
        <div style="background:#fff8e1;border:2px dashed #f9a825;border-radius:12px;
                    padding:16px;text-align:left;margin:0 0 18px;">
          <p style="margin:0 0 8px;font-size:14px;color:#1A1A2E;">📖 <b>Un mensaje del Cielo para ti hoy:</b></p>
          <p style="margin:0 0 8px;font-size:14px;font-style:italic;color:#1A1A2E;">"${versiculo.texto}"</p>
          <p style="margin:0;font-size:13px;font-weight:bold;color:#ef6c00;">— ${versiculo.referencia}</p>
        </div>
        <p style="font-size:15px;color:#1A1A2E;text-align:left;line-height:1.5;margin:0 0 20px;">
          ¡Sigue creciendo con ese corazón tan lindo y esa súper energía! 🚀🍭
        </p>
        <div style="background:linear-gradient(135deg,#14b8a6,#10b981);border-radius:14px;
                    padding:16px;margin:0 0 20px;">
          <p style="margin:0 0 6px;color:#ffffff;font-weight:bold;font-size:15px;">
            🎉 ¡TE ESPERAMOS ESTE FIN DE SEMANA!
          </p>
          <p style="margin:0;color:#ffffff;font-size:14px;">
            ❤️ Ven a RocaKids para celebrarte y darte un súper abrazo de cumpleaños 🤗🥹
          </p>
        </div>
      </div>
      <div style="padding:0 24px 24px;text-align:center;">
        <p style="font-size:12px;color:#9e9e9e;font-style:italic;margin:0;">
          Con muchísimo cariño, oraciones y abrazos,<br/>
          <b style="color:#9e9e9e;">Tu familia de RocaKids ❤️</b>
        </p>
      </div>
    </div>
  </div>`;
}

/** Correos (ya sin duplicados) de todos los acudientes vinculados a un niño. */
async function correosDeAcudientesDe(ninoId) {
  const relSnap = await db.collection('nino_acudiente').where('fk_idNino', '==', ninoId).get();
  const correos = new Set();
  for (const rel of relSnap.docs) {
    const acudienteId = rel.data().fk_idAcudiente;
    if (!acudienteId) continue;
    const acuDoc = await db.collection('acudientes').doc(acudienteId).get();
    if (!acuDoc.exists) continue;
    const correo = (acuDoc.data().correoElectronico || '').trim();
    if (EMAIL_VALIDO.test(correo)) correos.add(correo);
  }
  return [...correos];
}

async function enviarCorreosCumpleanosDeHoy() {
  // 2026-08-24: corrige un bug de raíz reportado por Rafael — el correo
  // llegaba un día TARDE (un niño que cumplió ayer en hora Bogotá
  // recibía el correo hoy). Antes esta función releía
  // `fechaNacimiento.toDate().getUTCMonth()/getUTCDate()` acá mismo, un
  // cálculo DISTINTO del que usa `mesDiaDe()` en Dart para guardar
  // `mesDiaNacimiento` al registrar/editar al niño — cualquier
  // corrimiento de zona horaria al convertir el `Timestamp` original
  // (ej. datos migrados desde el sistema anterior) podía desincronizar
  // los dos cálculos. La pantalla "Cumpleaños niños" de la app SIEMPRE
  // usó `mesDiaNacimiento` (`AuthService.obtenerNinosQueCumplieronEstaSemana()`)
  // y mostraba la fecha correcta — usar ese mismo campo acá elimina
  // cualquier posibilidad de que las dos partes de la app calculen un
  // día distinto para la misma fecha de nacimiento. Como beneficio
  // extra, ahora el filtro lo hace Firestore (`where`) en vez de traer
  // TODOS los niños "Activo" para filtrar en el cliente.
  const mesDiaHoy = mesDiaHoyBogota();
  const snap = await db
      .collection('ninos')
      .where('estadoRegistro', '==', 'Activo')
      .where('mesDiaNacimiento', '==', mesDiaHoy)
      .get();
  const cumpleaneros = snap.docs;

  if (cumpleaneros.length === 0) {
    console.log('Correo de cumpleaños: nadie cumple años hoy.');
    return;
  }

  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {user: 'rokakidsarmenia@gmail.com', pass: gmailAppPassword.value()},
  });

  let enviados = 0;
  let omitidos = 0;
  for (const doc of cumpleaneros) {
    const nino = doc.data();
    const correos = await correosDeAcudientesDe(doc.id);
    if (correos.length === 0) {
      omitidos++;
      continue;
    }
    const versiculo = elegirVersiculo();
    const html = plantillaCorreoCumpleanos(nino.nombres, versiculo);
    for (const correo of correos) {
      try {
        await transporter.sendMail({
          from: '"RocaKids" <rokakidsarmenia@gmail.com>',
          to: correo,
          subject: `¡Feliz cumpleaños ${sinSaltosDeLinea(nino.nombres)}! 🎂`,
          html,
        });
        enviados++;
      } catch (e) {
        console.error(`No se pudo enviar a ${correo} (niño ${doc.id}):`, e.message || e);
      }
    }
  }
  console.log(`Correo de cumpleaños: ${cumpleaneros.length} niño(s) cumplen hoy, ${enviados} correo(s) enviados, ${omitidos} niño(s) sin acudiente con correo válido.`);
}

// Todos los días a las 7:00am hora de Bogotá.
exports.correoCumpleanosDiario = onSchedule(
  {schedule: '0 7 * * *', timeZone: 'America/Bogota', secrets: [gmailAppPassword]},
  async () => {
    await enviarCorreosCumpleanosDeHoy();
  },
);

// ---------------------------------------------------------------------
// Recuperar contraseña — correo personalizado en español (2026-08-19).
// ---------------------------------------------------------------------
//
// Firebase Auth ya sabe generar el enlace de restablecimiento real
// (`generatePasswordResetLink`, Admin SDK — es el mismo mecanismo
// seguro de siempre, con el mismo enlace de un solo uso). Lo único que
// reemplaza esta función es QUIÉN entrega ese enlace: en vez del correo
// genérico de Firebase (en inglés, remitente "noreply@..."), se manda
// un correo propio desde `rokakidsarmenia@gmail.com`, con la misma
// plantilla visual y remitente "RocaKids" que ya usa el correo de
// cumpleaños. Llamada desde `AuthService.resetPassword()` en la app
// (paquete `cloud_functions`, función invocable/`onCall`).
function plantillaCorreoRecuperacion(link) {
  return `
  <div style="background:#f2f2f2;padding:24px 12px;font-family:Verdana,Arial,sans-serif;">
    <div style="max-width:480px;margin:0 auto;background:#ffffff;border:2px solid #003399;border-radius:20px;overflow:hidden;">
      <div style="background:linear-gradient(135deg,#003399,#2c5bb8);padding:24px 20px;text-align:center;">
        <div style="font-size:28px;line-height:1;margin-bottom:8px;">🔑</div>
        <div style="color:#ffffff;font-size:20px;font-weight:bold;letter-spacing:0.5px;">
          Restablece tu contraseña
        </div>
      </div>
      <div style="padding:24px;">
        <p style="font-size:15px;color:#1A1A2E;line-height:1.5;margin:0 0 16px;">¡Hola!</p>
        <p style="font-size:15px;color:#1A1A2E;line-height:1.5;margin:0 0 20px;">
          Recibimos una solicitud para restablecer la contraseña de tu cuenta en
          <b>RocaKids</b>. Toca el siguiente botón para elegir una nueva contraseña:
        </p>
        <div style="text-align:center;margin:0 0 20px;">
          <a href="${link}" style="display:inline-block;background:#ffcc00;color:#003399;
                    font-weight:bold;padding:12px 28px;border-radius:999px;font-size:15px;
                    text-decoration:none;">
            Restablecer contraseña
          </a>
        </div>
        <p style="font-size:13px;color:#666666;line-height:1.5;margin:0 0 8px;">
          Si tú no pediste este cambio, puedes ignorar este correo — tu contraseña
          actual seguirá funcionando sin ningún cambio.
        </p>
        <p style="font-size:13px;color:#666666;line-height:1.5;margin:0;">
          Este enlace vence en 1 hora por seguridad.
        </p>
      </div>
      <div style="padding:0 24px 24px;text-align:center;">
        <p style="font-size:12px;color:#9e9e9e;font-style:italic;margin:0;">
          Con cariño,<br/>
          <b style="color:#9e9e9e;">Tu familia de RocaKids ❤️</b>
        </p>
      </div>
    </div>
  </div>`;
}

// No lanza error al cliente en ningún caso (correo inválido, cuenta
// inexistente, o falla de envío) — mismo criterio de privacidad que ya
// tenía el cliente: nunca se revela si un correo está o no registrado
// en el sistema. `request.data` no requiere sesión iniciada (quien
// pide esto, por definición, no puede entrar).
exports.enviarCorreoRecuperacion = onCall(
  {secrets: [gmailAppPassword]},
  async (request) => {
    const correo = String(request.data?.correo || '').trim();
    if (!EMAIL_VALIDO.test(correo)) {
      return {enviado: false};
    }

    let link;
    try {
      // `generatePasswordResetLink` sigue siendo quien genera el
      // `oobCode` real (mecanismo de seguridad de Firebase, sin
      // cambios) — pero el LINK que devuelve apunta a la página
      // genérica alojada por Firebase (`handleCodeInApp` solo afecta
      // apps móviles con Dynamic Links, no cambia nada en Web). Por
      // eso se extrae el `oobCode` de ese enlace y se arma uno propio
      // hacia la app: `main.dart` ya sabe leer
      // `?mode=resetPassword&oobCode=...` de la URL y mostrar
      // `ResetPasswordScreen` en vez del login normal.
      const generado = await getAuth().generatePasswordResetLink(correo, {
        url: 'https://rocakidsarmenia-7935b.web.app',
      });
      const oobCode = new URL(generado).searchParams.get('oobCode');
      link = `https://rocakidsarmenia-7935b.web.app/?mode=resetPassword&oobCode=${encodeURIComponent(oobCode)}`;
    } catch (e) {
      console.log(`Recuperación de contraseña: ${correo} sin cuenta válida (${e.code || e.message}).`);
      return {enviado: false};
    }

    const transporter = nodemailer.createTransport({
      service: 'gmail',
      auth: {user: 'rokakidsarmenia@gmail.com', pass: gmailAppPassword.value()},
    });
    try {
      await transporter.sendMail({
        from: '"RocaKids" <rokakidsarmenia@gmail.com>',
        to: correo,
        subject: 'Restablece tu contraseña de RocaKids',
        html: plantillaCorreoRecuperacion(link),
      });
      console.log(`Recuperación de contraseña: correo enviado a ${correo}.`);
      return {enviado: true};
    } catch (e) {
      console.error(`No se pudo enviar correo de recuperación a ${correo}:`, e.message || e);
      return {enviado: false};
    }
  },
);

// ---------------------------------------------------------------------
// Notificaciones push (2026-09-02, pedido de Rafael: avisar a los
// servidores de un grupo cuando se les asigna un servicio). Primera
// etapa: solo la infraestructura (activar en el cliente + un envío de
// prueba) — todavía no está conectada a "asignar grupo" en
// Programación de Servidores, eso es el siguiente paso una vez se
// confirme que las notificaciones de prueba llegan de verdad.
// ---------------------------------------------------------------------

/// Manda una notificación push a una lista de uids (`usuarios/{uid}.fcmTokens`)
/// y limpia del perfil cualquier token que Firebase Cloud Messaging
/// devuelva como inválido/vencido (celular con la app desinstalada,
/// permiso revocado desde la configuración, etc.) — sin esto, esos
/// tokens muertos se seguirían intentando para siempre.
async function enviarNotificacionAUsuarios(uids, {titulo, cuerpo, datos}) {
  const uidsUnicos = [...new Set(uids)].filter(Boolean);
  if (uidsUnicos.length === 0) return {enviados: 0, fallidos: 0};

  const docs = await db.getAll(...uidsUnicos.map((uid) => db.collection('usuarios').doc(uid)));
  const tokensPorUid = new Map();
  const tokens = [];
  for (const doc of docs) {
    const propios = doc.exists ? doc.data().fcmTokens || [] : [];
    tokensPorUid.set(doc.id, propios);
    tokens.push(...propios);
  }
  if (tokens.length === 0) return {enviados: 0, fallidos: 0};

  const respuesta = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {title: titulo, body: cuerpo},
    data: datos || {},
    webpush: {fcmOptions: {link: 'https://rocakidsarmenia-7935b.web.app'}},
  });

  // Reconstruir qué token (índice de `tokens`) le tocó a cada uid, para
  // saber de qué documento quitarlo si falló como "ya no existe".
  const tokensInvalidos = new Set();
  respuesta.responses.forEach((r, i) => {
    const codigo = r.error && r.error.code;
    if (
      codigo === 'messaging/registration-token-not-registered' ||
      codigo === 'messaging/invalid-registration-token'
    ) {
      tokensInvalidos.add(tokens[i]);
    }
  });
  if (tokensInvalidos.size > 0) {
    const batch = db.batch();
    for (const [uid, propios] of tokensPorUid) {
      const aQuitar = propios.filter((t) => tokensInvalidos.has(t));
      if (aQuitar.length > 0) {
        batch.update(db.collection('usuarios').doc(uid), {
          fcmTokens: FieldValue.arrayRemove(...aQuitar),
        });
      }
    }
    await batch.commit();
  }

  return {enviados: respuesta.successCount, fallidos: respuesta.failureCount};
}

// Se manda a sí mismo, para poder probar de punta a punta que un
// dispositivo que activó notificaciones sí las recibe, antes de
// conectar esto a ningún evento real de la app.
exports.enviarNotificacionPrueba = onCall(async (request) => {
  if (!request.auth) {
    throw new Error('Necesitas iniciar sesión.');
  }
  const resultado = await enviarNotificacionAUsuarios([request.auth.uid], {
    titulo: 'RocaKids',
    cuerpo: '¡Notificaciones activadas correctamente!',
  });
  return resultado;
});

// ---------------------------------------------------------------------
// Resumen mensual de asistencia — mantiene el Dashboard rápido (2026-08-19).
// ---------------------------------------------------------------------
//
// El bloque "Histórico" del Dashboard (`admin/dashboard_screen.dart`)
// traía TODAS las Entradas alguna vez registradas (~3738+ tras la
// migración) en una sola consulta cada vez que se abría la pantalla —
// lento, sobre todo en celular. En vez de eso, esta función mantiene un
// documento por mes en `resumenes_mensuales/{AAAA-MM}` con los totales
// ya agregados, actualizado incrementalmente en cada Entrada nueva — el
// Dashboard ahora solo lee un puñado de documentos chiquitos (uno por
// mes transcurrido) en vez de miles de registros crudos.
//
// `ninos/{id}.primeraAsistencia` (nuevo campo) guarda cuándo fue la
// PRIMERA Entrada de ese niño en toda la historia — se fija una sola
// vez (dentro de una transacción, para no contarlo dos veces si dos
// Entradas llegaran casi simultáneas) y es lo que alimenta
// `resumenes_mensuales/{mes}.ninosNuevos`, la base del gráfico de
// "Crecimiento de niños registrados (acumulado)".
//
// `ninos/{id}.totalEntradas`/`ultimaAsistencia` (2026-08-21) alimentan
// el reporte "Niños que dejaron de asistir" del Dashboard: cuántas
// Entradas tiene en total y cuándo fue la más reciente. Se mantienen
// junto a `primeraAsistencia` en la misma transacción (mismo motivo:
// evitar una carrera si dos Entradas del mismo niño llegan casi
// simultáneas). El histórico previo a este cambio se calculó una sola
// vez con `AuthService.backfillEstadisticasAsistencia()` — ver
// docs/estado-proyecto.md.
function mesIdBogota(fecha) {
  const bogota = new Date(fecha.getTime() - OFFSET_BOGOTA_HORAS * 3600 * 1000);
  return `${bogota.getUTCFullYear()}-${String(bogota.getUTCMonth() + 1).padStart(2, '0')}`;
}

async function actualizarEstadisticasNino(ninoId, fechaMovimiento, mesId) {
  const ninoRef = db.collection('ninos').doc(ninoId);
  const resumenRef = db.collection('resumenes_mensuales').doc(mesId);
  await db.runTransaction(async (tx) => {
    const ninoDoc = await tx.get(ninoRef);
    if (!ninoDoc.exists) return;
    const datos = ninoDoc.data();

    // Un solo `tx.update()` por documento — Firestore no permite más de
    // una escritura sobre la misma referencia dentro de una transacción.
    const actualizacion = {totalEntradas: FieldValue.increment(1)};
    const ultimaActual = datos.ultimaAsistencia;
    if (!ultimaActual || fechaMovimiento.toMillis() > ultimaActual.toMillis()) {
      actualizacion.ultimaAsistencia = fechaMovimiento;
    }
    if (!datos.primeraAsistencia) {
      actualizacion.primeraAsistencia = fechaMovimiento;
      tx.set(resumenRef, {ninosNuevos: FieldValue.increment(1)}, {merge: true});
    }
    tx.update(ninoRef, actualizacion);
  });
}

exports.actualizarResumenMensual = onDocumentCreated(
  'registros/{registroId}',
  async (event) => {
    const registro = event.data?.data();
    if (!registro || registro.tipoMovimiento !== 'Entrada') return;

    try {
      const fecha = registro.fechaMovimiento.toDate();
      const mesId = mesIdBogota(fecha);
      const resumenRef = db.collection('resumenes_mensuales').doc(mesId);

      const actualizacion = {totalEntradas: FieldValue.increment(1)};
      if (registro.servicio) {
        actualizacion[`porServicio.${registro.servicio}`] = FieldValue.increment(1);
      }
      await resumenRef.set(actualizacion, {merge: true});

      if (registro.fkIdNino) {
        await actualizarEstadisticasNino(registro.fkIdNino, registro.fechaMovimiento, mesId);
      }
    } catch (e) {
      console.error('actualizarResumenMensual falló para', event.params.registroId, ':', e);
    }
  },
);
