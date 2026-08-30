# Implementación profesional de Delivery — 9 de agosto de 2026

Este documento registra la implementación del Plan Maestro de mejora de DistritoBG
Delivery. Complementa el [README operativo de Delivery](../distrito-delivery/README.md)
y las [decisiones de arquitectura](../distrito-api/ARCHITECTURE.md).

## Resultado

Delivery continúa usando la interfaz React y la API/PostgreSQL existentes, pero las
reglas críticas ya no dependen del navegador. El sistema incorpora dominio
transaccional, estados separados, turnos, presencia, un único dispositivo GPS,
cola offline, servicio Android, geocerca de servidor, outbox multiinstancia,
idempotencia y pruebas de carrera/E2E.

## Cambios realizados

- Aceptar y salir a entregar son acciones distintas.
- Perfil y pedido se bloquean dentro de una misma transacción al reservar o aceptar.
- Las reservas de Admin consumen la misma capacidad que los pedidos aceptados.
- Aceptar, iniciar, entregar, cancelar, turno y transferencia son idempotentes.
- La orden tiene versión y la edición administrativa rechaza datos obsoletos.
- Sesión, turno, presencia y GPS son conceptos independientes.
- Un solo dispositivo controla el GPS oficial del turno.
- Una ubicación se almacena una vez por conductor/dispositivo, no por pedido.
- La finalización valida GPS y geocerca en el servidor.
- Las excepciones de geocerca y las evidencias tienen permisos/tablas separadas.
- SSE usa IDs, replay y resincronización; cada instancia recorre el log compartido.
- La lista disponible minimiza datos personales y el detalle exige asignación.
- Android incorpora un servicio de ubicación persistente con almacenamiento seguro.
- Admin, seguimiento público y operadores externos conservan contratos compatibles.

## Archivos principales

### Delivery

- `distrito-delivery/src/components/AppLayout.jsx`: turno, heartbeat y estado operativo.
- `distrito-delivery/src/hooks/useDeliveryLocation.js`: GPS web y modos de captura.
- `distrito-delivery/src/hooks/useNativeDeliveryLocation.js`: reconciliación nativa.
- `distrito-delivery/src/hooks/useRealtime.js`: backoff, IDs y resync.
- `distrito-delivery/src/services/locationQueue.js`: cola IndexedDB.
- `distrito-delivery/src/services/nativeLocation.js`: bridge mínimo.
- `distrito-delivery/src/pages/Home.jsx`: capacidad y pedidos comprometidos.
- `distrito-delivery/src/pages/OrderDetail.jsx`: aceptar, iniciar y finalizar.
- `distrito-delivery/src/pages/Profile.jsx`: sesiones propias.

### Backend

- `distrito-api/src/delivery-domain.js`: máquina de estados.
- `distrito-api/src/delivery-order-service.js`: transacciones e idempotencia.
- `distrito-api/src/delivery-location-service.js`: GPS normalizado.
- `distrito-api/src/delivery-geo.js`: distancia y geocerca.
- `distrito-api/src/outbox.js`: publicación multiinstancia.
- `distrito-api/delivery_api.js`: contrato HTTP/SSE Delivery.
- `distrito-api/external_delivery_api.js`: flujo externo preservado.
- `distrito-api/server.js`: sesiones propias, health, configuración y outbox.

### Admin

- `distrito-admin/src/pages/AdminDeliveryMap.jsx`: presencia, GPS y capacidad reales.
- `distrito-admin/src/pages/AdminConfiguracion.jsx`: intervalos y tolerancias centrales.
- `distrito-admin/src/pages/AdminPedidos.jsx`: versión e idempotencia.
- `distrito-admin/src/pages/AdminUsuarios.jsx`: cupo individual.

### Android

- `distrito-delivery/android/app/src/main/java/com/distritobg/delivery/DeliveryLocationService.java`.
- `distrito-delivery/android/app/src/main/java/com/distritobg/delivery/DeliveryLocationStore.java`.
- `distrito-delivery/android/app/src/main/java/com/distritobg/delivery/DeliveryLocationPlugin.java`.
- `distrito-delivery/android/app/src/main/AndroidManifest.xml`.

