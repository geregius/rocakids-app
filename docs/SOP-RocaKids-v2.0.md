# **📘 Standard Operating Procedure (SOP): Arquitectura, Lógica y Operación del Sistema RocaKids**

---

**Versión:** 2.0  
**Fecha de Revisión:** Agosto 2026  
**Proyecto:** Sistema de Gestión Infantil y Control de Asistencia \- RocaKids  
**Propósito:** Especificación funcional y de ingeniería para la migración de AppSheet / Google Sheets a desarrollo nativo móvil (iOS / Android) y backend API.

## **1\. 🏗️ Resumen de la Arquitectura del Sistema**

---

El ecosistema **RocaKids** administra el registro, control de asistencia, relaciones familiares, comunicaciones masivas e información médica/autorizaciones para el ministerio infantil.

┌────────────────────────────────────────────────────────┐  
│               Cliente Móvil / Web                      │  
│        (iOS / Android \- React Native o Flutter)        │  
└───────────────────────────┬────────────────────────────┘  
                            │  
                            │ API REST / JSON (HTTPS)  
                            v  
┌────────────────────────────────────────────────────────┐  
│               Backend & Base de Datos                  │  
│       (Google Apps Script \+ Google Sheets DB / SQL)    │  
└─────────────┬───────────────────────────┬──────────────┘  
              │                           │  
   API HTTP   │                           │ API Webhook / HTTP  
              v                           v  
┌───────────────────────────┐   ┌────────────────────────┐  
│  Servidor de Correo API   │   │  Servicios Google      │  
│  (Brevo / Email Marketing)│   │  (Drive / Forms / Auth)│  
└───────────────────────────┘   └────────────────────────┘


## **2\. 🗄️ Modelo de Datos (Data Schema)**

### ---

**2.1. Tabla NINOS (Menores)**

| Campo | Tipo Dato | Clave / Restricción | Descripción |
| :---- | :---- | :---- | :---- |
| idNiNo | String | PK (Llave Primaria) | Hash único (Ej: RKNino-YYYYMMDDHHMMSS-HASH) |
| documentoIdentificacion | String | Unique | Llave compuesta legible (YYYYMMDD-NOMBRE-APELLIDO) |
| identificacionMenor | String | Unique | Número de documento real (Cédula/TI/RC) |
| tipoIdentificacion | Enum | Opcional | Registro Civil, Tarjeta de Identidad, Cédula de Extranjería, Pasaporte |
| nombres | String | Required | Primer y segundo nombre del menor |
| apellidos | String | Required | Apellidos del menor |
| fechaNacimiento | Date | Required | Formato YYYY-MM-DD |
| genero | Enum | Required | Masculino, Femenino |
| fotoUrl | String | Optional | URL directa al archivo almacenado |
| estadoRegistro | Enum | Required | Activo, Inactivo, Pendiente Información |
| alertaMedicaFlag | Boolean | Required | TRUE / FALSE |
| condicionMedica | Text | Optional | Detalle de alergias, medicamentos o indicaciones |
| autorizoFotoFlag | Boolean | Required | 1 (Sí) / 0 (No) |
| fg\_idGrado | String | FK | Vínculo con tabla de configuración de grados |

### **2.2. Tabla ACUDIENTES**

| Campo | Tipo Dato | Clave / Restricción | Descripción |
| :---- | :---- | :---- | :---- |
| idAcudiente | String | PK / Unique | Número de cédula/documento del acudiente |
| tipoDocumento | Enum | Required | Cedula de ciudadania, Cedula de extranjeria, Pasaporte |
| nombres | String | Required | Nombres del acudiente |
| apellidos | String | Required | Apellidos del acudiente |
| telefonoCelular | String | Required | Número telefónico / WhatsApp |
| correoElectronico | String | Required / Valid email | Correo principal de notificación |
| fotoSeguridadUrl | String | Optional | Imagen de perfil para validación de retiro |
| estadoAutorizacion | Enum | Required | Autorizado, Restringido |
| observacionesRestriccion | Text | Optional | Notas de seguridad para entrega del menor |

### **2.3. Tabla NINO\_ACUDIENTE (Tabla Puente)**

| Campo | Tipo Dato | Clave / Restricción | Descripción |
| :---- | :---- | :---- | :---- |
| idRelacion | String | PK | Identificador único del vínculo |
| fk\_idNino | String | FK | Referencia a NINOS.idNiNo |
| fk\_idAcudiente | String | FK | Referencia a ACUDIENTES.idAcudiente |
| parentestoTipo | Enum | Required | Padre, Madre, Tío/a, Abuelo/a, Acudiente Autorizado |
| autorizacionFormulario | String | Optional | Respuesta de confirmación (Sí / No) |
| autorizacionImagen | String | Optional | Confirmación de tratamiento de datos de imagen |
| esRepresentanteLegalFlag | Boolean | Required | TRUE si es el contacto principal |

### **2.4. Tabla REGISTROS (Asistencia y Check-in/Out)**

| Campo | Tipo Dato | Clave / Restricción | Descripción |
| :---- | :---- | :---- | :---- |
| idRegistro | String | PK | Identificador del movimiento |
| fk\_idNino | String | FK | Referencia a NINOS.idNiNo |
| tipoMovimiento | Enum | Required | Entrada, Salida |
| fechaMovimiento | DateTime | Required | Timestamp preciso del movimiento |
| numeroManilla | String | Required | Número de manilla física asignada |
| fk\_idServidor | String | FK | Correo/ID del voluntario que registró |
| fk\_idAcudienteContacto | String | FK | Cédula del acudiente que entrega o retira |
| modalidadRegistro | Enum | Required | AppSheet/App, Cierre Automático, Manual |
| servicio | String | Required | Nombre del servicio/culto (Ej. Dominical 10:00 AM) |
| grupoEdad | String | Required | Aula asignada según fecha de nacimiento |
| observacion | Text | Optional | Comentarios del check-in o check-out |

