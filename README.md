# RocaKids

Sistema de gestión infantil y control de asistencia para el ministerio infantil — migración desde AppSheet/Google Sheets a app nativa (Flutter) + backend Firebase.

## Documentación

- [`docs/SOP-RocaKids-v2.0.md`](docs/SOP-RocaKids-v2.0.md) — especificación funcional y de datos original (fuente de verdad de reglas de negocio).
- [`docs/plan-desarrollo.md`](docs/plan-desarrollo.md) — plan de arquitectura, módulos de desarrollo y plan de lanzamiento.

## Stack

- **App móvil (Android/iOS) y panel admin (Web):** Flutter — un solo código en Dart.
- **Backend:** Firebase (Auth, Firestore, Storage, Cloud Functions, Cloud Scheduler).
- **Correo masivo:** API de Brevo.
- **CI:** GitHub Actions (`flutter analyze` + `flutter test` en cada PR).
- **Build iOS:** Codemagic (no requiere Mac local).

## Estructura del repo

```
/app          → proyecto Flutter (móvil + web admin, un solo código)
/functions    → Cloud Functions (Node.js) — lógica de negocio, cron jobs, integración Brevo
/scripts      → scripts de migración de datos (AppSheet/Sheets → Firestore)
/docs         → SOP y documentación de arquitectura/plan
```

## Desarrollo por módulos

Ver [`docs/plan-desarrollo.md`](docs/plan-desarrollo.md) para el detalle de cada módulo (0 a 10). Cada módulo se desarrolla en su propia rama (`feature/modulo-N-nombre`) y se integra a `main` vía Pull Request una vez probado.
