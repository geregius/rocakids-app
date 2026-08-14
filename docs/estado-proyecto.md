# RocaKids — Estado del Proyecto (guía de continuación)

**Última actualización:** 2026-08-13
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

**Grupo/aula del ministerio infantil — a propósito NO es un campo de esta colección.** Se calcula en la UI a partir de la edad actual (`grupoParaEdad()` en `lib/models/nino.dart`), nunca se guarda: el grupo de un niño cambia con el tiempo según su edad en cada visita, así que guardarlo en el registro del menor lo dejaría desactualizado. Grupos actuales (fijados por Rafael, 2026-08-14):

| Grupo | Edad |
|---|---|
| José | 2 años |
| David | 3-4 años |
| Judá | 5-6 años |
| Daniel | 7-8 años |
| Santiago | 9-10 años |

RocaKids solo recibe niños de 2 a 10 años (`edadMinimaRegistro`/`edadMaximaRegistro` en `nino.dart`) — el registro de un niño fuera de ese rango queda bloqueado con un mensaje de error, tanto en el registro inicial de acudiente (`sign_up_acudiente_screen.dart`) como al agregar un hijo adicional (`agregar_hijo_screen.dart`). El campo de fecha de nacimiento en ambos formularios usa `SelectorFechaNacimiento` (día/mes/año en dropdowns en vez de un calendario, con el año acotado al rango plausible 2-10 años) y muestra la edad y el grupo calculados en vivo mientras se llena.

### `nino_acudiente/{autoId}` — relación muchos-a-muchos
Campos: `fk_idNino`, `fk_idAcudiente`, `parentescoTipo`, `autorizacionFormulario`, `autorizacionImagen`, `esRepresentanteLegalFlag`. Un niño puede tener varios acudientes, y un acudiente varios niños — ya soportado y probado.

---

## 6. Pantallas construidas (`lib/screens/`)

| Pantalla | Qué hace |
|---|---|
| `login_screen.dart` | Correo/contraseña + botones "Soy Acudiente" / "Soy Servidor". Selector mostrar/ocultar contraseña. |
| `sign_up_servidor_screen.dart` | Registro de servidor → queda en rol `pendiente`, cierra sesión, muestra diálogo de confirmación. |
| `sign_up_acudiente_screen.dart` | Registro de acudiente + su primer niño + relación, en un solo formulario. Fotos opcionales (acudiente y niño) con selector cámara/galería. Acceso inmediato al guardar. |
| `pending_approval_screen.dart` | Para rol `pendiente` (servidor esperando aprobación) o roles sin sentido (`desconocido`). |
| `complete_profile_screen.dart` | Bloqueo obligatorio: servidor con rol ya asignado no puede hacer nada más hasta llenar su perfil completo (documento, EPS, etc. + foto). |
| `home_screen.dart` | Pantalla principal del **administrador**: botones "Mis hijos", "Gestión de Servidores"; ícono "Mi perfil" y "Cerrar sesión" en el AppBar. |
| `modulo_en_construccion_screen.dart` | Pantalla principal para roles de servidor *distintos* a administrador (sus módulos aún no existen). También tiene "Mis hijos" y "Mi perfil". |
| `acudiente_portal_screen.dart` | "Mis hijos" — accesible por CUALQUIER cuenta logueada. Si el usuario no tiene perfil de acudiente todavía: si ya es servidor con perfil completo, ofrece **reutilizar esos datos** (documento, teléfono, foto — sin re-subir la foto, misma URL de Storage) con un botón "Usar estos datos y continuar", con opción de "Prefiero ingresar otros datos" para caer al formulario manual completo. Si no es servidor o prefiere otros datos, pide el formulario. Si ya tiene perfil de acudiente, muestra la lista de niños (foto, edad, número de documento — sin género) + botón "Agregar hijo"; tocar un niño abre `nino_detalle_sheet.dart`. |
| `nino_detalle_sheet.dart` | Ficha (hoja inferior) de un niño: foto, edad y grupo actuales (calculados al vuelo), documento, fecha de nacimiento, género, estado, autorización de imagen, y alerta médica si aplica. Se abre al tocar un niño en "Mis hijos". |
| `agregar_hijo_screen.dart` | Desde el portal: vincular un niño ya registrado por otro acudiente (busca por documento) o registrar uno nuevo. |
| `admin/admin_users_list_screen.dart` | Lista de todos los usuarios (`usuarios` collection), separa "pendientes de aprobación" del resto. Solo admin. |
| `admin/user_edit_sheet.dart` | Ficha de un usuario: si es admin viendo a otro, puede cambiar rol/activo/fecha de verificación de antecedentes, y ver los datos de perfil. Botón "Editar información" (perfil) visible si es admin o si es el propio dueño viendo su ficha. |
| `admin/edit_perfil_servidor_sheet.dart` | Formulario de edición de los campos de perfil de servidor (documento, EPS, etc.), reutilizado tanto para que el admin corrija a otro como para que uno mismo edite lo suyo. |
| `auth_gate.dart` | El "router" central: según rol + si el perfil está completo, decide qué pantalla mostrar. Reactivo (usa Streams de Firestore), no necesita refrescos manuales. |