### Tests

- `distrito-api/test/delivery-domain.test.js`.
- `distrito-api/test/delivery-concurrency.test.js`.
- `distrito-api/test/delivery-http.e2e.test.js`.
- Contratos existentes de esquema, fuentes, base y pedidos.

## Migraciones

| Migración | Finalidad |
| --- | --- |
| `015_delivery_professional_core.sql` | Versión, turnos, presencia, dispositivo, GPS normalizado, idempotencia, geocerca, evidencia y eventos |
| `016_delivery_runtime_settings.sql` | Capacidad predeterminada y backoff SSE |
| `017_delivery_native_bootstrap.sql` | Código Android de un solo uso |

Se conservaron los datos y valores históricos. `Recogido` se interpreta como
compatibilidad de una entrega que ya salió, sin una actualización masiva destructiva.

## Endpoints nuevos o consolidados

| Método | Ruta | Finalidad |
| --- | --- | --- |
| `GET` | `/api/pedidos/auth/me/sessions` | Lista sesiones propias |
| `DELETE` | `/api/pedidos/auth/me/sessions/:id` | Revoca una sesión propia |
| `POST` | `/api/pedidos/delivery/shift/start` | Inicia turno |
| `POST` | `/api/pedidos/delivery/shift/heartbeat` | Mantiene presencia |
| `POST` | `/api/pedidos/delivery/shift/transfer-device` | Transfiere GPS oficial |
| `POST` | `/api/pedidos/delivery/shift/end` | Finaliza turno |
| `POST` | `/api/pedidos/delivery/location/batch` | Sincroniza GPS web |
| `POST` | `/api/pedidos/delivery/native/bootstrap` | Emite código de 90 segundos |
| `POST` | `/api/pedidos/delivery/native/exchange` | Obtiene token GPS limitado |
| `POST` | `/api/pedidos/delivery/native/location/batch` | Sincroniza GPS Android |
| `POST` | `/api/pedidos/admin/delivery/drivers/:id/shift/end` | Fuerza fin de turno |
| `POST` | `/api/pedidos/admin/delivery/orders/:id/geofence-override` | Autoriza excepción |
| `GET` | `/api/pedidos/admin/delivery/orders/:id/evidence` | Lee evidencia autorizada |

Los endpoints preexistentes `accept`, `pickup`, `complete`, `overview`, `assign`,
`history`, `stats`, `realtime/stream` y `track` fueron alineados al nuevo dominio.

## Máquina de estados

```text
Comercial Listo / Entrega Pendiente
                  │ Aceptar
                  ▼
Comercial Listo / Entrega Aceptado
                  │ Recogí / Iniciar entrega
                  ▼
Comercial En camino / Entrega En camino
                  │ Finalizar con geocerca
                  ▼
Comercial Entregado / Entrega Entregado
```

`Pendiente`, `Aceptado` y `En camino` pueden cancelarse por el flujo autorizado.
`Entregado` y `Cancelado` son terminales. Las rutas administrativas genéricas no
pueden fabricar `En camino` o `Entregado` para reparto propio.

## GPS

- `OFF`: turno terminado; servicio y heartbeat apagados.
- `FREE`: turno activo sin pedido en recorrido; frecuencia reducida.
- `DELIVERY`: uno o más pedidos en camino; alta precisión configurable.
- La cola Android usa SQLite y la PWA usa IndexedDB.
- Los lotes tienen IDs, se deduplican y admiten reintentos.
- Los saltos físicamente imposibles no aumentan distancia.
- `tracking_device_id` impide mezclar varios teléfonos.
- `Foreground Service` no depende de la Activity o WebView visible.

El recorrido de una orden se consulta por conductor y ventana
`picked_up_at <= captured_at <= delivered_at`. Los kilómetros personales se suman
desde la ruta física, sin multiplicarlos por pedidos concurrentes.

## Seguridad

