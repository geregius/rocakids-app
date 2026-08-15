# RocaKids — Estado del Proyecto (guía de continuación)

**Última actualización:** 2026-08-14
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
| Alerta de presupuesto | Se recomendó crear una de $5 USD en Google Cloud Billing → **verificar si quedó creada**, no tengo confirmación certera |

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
- **Backend:** 100% Firebase — Authentication, Firestore (base de datos), Storage (fotos), Hosting (la web pública). Sin servidor propio ni Cloud Functions todavía (aunque el plan Blaze ya las soportaría si se necesitan).
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

Los niños registrados ANTES del 2026-08-14 no tenían documento en esta colección (se empezó a escribir recién con esta feature) — para eso existe el botón **"Reindexar búsqueda de niños"** en `home_screen.dart` (solo admin, ver `AuthService.reindexarBusquedaNinos()`): recorre TODO `ninos` y rellena `ninos_busqueda` para cualquiera que le falte. Ya se corrió una vez el 2026-08-14. **Importante para el Módulo 2 (migración de datos):** el script de importación masiva debería escribir también en `ninos_busqueda`, pero si se le olvida, correr este botón una vez después de la importación resuelve el problema sin tocar código.

`lib/models/nino.dart` → clase `NinoBusqueda` (con `coincideBusqueda()`, comparación sin distinguir mayúsculas/acentos). La búsqueda se trae completa una vez (`AuthService.obtenerIndiceBusquedaNinos()`) y se filtra en el cliente mientras se escribe — no hay índice por prefijo en Firestore, no hace falta para el volumen de una sola congregación.

### `nino_acudiente/{ninoId}_{acudienteUid}` — relación muchos-a-muchos
Campos: `fk_idNino`, `fk_idAcudiente`, `parentescoTipo`, `autorizacionFormulario`, `autorizacionImagen`, `esRepresentanteLegalFlag`. Un niño puede tener varios acudientes, y un acudiente varios niños — ya soportado y probado.

**El ID del documento cambió de aleatorio a determinístico (`{fkIdNino}_{fkIdAcudiente}`) el 2026-08-14.** Motivo: para poder chequear en `firestore.rules` "¿esta persona es el padre/madre de este niño?" con una sola lectura directa (`exists()`/`get()` por ID), en vez de una consulta — necesario para permitir que el padre/madre edite la ficha del niño (ver abajo). Efecto colateral bueno: ahora también previene vínculos duplicados por diseño (mismo patrón create-only que `ninos`/`acudientes_documentos`), algo que antes solo se evitaba con una consulta manual en `vincularNinoExistente`.

⚠️ **Los vínculos creados ANTES del 2026-08-14 quedaron con su ID aleatorio viejo** — no calzan con lo que esperan las reglas nuevas, así que esos padres/madres no podrían editar la ficha de su hijo hasta migrarlos. Para eso existe el botón admin **"Migrar vínculos niño-acudiente"** en el menú (ver `AuthService.migrarRelacionesADeterministico()`) — recorre TODO `nino_acudiente`, crea la copia en la ruta nueva y borra la vieja. Hay que correrlo una vez (igual que se hizo con "Reindexar búsqueda de niños").

### `registros/{autoId}` — entrada/salida de niños (Módulo 4, Fase 1 — 2026-08-14)
Campos: `fkIdNino` (vacío si es visitante), `nombreNinoVisitante`, `tipoMovimiento` (Entrada/Salida), `fechaMovimiento`, `numeroManilla`, `fkIdServidor`, `nombreServidor`, `fkIdAcudienteContacto`, `nombreAcudienteContacto`, `telefonoAcudienteVisitante`, `alertaMedicaVisitante`, `condicionMedicaVisitante`, `modalidadRegistro` (siempre `'App'` para lo escrito desde esta app), `servicio`, `grupoEdad`, `observacion`.

**Fuente de verdad real:** no el SOP (que documenta un enum de `modalidadRegistro` que no coincide con lo real), sino el export real `D:\Downloads\DB RocaKids V2 (15).xlsx` → pestaña `REGISTROS` (3873 movimientos históricos). De ahí salió la lista de `Servicio` (`serviciosDisponibles` en `lib/models/registro.dart`): Domingo 1° Servicio, Domingo 2° Servicio, Miércoles, Ayuno, Casa2 — y la confirmación de que `grupoEdad` casi nunca se llenaba a mano en el sistema viejo (por eso se calcula automático, nunca manual, para niños ya registrados).

