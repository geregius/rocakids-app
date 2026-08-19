# RocaKids — Estado del Proyecto (guía de continuación)

**Última actualización:** 2026-08-18
**Propósito de este documento:** que una conversación nueva (u otra persona) pueda retomar el desarrollo sin perder contexto. Resume qué existe, qué funciona, cómo está armado, y qué falta.

Documentos relacionados en `docs/`:
- [`SOP-RocaKids-v2.0.md`](SOP-RocaKids-v2.0.md) — especificación funcional original (fuente de verdad de reglas de negocio).
- [`plan-desarrollo.md`](plan-desarrollo.md) — plan de módulos original (roadmap aspiracional; este documento (`estado-proyecto.md`) es el que refleja la realidad actual).

---

## 1. Datos clave del proyecto

| Cosa | Valor |
|---|---|
| Carpeta local del proyecto | `D:\Konektu\Proyecto RocaKids` |
| Repo de GitHub | https://github.com/geregius/rocakids-app (privado) |
| App Flutter | dentro de `/app` en el repo |
| Proyecto Firebase | `rocakidsarmenia-7935b` |
| URL pública (Hosting) | https://rocakidsarmenia-7935b.web.app |
| QR de acceso a la app | [`QR Aplicación.png`](../QR%20Aplicaci%C3%B3n.png) en la raíz del repo — QR para compartir con acudientes/servidores, apunta a la URL de Hosting. Por eso el fix de caché de la sección 8 es importante: quien entra por este QR debe ver siempre la versión más reciente sin pasos extra. |
| Región Firestore | `southamerica-east1` (São Paulo) |
| Región Storage (bucket) | `us-east1` — **a propósito distinta** a Firestore, es la única forma de tener el nivel gratuito real de Storage (`southamerica-east1` no tiene capa gratuita) |
| Plan de Firebase | Blaze (pago por uso), pero configurado para costo real ≈ $0 en este volumen |
| Alerta de presupuesto | ✅ **Confirmada y corregida el 2026-08-18** — ya existía pero mal configurada (1 COP, un placeholder que dejó Firebase automáticamente). Corregida a 5 USD/mes, avisos a 50/90/100% del gasto. Es una alerta por correo, NO un corte automático de servicio. |
| Backups de Firestore | `gs://rocakidsarmenia-7935b-backups/` (bucket nuevo, misma región que Firestore) — ahí vive el export de antes de la migración de datos reales, ver [[restore-point-pre-migracion-modulo2]] en la memoria |

---

## 2. Entorno de desarrollo (ya instalado en la máquina de Rafael)

Todo esto ya está instalado y funcionando en el computador donde se ha trabajado (Windows):

- **Flutter SDK** (canal stable) clonado en `C:\src\flutter`, agregado al PATH de usuario.
- **Android Studio** + Android SDK + cmdline-tools, licencias aceptadas. `flutter doctor` en verde para Android y Web.
- **Node.js LTS** (via winget) — necesario para Firebase CLI.
- **Firebase CLI** (`firebase-tools`, instalado global con npm).
- **FlutterFire CLI** (`dart pub global activate flutterfire_cli`).
- **Google Cloud SDK** (`gcloud`/`gsutil`) — se instaló específicamente para configurar CORS del bucket de Storage. Puede ser útil para más administración de infraestructura a futuro.
- Autenticado: `firebase login` y `gcloud auth login`, ambos con la cuenta `rafaelbalaguera@gmail.com`.

**Importante sobre el flujo de trabajo:** los comandos que abren una ventana de login de Google (`git push` la primera vez, `firebase login`, `gcloud auth login`) **no funcionan bien si Claude los ejecuta directamente** — la ventana de navegador no se abre correctamente desde ese contexto. La solución que funcionó: pedirle a Rafael que corra el comando él mismo en su propia terminal. Una vez autenticado una vez, las siguientes ejecuciones sí funcionan bien desde Claude.

### Comandos típicos para seguir trabajando

```bash
# Ir a la carpeta del proyecto Flutter
cd "D:/Konektu/Proyecto RocaKids/app"

# Instalar dependencias
flutter pub get

# Verificar que no haya errores
flutter analyze
flutter test

# Probar localmente (abre Chrome)
flutter run -d chrome --web-port=5050

# Compilar y publicar a producción
flutter build web
firebase deploy --only hosting --project rocakidsarmenia-7935b

# Desplegar solo reglas de Firestore o Storage
firebase deploy --only firestore:rules --project rocakidsarmenia-7935b
firebase deploy --only storage --project rocakidsarmenia-7935b
```

**Nota sobre caché al probar cambios:** Flutter Web usa un "service worker" que cachea la app. Un F5 normal no siempre trae la versión nueva. Soluciones: ventana de incógnito, o en DevTools (F12) → pestaña **Application** → **Service Workers** → marcar **"Update on reload"**.

---

## 3. Stack técnico

- **Frontend:** Flutter (un solo código para Android, iOS y Web). Paquetes clave: `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_storage`, `image_picker`, `google_fonts`.
- **Backend:** 100% Firebase — Authentication, Firestore (base de datos), Storage (fotos), Hosting (la web pública), y desde 2026-08-15 **Cloud Functions** (`/app/functions`, Node.js 20, plan Blaze) — ver sección 5.5.
- **Tipografía:** Fredoka (Google Fonts) — sustituto libre de VAG Rounded BT (la fuente real del logo, que es de pago).
- **Paleta de marca** (`lib/theme/app_colors.dart`): azul marino `#003399` (primario), azul claro `#2C5BB8`, azul oscuro `#002266`, amarillo `#FFCC00`, rojo `#E50000`, púrpura `#990099`.
- **CI:** GitHub Actions (`.github/workflows/flutter-ci.yml`) corre `flutter analyze` + `flutter test` en cada push/PR a `main`.

---

## 4. Estructura del repo

```
/app                    → proyecto Flutter
  /lib
    /models             → UsuarioApp, Acudiente, Nino, NinoAcudiente
    /screens            → todas las pantallas (ver sección 6)
      /admin            → pantallas exclusivas de administrador
    /services           → AuthService (único punto de acceso a Firebase)
    /theme              → colores y tema visual
    /utils              → foto_picker.dart (selector cámara/galería reutilizable), selector_fecha_nacimiento.dart (día/mes/año + edad/grupo en vivo, ver sección 5)
    /widgets            → app_shell.dart (menú lateral + layout responsivo, ver sección 6)
  /assets/images         → logo_rocakids.png (completo), logo_rocakids_compacto.png (sin tagline, para espacios chicos)
  /functions              → Cloud Functions (Node.js, ver sección 5.5) — cierre automático de asistencia
  firestore.rules        → reglas de seguridad de Firestore
  storage.rules           → reglas de seguridad de Storage
  storage-cors.json       → configuración CORS aplicada al bucket (vía gsutil)
/docs                    → SOP, plan de desarrollo, este documento
/.github/workflows        → CI
```

---

## 5. Modelo de datos actual (Firestore)

### `usuarios/{uid}` — capa de acceso y rol (TODA cuenta con login tiene un doc acá)
Campos: `correo`, `nombre`, `apellido`, `rol`, `activo`, `creadoEn`, y campos de perfil de servidor (ver abajo).

**Roles** (`lib/models/usuario_app.dart` → `RolUsuario`):
`administrador`, `lider_ministerio`, `columna`, `lider_escuela_siervos`, `maestro_principal`, `maestro_auxiliar`, `usuario_externo`, `pendiente`, `desconocido`.

⚠️ **Solo `administrador` tiene pantallas funcionales hoy.** Los demás roles de servidor (líder ministerio, columna, maestro, etc.) ya existen en el modelo y se pueden asignar desde el panel admin, pero al iniciar sesión ven una pantalla genérica "módulo en construcción" — sus herramientas específicas están pendientes de construir.

Campos de **perfil de servidor** (obligatorios antes de poder usar la app, una vez el admin asigna el rol): `tipoDocumento`, `numeroDocumento`, `telefono`, `epsNombre`, `grupoSanguineo`, `contactoEmergenciaNombre`, `contactoEmergenciaTelefono`, `fotoUrl`. Además `fechaVerificacionAntecedentes` (Timestamp, **solo lo edita un admin**, no autoreportable).

### `acudientes/{uid}` — perfil de acudiente (independiente del rol)
Campos: `tipoDocumento`, `numeroDocumento`, `nombres`, `apellidos`, `telefonoCelular`, `correoElectronico`, `fotoSeguridadUrl`, `estadoAutorizacion` (Autorizado/Restringido, solo admin lo cambia), `observacionesRestriccion` (solo admin).

Cualquier cuenta (admin, maestro, etc.) puede además tener un doc acá — "ser acudiente" no es un rol, es una capacidad que cualquiera puede activar desde "Mis hijos".

### `acudientes_documentos/{numeroDocumento}` — reserva de unicidad
Solo contiene `{uid}`. Existe únicamente para que las reglas de seguridad bloqueen que dos cuentas se registren con el mismo número de documento de acudiente (patrón "create-only": si el doc ya existe, el segundo intento cae en "update", que está prohibido).

### `ninos/{documentoIdentificacion}` — el ID del documento ES la llave primaria
El **ID del documento en Firestore** es el documento real del menor, o si no tiene, la llave interna generada según el SOP §3.2 (`fechaNacimiento-PRIMERNOMBRE-PRIMERAPELLIDO`, ver `generarLlaveInterna()` en `lib/models/nino.dart`). Esto previene duplicados de la misma forma que `acudientes_documentos`, sin necesitar una colección aparte.

