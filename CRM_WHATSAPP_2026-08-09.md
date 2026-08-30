# CRM y WhatsApp oficial de Distrito BG

Documento de arquitectura, operación y despliegue del CRM comercial integrado al
ERP. La implementación extiende el módulo histórico de Clientes: no lo reemplaza,
no borra pedidos y no concede consentimiento de marketing durante el backfill.

## Resultado funcional

El flujo implementado relaciona una identidad comercial canónica con sus
conversaciones, pedidos, campañas y conversiones:

```text
WhatsApp Cloud API → webhook firmado → contacto CRM → conversación
                                           ↓
Clientes históricos ← vínculo canónico → pedidos → métricas y preferencias
                                           ↓
segmentos → campañas → cola → estados Meta → atribución de venta
                                           ↓
                                      reportes CRM
```

Desde **Admin → CRM** están disponibles:

- dashboard con prospectos, clientes, recurrentes, VIP, inactivos, conversaciones,
  campañas y ventas atribuidas;
- directorio paginado, filtros, búsqueda por contacto o pedido y ficha 360°;
- edición del perfil comercial, etiquetas, notas sensibles auditadas, consentimiento,
  pedidos, timeline y productos preferidos;
- Inbox responsive con conversación, asignación, estados y respuesta;
- segmentos dinámicos mediante un constructor seguro de reglas;
- plantillas locales y sincronización de plantillas aprobadas por Meta;
- campañas con vista previa, consentimiento, frequency cap, horario, cola, pausa,
  estados y conversión;
- automatizaciones por contacto, mensaje, compra, inactividad, falta de compra y
  cumpleaños;
- reportes diarios, campañas y productos;
- configuración CRM, diagnóstico de WhatsApp y profundidad de cola;
- exportación CSV filtrada y auditada.

## Identidad única y datos existentes

`normalized_phone` usa E.164 como clave comercial. Para Colombia se convierten,
entre otras, `3001234567`, `573001234567`, `+57 300 123 4567` y
`00573001234567` a `+573001234567`. Los números inválidos se conservan en los
pedidos históricos, pero no se fuerza una identidad incorrecta.

La relación `pedidos_app_crm_contact_customers` permite que varias fichas antiguas
duplicadas apunten a un solo contacto sin destruirlas ni fusionarlas a ciegas. Los
pedidos usan `crm_contact_id`; sus importes y estados continúan siendo la fuente
financiera. Los contadores del contacto se mantienen con la función
`pedidos_app_crm_refresh_contact` y triggers de pedido.

Fotografía después del backfill del 9 de agosto de 2026:

| Indicador | Resultado |
| --- | ---: |
| Contactos canónicos | 146 |
| Fichas históricas enlazadas | 148 |
| Pedidos | 235 |
| Pedidos enlazados | 222 |
| Opt-in creado por backfill | 0 |
| Índices CRM | 30 |

Los 13 pedidos no enlazados no se eliminaron: sus teléfonos no permiten deducir
una identidad E.164 colombiana con seguridad.

## Estados CRM

| Estado | Regla principal |
| --- | --- |
| `NUEVO_CONTACTO` | Contacto creado sin interacción o compra suficiente |
| `PROSPECTO` | Escribió o fue contactado y todavía no compró |
| `CLIENTE_NUEVO` | Primera compra válida |
| `CLIENTE_RECURRENTE` | Compró más de una vez |
| `CLIENTE_FRECUENTE` | Supera el umbral configurable de pedidos |
| `VIP` | Supera pedidos o gasto VIP configurado |
| `INACTIVO` | Última compra anterior al umbral de inactividad |
| `RECUPERADO` | Regresa después de estar inactivo |
| `NO_CONTACTAR` | Opt-out o bloqueo comercial explícito |

Las métricas excluyen pedidos cancelados o rechazados. Los umbrales viven en
`pedidos_app_settings`; no están duplicados en el navegador.

## WhatsApp Cloud API

La integración usa la API oficial de Meta. No automatiza WhatsApp Web y no depende
de una sesión de navegador.

### Variables privadas