**Decisiones de esta fase (confirmadas por Rafael, 2026-08-14):**
- **Solo registro manual, con internet.** Sin escáner QR ni modo offline todavía — quedan para después, una vez esto se use en la iglesia y funcione bien.
- **Quién puede registrar:** Administrador, Columna, Líder de Ministerio, Líder Escuela de Siervos, Maestro Principal, Maestro Auxiliar (`puedeRegistrarAsistencia()` en `firestore.rules` — básicamente todos los roles de servidor, `usuario.rol.esRolDeServidor`).
- **Manilla:** campo de texto libre (no hay lista fija de manillas por salón, coincide con el dato real).
- **Niño visitante (sin cuenta previa):** SÍ soportado desde ya, para no rechazar a nadie en la puerta — se guarda solo en el `registro` (nombre, adulto que lo trae, teléfono, alerta médica, grupo elegido a mano ya que no hay fecha de nacimiento), sin crear `ninos`/`acudientes`. ⚠️ Limitación conocida: como el visitante no queda en `ninos_busqueda`, no se puede "buscar" para registrarle la salida después — por ahora su registro queda solo como Entrada. Si un visitante vuelve, lo ideal es registrarlo formalmente (acudiente o maestro) para que tenga ficha completa.
- Quién entrega/retira a un niño YA registrado se elige de la lista de acudientes vinculados (`AuthService.obtenerAcudientesDeNino()`, vía `nino_acudiente`) con su foto de seguridad para verificar identidad — y si su `estadoAutorizacion` es `Restringido`, se lo advierte en rojo al servidor. Esto es el control de seguridad real del que habla el SOP. Hay opción "Otro" con nombre libre por si quien retira no está en la lista.
- **Bloqueo de niño sin documento (2026-08-14):** pensando en la migración del Módulo 2 (muchos de los ~578 niños reales no tienen `identificacionMenor`), un niño YA registrado **sin número de documento no puede tener ningún movimiento** (ni Entrada ni Salida) hasta completarlo. **Ajuste inmediato (mismo día):** en vez de mandar a buscar a un admin, quien está haciendo el check-in (cualquier rol de `puedeRegistrarAsistencia()`) puede completar el documento ahí mismo, en la propia pantalla — `AuthService.completarDocumentoNino()`, con permiso de Firestore acotado a SOLO esos dos campos (`tipoIdentificacion`/`identificacionMenor`), nada más del niño se puede tocar por esa vía. Esto se aplica en 3 capas: la UI muestra el mini-formulario en vez del bloqueo puro, `_registrarMovimientoNino()` revalida antes de enviar, y **la regla de Firestore también lo exige** (`get()` sobre `ninos/{fkIdNino}.identificacionMenor != ''`) — no se puede saltar aunque alguien modifique la app.
- **Niños VISITANTE también deben tener documento (2026-08-14):** el formulario de visitante ahora pide tipo + número de documento como campos obligatorios (`tipoIdentificacionVisitante`/`documentoNinoVisitante` en `registros`). La regla de Firestore lo exige simétricamente: si `fkIdNino` está vacío (visitante), `documentoNinoVisitante` no puede estarlo.

**Reglas de Firestore:** nueva función `puedeRegistrarAsistencia()` (lista fija de roles). `nino_acudiente` se abrió a `get`/`list` para cualquier autenticado (antes solo el propio acudiente o admin) — hace falta para poder ver quién puede retirar a CUALQUIER niño, no solo a los propios. Nuevo índice compuesto en `firestore.indexes.json` (`fkIdNino` + `fechaMovimiento desc`) para poder preguntar "¿cuál fue el último movimiento de este niño?" y así decidir si el próximo botón dice "Entrada" o "Salida".

**Pendiente de esta misma pantalla:** escáner QR (Fase 2) y modo offline con cola de sincronización (Fase 3) — ver sección 9. El cierre automático nocturno es el Módulo 5, aparte, y necesita la primera Cloud Function del proyecto.

---

## 6. Pantallas construidas (`lib/screens/`)

### `widgets/app_shell.dart` — estructura de navegación (2026-08-14)
Todas las pantallas principales (`home_screen.dart`, `modulo_en_construccion_screen.dart`, `acudiente_portal_screen.dart`, `admin/admin_users_list_screen.dart`) se envuelven en `AppShell`, que da un **menú con todas las secciones**, filtrado según el rol de la cuenta:
- Pantalla ≥800px de ancho (computador/navegador ancho): menú fijo a la izquierda, contenido a la derecha.
- Pantalla angosta (celular): el mismo menú colapsa en un cajón deslizable (ícono ☰ en la barra superior).