Campos: `tipoIdentificacion`, `identificacionMenor`, `nombres`, `apellidos`, `fechaNacimiento`, `genero`, `estadoRegistro`, `alertaMedicaFlag`, `condicionMedica`, `autorizoFotoFlag`, `fotoUrl`.

**Edición (2026-08-14):** solo un admin, o el acudiente vinculado con `parentescoTipo` **Padre o Madre** (no tíos/abuelos/otros autorizados), puede editar `nombres`, `apellidos`, `fechaNacimiento`, `genero`, `autorizoFotoFlag`, `alertaMedicaFlag`, `condicionMedica` — desde "Editar información" en `nino_detalle_sheet.dart` (`editar_nino_sheet.dart`). A propósito **NO** se puede editar así `tipoIdentificacion`/`identificacionMenor` (cambiarlos movería la llave primaria del documento — una migración más delicada, no soportada todavía) ni `estadoRegistro`/`fotoUrl` (quedan admin-only). Ver `esPadreOMadreDe()` en `firestore.rules` — depende de que `nino_acudiente` tenga ID determinístico (ver abajo).

**Grupo/aula del ministerio infantil — a propósito NO es un campo de esta colección.** Se calcula en la UI a partir de la edad actual (`grupoParaEdad()` en `lib/models/nino.dart`), nunca se guarda: el grupo de un niño cambia con el tiempo según su edad en cada visita, así que guardarlo en el registro del menor lo dejaría desactualizado. Grupos actuales (fijados por Rafael, 2026-08-14):

| Grupo | Edad |
|---|---|
| José | 2 años |
| David | 3-4 años |
| Judá | 5-6 años |
| Daniel | 7-8 años |
| Santiago | 9-10 años |

RocaKids solo recibe niños de 2 a 10 años (`edadMinimaRegistro`/`edadMaximaRegistro` en `nino.dart`) — el registro de un niño fuera de ese rango queda bloqueado con un mensaje de error, tanto en el registro inicial de acudiente (`sign_up_acudiente_screen.dart`) como al agregar un hijo adicional (`agregar_hijo_screen.dart`). El campo de fecha de nacimiento en ambos formularios usa `SelectorFechaNacimiento` (día/mes/año en dropdowns en vez de un calendario, con el año acotado al rango plausible 2-10 años) y muestra la edad y el grupo calculados en vivo mientras se llena.

### `ninos_busqueda/{documentoIdentificacion}` — índice de búsqueda por nombre (mismo ID que `ninos`)
Copia mínima de cada niño: **solo** `nombres`, `apellidos`, `fechaNacimiento` — a propósito SIN foto, documento real ni info médica. Se escribe junto con `ninos` en el mismo batch al registrar un niño (`registrarAcudienteConNino`, `registrarNinoAdicional` en `auth_service.dart`).

**Por qué existe (decisión de privacidad, 2026-08-14):** al vincular un niño ya registrado, Rafael pidió poder buscarlo por nombre con una lista en vivo en vez de solo por número de documento. El riesgo: las reglas de Firestore no pueden ocultar campos específicos de un documento, así que si la búsqueda usara `ninos` directamente, cualquier cuenta logueada podría "navegar" el nombre, foto, documento real y alertas médicas de niños con los que no tiene ningún vínculo. Rafael eligió explícitamente la opción seria: la búsqueda solo expone nombre + edad; el resto de la ficha se revela solo después de vincular (o si ya eres su acudiente).

Los niños registrados ANTES del 2026-08-14 no tenían documento en esta colección (se empezó a escribir recién con esta feature). Existió un botón admin **"Reindexar búsqueda de niños"** para rellenar los que faltaran — se corrió una vez el 2026-08-14 y **se eliminó el 2026-08-17** (junto con "Migrar vínculos niño-acudiente" y "Sincronizar presencia de niños") porque los datos de prueba se van a borrar antes del lanzamiento real, así que no va a quedar nada "viejo" que estas herramientas de migración de una sola vez necesiten arreglar. **Importante para el Módulo 2 (migración de datos):** el script de importación masiva debe escribir también en `ninos_busqueda` directamente — ya no hay un botón de respaldo si se le olvida.

`lib/models/nino.dart` → clase `NinoBusqueda` (con `coincideBusqueda()`, comparación sin distinguir mayúsculas/acentos). La búsqueda se trae completa una vez (`AuthService.obtenerIndiceBusquedaNinos()`) y se filtra en el cliente mientras se escribe — no hay índice por prefijo en Firestore, no hace falta para el volumen de una sola congregación.

### `nino_acudiente/{ninoId}_{acudienteUid}` — relación muchos-a-muchos
Campos: `fk_idNino`, `fk_idAcudiente`, `parentescoTipo`, `autorizacionFormulario`, `autorizacionImagen`, `esRepresentanteLegalFlag`. Un niño puede tener varios acudientes, y un acudiente varios niños — ya soportado y probado.

**El ID del documento cambió de aleatorio a determinístico (`{fkIdNino}_{fkIdAcudiente}`) el 2026-08-14.** Motivo: para poder chequear en `firestore.rules` "¿esta persona es el padre/madre de este niño?" con una sola lectura directa (`exists()`/`get()` por ID), en vez de una consulta — necesario para permitir que el padre/madre edite la ficha del niño (ver abajo). Efecto colateral bueno: ahora también previene vínculos duplicados por diseño (mismo patrón create-only que `ninos`/`acudientes_documentos`), algo que antes solo se evitaba con una consulta manual en `vincularNinoExistente`.

**Los vínculos creados ANTES del 2026-08-14 quedaron con su ID aleatorio viejo** — no calzaban con lo que esperan las reglas nuevas. Existió un botón admin "Migrar vínculos niño-acudiente" para pasarlos al esquema nuevo; se corrió una vez y **se eliminó el 2026-08-17** (ver nota en `ninos_busqueda` arriba — datos de prueba se van a borrar, y todo vínculo nuevo ya usa el ID determinístico desde el código, así que no hace falta la herramienta de migración).

### `registros/{autoId}` — entrada/salida de niños (Módulo 4, Fase 1 — 2026-08-14)
Campos: `fkIdNino` (vacío si es visitante), `nombreNinoVisitante`, `tipoMovimiento` (Entrada/Salida), `fechaMovimiento`, `numeroManilla`, `fkIdServidor`, `nombreServidor`, `fkIdAcudienteContacto`, `nombreAcudienteContacto`, `telefonoAcudienteVisitante`, `alertaMedicaVisitante`, `condicionMedicaVisitante`, `modalidadRegistro` (`'App'` para lo escrito desde la app por una persona; `'Automático'` desde 2026-08-15 para los cierres que hace la Cloud Function — ver sección 5.5), `servicio`, `grupoEdad`, `observacion`.

**Fuente de verdad real:** no el SOP (que documenta un enum de `modalidadRegistro` que no coincide con lo real), sino el export real `D:\Downloads\DB RocaKids V2 (15).xlsx` → pestaña `REGISTROS` (3873 movimientos históricos). De ahí salió la lista de `Servicio` (`serviciosDisponibles` en `lib/models/registro.dart`): Domingo 1° Servicio, Domingo 2° Servicio, Miércoles, Ayuno, Casa2 — y la confirmación de que `grupoEdad` casi nunca se llenaba a mano en el sistema viejo (por eso se calcula automático, nunca manual, para niños ya registrados).