- JWT normal validado contra sesión PostgreSQL activa.
- Tres sesiones por usuario y rutas propias sin acceso administrativo.
- Revocar el dispositivo oficial libera su lease GPS y emite evento dirigido.
- Código Android consumible una sola vez; token GPS final protegido por Keystore.
- Lista disponible sin teléfono, apartamento, referencia privada, cambio ni ítems.
- Detalle del pedido solo para el conductor responsable.
- Geocerca, precisión, antigüedad y propiedad validadas en backend.
- Evidencia validada por contenido, MIME y límite de 2 MB.
- Logs estructurados sin token, contraseña, cookie o cuerpo.
- Archivos `.env`, variantes y `local.properties` ignorados por Git.

## Tiempo real

Los eventos de negocio se insertan junto con la mutación. Cada proceso conserva un
cursor sobre `pedidos_app_domain_events`; el sondeo incremental garantiza
multiinstancia y `LISTEN/NOTIFY` sirve como acelerador. Esto evita depender del hub
en memoria y funciona con conexiones PostgreSQL mediante pooler.

Las posiciones generan un aviso efímero por lote/conductor en el mismo log, no una
copia física del GPS por pedido. Se conservan un día; los eventos de negocio,
treinta días. SSE usa `Last-Event-ID`, replay y resync REST.

## Validación ejecutada

| Validación | Resultado |
| --- | --- |
| Migraciones | 17 aplicadas |
| API syntax/check | Aprobado |
| Suite Node | 36/36 aprobadas |
| Concurrencia mismo pedido | Solo un conductor gana |
| Concurrencia capacidad 1 | Solo un pedido queda comprometido |
| Carrera Admin + Delivery | Sin sobreasignación |
| Idempotencia | Un único efecto lógico |
| E2E propio | Login → turno → aceptar → iniciar → GPS → entregar |
| E2E externo | Asignar → entregar a operador → en camino → entregar |
| SSE dos instancias | GPS recibido por una y emitido por la otra |
| Build tienda | Aprobado |
| Build Admin | Aprobado |
| Build Delivery | Aprobado |
| Auditoría runtime npm | 0 vulnerabilidades en los cinco paquetes |
| Android | `testDebugUnitTest`, `assembleRelease` y `bundleRelease` aprobados |
| Servicios localhost/LAN | API y tres frontends responden 200 |

La auditoría Core Web Vitals no se ejecutó porque el entorno Codex no dispone del
servidor Chrome DevTools MCP. No se registran métricas estimadas como si fueran una
medición real.

## Compatibilidad

- Pedidos históricos conservan sus valores y se normalizan al leer.
- El flujo externo permanece separado y nunca genera GPS falso ni consume cupo.
- Admin usa los mismos servicios de capacidad/estado y mantiene el mapa operativo.
- El cliente solo ve `En camino` después de iniciar realmente el recorrido.
- El enlace temporal deja de exponer ubicación al entregar o cancelar.
- La PWA sigue siendo fallback funcional en navegadores sin envoltura nativa.

## Pendientes reales para publicación

1. Desplegar en Render el backend Delivery actual. La API pública todavía responde
   404 al iniciar turno aunque salud, login y consulta inicial funcionan.
2. Repetir el E2E completo contra producción y en dispositivos Android reales.
3. Migrar refresh tokens web a cookies `HttpOnly/Secure/SameSite` cuando API y
   frontends compartan una topología de dominios compatible; actualmente se
   conserva el contrato existente de almacenamiento web para no romper sesiones.
4. Mover evidencias a almacenamiento de objetos cuando exista proveedor y política
   de respaldo/retención. Hoy están separadas del pedido, pero continúan en PostgreSQL.
5. Conectar logs/health a APM y alertas externas de SLO.
6. Ejecutar pruebas reales en varios modelos Android: pantalla apagada, ahorro de
   batería, pérdida prolongada de red, GPS revocado y detención forzada.
7. Configurar Chrome DevTools MCP o CI Lighthouse para medir Core Web Vitals.
8. La variante iOS continúa como PWA; no existe servicio nativo iOS en este alcance.

Ninguna aplicación puede garantizar GPS con el teléfono apagado, sin batería, con
permiso revocado, GPS deshabilitado o detención forzada por el usuario/sistema.