Ítems según rol: "Inicio", "Mis hijos", "Registro de asistencia", "Registrar familia" y "Acudientes y Niños" (cualquier rol de servidor o admin — "Registrar familia" se amplió de solo Maestro Principal/Auxiliar a **todos los roles de servidor** el 2026-08-14; "Acudientes y Niños" nació admin-only el 2026-08-14 y se amplió a todos los roles de servidor ese mismo día, ver tabla abajo), "Gestión de Servidores", "Reindexar búsqueda de niños" y "Migrar vínculos niño-acudiente" (solo admin, herramientas de mantenimiento — ver sección 5), "Mi perfil" (roles de servidor), "Cerrar sesión" (todos). Un acudiente puro (`usuario_externo`) solo ve "Mis hijos" y "Cerrar sesión" — su portal ya funciona como su "inicio".

Cada pantalla le pasa a `AppShell` su propio contenido (ya no tienen su propio `Scaffold`/`AppBar`/botones de navegación — eso ahora vive todo en el shell) y el nombre de su sección (`seccionActiva`, para resaltarla en el menú y como título). Navegar entre secciones usa `Navigator.pushReplacement` (no se apilan pantallas ni aparece flecha de "atrás" al cambiar de sección).

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
| `nino_detalle_sheet.dart` | Ficha (hoja inferior) de un niño: foto, edad y grupo actuales (calculados al vuelo), documento, fecha de nacimiento, género, estado, autorización de imagen, y alerta médica si aplica. Se abre al tocar un niño en "Mis hijos". Si quien la ve es el padre/madre vinculado (o admin), muestra botón "Editar información" → abre `editar_nino_sheet.dart`. |
| `editar_nino_sheet.dart` | Formulario para corregir nombres, apellidos, fecha de nacimiento, género, autorización de imagen y alerta médica de un niño (2026-08-14). NO permite editar el documento del menor ni su estado/foto — ver sección 5. |
| `agregar_hijo_screen.dart` | Desde el portal: vincular un niño ya registrado (buscándolo por nombre con lista en vivo — solo nombre/edad visibles, ver `ninos_busqueda` en sección 5 — o por número de documento como respaldo) o registrar uno nuevo. |
| `registrar_familia_screen.dart` | Sección "Registrar familia" — **cualquier rol de servidor o admin** (ampliado el 2026-08-14; nació el 2026-08-14 solo para Maestro Principal/Auxiliar, mismo día se abrió a Columna/Líderes/Admin también). Mismo formulario que el auto-registro público de acudiente (acudiente + primer niño + relación), pero lo llena el servidor EN NOMBRE de la familia (ej. en la mesa de registro de un servicio). Al terminar, puede registrar otra familia sin salir de su propia sesión. Ver `AuthService.registrarAcudienteConNinoDesdeServidor()` — usa una app de Firebase secundaria y temporal para crear la cuenta nueva, así quien registra nunca pierde su propia sesión (`createUserWithEmailAndPassword` normalmente dejaría logueado como la cuenta recién creada). No requirió cambios en `firestore.rules`/`storage.rules`: los escritos ocurren autenticados como el nuevo acudiente, igual que el auto-registro. |
| `admin/admin_users_list_screen.dart` | Lista de todos los usuarios con rol de servidor (`usuarios` collection), separa "pendientes de aprobación" del resto. Solo admin. **Filtra `usuario_externo` desde 2026-08-14** (bug reportado por Rafael: un acudiente de prueba aparecía mezclado aquí — los acudientes ahora viven solo en "Acudientes y Niños"). |
| `admin/admin_acudientes_ninos_screen.dart` | Sección "Acudientes y Niños" (nuevo 2026-08-14; nació admin-only, se amplió el mismo día a **cualquier rol de servidor** — pedido de Rafael para que líderes/columnas/maestros también lo vean) — pestañas "Niños" y "Acudientes", cada una lista TODA la colección correspondiente (`AuthService.listarNinosAdmin()` / `listarAcudientes()`). Tocar un niño abre `nino_detalle_sheet.dart`; tocar un acudiente abre `acudiente_detalle_sheet.dart`. Es la extensión del pendiente "Administración de Niños" que Rafael pidió incluir también a los acudientes. |
| `acudiente_detalle_sheet.dart` | Ficha (hoja inferior) de un acudiente: documento, teléfono, correo, foto de seguridad, estado de restricción si aplica, y la lista de niños que tiene vinculados (`AuthService.obtenerHijosDeAcudiente()`). Si quien la ve tiene un rol de servidor (`usuario.rol.esRolDeServidor` — mismo conjunto que `puedeRegistrarAsistencia()` en las reglas), muestra botón "Editar información" → abre `editar_acudiente_sheet.dart`. Se usa tanto desde "Acudientes y Niños" (admin) como desde el check-in. |
| `editar_acudiente_sheet.dart` | Formulario para corregir tipo/número de documento, nombres, apellidos, teléfono y correo de un acudiente (2026-08-14). NO permite editar `estadoAutorizacion` ni `observacionesRestriccion` (admin-only) ni la foto — ver sección 5. |
| `admin/user_edit_sheet.dart` | Ficha de un usuario: si es admin viendo a otro, puede cambiar rol/activo/fecha de verificación de antecedentes, y ver los datos de perfil. Botón "Editar información" (perfil) visible si es admin o si es el propio dueño viendo su ficha. |
| `admin/edit_perfil_servidor_sheet.dart` | Formulario de edición de los campos de perfil de servidor (documento, EPS, etc.), reutilizado tanto para que el admin corrija a otro como para que uno mismo edite lo suyo. |
| `registro_asistencia_screen.dart` | Sección "Registro de asistencia" (2026-08-14) — **todos los roles de servidor**. Busca un niño por nombre (reutiliza `ninos_busqueda`), muestra su foto/alerta médica, calcula si toca Entrada o Salida según su último movimiento, y pide quién lo entrega/retira (lista de acudientes vinculados con foto de seguridad, o "Otro"), servicio, manilla y observación. También permite registrar un niño **visitante** sin cuenta previa. Ver `registros/{autoId}` en sección 5 para el detalle completo y las limitaciones de esta primera fase. **Desde 2026-08-14**, también permite editar ahí mismo al niño seleccionado (ícono de lápiz junto a su ficha, abre `editar_nino_sheet.dart`) y a cualquiera de sus acudientes (ícono de lápiz en cada tarjeta, abre `editar_acudiente_sheet.dart`) — pedido explícito de Rafael, "para facilitar el proceso". |
| `auth_gate.dart` | El "router" central: según rol + si el perfil está completo, decide qué pantalla mostrar. Reactivo (usa Streams de Firestore), no necesita refrescos manuales. |