**Decisiones de esta fase (confirmadas por Rafael, 2026-08-14):**
- **Solo registro manual, con internet.** Sin escáner QR ni modo offline todavía — quedan para después, una vez esto se use en la iglesia y funcione bien.
- **Quién puede registrar:** Administrador, Columna, Líder de Ministerio, Líder Escuela de Siervos, Maestro Principal, Maestro Auxiliar (`puedeRegistrarAsistencia()` en `firestore.rules` — básicamente todos los roles de servidor, `usuario.rol.esRolDeServidor`).
- **Manilla:** campo de texto libre (no hay lista fija de manillas por salón, coincide con el dato real).
- **Servicio pre-seleccionado según el día/hora (2026-08-15):** `servicioSugerido()` en `registro.dart` — miércoles→Miércoles, viernes→Casa2, sábado→Ayuno, domingo antes de las 10:00am→Domingo 1° Servicio, domingo desde las 10:00am→Domingo 2° Servicio, cualquier otro día→sin sugerencia (el servidor elige a mano). Es solo un valor inicial del dropdown — se puede cambiar igual si hace falta.
- **Niño visitante (sin cuenta previa):** SÍ soportado desde ya, para no rechazar a nadie en la puerta — se guarda solo en el `registro` (nombre, adulto que lo trae, teléfono, alerta médica, grupo elegido a mano ya que no hay fecha de nacimiento), sin crear `ninos`/`acudientes`. ⚠️ Limitación conocida: como el visitante no queda en `ninos_busqueda`, no se puede "buscar" para registrarle la salida después desde `registro_asistencia_screen.dart` — pero SÍ puede dársele salida deslizando su tarjeta en "Menores Recibidos" (ver sección 6), o le llega igual por el cierre automático (sección 5.5) si nadie lo hace a mano. Si un visitante vuelve, lo ideal es registrarlo formalmente (acudiente o maestro) para que tenga ficha completa.
- Quién entrega/retira a un niño YA registrado se elige de la lista de acudientes vinculados (`AuthService.obtenerAcudientesDeNino()`, vía `nino_acudiente`) con su foto de seguridad para verificar identidad — y si su `estadoAutorizacion` es `Restringido`, se lo advierte en rojo al servidor. Esto es el control de seguridad real del que habla el SOP. Hay opción "Otro" con nombre libre por si quien retira no está en la lista.
- **⚠️ El bloqueo de niño sin documento (2026-08-14) SE QUITÓ el 2026-08-17.** Historia: pensando en la migración del Módulo 2 (muchos de los ~578 niños reales no tienen `identificacionMenor`), se bloqueaba por completo cualquier movimiento (Entrada/Salida) de un niño sin documento, en 3 capas (UI, revalidación del cliente, regla de Firestore). **Rafael probó esto en la práctica y no funcionó** ("no puedo hacer esto") — en el mundo real no siempre se puede conseguir el documento en el momento. Nueva decisión: **se permite el registro igual, con una advertencia.**
  - **Advertencia normal:** si el niño (ya registrado, con ficha en `ninos`) no tiene `identificacionMenor`, se muestra un aviso (`_avisoSinDocumento()` en `registro_asistencia_screen.dart`) mientras el formulario de Entrada/Salida sigue disponible normalmente. El mini-formulario para completar el documento ahí mismo (`AuthService.completarDocumentoNino()`) se mantiene, pero ahora es **opcional**, no obligatorio.
  - **Advertencia reforzada:** si además ese niño ya tuvo **más de 2 Entradas en los últimos 30 días** sin documento (`AuthService.contarEntradasUltimoMes()`, nuevo índice compuesto `fkIdNino`+`tipoMovimiento`+`fechaMovimiento` en `firestore.indexes.json`), el aviso cambia a un estilo más fuerte (rojo, borde, ícono de bloqueo) pidiendo insistir con la familia — pero SIGUE sin bloquear el registro.
  - **Niños VISITANTE:** el documento (`tipoIdentificacionVisitante`/`documentoNinoVisitante`) pasó de obligatorio a **opcional**, con una nota debajo del campo. No se implementó conteo de repetición para visitantes (no tienen una identidad estable entre visitas — cada entrada de visitante es un registro anónimo distinto, no hay forma de saber si es "el mismo niño" que volvió).
  - **Firestore:** la condición de documento se quitó por completo de la regla `create` de `registros` — solo queda el bloqueo de Entrada duplicada (`ninoYaPresente()`, sin cambios).
- **No se puede duplicar la Entrada de un niño ya presente (2026-08-17):** pedido de Rafael, para que no quede el mismo niño "registrado 2 veces" el mismo día (ej. dos servidores registrándolo casi al mismo tiempo). Solo bloquea una SEGUNDA Entrada mientras sigue presente — un niño SÍ puede volver a entrar el mismo día después de una Salida real (ej. 1° y 2° servicio del domingo). Se apoya en un campo nuevo `ninos/{id}.presente` (bool), que `AuthService.registrarMovimiento()` actualiza en el MISMO batch atómico que crea el `Registro` (`true` en una Entrada, `false` en una Salida) — así la regla de Firestore (`ninoYaPresente()`) puede rechazar la segunda Entrada aunque dos servidores la envíen casi al mismo tiempo, no es solo una validación de la UI. Los cierres automáticos (sección 5.5) también limpian este flag al cerrar a un niño, para que no quede bloqueado para siempre. Existió un botón admin "Sincronizar presencia de niños" para marcar retroactivamente a quien ya estaba presente antes de este cambio — se corrió una vez y **se eliminó el 2026-08-17** (mismo motivo que las otras 2 herramientas de migración: los datos de prueba se van a borrar).
  - **Ajuste el mismo día, tras la primera prueba de Rafael:** el intento inicial dejaba que la pantalla, al buscar de nuevo a un niño ya presente, mostrara el formulario de SALIDA (comportamiento previo del toggle Entrada/Salida) — Rafael probó y terminó dándole salida sin querer, pensando que estaba probando el bloqueo de Entrada. Se ajustó `registro_asistencia_screen.dart`: **esta pantalla ahora es solo para registrar ENTRADAS.** Si el niño buscado ya está presente (`_accion == 'Salida'`), se le sigue permitiendo seleccionarlo (para no generar confusión de "no lo encuentro"), pero se muestra un aviso ("Este niño ya tiene una entrada registrada hoy...") **sin ningún botón de registrar**. Dar la salida ahora es EXCLUSIVO de "Menores Recibidos" (deslizar la tarjeta, sección 6).

**Reglas de Firestore:** nueva función `puedeRegistrarAsistencia()` (lista fija de roles). `nino_acudiente` se abrió a `get`/`list` para cualquier autenticado (antes solo el propio acudiente o admin) — hace falta para poder ver quién puede retirar a CUALQUIER niño, no solo a los propios. Nuevo índice compuesto en `firestore.indexes.json` (`fkIdNino` + `fechaMovimiento desc`) para poder preguntar "¿cuál fue el último movimiento de este niño?" y así decidir si el próximo botón dice "Entrada" o "Salida". Nueva función `ninoYaPresente(ninoId)` (2026-08-17) para el bloqueo de Entrada duplicada.

**Pendiente de esta misma pantalla:** escáner QR (Fase 2) y modo offline con cola de sincronización (Fase 3) — ver sección 9. El cierre automático (antes Módulo 5) ya está implementado, ver sección 5.5.

---

## 5.5. Cloud Functions (`app/functions/`) — cierre automático de asistencia (2026-08-15)

**Primera Cloud Function del proyecto.** Pedido de Rafael: si pasan los días y quedan niños con "Entrada" sin "Salida" (se les olvidó registrar la salida, o es un visitante — que hoy no tiene forma de recibir una salida manual buscándolo por nombre), deben cerrarse automáticamente. Node.js 20, Cloud Functions v2 (`onSchedule`), Admin SDK (escribe sin pasar por `firestore.rules` — no hizo falta tocarlas).

**Dos funciones programadas**, ambas en `functions/index.js`, mismo criterio de "presente ahora" que usa `ninos_presentes_screen.dart` (`_calcularPresentes`, ver sección 6):
- `cierreAutomaticoDomingoMediodia`: todos los domingos a las **10:30am hora de Bogotá** — cierra a quien se haya quedado del primer servicio antes de que arranque el segundo (decisión explícita de Rafael).
- `cierreAutomaticoFinDeDia`: **todos los días a las 11:55pm hora de Bogotá** — cierra a cualquiera que siga presente, sea cual sea el servicio.

Cada niño cerrado así recibe un nuevo `Registro` de Salida que copia `fkIdAcudienteContacto`/`nombreAcudienteContacto` **de su propia entrada** (mismo criterio que el swipe manual, "se entrega a la misma persona que lo recibió"), con `fkIdServidor: 'sistema'`, `modalidadRegistro: 'Automático'`, y una `observacion` que deja constancia de que fue un cierre automático (para distinguirlo de una salida real). **Desde 2026-08-17** también limpia `ninos/{id}.presente = false` (ver sección 5, bloqueo de Entrada duplicada) — si no lo hiciera, un niño cerrado automáticamente quedaría bloqueado para siempre sin poder recibir una nueva Entrada.

**Detalle técnico importante:** Colombia no tiene horario de verano, así que el cálculo de "medianoche de hoy en Bogotá" usa un offset fijo de -5 horas (`rangoDeHoyBogota()` en el código) en vez de depender del huso horario del contenedor de la función — el parámetro `timeZone` de `onSchedule` solo controla CUÁNDO dispara el cron, no afecta los cálculos con `Date` dentro del código.

**Deploy:** `firebase deploy --only functions --project rocakidsarmenia-7935b` (desde `/app`, no la raíz del repo — ver `firebase.json`). Se corrió también `firebase functions:artifacts:setpolicy --force` una vez, para que las imágenes de contenedor viejas se borren solas (evita que se acumule un costo pequeño de Artifact Registry).

### `correoCumpleanosDiario` — correo automático de cumpleaños (2026-08-18)

**Tercera función programada** (pedido de Rafael): todos los días a las **7:00am hora de Bogotá**, revisa qué niños `Activo` cumplen años **hoy** (mismo cálculo de mes/día que `cumpleEnUltimaSemana()`/`diasDesdeCumpleanos()` de `lib/models/nino.dart`, sección 6, pero solo el día exacto) y le manda un correo festivo a **todos** los acudientes vinculados de cada uno (decisión explícita de Rafael: no solo Padre/Madre). Un niño sin ningún acudiente con correo real y válido se omite en silencio — no bloquea el resto del envío ni genera alerta.

**Envío real por Gmail SMTP** (`nodemailer`, agregado como dependencia de `functions/`) desde **`rokakidsarmenia@gmail.com`** — ⚠️ **con K, no "roca"** como el nombre del proyecto de Firebase (`rocakidsarmenia-7935b`); confundir esto costó 5 intentos fallidos de prueba antes de detectarlo. La contraseña de aplicación de Gmail vive en Secret Manager como `GMAIL_APP_PASSWORD` (`firebase functions:secrets:set`, la generó y guardó Rafael mismo — Claude nunca vio el valor). Validado con envíos reales de prueba antes de dejar la función programada activa.

