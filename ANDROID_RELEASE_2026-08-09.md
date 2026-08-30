# Release Android de Distrito BG Delivery

Fecha de auditoría: 9 de agosto de 2026.

## Resultado ejecutivo

Se generaron un APK y un AAB Release firmados. Ambos contienen exclusivamente la
API `https://api.distritobg.app/api/pedidos`, deshabilitan tráfico HTTP y no
contienen `localhost:3001`, `127.0.0.1`, `10.0.2.2` ni direcciones `192.168.*`.

Los artefactos son **Release Candidate** y no deben distribuirse todavía. La API
de Render responde salud, login y consulta inicial, pero devuelve `404` para
`POST /api/pedidos/delivery/shift/start`. Esto demuestra que la versión desplegada
del backend es anterior al contrato Delivery vigente. Debe desplegarse primero el
backend actual y repetir la prueba integral.

## Auditoría de la versión anterior

El APK de depuración existente estaba compilado sin `VITE_API_URL` y resolvía:

```text
http://localhost:3001/api/pedidos
```

Tampoco existía configuración de firma Release. Por tanto, ese APK no era apto
para teléfonos reales fuera del PC de desarrollo.

## Ambientes

La fuente de verdad es `distrito-delivery/config/api-environments.json`:

| Ambiente | API | Uso |
| --- | --- | --- |
| Desarrollo web | `auto`, puerto 3001 | Navegador local o LAN |
| Android desarrollo | `http://10.0.2.2:3001` | Emulador Android, solo Debug |
| Producción | `https://api.distritobg.app` | APK/AAB Release |

`vite.config.mjs` detiene el build si Producción no usa HTTPS, si el host es local
o privado, o si no coincide exactamente con `api.distritobg.app`. El mismo valor
se lee desde Gradle y vuelve a validarse en el plugin y servicio GPS nativos.

Capacitor usa en producción:

```json
{
  "server": {
    "androidScheme": "https",
    "hostname": "delivery.distritobg.app"
  },
  "android": {
    "allowMixedContent": false
  }
}
```

Ese origen ya está autorizado por CORS en la API real. El origen anterior de
Capacitor, `https://localhost`, era rechazado con HTTP 500 durante el preflight.

## Firma

La identidad se guardó fuera del repositorio:

```text
C:\Users\XploiT\.distritobg\distritobg-delivery-release.p12
C:\Users\XploiT\.distritobg\android-release-signing.properties
```

- Alias: `distritobg-delivery`.
- Algoritmo: RSA 4096 bits.
- Certificado SHA-256:
  `cc257e71157e8edba61e6ce67fcd93ab80a8a3b439c6bff6a5dc244c137c00c2`.
- El APK verifica mediante APK Signature Scheme v2.
- El AAB pasa `jarsigner -verify`.
- Las contraseñas no se imprimieron, no están en Git y no están dentro del APK.

Se debe respaldar el `.p12` y el archivo de propiedades en una bóveda. Sin esa
clave no será posible publicar actualizaciones compatibles con la aplicación.

La clave cliente de Google Maps sí queda dentro del JavaScript, como ocurre con
cualquier integración Maps ejecutada en el dispositivo. No es un secreto del
backend, pero debe confirmarse en Google Cloud que sea la clave de producción y que
esté restringida al origen `https://delivery.distritobg.app/*` y únicamente a las
APIs de Maps necesarias. El análisis no encontró `DATABASE_URL`, secretos JWT,
correo ni credenciales privadas de WhatsApp en los assets.

## Artefactos

```text
distrito-delivery/android/app/build/outputs/apk/release/app-release.apk
distrito-delivery/android/app/build/outputs/bundle/release/app-release.aab
```

Datos del build actual:

| Artefacto | Tamaño | SHA-256 |
| --- | ---: | --- |
| APK | 6.482.551 bytes | `935F196DD7B9B8D3F47F922EC1B08C6F4C0D56B24D44D30D03880676501465EB` |
| AAB | 6.181.728 bytes | `EE2C77267CA7FA2407B3458EB4E2ECFBA9A66DE9B1F3FF37E6D13015EC567763` |

Aplicación: `com.distritobg.delivery`, `versionCode=1`, `versionName=1.0`, Android
mínimo API 24 y objetivo API 36.

## Validación contra producción

Resultado contra `https://api.distritobg.app`:

| Comprobación | Resultado |
| --- | --- |
| HTTPS y certificado | Aprobado |
| `GET /health` | 200, PostgreSQL `neondb`, 22 migraciones |
| CORS desde `https://delivery.distritobg.app` | 204, aprobado |
| Login temporal de domiciliario | Aprobado |
| Consulta de pedidos actuales | Aprobado |
| Iniciar turno | **Bloqueado: 404 en Render** |
| Aceptar, recoger, GPS, seguimiento y finalizar | No ejecutados en producción por el bloqueo anterior |

El usuario, pedido y contacto temporales usados para la comprobación fueron
eliminados; el recuento residual E2E quedó en cero.

La suite local sí cubre autenticación, sesiones, aceptación concurrente, cupo,
cambio de estados, geocerca, GPS, seguimiento, cierre, SSE, token nativo de un solo
uso, deduplicación y cola sin conexión.

## Cómo reconstruir

```powershell
Set-Location C:\Users\XploiT\AndroidStudioProjects\DistritoBG\distrito-delivery
npm ci
npm run android:release
```

El script compila en modo producción, sincroniza Capacitor con configuración
segura, busca URLs prohibidas, ejecuta pruebas Android y genera APK/AAB. Gradle
detiene el Release si no encuentra la firma.

## Cómo verificar la conexión

1. Desplegar el backend actual en Render.
2. Confirmar que `/api/pedidos/delivery/shift/start` ya no devuelve 404.
3. Instalar el APK en un teléfono de prueba limpio.
4. Iniciar sesión con un domiciliario de pruebas.
5. Revisar los logs de Render: las solicitudes deben llegar a
   `/api/pedidos/delivery/*` desde la aplicación instalada.
6. Iniciar turno, aceptar un pedido controlado, recogerlo, enviar GPS y comprobar el
   mapa administrativo y el seguimiento del cliente.
7. Activar modo avión, capturar varias posiciones, recuperar la red y confirmar el
   vaciado de la cola SQLite sin puntos duplicados.
8. Finalizar dentro de la geocerca y verificar historial, tiempo y cese del GPS.

## Pasos antes de instalar definitivamente

1. Desplegar `distrito-api` actual en Render; es el bloqueo obligatorio.
2. Repetir el E2E HTTPS completo contra producción.
3. Probar el APK en al menos dos modelos Android con pantalla apagada, ahorro de
   batería, GPS revocado y pérdida prolongada de red.
4. Respaldar la clave Release y sus contraseñas en una bóveda segura.
5. Restringir la clave pública de Google Maps a los usos necesarios y monitorear su
   cuota. No hay credenciales privadas del backend dentro del APK.
6. Incrementar `versionCode` en cada publicación posterior.
7. Si un teléfono tiene el APK Debug, desinstalarlo antes del Release porque ambos
   usan el mismo `applicationId` pero firmas distintas. Esto borra la sesión local.
