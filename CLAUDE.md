# RocaKids — instrucciones para Claude

App de control de asistencia para el ministerio infantil de la Iglesia
Casa Sobre la Roca (Armenia). Flutter Web + Firebase, en producción con
datos reales de ~460 niños y ~456 acudientes.

**Antes de trabajar, lee [`docs/estado-proyecto.md`](docs/estado-proyecto.md)** —
es la fuente de verdad de qué existe, qué funciona y qué falta.

## ⚠️ Control de costos — leer ANTES de construir o desplegar

Este proyecto tiene un **tope de 5 USD/mes**, vigilado a diario desde
otra conversación con acceso a la consola de GCP. Las restricciones
completas y vigentes están en la **sección 1.5 de
[`docs/estado-proyecto.md`](docs/estado-proyecto.md)** — son de
cumplimiento obligatorio, no sugerencias. Resumen:

- **Regla general:** ante cualquier cosa que Rafael pida, evaluar si
  aumenta el costo por cualquier motivo y **avisarlo ANTES de desplegar,
  no después.**
- Cloud Functions siempre en `southamerica-east1`; buckets de Storage
  siempre en `us-east1`/`us-west1`/`us-central1`.
- Nunca `minInstances > 0`, nunca habilitar APIs de pago nuevas, nunca
  tocar configuración de facturación.
- Consolidar cambios y desplegar **una sola vez**, no varias seguidas.
- Probar en local con el Firebase Emulator Suite antes de desplegar.

## Flujo de trabajo

- **Rafael prueba la interfaz, no Claude.** No levantar un servidor de
  desarrollo ni automatizar el navegador para verificar una feature —
  avisar qué cambió y dejar que él la pruebe.
- Tras un cambio confirmado: actualizar `docs/estado-proyecto.md`,
  hacer commit y push, y desplegar a Hosting.
- **Verificar siempre el deploy de hosting por separado**
  (`firebase deploy --only hosting`) si un deploy combinado termina con
  cualquier advertencia — un deploy combinado puede reportar éxito sin
  haber publicado hosting.