**Diseño del correo:** plantilla HTML propia (`plantillaCorreoCumpleanos()`) que replica el diseño exacto que Rafael compartió — encabezado con degradado naranja/rojo y emojis de fiesta, pastilla turquesa con el nombre del niño, recuadro de versículo con borde punteado, bloque de invitación al fin de semana con degradado verde, firma "Tu familia de RocaKids". El versículo se elige al azar entre 8 opciones fijas en el código (`VERSICULOS_CUMPLEANOS`), todas de tono de bendición/alegría/esperanza.

**Costo:** $0 esperado — mismo criterio que las otras dos funciones programadas (nivel gratuito de Cloud Functions/Firestore), y esta es la **3ª y última tarea de Cloud Scheduler que entra gratis** (el nivel gratuito da 3 jobs; una 4ª tarea programada en el futuro sí tendría un costo pequeño, ~$0.10/mes). El envío por Gmail SMTP no tiene costo de Google Cloud — el único límite es el propio de Gmail (500 correos/día en cuenta normal), muy por encima del volumen esperado.

**Pendiente/no implementado a propósito:** no hay mecanismo de "ya se envió este año" (si la función se reintentara el mismo día podría reenviar) — no se consideró necesario para el volumen actual; y no hay forma de probar el envío real sin usar una Cloud Function HTTP temporal (desplegar → invocar con `curl` → borrar) porque `onSchedule` no es invocable directamente por HTTP — patrón ya usado varias veces en este proyecto, ver [[feature-correo-cumpleanos]] en la memoria para el detalle completo de cómo se diagnosticó y probó.

---

## 6. Pantallas construidas (`lib/screens/`)

### `widgets/app_shell.dart` — estructura de navegación (2026-08-14)
Todas las pantallas principales (`home_screen.dart`, `modulo_en_construccion_screen.dart`, `acudiente_portal_screen.dart`, `admin/admin_users_list_screen.dart`) se envuelven en `AppShell`, que da un **menú con todas las secciones**, filtrado según el rol de la cuenta:
- Pantalla ≥800px de ancho (computador/navegador ancho): menú fijo a la izquierda, contenido a la derecha.
- Pantalla angosta (celular): el mismo menú colapsa en un cajón deslizable (ícono ☰ en la barra superior).

Ítems según rol: "Inicio", "Mis hijos", "Registro de asistencia", "Menores Recibidos" (nuevo 2026-08-15), "Registrar familia" (cualquier rol de servidor o admin — "Registrar familia" se amplió de solo Maestro Principal/Auxiliar a **todos los roles de servidor** el 2026-08-14), "Cumpleaños" (nuevo 2026-08-18, **todos los roles principales**, mismo conjunto que "Registro de asistencia" — ver `cumpleanos_screen.dart` en la tabla de abajo), "Dashboard" (nuevo 2026-08-18, **solo administrador, columna y líder de ministerio** — `RolUsuario.puedeVerDashboard`, mismo conjunto que `puedeVerAcudientesYNinos`), "Acudientes y Niños" (nació admin-only el 2026-08-14, se amplió a todos los roles de servidor ese mismo día, y el 2026-08-17 Rafael pidió acotarlo a **solo administrador, columna y líder de ministerio** — ver `RolUsuario.puedeVerAcudientesYNinos`, tabla abajo), "Gestión de Servidores" (solo admin), "Mi perfil" (roles de servidor), "Cambiar contraseña" (nuevo 2026-08-17, **todos los usuarios logueados sin importar el rol**, incluidos acudientes — ver tabla abajo), "Cerrar sesión" (todos). (Las 3 herramientas de migración de una sola vez que vivían junto a "Gestión de Servidores" — "Reindexar búsqueda de niños", "Migrar vínculos niño-acudiente", "Sincronizar presencia de niños" — se eliminaron el 2026-08-17, ver sección 5: los datos de prueba se van a borrar antes del lanzamiento real, así que no queda nada "viejo" que arreglar.) Un acudiente puro (`usuario_externo`) ve "Mis hijos", "Cambiar contraseña" y "Cerrar sesión" — su portal ya funciona como su "inicio".

**Nota de vocabulario (2026-08-14):** Rafael llama **"roles principales"** al conjunto Administrador, Líder de Ministerio, Columna, Líder Escuela de Siervos, Maestro Principal y Maestro Auxiliar — exactamente el mismo conjunto que `esRolDeServidor` en Dart y `puedeRegistrarAsistencia()` en `firestore.rules`.

Cada pantalla le pasa a `AppShell` su propio contenido (ya no tienen su propio `Scaffold`/`AppBar`/botones de navegación — eso ahora vive todo en el shell) y el nombre de su sección (`seccionActiva`, para resaltarla en el menú y como título). Navegar entre secciones usa `Navigator.pushReplacement` (no se apilan pantallas ni aparece flecha de "atrás" al cambiar de sección).

⚠️ **Bug encontrado y arreglado (2026-08-17): "Cerrar sesión" no llevaba al login.** Causa raíz: `AuthGate` (el `StreamBuilder` que decide qué pantalla mostrar según el estado de sesión, ver más abajo) es el `home` de `MaterialApp` — pero como `_irA()` navega con `pushReplacement`, la PRIMERA vez que alguien cambia de sección desde el menú, esa navegación reemplaza la ruta que contenía a `AuthGate`, sacándolo del árbol. Desde ese momento, ya no hay nadie escuchando `authStateChanges` para reaccionar solo cuando se cierra sesión — Firebase sí cerraba la sesión, pero la pantalla se quedaba igual. Se arregló en `_cerrarSesion()` (`app_shell.dart`): después de `signOut()`, se limpia TODO el stack de navegación con `Navigator.pushAndRemoveUntil` y se vuelve a poner un `AuthGate` desde cero, que con la sesión ya cerrada cae al login de inmediato. **Nota para el futuro:** esta misma causa raíz podría afectar OTRAS transiciones reactivas de `AuthGate` que dependan de navegar lejos de la pantalla inicial post-login (ej. si un admin le cambia el rol a alguien mientras esa persona ya navegó a otra sección) — no se ha confirmado si eso también falla, solo se arregló el caso reportado (cerrar sesión).