```env
WHATSAPP_VERIFY_TOKEN=
WHATSAPP_ACCESS_TOKEN=
WHATSAPP_PHONE_NUMBER_ID=
WHATSAPP_BUSINESS_ACCOUNT_ID=
WHATSAPP_APP_SECRET=
WHATSAPP_GRAPH_API_VERSION=vNN.N
WHATSAPP_WEBHOOK_LOG_PAYLOAD=true
```

Estas variables se guardan en el `.env` privado del servidor o en el gestor de
secretos del proveedor. No se usa `VITE_*` porque ningún valor puede llegar al
bundle del navegador. El Admin solo ve indicadores, fechas y los últimos cuatro
dígitos del identificador del número.

### Webhook

URL pública:

```text
https://api.distritobg.app/api/pedidos/webhooks/whatsapp
```

- `GET` valida `hub.mode`, el verify token y devuelve `hub.challenge`.
- `POST` conserva temporalmente el cuerpo JSON original y valida
  `X-Hub-Signature-256` mediante HMAC SHA-256 y `WHATSAPP_APP_SECRET`.
- en producción ambos métodos rechazan transporte HTTP; Render debe entregar
  `X-Forwarded-Proto: https` desde `https://api.distritobg.app`;
- una firma ausente o inválida devuelve 401 antes de tocar datos;
- cada cuerpo aceptado recibe una huella SHA-256 única en
  `pedidos_app_crm_webhook_events`;
- después de persistirlo, la API responde inmediatamente `{ status: "accepted" }`
  y procesa mensajes/estados fuera del ciclo HTTP. El worker recupera eventos que
  permanezcan en `RECEIVED` después de un reinicio;
- `provider_message_id` también es único, de modo que una redelivery no duplica el
  mensaje ni aumenta dos veces los no leídos;
- los eventos `sent`, `delivered`, `read` y `failed` actualizan mensaje, destinatario
  y métricas; un estado atrasado nunca degrada `READ` a `SENT`.

`WHATSAPP_WEBHOOK_LOG_PAYLOAD=true` registra temporalmente en los logs del backend
solo payloads cuya firma sea válida. No registra access tokens. Después de validar
el primer mensaje y sus estados en Render debe cambiarse a `false`, ya que el cuerpo
puede contener teléfonos y texto de clientes.

Los adjuntos entrantes guardan solo metadata autorizada (`mediaId`, MIME, nombre y
hash). La implementación no descarga ni almacena blobs sin una política de tamaño,
antivirus y almacenamiento de objetos.

### Salida y ventana de atención

Una respuesta libre solo se pone en cola si el cliente escribió durante las últimas
24 horas. Fuera de esa ventana se exige una plantilla aprobada. Las campañas siempre
usan plantillas aprobadas y vuelven a comprobar opt-in, opt-out y no-contactar justo
antes del envío.

El worker reclama trabajos con `FOR UPDATE SKIP LOCKED`, por lo que varias instancias
pueden procesar la cola sin tomar el mismo registro. Los rechazos confirmados de Meta
usan reintento exponencial. Si la conexión se corta y no es posible saber si Meta
recibió el mensaje, el trabajo queda `FAILED` con
`WHATSAPP_DELIVERY_UNCERTAIN`: no se reenvía automáticamente para evitar duplicados
y debe revisarse manualmente.

## Segmentos

El navegador no envía SQL. Envía reglas declarativas validadas por una lista
permitida. El compilador genera SQL parametrizado y rechaza campos, operadores y
valores desconocidos. Se admiten criterios como estado, fuente, pedidos, gasto,
última compra, barrio, consentimiento y etiquetas.

Ejemplo conceptual para responder “¿quién escribió por WhatsApp y no compró?”:

```json
{
  "combinator": "AND",
  "rules": [
    { "field": "source", "operator": "eq", "value": "WHATSAPP" },
    { "field": "orders_count", "operator": "eq", "value": 0 }
  ]
}
```

El preview devuelve total y elegibles. El lanzamiento vuelve a evaluar el segmento
en el servidor y toma una fotografía en `crm_campaign_recipients`.

## Campañas y consentimiento

1. Se crea o sincroniza una plantilla.
2. Meta debe marcarla `APPROVED`.
3. Se crea un segmento y se revisa su preview.
4. Se configura campaña, objetivo, variables, fecha y ventana de atribución.
5. Al lanzar, la API excluye sin opt-in, opt-out, no-contactar y contactos dentro
   del límite de frecuencia.