**`lib/services/auth_service.dart`** centraliza TODA la lógica de Firebase (login, registro, subida de fotos, consultas). Vale la pena leerlo completo para entender los flujos exactos antes de tocarlo.

---

## 7. Reglas de seguridad — resumen de la lógica

**Firestore (`firestore.rules`):**
- `usuarios`: cada quien lee lo suyo; admin lee/lista todo. Auto-registro solo con rol `usuario_externo` o `pendiente` (nunca uno con privilegios). Auto-edición permitida excepto `rol`, `activo`, `correo`, `fechaVerificacionAntecedentes` (esos son admin-only).
- `acudientes`: auto-registro propio; `get`/`list` propio, de un admin, o de quien tiene `puedeRegistrarAsistencia()` (desde 2026-08-14 — antes un maestro/columna/líder haciendo check-in no podía ni leer la ficha de un acudiente ajeno, lo cual era en realidad un bug latente: `obtenerAcudientesDeNino()` ya intentaba leerlas; el `list` completo se amplió el mismo día para el panel "Acudientes y Niños"). `update` permitido al propio dueño, a un admin, o a `puedeRegistrarAsistencia()` — en los tres casos excepto `estadoAutorizacion`/`observacionesRestriccion` (siempre admin-only).
- `acudientes_documentos`: **create-only** (el ID del documento es la clave única; un segundo intento con el mismo ID no puede "actualizar" porque no hay regla `allow update` para el cliente ahí) → previene duplicados sin lógica extra.
- `ninos`: create-only para cualquier autenticado. `update` para admin, para el padre/madre vinculado, o para `puedeRegistrarAsistencia()` (desde 2026-08-14, pedido de Rafael para editar en el momento del check-in) — en ambos casos excepto documento/estado/foto, que quedan admin-only. Rama aparte (sin cambios): `puedeRegistrarAsistencia()` también puede tocar SOLO documento (`completarDocumentoNino`). `list` (traer toda la colección) para admin o `puedeRegistrarAsistencia()` (ampliado 2026-08-14, mismo motivo que `acudientes`).
- `ninos_busqueda`: mismo permiso de `update` que `ninos` (debe quedar sincronizado).
- `nino_acudiente`: ID determinístico `{fkIdNino}_{fkIdAcudiente}` (desde 2026-08-14, ver sección 5). Cualquiera autenticado puede crear una relación donde `fk_idAcudiente` sea su propio uid (o un admin, para migraciones). Vínculo a un niño existente es **instantáneo, sin aprobación** (decisión explícita de Rafael: el control real de seguridad ocurre en el check-in/check-out, no aquí). `get`/`list` abierto a cualquier autenticado (desde 2026-08-14, para el check-in — antes solo el propio acudiente o admin).
- `registros`: solo los roles de `puedeRegistrarAsistencia()` (administrador, columna, líder de ministerio, líder escuela de siervos, maestro principal, maestro auxiliar) pueden crear o leer — es información operativa de seguridad, no algo que un acudiente cualquiera deba poder ver. `fkIdServidor` debe coincidir con el uid de quien escribe.

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