| Pantalla | Qué hace |
|---|---|
| `login_screen.dart` | Correo/contraseña + botones "Soy Acudiente" / "Soy Servidor". Selector mostrar/ocultar contraseña. |
| `sign_up_servidor_screen.dart` | Registro de servidor → queda en rol `pendiente`, cierra sesión, muestra diálogo de confirmación. |
| `sign_up_acudiente_screen.dart` | Registro de acudiente + su primer niño + relación, en un solo formulario. Fotos opcionales (acudiente y niño) con selector cámara/galería. Acceso inmediato al guardar. |
| `pending_approval_screen.dart` | Para rol `pendiente` (servidor esperando aprobación) o roles sin sentido (`desconocido`). Sin menú — todavía no hay nada que navegar. |
| `complete_profile_screen.dart` | Bloqueo obligatorio: servidor con rol ya asignado no puede hacer nada más hasta llenar su perfil completo (documento, EPS, etc. + foto). Sin menú, por el mismo motivo. |
| `home_screen.dart` | Sección "Inicio" del **administrador**: mensaje de bienvenida + rol. Las acciones (Mis hijos, Gestión de Servidores, Reindexar, Migrar vínculos, Mi perfil, Cerrar sesión) ahora viven en el menú de `AppShell`, no en botones propios de esta pantalla. |
| `modulo_en_construccion_screen.dart` | Sección "Inicio" para roles de servidor *distintos* a administrador (sus módulos aún no existen). |
| `acudiente_portal_screen.dart` | "Mis hijos" — accesible por CUALQUIER cuenta logueada. Si el usuario no tiene perfil de acudiente todavía: si ya es servidor con perfil completo, ofrece **reutilizar esos datos** (documento, teléfono, foto — sin re-subir la foto, misma URL de Storage) con un botón "Usar estos datos y continuar", con opción de "Prefiero ingresar otros datos" para caer al formulario manual completo. Si no es servidor o prefiere otros datos, pide el formulario. Si ya tiene perfil de acudiente, muestra la lista de niños (foto, edad, número de documento — sin género) + botón "Agregar hijo"; tocar un niño abre `nino_detalle_sheet.dart`. |
| `nino_detalle_sheet.dart` | Ficha (hoja inferior) de un niño: foto, edad y grupo actuales (calculados al vuelo), documento, fecha de nacimiento, género, estado, autorización de imagen, y alerta médica si aplica. Se abre al tocar un niño en "Mis hijos". Si quien la ve es el padre/madre vinculado (o admin), muestra botón "Editar información" → abre `editar_nino_sheet.dart`. **Solo admin** (2026-08-18): botón "Eliminar niño" con confirmación (`widgets/confirmar_eliminar.dart`) → `AuthService.eliminarNino()`, ver sección 9. |
| `editar_nino_sheet.dart` | Formulario para corregir nombres, apellidos, fecha de nacimiento, género, autorización de imagen y alerta médica de un niño (2026-08-14). NO permite editar el documento del menor ni su estado/foto — ver sección 5. |
| `agregar_hijo_screen.dart` | Desde el portal: vincular un niño ya registrado (buscándolo por nombre con lista en vivo — solo nombre/edad visibles, ver `ninos_busqueda` en sección 5 — o por número de documento como respaldo) o registrar uno nuevo. |
| `registrar_familia_screen.dart` | Sección "Registrar familia" — **cualquier rol de servidor o admin** (ampliado el 2026-08-14; nació el 2026-08-14 solo para Maestro Principal/Auxiliar, mismo día se abrió a Columna/Líderes/Admin también). Lo llena el servidor EN NOMBRE de la familia (ej. en la mesa de registro de un servicio). **"Formulario inteligente" desde 2026-08-17:** antes solo cubría acudiente+niño ambos nuevos; ahora busca primero si el acudiente (por documento, vía `acudientes_documentos`) y/o el niño (por nombre, reutilizando `ninos_busqueda`) YA EXISTEN, y arma la combinación correcta — 4 casos, cada uno con su propio método en `AuthService`: ambos nuevos (`registrarAcudienteConNinoDesdeServidor`, sin cambios), acudiente existente+niño nuevo (`registrarNinoAdicional(..., acudienteUid:)`, ahora acepta un uid explícito), acudiente nuevo+niño existente (`vincularAcudienteNuevoANinoExistenteDesdeServidor`, nuevo), y ambos existentes — solo falta el vínculo (`vincularNinoAcudienteExistentes`, nuevo). Al terminar, puede registrar otra familia sin salir de su propia sesión. Los casos con acudiente nuevo usan la app de Firebase secundaria y temporal (`createUserWithEmailAndPassword` normalmente dejaría logueado como la cuenta recién creada). **Cambio en `firestore.rules`:** `nino_acudiente` ahora permite `create` también a `puedeRegistrarAsistencia()` (antes solo el propio acudiente o admin) — necesario para vincular a un acudiente que YA existe y no es quien llama. |
| `admin/admin_users_list_screen.dart` | Lista de todos los usuarios con rol de servidor (`usuarios` collection), separa "pendientes de aprobación" del resto. Solo admin. **Filtra `usuario_externo` desde 2026-08-14** (bug reportado por Rafael: un acudiente de prueba aparecía mezclado aquí — los acudientes ahora viven solo en "Acudientes y Niños"). |
| `admin/admin_acudientes_ninos_screen.dart` | Sección "Acudientes y Niños" (2026-08-14; nació admin-only, se amplió el mismo día a cualquier rol de servidor, y el **2026-08-17 Rafael pidió acotarlo a solo administrador, columna y líder de ministerio** — `RolUsuario.puedeVerAcudientesYNinos` en el menú de `AppShell`) — pestañas "Niños" y "Acudientes", cada una lista TODA la colección correspondiente (`AuthService.listarNinosAdmin()` / `listarAcudientes()`). Tocar un niño abre `nino_detalle_sheet.dart`; tocar un acudiente abre `acudiente_detalle_sheet.dart`. Es la extensión del pendiente "Administración de Niños" que Rafael pidió incluir también a los acudientes. ⚠️ **Nota técnica:** el permiso de Firestore para `list` de `acudientes` SÍ quedó acotado a esos 3 roles (`puedeVerInfoLiderazgo()`); el de `ninos` NO (`listarNinosAdmin()` comparte la regla `list` con `obtenerTodosLosNinos()` de "Menores Recibidos", que debe seguir abierta a TODOS los roles principales) — así que un maestro/líder escuela sin acceso al menú técnicamente podría seguir listando `ninos` completo si navegara ahí por otra vía, pero no `acudientes`. |
| `acudiente_detalle_sheet.dart` | Ficha (hoja inferior) de un acudiente: documento, teléfono, correo, foto de seguridad, estado de restricción si aplica, aviso si tiene `correoPendienteDeCorregir`, y la lista de niños que tiene vinculados (`AuthService.obtenerHijosDeAcudiente()`). Si quien la ve tiene un rol de servidor (`usuario.rol.esRolDeServidor` — mismo conjunto que `puedeRegistrarAsistencia()` en las reglas), muestra botón "Editar información" → abre `editar_acudiente_sheet.dart`. Se usa tanto desde "Acudientes y Niños" (admin) como desde el check-in. **Solo admin** (2026-08-18): botón "Eliminar acudiente" → `AuthService.eliminarAcudiente()`, ver sección 9. |
| `editar_acudiente_sheet.dart` | Formulario para corregir tipo/número de documento, nombres, apellidos, teléfono y correo de un acudiente (2026-08-14). NO permite editar `estadoAutorizacion` ni `observacionesRestriccion` (admin-only) ni la foto — ver sección 5. |
| `admin/user_edit_sheet.dart` | Ficha de un usuario: si es admin viendo a otro, puede cambiar rol/activo/fecha de verificación de antecedentes, y ver los datos de perfil. Botón "Editar información" (perfil) visible si es admin o si es el propio dueño viendo su ficha. **Solo admin, y no sobre sí mismo** (2026-08-18): botón "Eliminar servidor" → `AuthService.eliminarServidor()`, ver sección 9. |
| `cambiar_password_sheet.dart` | Sección "Cambiar contraseña" (nuevo 2026-08-17) — **cualquier usuario logueado**, servidor o acudiente. Pide contraseña actual (Firebase Auth exige reautenticación reciente para esto, `AuthService.cambiarPassword()` usa `reauthenticateWithCredential` + `updatePassword`) y la nueva dos veces. Solo se puede cambiar la propia — el SDK de cliente no permite cambiar la de otro usuario (eso requeriría Admin SDK, no implementado). |
| `admin/edit_perfil_servidor_sheet.dart` | Formulario de edición de los campos de perfil de servidor (documento, EPS, etc.), reutilizado tanto para que el admin corrija a otro como para que uno mismo edite lo suyo. |
| `registro_asistencia_screen.dart` | Sección "Registro de asistencia" (2026-08-14) — **todos los roles principales**. Busca un niño por nombre (reutiliza `ninos_busqueda`), muestra su foto/alerta médica, pide quién lo entrega (lista de acudientes vinculados con foto de seguridad, o "Otro"), servicio (pre-seleccionado según el día/hora, ver sección 5), manilla y observación. **Solo registra ENTRADAS (2026-08-17):** si el niño buscado ya está presente, se le puede seleccionar igual (para no generar confusión de "no lo encuentro") pero se muestra un aviso sin botón de registrar — la salida se da EXCLUSIVAMENTE desde "Menores Recibidos" (deslizar la tarjeta). También permite registrar un niño **visitante** sin cuenta previa. Ver `registros/{autoId}` en sección 5 para el detalle completo y las limitaciones de esta primera fase. **Desde 2026-08-14**, también permite editar ahí mismo al niño seleccionado (ícono de lápiz junto a su ficha, abre `editar_nino_sheet.dart`) y a cualquiera de sus acudientes (ícono de lápiz en cada tarjeta, abre `editar_acudiente_sheet.dart`) — pedido explícito de Rafael, "para facilitar el proceso". **Desde 2026-08-18:** si el niño seleccionado cumplió años en los últimos 7 días (`cumpleEnUltimaSemana()` en `nino.dart`), muestra un aviso festivo (fondo degradado con los colores de marca, ícono grande) para felicitarlo en el momento del check-in — rediseñado el mismo día a pedido de Rafael, para que fuera más llamativo que el aviso de texto plano inicial (`_avisoCumpleanos()`). **También desde 2026-08-18:** el campo "Número de manilla" tiene un botón de escanear (`_campoManilla()`) que abre la cámara (`escanearCodigoManilla()`, paquete `mobile_scanner`) y llena el campo con lo leído — pensado para manillas físicas con QR pre-impreso (todavía no las tienen, ver sección 9). Antes de aceptar el código, `AuthService.manillaEnUsoHoy()` revisa que esa manilla no esté puesta en otro niño presente ahora mismo. |
| `cumpleanos_screen.dart` | Sección "Cumpleaños" (2026-08-18, pedido de Rafael) — **todos los roles principales**, mismo gate que "Registro de asistencia". Lista los niños "Activo" que cumplen años hoy o cumplieron en los últimos 7 días (`AuthService.obtenerNinosQueCumplieronEstaSemana()`), ordenados del más reciente al más antiguo, con una etiqueta ("Cumple hoy" / "Cumplió hace N días"). Compara solo mes y día contra hoy, sin importar el año (`cumpleEnUltimaSemana()`/`diasDesdeCumpleanos()` en `lib/models/nino.dart`, mismo criterio que usa el aviso del check-in de arriba). Tocar un niño abre `nino_detalle_sheet.dart`. |
| `admin/dashboard_screen.dart` | Sección "Dashboard" (2026-08-18, ampliado el mismo día — **solo administrador, columna y líder de ministerio**, `RolUsuario.puedeVerDashboard`, mismo gate que "Acudientes y Niños") — gráficas interactivas con `fl_chart` (tooltip al tocar/pasar el mouse sobre cada barra o punto). **Bloque "Totales del sistema"**: niños registrados, acudientes registrados y **servidores activos** (`contarNinosRegistrados()`/`contarAcudientesRegistrados()`/`contarServidoresActivos()`), los tres con el mismo permiso — `puedeVerInfoLiderazgo()` en `firestore.rules` (administrador, columna, líder de ministerio). Rafael confirmó explícitamente (2026-08-18) que columna y líder de ministerio SÍ pueden ver la información de los servidores (no solo el conteo) — solo líder de escuela de siervos no, y ese rol de todas formas no tiene acceso al Dashboard. Por eso `usuarios` amplió su regla de `get`/`list` de "solo `esAdmin()`" a "`esAdmin()` o `puedeVerInfoLiderazgo()`" (antes esta función se llamaba `puedeVerListaAcudientes()` y solo controlaba `acudientes`; se renombró porque ahora también controla `usuarios`). **Bloque "Hoy"** (reactivo, `registrosDeHoy()`): tarjetas de recibidos/presentes ahora/ya salieron/visitantes/sin documento, y dos gráficas de barras (por grupo de edad, por servicio) — reutiliza la lógica de "presentes ahora" de `ninos_presentes_screen.dart`. **Bloque "Histórico"** (filtro de **1/3/6/9/12 meses**, `ChoiceChip`): trae TODAS las Entradas alguna vez registradas en UNA sola consulta al abrir la pantalla (`AuthService.obtenerEntradasDesde(DateTime(2000))`) y agrega todo del lado del cliente — cambiar el filtro NO vuelve a consultar Firestore, solo re-agrega los mismos datos ya traídos. Tres gráficas: **"Crecimiento de niños registrados" (línea, acumulado)** — mide la fecha de la PRIMERA Entrada de cada niño (no una fecha de creación del documento `ninos`, que no existe) y acumula cuántos niños únicos ya habían asistido al menos una vez para cada mes, usando el historial COMPLETO como base aunque solo se muestre la ventana seleccionada (así el acumulado no arranca en cero al cambiar a un filtro corto); "Asistencia por mes" (barras, todas las Entradas incluidos visitantes); "Comparación entre servicios" (barras), estas dos sí acotadas a la ventana seleccionada. Requirió dos índices compuestos nuevos en `firestore.indexes.json` (`registros`: `tipoMovimiento`+`fechaMovimiento`; `usuarios`: `rol`+`activo`). Decisión explícita: empezar con consultas directas (incluso trayendo todo el historial de `registros`) y resolver con una tabla de resúmenes pre-calculados (mismo patrón que el cierre automático, sección 5.5) **solo si se vuelve lento** con más volumen (ej. tras importar los ~3873 registros históricos del Módulo 2) — no antes. **Agregado más tarde el mismo día** (tras migrar los datos reales): 4ª tarjeta en "Totales" con niños graduados; **tarjeta tocable** de quién cumple 11 años este mes (antes era un banner de texto); **bloque "Pendientes"** — 4 tarjetas tocables (niños sin foto/documento, acudientes sin foto/correo pendiente) que abren la lista exacta y de ahí la ficha de cada quien, ver `_TarjetaPendiente`/`_ListaPendientesSheet` en el mismo archivo. |
| `ninos_presentes_screen.dart` | Sección "Menores Recibidos" (nuevo 2026-08-15, todos los roles principales) — quiénes están AHORA MISMO en el salón (último movimiento de hoy = "Entrada"), subdivididos por grupo de edad en tarjetas **colapsables** (`ExpansionTile`, `initiallyExpanded: true`), cada una con su total y el rango de edad junto al nombre del grupo (ej. "Grupo Daniel · 7-8 años (1)", ver `rangoEdadPorGrupo` en `nino.dart`). Subtítulo de cada niño: documento + número de manilla. Tocar un niño registrado abre `nino_detalle_sheet.dart` (su ficha completa); tocar un visitante abre una ficha mínima propia (`_VisitanteDetalleSheet`, dentro del mismo archivo — no tiene documento `Nino` en la base). **Deslizar la tarjeta de un niño (`Dismissible`, cualquier dirección) le da la Salida al instante** — sin confirmación ni volver a preguntar quién lo retira: copia `fkIdAcudienteContacto`/`nombreAcudienteContacto` de su propia entrada (pedido explícito de Rafael, "solo se entrega a la misma persona que lo recibió"). Los visitantes cuentan también en los grupos (cada Entrada de hoy sin Salida manual/automática cuenta como presente). Usa `AuthService.registrosDeHoy()` (stream con rango de fecha del día) + `obtenerTodosLosNinos()` (una sola lectura, para cruzar nombre/foto/alerta médica/documento). Quien se quede sin salida manual lo cierra el cierre automático (sección 5.5). **Pendiente explícito, para después:** una vista histórica del día completo que incluya a quien ya salió (decisión de Rafael de dejarla para otra sesión). **Desde 2026-08-18:** botón flotante "Salida por manilla" — escanea la manilla gemela del acudiente (`escanearCodigoManilla()`), busca con `AuthService.buscarPresentePorManilla()` quién está presente ahora con ese código, muestra su foto/nombre en un diálogo de confirmación, y al confirmar da la salida reutilizando `_darSalida()` (la misma función del swipe, ahora con un parámetro `observacion` para distinguir "deslizó la tarjeta" de "escaneó la manilla"). |
| `auth_gate.dart` | El "router" central: según rol + si el perfil está completo, decide qué pantalla mostrar. Reactivo (usa Streams de Firestore), no necesita refrescos manuales. |