6. Los elegibles se procesan por lotes y solo dentro del horario configurado en
   `America/Bogota`.
7. Meta actualiza enviado, entregado, leído o fallido mediante webhook.
8. Una compra finalizada dentro de la ventana se atribuye a la campaña más reciente.

El backfill y la existencia de un teléfono jamás equivalen a consentimiento. Cada
cambio crea un registro inmutable en `pedidos_app_crm_consents`; el opt-out impide
nuevas campañas incluso si ya existía un destinatario en cola.

## Automatizaciones

Disparadores implementados:

- `CONTACT_CREATED`;
- `MESSAGE_RECEIVED`;
- `ORDER_COMPLETED`;
- `INACTIVITY`;
- `NO_PURCHASE_AFTER_CONTACT`;
- `BIRTHDAY`.

Acciones implementadas:

- inscribir en campaña;
- agregar etiqueta;
- cambiar estado CRM;
- asignar responsable.

Cada ejecución tiene `run_key` único. Las condiciones se vuelven a validar al
ejecutar: si el contacto compró antes de una automatización de “no compró”, deja de
cumplir la regla y no recibe la acción.

## Tablas

| Grupo | Tablas principales |
| --- | --- |
| Identidad | `crm_contacts`, `crm_contact_customers`, `crm_consents` |
| Clasificación | `crm_tags`, `crm_contact_tags`, `crm_contact_interests`, `crm_notes` |
| Conversaciones | `crm_conversations`, `crm_messages`, `crm_webhook_events` |
| Segmentación | `crm_segments`, `crm_segment_members` |
| Campañas | `crm_whatsapp_templates`, `crm_campaigns`, `crm_campaign_recipients`, `crm_message_jobs` |
| Automatización | `crm_automations`, `crm_automation_runs` |
| Analítica | `crm_activities`, `crm_attributions`, `crm_provider_state` |

Todos los nombres reales llevan el prefijo `pedidos_app_`.

Migraciones:

- `018_crm_foundation.sql`: identidad, conversaciones, mensajes, consentimiento,
  backfill, métricas e integración con pedidos;
- `019_crm_commercial.sql`: segmentos, plantillas, campañas, cola,
  automatizaciones y atribución;
- `020_crm_normalization_and_integrity.sql`: paridad E.164 para prefijos
  internacionales;
- `021_crm_search_indexes.sql`: índices GIN/trigram para búsquedas parciales.
- `022_crm_acquisition_source.sql`: recuperación de fuente WhatsApp/Web/Presencial
  desde el primer pedido y conservación para nuevas órdenes.

## API

Todas las rutas usan el prefijo `/api/pedidos`.

| Método | Ruta | Función |
| --- | --- | --- |
| GET/POST | `/webhooks/whatsapp` | Verificación y eventos firmados de Meta |
| GET | `/admin/crm/dashboard` | KPIs y embudo |
| GET | `/admin/crm/contacts` | Directorio paginado y filtrado |
| GET/PUT | `/admin/crm/contacts/:id` | Ficha 360° y edición |
| POST | `/admin/crm/contacts/:id/consent` | Opt-in/opt-out con evidencia |
| POST | `/admin/crm/contacts/:id/notes` | Nota interna/sensible |
| POST/DELETE | `/admin/crm/contacts/:id/tags[...]` | Etiquetado |
| GET/POST | `/admin/crm/tags` | Catálogo de etiquetas |
| GET | `/admin/crm/conversations` | Inbox paginado |
| GET/PUT | `/admin/crm/conversations/:id` | Mensajes, estado y asignación |
| POST | `/admin/crm/conversations/:id/read` | Marca conversación leída |
| POST | `/admin/crm/conversations/:id/messages` | Respuesta idempotente |
| GET/POST/PUT | `/admin/crm/segments[...]` | Constructor, preview y edición |
| GET/POST | `/admin/crm/templates[...]` | Plantillas y sincronización Meta |
| GET/POST/PUT | `/admin/crm/campaigns[...]` | Campañas, preview, lanzamiento y pausa |
| GET/POST/PUT | `/admin/crm/automations[...]` | Reglas comerciales |
| GET | `/admin/crm/reports` | Tendencia, campañas y productos |
| GET/PUT | `/admin/crm/config` | Umbrales y estado de integración |
| GET | `/admin/crm/export.csv` | Exportación con filtros actuales |

