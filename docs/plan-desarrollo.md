# Plan de Arquitectura, Desarrollo y Lanzamiento — RocaKids

> Copia de referencia del plan acordado con Rafael el 2026-08-12. La fuente editable vive en `C:\Users\rafae\.claude\plans\d-downloads-sop-rocakids-arquitectura-structured-hollerith.md`; este archivo se actualiza a mano cuando el plan cambie de forma relevante.

## Contexto

RocaKids es el sistema de gestión infantil y control de asistencia para el ministerio infantil de la iglesia, actualmente operado sobre AppSheet + Google Sheets. El SOP v2.0 (`docs/SOP-RocaKids-v2.0.md`) especifica el modelo de datos, reglas de negocio e integraciones que debe tener la migración a app nativa.

Este es un proyecto 100% greenfield. Rafael opera KONEKTU como FDE solo/equipo reducido, no tenía experiencia previa con GitHub, y quiere programar junto con Claude Code y aprender, en vez de que el código se genere de forma opaca. Existen datos reales en producción (AppSheet/Sheets, ~200-1000 niños) que deben migrarse.

## Decisiones de arquitectura

- **App móvil:** Flutter (Dart), un solo código para Android e iOS.
- **Backend:** Firebase (Auth, Firestore, Storage, Cloud Functions) — tier gratuito mientras el volumen lo permita.
- **iOS:** build vía **Codemagic** (Rafael está en Windows, sin Mac). Se desarrolla y prueba primero en Android.
- **Panel de administración:** **Flutter Web** (mismo código Dart), desplegado en Firebase Hosting.
- **GitHub:** repo único `rocakids-app` (monorepo: app Flutter + Cloud Functions + docs).
- **Presupuesto:** mínimo posible — tiers gratuitos hasta que sea indispensable pagar.
- **Ritmo:** sin fecha límite fija — desarrollo iterativo por módulos.

## Mapeo del modelo de datos (SOP §2 → Firestore)

- `ninos` (de NINOS)
- `acudientes` (de ACUDIENTES)
- `nino_acudiente` (tabla puente, de NINO_ACUDIENTE)
- `registros` (de REGISTROS — check-in/check-out)
- `campanas_eventos` (de CAMPANAS_EVENTOS)

Reglas de negocio del SOP §3 (unicidad de documento, generación de llave interna, cierre automático nocturno) → Cloud Functions.

## Identidad de marca

Logo oficial: `Logo Final Iglesia Infantil.pdf` (Rafael). Paleta (ver `app/lib/theme/app_colors.dart`):

| Color | Hex |
|---|---|
| Azul marino | `#003399` |
| Azul claro (variante fondo oscuro) | `#2C5BB8` |
| Amarillo | `#FFCC00` |
| Rojo | `#E50000` |
| Púrpura | `#990099` |

Tipografía del logo: VAG Rounded BT (de pago, no usable en la app). Sustituto libre usado en la UI: **Fredoka** (Google Fonts). El logo se usa como imagen (`app/assets/images/logo_rocakids.png`) en momentos de marca (login, splash), no se recrea con texto.

## Módulos de desarrollo

0. **Entorno y esqueleto del proyecto** ✅ — herramientas, proyecto Flutter, proyecto Firebase, repo GitHub, CI básico.
1. **Modelo de datos y autenticación** ✅ — Firestore (Auth + colección `usuarios`), reglas de seguridad, login por correo/contraseña, rol leído del servidor (no del cliente). Hoy solo existe el rol `administrador`; los demás roles del ministerio (Líder Ministerio, Columna, Líder Escuela de Siervos, Maestro Principal/Auxiliar, Usuario externo/portal de padres) quedan documentados para diseñarse más adelante, cuando haya más pantallas construidas sobre las cuales decidir permisos concretos.
2. **Migración de datos existentes** — script de import AppSheet/Sheets → Firestore (staging primero).
3. **CRUD de Niños y Acudientes** — validación de duplicados, vínculos, autorizaciones.
4. **Check-in / Check-out con QR** — escaneo, modo offline con cola de sincronización.
5. **Cierre automático nocturno** — Cloud Function programada + informe por correo.
6. **Panel Admin Web** — listado/búsqueda, reportes, gestión de roles, configuración.
7. **Campañas de correo masivo (Brevo)** — segmentación, editor, envío.
8. **Cumpleaños automáticos** — Cloud Function diaria + versículo + Brevo.
9. **Piloto con usuarios reales y hardening**.
10. **Lanzamiento** — Android (Google Play, Internal Testing → producción), luego iOS (Codemagic → TestFlight → App Store, evaluando entonces el pago de Apple Developer Program).

## Flujo de trabajo GitHub

- Rama `main` protegida.
- Una rama por módulo (`feature/modulo-N-nombre`), PR hacia `main` al cerrar cada módulo.
- GitHub Actions corre `flutter analyze` + `flutter test` en cada PR.

## Pendientes operativos

- Confirmar forma de exportar los datos actuales de AppSheet/Sheets.
- Confirmar si ya existe cuenta de Brevo con API key.