**`lib/services/auth_service.dart`** centraliza TODA la lógica de Firebase (login, registro, subida de fotos, consultas). Vale la pena leerlo completo para entender los flujos exactos antes de tocarlo.

---

## 7. Reglas de seguridad — resumen de la lógica

**Firestore (`firestore.rules`):**
- `usuarios`: cada quien lee lo suyo; `get`/`list` de OTRO usuario para admin, o (desde 2026-08-18, pedido explícito de Rafael) para columna/líder de ministerio vía `puedeVerInfoLiderazgo()` — antes era admin-only, se amplió para que el Dashboard pueda mostrarles "servidores activos" y en general puedan ver la ficha de un servidor; líder de escuela de siervos (y el resto de roles operativos) sigue sin poder. Auto-registro solo con rol `usuario_externo` o `pendiente` (nunca uno con privilegios). Auto-edición permitida excepto `rol`, `activo`, `correo`, `fechaVerificacionAntecedentes` (esos son admin-only) — **editar** el perfil de OTRO usuario sigue siendo admin-only, `puedeVerInfoLiderazgo()` solo amplió lectura, no escritura.
- `acudientes`: auto-registro propio; `get` propio, de un admin, o de quien tiene `puedeRegistrarAsistencia()` (desde 2026-08-14 — antes un maestro/columna/líder haciendo check-in no podía ni leer la ficha de un acudiente ajeno, lo cual era en realidad un bug latente: `obtenerAcudientesDeNino()` ya intentaba leerlas). `list` (traer TODA la colección) es más acotado: admin, o `puedeVerInfoLiderazgo()` (**solo** administrador/columna/líder de ministerio, desde 2026-08-17 — antes cualquier rol de servidor, ver sección 6; función renombrada 2026-08-18 de `puedeVerListaAcudientes()` porque ahora también controla `usuarios`). `update` permitido al propio dueño, a un admin, o a `puedeRegistrarAsistencia()` — en los tres casos excepto `estadoAutorizacion`/`observacionesRestriccion` (siempre admin-only).
- `acudientes_documentos`: **create-only** (el ID del documento es la clave única; un segundo intento con el mismo ID no puede "actualizar" porque no hay regla `allow update` para el cliente ahí) → previene duplicados sin lógica extra.
- `ninos`: create-only para cualquier autenticado. `update` para admin, para el padre/madre vinculado, o para `puedeRegistrarAsistencia()` (desde 2026-08-14, pedido de Rafael para editar en el momento del check-in) — en ambos casos excepto documento/estado/foto, que quedan admin-only. Rama aparte (sin cambios): `puedeRegistrarAsistencia()` también puede tocar SOLO documento (`completarDocumentoNino`). `list` (traer toda la colección) para admin o `puedeRegistrarAsistencia()` (ampliado 2026-08-14, mismo motivo que `acudientes`).
- `ninos_busqueda`: mismo permiso de `update` que `ninos` (debe quedar sincronizado).
- `nino_acudiente`: ID determinístico `{fkIdNino}_{fkIdAcudiente}` (desde 2026-08-14, ver sección 5). Cualquiera autenticado puede crear una relación donde `fk_idAcudiente` sea su propio uid; un admin o (desde 2026-08-17) `puedeRegistrarAsistencia()` también pueden crearla para OTRO acudiente — este último caso hace falta para el "formulario inteligente" de "Registrar familia" (sección 6), cuando el servidor vincula a un acudiente que YA existe. Vínculo a un niño existente es **instantáneo, sin aprobación** (decisión explícita de Rafael: el control real de seguridad ocurre en el check-in/check-out, no aquí). `get`/`list` abierto a cualquier autenticado (desde 2026-08-14, para el check-in — antes solo el propio acudiente o admin).
- `registros`: solo los roles de `puedeRegistrarAsistencia()` (administrador, columna, líder de ministerio, líder escuela de siervos, maestro principal, maestro auxiliar) pueden crear o leer — es información operativa de seguridad, no algo que un acudiente cualquiera deba poder ver. `fkIdServidor` debe coincidir con el uid de quien escribe. Una Entrada no se puede crear si el niño ya está `presente` (`ninoYaPresente()`, 2026-08-17) — evita duplicados incluso si dos servidores lo registran casi al mismo tiempo. **Ya NO exige documento** (el bloqueo por falta de `identificacionMenor`/`documentoNinoVisitante` se quitó el 2026-08-17, ver sección 5 — ahora es solo una advertencia en la UI, no una regla de Firestore).

**Storage (`storage.rules`):**
- `servidores_fotos/{uid}` y `acudientes_fotos/{uid}`: cada quien sube/reemplaza solo la suya.
- `ninos_fotos/{ninoId}`: cualquiera autenticado puede subir, pero **solo la primera vez** (`resource == null`), igual que el registro del niño.
- Todo límite a 5MB y solo tipo `image/*`.