**`lib/services/auth_service.dart`** centraliza TODA la lógica de Firebase (login, registro, subida de fotos, consultas). Vale la pena leerlo completo para entender los flujos exactos antes de tocarlo.

---

## 7. Reglas de seguridad — resumen de la lógica

**Firestore (`firestore.rules`):**
- `usuarios`: cada quien lee lo suyo; admin lee/lista todo. Auto-registro solo con rol `usuario_externo` o `pendiente` (nunca uno con privilegios). Auto-edición permitida excepto `rol`, `activo`, `correo`, `fechaVerificacionAntecedentes` (esos son admin-only).
- `acudientes`: mismo patrón — auto-registro propio, auto-edición excepto `estadoAutorizacion`/`observacionesRestriccion` (admin-only).
- `acudientes_documentos` y `ninos`: **create-only** (el ID del documento es la clave única; un segundo intento con el mismo ID no puede "actualizar" porque no hay regla `allow update` para el cliente ahí) → previene duplicados sin lógica extra.
- `nino_acudiente`: cualquiera autenticado puede crear una relación donde `fk_idAcudiente` sea su propio uid. Vínculo a un niño existente es **instantáneo, sin aprobación** (decisión explícita de Rafael: el control real de seguridad ocurre en el check-in/check-out, no aquí).

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

1. **Administración de Niños** (el resto del Módulo 3, explícitamente pospuesto): pantalla admin para listar/buscar niños, ver su ficha completa, y desde ahí vincular un acudiente ya existente o registrar uno nuevo. Roca­Kids ya soporta la relación muchos-a-muchos en el modelo de datos — falta la UI de administración.
2. **Los otros 6 roles de servidor** (Líder Ministerio, Columna, Líder Escuela de Siervos, Maestro Principal, Maestro Auxiliar) no tienen pantallas propias todavía — el modelo y el flujo de aprobación ya los soporta.
3. **Módulo 2 — Migración de datos reales:** existen archivos `DB RocaKids V2 (*).xlsx` en las Descargas de Rafael con datos reales de producción (niños, acudientes, servidores, equipos, formación, etc. — hoja `SERVIDORES` fue la referencia para el perfil de servidor que ya se construyó). Falta el script de importación a Firestore.
4. **Módulo 4 — Check-in/Check-out con QR**, modo offline. Es el corazón operativo de la app según el SOP.
5. **Módulo 5 — Cierre automático nocturno** (requiere la primera Cloud Function del proyecto; ya se puede, el plan es Blaze).
6. **Módulo 7 — Campañas de correo (Brevo):** falta confirmar si Rafael ya tiene cuenta/API key de Brevo.
7. **Módulo 8 — Cumpleaños automáticos.**
8. Verificar si quedó creada la alerta de presupuesto de $5 en Google Cloud Billing (se recomendó, no está confirmado).
9. Antes de un lanzamiento real: limpiar cuentas/datos de prueba creadas durante el desarrollo (hay al menos un servidor y un par de niños/acudientes de prueba en la base de datos real de Firebase — no es un ambiente de staging separado).

---

## 10. Cuentas de prueba existentes

- **Admin:** `rafaelbalaguera@gmail.com` (rol administrador; también tiene o puede activar perfil de acudiente).
- **Servidor de prueba:** `sweetgirl288kp@gmail.com` — Karen Alicia Paba Lopez, rol Maestro Principal.
- Puede haber niños/acudientes de prueba adicionales creados durante las pruebas de esta conversación.

*(No se documentan contraseñas aquí por seguridad — las tiene Rafael.)*