---

## 9. Qué falta (pendiente, en orden sugerido)

**Resueltos el 2026-08-14** los 3 puntos que Rafael reportó tras probar "Registrar familia" (bug de acudientes mezclados en "Gestión de Servidores", pantalla admin de acudientes/niños, y edición de acudiente/niño desde el check-in) — ver la tabla de pantallas en sección 6 y el resumen de reglas en sección 7 para el detalle de cada uno. Alcance confirmado con Rafael antes de programar: el niño se edita con los mismos campos que ya podía tocar el padre/madre (`editarNino`); el acudiente se edita con "ficha completa" excepto `estadoAutorizacion`/`observacionesRestriccion` y la foto (esos quedan admin-only, mismo patrón ya usado en el resto del proyecto).

1. **Administración de Niños** — ✅ hecho el 2026-08-14 como parte de lo anterior, ver `admin/admin_acudientes_ninos_screen.dart` en sección 6 (incluye también acudientes, no solo niños).
2. **Pantallas propias por rol:** desde 2026-08-14, Líder Ministerio, Columna, Líder Escuela de Siervos, Maestro Principal y Maestro Auxiliar YA tienen acceso a "Registro de asistencia" (todos) y Maestro Principal/Auxiliar además a "Registrar familia" — pero siguen sin una pantalla de **inicio propia** con herramientas específicas de su rol (ven la genérica "módulo en construcción").
3. **Módulo 2 — Migración de datos reales:** el archivo real es `D:\Downloads\DB RocaKids V2 (*).xlsx` (⚠️ ojo: NO es la carpeta Descargas normal de Windows, es una ruta directa en el disco D:) — datos reales de producción (niños, acudientes, servidores, equipos, formación, **3873 registros históricos de asistencia**, etc.). Ya se usó para diseñar `registros/` (sección 5) y para el perfil de servidor. Falta el script de importación a Firestore.
4. **Módulo 4 — Check-in/Check-out:** ✅ Fase 1 (registro manual con internet) lista, ver `registros/{autoId}` en sección 5. Faltan Fase 2 (escáner QR) y Fase 3 (modo offline con cola de sincronización) — decisión explícita de Rafael de dejarlas para después.
5. **Módulo 5 — Cierre automático nocturno** (requiere la primera Cloud Function del proyecto; ya se puede, el plan es Blaze).
6. **Módulo 7 — Campañas de correo (Brevo):** falta confirmar si Rafael ya tiene cuenta/API key de Brevo.
7. **Módulo 8 — Cumpleaños automáticos.**
8. Verificar si quedó creada la alerta de presupuesto de $5 en Google Cloud Billing (se recomendó, no está confirmado).
9. Antes de un lanzamiento real: limpiar cuentas/datos de prueba creadas durante el desarrollo (hay al menos un servidor y un par de niños/acudientes de prueba en la base de datos real de Firebase — no es un ambiente de staging separado).

---

## 10. Cuentas de prueba existentes

- **Admin:** `rafaelbalaguera@gmail.com` (rol administrador; también tiene o puede activar perfil de acudiente).
- **Servidor de prueba:** `sweetgirl288kp@gmail.com` — Karen Alicia Paba Lopez, rol Maestro Principal.
- **Acudiente de prueba:** `jairoalex@hotmail.com` — Jairo Alexander Castañeda Barrios, rol Usuario externo (creado el 2026-08-14 vía "Registrar familia" para probar ese flujo — es el que expuso el bug de la sección 9).
- Puede haber niños/acudientes de prueba adicionales creados durante las pruebas de esta conversación.

*(No se documentan contraseñas aquí por seguridad — las tiene Rafael.)*