---

## 8. Problemas ya resueltos (para no repetirlos)

- **`image_picker` fallaba en producción** (`MissingPluginException`) pero funcionaba en modo debug → se resolvió con `flutter clean` + `flutter pub get` antes de rebuildear. Si vuelve a pasar algo similar tras agregar un plugin nuevo, probar eso primero.
- **Fotos no se veían (CORS)** → el bucket de Storage necesita configuración CORS explícita para que el navegador pueda cargar las imágenes. Ya aplicada (`storage-cors.json`, vía `gcloud storage buckets update ... --cors-file=storage-cors.json`). Si se crea un bucket nuevo o cambia el dominio de Hosting, hay que re-aplicar esto.
- **Storage no tiene capa gratuita fuera de EE.UU.** → por eso el bucket quedó en `us-east1` en vez de `southamerica-east1` (donde está Firestore). Firestore/Auth/Hosting sí son gratis en cualquier región.
- **Caché del service worker hacía que usuarios vieran versiones viejas tras un deploy** (no solo durante pruebas — le pasaba a usuarios reales, ej. Rafael entrando desde el celular no veía el botón "Mis hijos" recién agregado, solo funcionaba en incógnito). **Resuelto 2026-08-13:** se agregó un bloque `headers` en `app/firebase.json` (dentro de `hosting`) que fuerza `Cache-Control: no-cache, no-store, must-revalidate` en `index.html`, `flutter_service_worker.js`, `flutter_bootstrap.js` y `version.json`.
  - **Vuelta a aparecer 2026-08-14 con `main.dart.js`:** ese archivo (el código Dart compilado, ~3 MB) no tiene hash en el nombre, así que cada deploy lo sobrescribe en la MISMA URL — y como no estaba en la lista de `no-cache`, Firebase lo servía con `max-age=3600` (1 hora) por defecto. Resultado: `index.html` se actualizaba al toque, pero el navegador seguía usando el `main.dart.js` viejo cacheado hasta que pasaba esa hora, así que una página "nueva" podía seguir mostrando comportamiento viejo. Se agregó `/main.dart.js` a la misma lista de `no-cache` en `firebase.json`. Costo adicional: sí es real esta vez (~3 MB por visita en vez de cacheado), pero para el volumen de esta app es insignificante frente al nivel gratuito.
  - Con esto, `index.html`, el service worker, y `main.dart.js` — las tres piezas que definen qué versión de la app corre — siempre se revalidan. Ya no debería hacer falta pedirle a nadie que limpie caché o use incógnito después de un deploy (salvo, quizás, una vez más para quien ya tenía el `main.dart.js` viejo cacheado desde ANTES de este segundo fix). Ver también la nota de sección 2 sobre caché (ese consejo de incógnito/"Update on reload" ahora es solo para casos raros, no el flujo normal).
- Un ícono/campo puede quedar invisible si hereda el color blanco global de `IconButton` sobre fondo claro — hay que ponerle color explícito (pasó con los íconos de correo/contraseña del login).
- **Un ícono de Material nuevo puede no verse en producción aunque compile bien y exista en el SDK de Flutter** (pasó con `Icons.how_to_reg` en el menú de "Menores Recibidos", 2026-08-15: la fila quedaba sin ícono, solo el texto). Sospecha: el build web hace tree-shaking de la fuente `MaterialIcons` (reduce el `.otf` de ~1.6MB a ~11KB, ver el log de `flutter build web`) y el glifo específico puede faltar en el subset resultante aunque el `IconData` exista en Dart. Se resolvió cambiando a `Icons.fact_check`. **Volvió a pasar el 2026-08-18** con `Icons.qr_code_scanner` (botón de escanear manilla) e `Icons.keyboard` (ingresar código manualmente) — se resolvió igual, cambiándolos por `Icons.photo_camera` e `Icons.edit`. Si vuelve a pasar con un ícono nuevo: preferir uno ya usado y confirmado visualmente en la app (correr `grep -rhoE "Icons\.[a-zA-Z_0-9]+" lib/ | sort -u` da la lista completa actual — incluye `groups`, `badge_outlined`, `checklist`, `diversity_3`, `assignment_turned_in`, `people`, `family_restroom`, `group_add`, `person`, `logout`, `home`, `photo_camera`, `photo_library`, `edit`, `cake`, `celebration`, entre otros) antes de investigar más.
- **"Cerrar sesión" no llevaba al login (2026-08-17)** — ver el detalle completo en sección 6 (nota junto a la descripción de `AppShell`). Causa raíz: `_irA()` navega con `pushReplacement`, y la primera vez que alguien cambia de sección desde el menú, esa navegación saca a `AuthGate` del árbol — así que ya no quedaba nadie escuchando `authStateChanges` para reaccionar al cerrar sesión. Firebase sí cerraba la sesión, pero la pantalla no cambiaba. Arreglado en `_cerrarSesion()` limpiando todo el stack de navegación y reinstalando un `AuthGate` fresco tras el `signOut()`.
- **Favicon (ícono de la pestaña del navegador) reemplazado (2026-08-18):** era el ícono genérico de Flutter (16×16 px). El logo completo de RocaKids es un wordmark con mucho detalle fino (texto, rayas de color) que no se lee a tamaño de pestaña (16-32px) — se probó y se descartó. Se usó en su lugar el ícono "K" que ya forma parte del logo (recortado de `assets/images/logo_rocakids_compacto.png`, que tiene transparencia real y alta resolución), centrado en un lienzo cuadrado. A 16px se ve borroso pero reconocible por color; a 32px (pantallas de alta resolución, la mayoría hoy) se distingue bien la "K". Se agregó `/favicon.png` a la lista de `no-cache` en `firebase.json` (los navegadores cachean íconos de pestaña de forma más agresiva que el resto de recursos — puede hacer falta cerrar y reabrir la pestaña para verlo, incluso con esto). **Nota:** Rafael envió un `.ico` propio para usarlo, pero resultó ser una captura de pantalla del mismo logo a mucha menor resolución (256×159, fondo sólido) — se le explicó y se optó por la versión de mejor calidad ya generada del archivo fuente real.

---

## 9. Qué falta (pendiente, en orden sugerido)

### ⚠️ Pendiente inmediato — retomar aquí

**Módulo 2 — falta migrar los 3873 registros históricos de asistencia** (`REGISTROS` de `DB RocaKids V2 (*).xlsx`). Explícitamente pospuesto a pedido directo de Rafael (2026-08-18: "NO cargues aún ningún registro histórico") — todo lo demás del archivo (niños, acudientes, relaciones, servidores, fotos) ya está migrado y en producción. Decisión de transformación ya acordada para cuando se retome: la base vieja solo registraba "Salida" (una salida implica que hubo ingreso), así que cada "Salida" histórica se importa como **"Entrada"** en el esquema nuevo. Detalle técnico completo (scripts, autenticación sin crear credenciales nuevas, patrón de reanudar procesos que se cortan solos, etc.) en la memoria: [[feature-migracion-modulo2-datos-reales]] — **leerla completa antes de retomar esto**.

**Escaneo de manilla con QR (2026-08-18) — construido, probado en producción por Rafael, 2 bugs encontrados y corregidos el mismo día.** Se construyó el flujo completo (escanear para llenar el número de manilla en Entrada, botón "Salida por manilla" en Menores Recibidos, aviso si una manilla ya está en uso) pidiendo que fuera lo más simple posible de implementar: **no requirió ningún cambio al modelo de datos**, el código QR se trata como texto plano y se guarda en el mismo campo `numeroManilla` de siempre. **Rafael todavía NO tiene manillas físicas con QR** — el plan es comprarlas ya fabricadas en pares (una para la muñeca del niño, una gemela para el acudiente, ambas con el mismo código, como las de guardarropa/parques), no imprimirlas desde la app. Mientras tanto, el escáner tiene un botón "Ingresar código manualmente" que sirve tanto de respaldo real (manilla perdida/dañada) como para poder probar el flujo sin manillas de verdad.

Rafael probó el flujo manual en producción (sin poder verse en el navegador de Claude, ver `dev_server_testing` en la memoria) y reportó 2 problemas, ambos corregidos el mismo día:
1. **El ícono de escanear no se veía** (dos rondas: primero `Icons.qr_code_scanner`/`Icons.keyboard` no sobrevivieron el tree-shaking del build — se cambiaron por `Icons.photo_camera`/`Icons.edit`, ya confirmados en la app; la segunda vez el ícono seguía sin verse porque le faltaba `color` explícito y heredaba un color que se perdía sobre el fondo claro del campo — mismo patrón de bug ya documentado en esta sección con los íconos de correo/contraseña del login).
2. **"Salida por manilla" no daba la salida** al confirmar. Causa real: la consulta nueva (`numeroManilla` + `fechaMovimiento`, usada tanto para el aviso de "manilla en uso" como para buscar a quién dar salida) necesitaba un índice compuesto de Firestore que no se había agregado — y como no había manejo de errores alrededor de esa consulta, fallaba en silencio sin ningún mensaje. Se agregó el índice (`registros`: `numeroManilla` + `fechaMovimiento desc`) y `try/catch` con mensaje claro en ambos flujos, para que un problema similar en el futuro se vea en vez de fallar callado.

**Cuando lleguen las manillas reales, probar con QR de verdad desde un celular** (la cámara la abre `mobile_scanner`) — todo lo demás ya se validó con datos reales usando el modo manual.