## Permisos y auditoría

Acciones CRM: `ver`, `contactos`, `conversaciones`, `responder`, `notas`,
`segmentos`, `campanas`, `campanas_crear`, `campanas_enviar`, `automatizaciones`,
`reportes`, `configurar` y `exportar`.

La API comprueba cada permiso. Tener acceso al panel no concede envío ni
exportación. Se auditan perfiles, consentimiento, notas sensibles, asignaciones,
segmentos, campañas, sincronización, configuración y exportaciones sin guardar
tokens, cuerpos de WhatsApp ni secretos.

## Rendimiento, tiempo real y retención

- contactos e Inbox usan paginación en servidor;
- mensajes usan cursor `before`;
- el dashboard consulta agregados y no descarga toda la base;
- búsquedas parciales usan `pg_trgm`;
- pedidos por contacto, timeline, cola y campañas tienen índices dedicados;
- los eventos CRM pasan por `domain_events`, `LISTEN/NOTIFY` y SSE, compatibles con
  múltiples instancias;
- el worker de automatizaciones hace el barrido temporal una vez por minuto, no
  en cada consulta del navegador.

Ejecutar periódicamente:

```powershell
npm run db:prune
```

Por defecto elimina cuerpos de webhook mayores de 90 días, trabajos terminados
mayores de 30 días y ejecuciones de automatización terminadas mayores de 180 días.
No elimina mensajes comerciales, pedidos ni auditoría. Variables ajustables:

```env
CRM_WEBHOOK_RETENTION_DAYS=90
CRM_JOB_RETENTION_DAYS=30
```

## Health y observabilidad

`GET /api/pedidos/health` expone únicamente señales no secretas:

- PostgreSQL y número de migraciones;
- worker CRM y profundidad de cola;
- WhatsApp configurado o no;
- fecha del último webhook;
- outbox y clientes SSE.

Las rutas CRM generan logs JSON con `request_id`, método, ruta, estado, duración,
usuario y entidad numérica cuando existe. Los workers agregan componente, código y
entidad, nunca access token, app secret, cookie o contraseña.

## Pruebas

`npm test` valida:

- normalización E.164 y clasificación;
- compilación parametrizada de segmentos;
- firma HMAC y variables de plantillas;
- vínculo contacto/cliente/pedido, métricas, recurrencia y atribución;
- transacciones y rollback;
- webhook HTTP válido/inválido/duplicado;
- estado leído resistente a eventos atrasados;
- permisos de lectura, envío y exportación;
- convivencia con las pruebas de Delivery, checkout, inventario, sesiones y SSE.

Resultado acumulado validado: **50/50 pruebas aprobadas** y builds de Admin y tienda aprobados. Las pruebas incluyen verificación GET, firma POST, restricción HTTPS, acuse asíncrono, idempotencia y el ciclo Unicode completo tanto para enlaces `wa.me` como para payloads de WhatsApp Cloud API.

## Despliegue y único pendiente externo

El código, esquema, UI, worker y tests están listos. Para activar tráfico real falta
una acción fuera del repositorio:

1. disponer de una app Meta y un WhatsApp Business Account verificados;
2. crear un usuario del sistema/token permanente con permisos necesarios;
3. cargar las variables privadas en el proveedor de la API, sin prefijo `VITE_`;
4. publicar la API por HTTPS;
5. registrar la URL del webhook y el verify token en Meta;
6. suscribir el WABA al campo `messages`;
7. aprobar al menos una plantilla y pulsar **CRM → Marketing → Sincronizar**;
8. enviar un mensaje real de prueba y confirmar en **CRM → Configuración** que el
   webhook y el número aparecen conectados.

No hay proveedor falso ni envío simulado. Mientras falten estas credenciales, el
CRM local, contactos, pedidos, segmentos, campañas en borrador, reportes y pruebas
funcionan; el envío real responde `WHATSAPP_NOT_CONFIGURED` de forma controlada.