### **2.5. Tabla CAMPANAS\_EVENTOS (Comunicaciones Masivas)**

| Campo | Tipo Dato | Clave / Restricción | Descripción |
| :---- | :---- | :---- | :---- |
| idCampana | String | PK | Identificador de la campaña |
| asunto | String | Required | Asunto del correo electrónico |
| tituloHeader | String | Required | Encabezado principal del banner |
| mensajeCopy | Text | Required | Cuerpo del mensaje (admite saltos de línea) |
| imagenUrl | String | Optional | Ruta/URL de la imagen en Drive o CDN |
| filtroSegmento | Enum | Required | Todos, Activos ultimos 30 dias, Mayores de 11 años |
| estado | Enum | Required | Borrador, Listo para enviar, Enviado |
| totalEnviados | Integer | System | Conteo final de correos entregados |
| fechaEnvio | DateTime | System | Timestamp de ejecución |

## **3\. ⚙️ Reglas de Negocio y Lógica de Validación (Business Rules)**

### ---

**3.1. Regla de Unicidad de Menor (Duplicados)**

* **Validación en Cliente (Front-End):**  
  Antes de procesar la creación de un nuevo menor, el campo identificacionMenor debe evaluarse contra la base de datos existente:  
  Valid\_If \= NOT(IN(TEXT(\[.identificacionMenor\]), SELECT(NINOS\[identificacionMenor\], \[idNiNo\] \!= \[\_THISROW.idNiNo\])))  
* **Respuesta visual:** Si el documento ya existe, la UI debe bloquear la acción de guardar y desplegar el mensaje de error: *"Este número de documento ya se encuentra registrado en el sistema."*

### **3.2. Generación Dinámica de Llave Interna**

Si el menor no cuenta con número de documento en el momento del registro rápido, el sistema genera la llave primaria (documentoIdentificacion) mediante la fórmula:

\=TEXTO(fechaNacimiento; "yyyyMMdd") & "-" & MAYUSC(REGEXEXTRACT(ESPACIOS(nombres); "^\\S+")) & "-" & MAYUSC(REGEXEXTRACT(ESPACIOS(apellidos); "^\\S+"))

### **3.3. Control de Check-In / Check-Out y Salidas Automáticas**

1. Todo niño que ingresa registra un movimiento tipoMovimiento \= 'Entrada'.  
2. Para considerarse retirado debe existir un movimiento posterior con tipoMovimiento \= 'Salida'.  
3. **Proceso Nocturno Automático (Cron Job):**  
   * El sistema escanea la tabla REGISTROS buscando menores cuyo último estado sea 'Entrada'.  
   * Inserta un registro automático de salida con tipoMovimiento \= 'Salida', fk\_idServidor \= 'SISTEMA\_AUTO', modalidadRegistro \= 'Cierre Automático'.  
   * Emite un informe consolidado por correo al administrador notificando la lista de niños que no fueron retirados manualmente por el servidor.

## **4\. 🌐 Integración de Servicios Externos (APIs)**

### ---

**4.1. Motor de Correos Masivos (API Brevo / Sendinblue)**

Para evitar bloqueos por cuotas diarias de correo (MailApp / GmailApp), las campañas masivas se procesan enviando un payload estructurado JSON en una sola llamada HTTP POST a la API de Brevo.

* **Endpoint:** https://api.brevo.com/v3/smtp/email  
* **Método:** POST  
* **Headers:**

{  
  "api-key": "YOUR\_BREVO\_API\_KEY",  
  "accept": "application/json",  
  "content-type": "application/json"  
}

* **Payload Estructurado:**

{  
  "sender": {  
    "name": "RocaKids",  
    "email": "rokakidsarmenia@gmail.com"  
  },  
  "to": \[  
    { "email": "acudiente1@gmail.com" },  
    { "email": "acudiente2@gmail.com" }  
  \],  
  "subject": "🎉 Evento Especial RocaKids",  
  "htmlContent": "\<html\>...\</html\>"  
}

### **4.2. Algoritmo de Segmentación de Destinatarios**

El motor de filtrado evalúa los siguientes criterios antes de despachar el correo:

* **Todos:** Obtiene todos los acudientes activos con correos válidos (@) vinculados en NINO\_ACUDIENTE.  
* **Activos ultimos 30 dias:** Cruza la tabla REGISTROS filtrando aquellos fk\_idNino con asistencias tipo Entrada registradas en los últimos 30 días calendario.  
* **Mayores de 11 años:** Calcula la edad en base a fechaNacimiento (Edad ≥ 11\) y extrae los correos de sus acudientes asociados.

## **5\. 📱 Guía para el Desarrollo Nativo (iOS / Android)**

### ---

**5.1. Formularios Dinámicos de Actualización**

* Implementar vistas de edición donde los campos se carguen pre-llenados desde el estado del backend.  
* Permitir edición offline con sincronización diferida (Queue pattern) para la toma de asistencia en zonas de baja cobertura dentro del templo.

### **5.2. Escaneo y Lectura de Código de Barras / QR**

* El número de manilla (numeroManilla) o la identificación del menor (identificacionMenor) deben poder ser escaneados usando la cámara del dispositivo móvil para agilizar el proceso de entrada y salida en puerta.

### **5.3. Módulo de Cumpleaños Automáticos**

* El backend debe incluir una tarea programada (Ej. 07:00 AM diario) que compare el día y mes actual contra NINOS.fechaNacimiento, seleccione un versículo aleatorio del banco de promesas y despache la plantilla de felicitación a los acudientes vinculados.