### ✅ Resuelto 2026-08-18 (sesión larga — migración de datos reales + varias features del Dashboard)

Todo en la misma sesión, en este orden:

1. **Dashboard con gráficas** — implementado y ampliado el mismo día (gráficas interactivas con `fl_chart`, filtros de 1/3/6/9/12 meses, crecimiento acumulado). Gate: `RolUsuario.puedeVerDashboard` (administrador, columna, líder de ministerio). **Rafael ya lo confirmó viendo la pantalla real** (mandó una captura de la tarjeta de graduación funcionando). Ver `admin/dashboard_screen.dart` en sección 6.
2. **Migración de datos reales (Módulo 2), primeras tandas:** migrados **460 niños**, **456 acudientes** (con cuenta de Firebase Auth real, contraseña = su número de documento), **626 relaciones niño↔acudiente**, **30 servidores** (contraseña = documento, rol `'pendiente'` salvo Rafael que ya era admin), y **todas las fotos** (subidas desde ZIP que compartió Rafael tras un límite de accesos de Google Drive). Detalle completo, decisiones de diseño, y cómo restaurar si algo sale mal: [[feature-migracion-modulo2-datos-reales]] — **incluye un incidente real ya corregido** (un bug sobreescribió brevemente el rol de administrador de Rafael, detectado y arreglado al instante).
3. **Nuevo, relacionado con la migración:**
   - `Nino.estadoRegistro` ahora puede ser `'Graduado'` (más de 10 años) — 51 niños quedaron así. Dashboard: dato "Niños graduados" y una **tarjeta tocable** de quién cumple 11 años ese mes (`obtenerNinosQueGraduanEsteMes()`) — al tocarla se ve la lista exacta. **No hay filtro automático todavía** que oculte a los graduados de la búsqueda en "Registro de asistencia".
   - `Acudiente.correoPendienteDeCorregir` (nuevo campo): dispara un aviso en la ficha del acudiente y en el check-in hasta que alguien le guarde un correo real.
   - **Bloque "Pendientes" en el Dashboard** (interactivo): tarjetas tocables — niños sin foto/sin documento, acudientes sin foto/con correo pendiente — que abren la lista exacta de quiénes son, y de ahí su ficha completa para corregirlo.
4. **Eliminar niño/acudiente/servidor** — botón en las tres fichas, **solo administrador**, con confirmación (`widgets/confirmar_eliminar.dart`). `AuthService.eliminarNino/eliminarAcudiente/eliminarServidor` borran el registro y sus relaciones dependientes (pero no los `registros` históricos de un niño, ni la cuenta de servidor de un acudiente que también sea servidor, etc. — ver [[feature-eliminar-registros]] para el detalle exacto de qué borra cada uno). **Límite importante:** ninguno borra la cuenta de Firebase Auth de la persona — el SDK de cliente no puede borrar la cuenta de OTRO usuario, solo la propia.
5. **Punto de restauración creado antes de tocar datos reales:** tag de git `pre-migracion-modulo2-2026-08-18` + export de Firestore en `gs://rocakidsarmenia-7935b-backups/` — ver [[restore-point-pre-migracion-modulo2]].
6. **Presupuesto de Google Cloud verificado y corregido** — ver sección 1 (tabla de datos clave).
7. **Contraseña de los 27 servidores `'pendiente'` cambiada a su correo electrónico** (mismo día, pedido explícito de Rafael — alcance confirmado con él: solo los migrados con rol `'pendiente'`, no los que ya tienen un rol asignado ni la cuenta admin de Rafael). Antes tenían contraseña = número de documento (punto 2 de arriba). **26 de 27 actualizados**; 1 (David Fernando Romero Otalora) se omitió por no tener correo real (quedó con el correo placeholder `sincorreo.*@rocakids.pendiente` de la migración). Se hizo con una Cloud Function HTTP temporal, protegida con un secreto de un solo uso, corrida una vez y **eliminada del proyecto inmediatamente después** (`firebase functions:delete`) — nunca quedó código de esto en el repo, mismo criterio que las demás herramientas de migración de un solo uso (ver [[herramientas-migracion-eliminadas]]). Correo electrónico también se agregó como dato visible en la ficha de servidor (`admin/user_edit_sheet.dart`, ya se veía como subtítulo pero no como fila junto a documento/teléfono/EPS).

**Pendiente real que quedó fuera de esta sesión:** si el volumen de `registros` crece mucho (ej. al importar los 3873 históricos, punto pendiente de arriba), la consulta directa del bloque "Histórico" del Dashboard puede volverse lenta/costosa — resolver con una tabla de resúmenes pre-calculados (mismo patrón que el cierre automático de sección 5.5), no antes.

---

**Resueltos el 2026-08-14** los 3 puntos que Rafael reportó tras probar "Registrar familia" (bug de acudientes mezclados en "Gestión de Servidores", pantalla admin de acudientes/niños, y edición de acudiente/niño desde el check-in) — ver la tabla de pantallas en sección 6 y el resumen de reglas en sección 7 para el detalle de cada uno. Alcance confirmado con Rafael antes de programar: el niño se edita con los mismos campos que ya podía tocar el padre/madre (`editarNino`); el acudiente se edita con "ficha completa" excepto `estadoAutorizacion`/`observacionesRestriccion` y la foto (esos quedan admin-only, mismo patrón ya usado en el resto del proyecto).

1. **Administración de Niños** — ✅ hecho el 2026-08-14 como parte de lo anterior, ver `admin/admin_acudientes_ninos_screen.dart` en sección 6 (incluye también acudientes, no solo niños).
2. **Vista histórica de asistencia del día** (2026-08-15, explícitamente pospuesta por Rafael): "Menores Recibidos" (`ninos_presentes_screen.dart`, sección 6) solo muestra quién está presente AHORA; falta una segunda vista que muestre a TODOS los que pasaron hoy, incluyendo quien ya salió — pensada como reporte de asistencia del día, no "quién está en el salón".
3. **Pantallas propias por rol:** desde 2026-08-14, Líder Ministerio, Columna, Líder Escuela de Siervos, Maestro Principal y Maestro Auxiliar YA tienen acceso a "Registro de asistencia" (todos) y Maestro Principal/Auxiliar además a "Registrar familia" — pero siguen sin una pantalla de **inicio propia** con herramientas específicas de su rol (ven la genérica "módulo en construcción").
4. **Módulo 2 — Migración de datos reales:** ✅ niños/acudientes/relaciones/servidores/fotos hechos el 2026-08-18 (ver "⚠️ Pendiente inmediato" y "✅ Resuelto" al principio de esta sección). El archivo real es `D:\Downloads\DB RocaKids V2 (*).xlsx` (⚠️ ojo: NO es la carpeta Descargas normal de Windows, es una ruta directa en el disco D:). **Falta todavía:** los **3873 registros históricos de asistencia** (`REGISTROS`) — explícitamente pospuesto, ver arriba.
5. **Módulo 4 — Check-in/Check-out:** ✅ Fase 1 (registro manual con internet) lista, ver `registros/{autoId}` en sección 5. Faltan Fase 2 (escáner QR) y Fase 3 (modo offline con cola de sincronización) — decisión explícita de Rafael de dejarlas para después.
6. **Módulo 5 — Cierre automático** — ✅ hecho el 2026-08-15, ver sección 5.5 (primera Cloud Function del proyecto: domingo 10:30am + fin de día todos los días, según lo pedido por Rafael).
7. **Módulo 7 — Campañas de correo (Brevo):** falta confirmar si Rafael ya tiene cuenta/API key de Brevo.
8. **Módulo 8 — Cumpleaños:** ✅ hecho el 2026-08-18 — vista "Cumpleaños" dentro de la app (niños que cumplieron años en los últimos 7 días) y aviso al registrar el ingreso de un niño que está/estuvo de cumpleaños (`cumpleanos_screen.dart`, sección 6), **más** el correo automático diario a los acudientes el mismo día del cumpleaños (`correoCumpleanosDiario`, sección 5.5) — ya no depende de Brevo/Módulo 7, se resolvió directo con Gmail SMTP. **Falta, si se quiere ampliar después:** otros canales (WhatsApp) o campañas más allá del cumpleaños individual (eso sí seguiría dependiendo del punto 7).
9. Antes de un lanzamiento real: limpiar cuentas/datos de prueba creadas durante el desarrollo (hay al menos un servidor y un par de niños/acudientes de prueba en la base de datos real de Firebase — no es un ambiente de staging separado; ahora hay un botón "Eliminar" para admin, ver sección 9 arriba, así que esta limpieza ya se puede hacer desde la propia app).

---

## 10. Cuentas de prueba existentes

- **Admin:** `rafaelbalaguera@gmail.com` (rol administrador; también tiene o puede activar perfil de acudiente).
- **Servidor de prueba:** `sweetgirl288kp@gmail.com` — Karen Alicia Paba Lopez, rol Maestro Principal.
- **Acudiente de prueba:** `jairoalex@hotmail.com` — Jairo Alexander Castañeda Barrios, rol Usuario externo (creado el 2026-08-14 vía "Registrar familia" para probar ese flujo — es el que expuso el bug de la sección 9).
- Puede haber niños/acudientes de prueba adicionales creados durante las pruebas de esta conversación.

*(No se documentan contraseñas aquí por seguridad — las tiene Rafael.)*
