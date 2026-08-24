/// A quién está dirigido cada capítulo del manual (`ManualUsuarioScreen`,
/// `manual_pdf.dart`). No tiene relación con `RolUsuario`: un mismo
/// capítulo puede aplicar a varios roles reales (ej. "Servidores" agrupa
/// maestro auxiliar, maestro principal, líder escuela de siervos, etc.).
enum AudienciaManual { acudientes, servidores, liderazgo }

/// Un tema dentro de un capítulo: título, la captura de pantalla real
/// que lo ilustra (nombre de archivo dentro de `assets/images/manual/`,
/// sin ruta — la resuelve quien lo use), y los pasos/puntos explicados
/// en lenguaje simple.
class ManualSeccion {
  final String titulo;
  final String imagen;
  final List<String> puntos;

  const ManualSeccion({
    required this.titulo,
    required this.imagen,
    required this.puntos,
  });
}

class ManualCapitulo {
  final AudienciaManual audiencia;
  final String titulo;
  final String descripcion;
  final List<ManualSeccion> secciones;

  const ManualCapitulo({
    required this.audiencia,
    required this.titulo,
    required this.descripcion,
    required this.secciones,
  });
}

/// Contenido completo del manual — texto fijo, no depende de Firestore.
/// Se mantiene a mano junto con el resto de la app: cuando una pantalla
/// cambie de verdad, este archivo (y sus capturas en
/// `assets/images/manual/`) hay que actualizarlos también.
const manualCapitulos = <ManualCapitulo>[
  ManualCapitulo(
    audiencia: AudienciaManual.acudientes,
    titulo: 'Para acudientes (padres y madres)',
    descripcion:
        'Cómo crear tu cuenta, vincular a tus hijos y mantener su información al día.',
    secciones: [
      ManualSeccion(
        titulo: 'Crear tu cuenta',
        imagen: 'registro_acudiente.png',
        puntos: [
          'En la pantalla de inicio de sesión, toca "Soy Acudiente".',
          'Completa tus datos (documento, nombre, teléfono, correo, contraseña) y los de tu primer hijo o hija.',
          'Si tu hijo ya fue registrado antes por otra persona (por ejemplo el otro papá o mamá), búscalo por su número de documento en vez de crear una ficha nueva — así evitas duplicados.',
        ],
      ),
      ManualSeccion(
        titulo: 'Iniciar sesión',
        imagen: 'login.png',
        puntos: [
          'Ingresa con tu correo electrónico y contraseña.',
          'Si aún no tienes cuenta, usa "¿No tienes cuenta?" y elige "Soy Acudiente".',
          'Si olvidaste tu contraseña, toca "¿Olvidaste tu contraseña?" y sigue las instrucciones que llegan a tu correo.',
        ],
      ),
      ManualSeccion(
        titulo: '"Mis hijos"',
        imagen: 'mis_hijos.png',
        puntos: [
          'Aquí ves a todos los niños vinculados a tu cuenta, con su edad y documento.',
          'Toca "Agregar hijo" para vincular otro hijo — propio o ya registrado por alguien más.',
          'Toca cualquier niño de la lista para abrir su ficha completa.',
        ],
      ),
      ManualSeccion(
        titulo: 'Ficha de un hijo',
        imagen: 'ficha_nino.png',
        puntos: [
          'Muestra documento, fecha de nacimiento, grupo del ministerio infantil, autorización de foto y alertas médicas.',
          '"Editar información" solo está disponible para el padre o la madre — no para tíos, abuelos u otros autorizados a retirarlo.',
          '"Quitar de mis hijos" deshace el vínculo sin borrar al niño ni tus datos — útil si te vinculaste por error.',
        ],
      ),
      ManualSeccion(
        titulo: 'Cambiar tu contraseña',
        imagen: 'cambiar_password.png',
        puntos: [
          'Desde el menú, "Cambiar contraseña", en cualquier momento.',
          'Debes escribir tu contraseña actual antes de definir una nueva.',
        ],
      ),
    ],
  ),
  ManualCapitulo(
    audiencia: AudienciaManual.servidores,
    titulo: 'Para maestros y líderes',
    descripcion:
        'El día a día de recibir y entregar niños: registrar entradas, salidas y familias nuevas.',
    secciones: [
      ManualSeccion(
        titulo: 'El menú principal',
        imagen: 'inicio_menu.png',
        puntos: [
          'El menú de la izquierda (o el ícono ☰ en el celular) lleva a cada sección de la app.',
          'Lo que ves depende de tu rol: un maestro ve menos opciones que un líder de ministerio o un administrador.',
          '"Mi perfil" y "Cambiar contraseña" están siempre al final, para cualquier cuenta.',
        ],
      ),
      ManualSeccion(
        titulo: 'Menores Registrados (quién está presente)',
        imagen: 'menores_recibidos.png',
        puntos: [
          'Vista en vivo de quién está presente ahora mismo, agrupada por grupo de edad (José, David, Judá, Daniel, Santiago).',
          'El botón "+" abre el registro de una nueva ENTRADA (ver siguiente sección) — ya no es una opción aparte en el menú.',
          'Desliza la tarjeta de un niño para registrar su SALIDA, eligiendo quién lo retira de la lista de acudientes vinculados.',
          'Si la persona que retira tiene una restricción de seguridad, la app te lo advierte en rojo antes de confirmar.',
        ],
      ),
      ManualSeccion(
        titulo: 'Registrar una entrada',
        imagen: 'registro_asistencia.png',
        puntos: [
          'Se abre con el botón "+" de "Menores Registrados".',
          'Busca al niño por nombre para registrar su ENTRADA.',
          'Si es la primera vez que viene y no tiene ficha, usa "Es la primera vez que viene (visitante)".',
          'Si el niño no tiene documento registrado, la app te deja continuar igual, con una advertencia — no es obligatorio para poder recibirlo.',
          'No se puede duplicar una entrada: si el niño ya está presente, la app te avisa y no muestra el botón de registrar — la salida se hace desde "Menores Registrados".',
        ],
      ),
      ManualSeccion(
        titulo: 'Registrar familia',
        imagen: 'registrar_familia.png',
        puntos: [
          'Úsala cuando llega una familia nueva, o cuando quieras vincular un niño que ya existe a un acudiente que ya existe.',
          'Siempre busca primero por documento (acudiente) o por nombre (niño) antes de llenar datos nuevos — evita duplicar fichas.',
          'Cubre las cuatro combinaciones posibles: acudiente y niño nuevos, o cualquiera de los dos ya registrado.',
        ],
      ),
      ManualSeccion(
        titulo: 'Cumpleaños niños',
        imagen: 'cumpleanos_ninos.png',
        puntos: [
          'Niños que cumplieron años en los últimos 7 días, para felicitarlos en el salón.',
          'Toca un niño para abrir su ficha completa.',
        ],
      ),
      ManualSeccion(
        titulo: 'Mi perfil',
        imagen: 'mi_perfil.png',
        puntos: [
          'Tus propios datos de servidor: documento, teléfono, EPS, grupo sanguíneo y contacto de emergencia.',
          'Mantenlos actualizados — son los que se usan si algo pasa mientras estás sirviendo.',
          'La verificación de antecedentes la registra únicamente un administrador.',
        ],
      ),
    ],
  ),
  ManualCapitulo(
    audiencia: AudienciaManual.liderazgo,
    titulo: 'Para administración y liderazgo',
    descripcion:
        'Panel completo del ministerio: cifras, aprobación de servidores y modo emergencia.',
    secciones: [
      ManualSeccion(
        titulo: 'Dashboard',
        imagen: 'dashboard.png',
        puntos: [
          'Totales del sistema: niños registrados, acudientes, servidores activos, niños graduados.',
          '"Pendientes" agrupa lo que falta completar: niños sin foto o sin documento, acudientes sin foto o sin correo.',
          '"Hoy" resume el movimiento del día — recibidos, presentes ahora, visitantes — y hay un desglose por grupo de edad y por servicio.',
        ],
      ),
      ManualSeccion(
        titulo: 'Acudientes y Niños',
        imagen: 'acudientes_y_ninos.png',
        puntos: [
          'Panel de consulta de todos los niños y acudientes registrados en el sistema, con búsqueda por nombre.',
          'Disponible solo para administrador, columna y líder de ministerio — no para maestros.',
          'Desde aquí también se edita o elimina una ficha cuando hace falta.',
        ],
      ),
      ManualSeccion(
        titulo: 'Gestión de Servidores',
        imagen: 'gestion_servidores.png',
        puntos: [
          'Aprueba las cuentas de servidores pendientes de aprobación (creadas al registrarse como "Soy Servidor").',
          'Asigna o cambia el rol de cada servidor, y activa o desactiva su cuenta.',
          'Solo visible para el administrador.',
        ],
      ),
      ManualSeccion(
        titulo: 'Cumpleaños Servidores',
        imagen: 'cumpleanos_servidores.png',
        puntos: [
          'Igual que "Cumpleaños niños", pero para el equipo de servidores.',
          'Depende de que cada servidor haya llenado su propia fecha de nacimiento en "Mi perfil".',
        ],
      ),
      ManualSeccion(
        titulo: 'Modo emergencia',
        imagen: 'modo_emergencia.png',
        puntos: [
          'Solo administrador, columna y líder de ministerio pueden activarlo o desactivarlo.',
          'Mientras está activo, toda la app queda bloqueada para el resto de servidores y acudientes, salvo la pantalla de emergencia.',
          'Cada salida durante la emergencia exige foto y firma de quien retira al niño — quedan como evidencia.',
          '"Generar reporte PDF (hoy)" arma la constancia del día: quién entregó cada niño originalmente según RocaKids, comparado con quién lo retiró en la emergencia.',
        ],
      ),
    ],
  ),
];
