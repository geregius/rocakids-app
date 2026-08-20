# zxing-wasm (auto-hospedado)

Copia local de `zxing-wasm@3.1.1` (build IIFE del lector, `dist/iife/reader/index.js`
+ `dist/reader/zxing_reader.wasm`), usada por el paquete `mobile_scanner` en
navegadores que no tienen la API nativa `BarcodeDetector` (todo iOS/Safari,
Firefox, navegadores viejos).

**Por qué está vendorizado acá en vez de usar el CDN por defecto:** el paquete
`mobile_scanner` normalmente carga esta librería desde `cdn.jsdelivr.net`, y el
propio bundle de esa librería tiene codificada una URL de OTRO CDN
(`fastly.jsdelivr.net`) para el binario `.wasm` real. Si esa descarga se cuelga
(red del celular, filtrado del operador, lo que sea), la app se queda
"cargando" la cámara para siempre sin ningún error — encontrado 2026-08-19
probando en iPhone. `index.js` es una copia parchada: se cambió la única línea
que arma la URL del `.wasm` para que apunte a este mismo folder
(`zxing/zxing_reader.wasm`) en vez del CDN externo — el resto del archivo es
idéntico al original.

**`AuthService`/`escaner_qr.dart` apunta acá con
`MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl('zxing/index.js')`.**

**Si se actualiza el paquete `mobile_scanner` en el futuro** y cambia la
versión de `zxing-wasm` que usa (ver `zxingWasmVersion` en
`mobile_scanner/lib/src/web/web_library_versions.dart` dentro de
`.pub-cache`), hay que repetir el mismo parche:
1. Descargar `https://cdn.jsdelivr.net/npm/zxing-wasm@VERSION/dist/iife/reader/index.js`
2. Buscar la línea con `fastly.jsdelivr.net` dentro de la función `locateFile`
   y cambiar la plantilla por `` `zxing/${e}` `` (ruta relativa a este folder).
3. Descargar `https://fastly.jsdelivr.net/npm/zxing-wasm@VERSION/dist/reader/zxing_reader.wasm`
   y reemplazar el archivo de acá.

zxing-wasm es un binding a `zxing-cpp`, licencia Apache 2.0.
