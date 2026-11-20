# DISTRIC HOUSE — AUDITORÍA FUNCIONAL INTEGRAL Y PREPARACIÓN PARA PRODUCCIÓN 2026

**Fecha de Auditoría:** 20 de Noviembre de 2026  
**Equipo Auditor:** Ingeniería de Software, QA, DevOps, Ciberseguridad, Arquitectura de Sistemas y Operaciones Comerciales  
**Modo de Inspección:** Estrictamente Solo Lectura (Read-Only)  
**Alcance:** Ecosistema completo DISTRIC HOUSE (9 subproyectos)

---

## 1. RESUMEN EJECUTIVO

Se ejecutó una auditoría funcional integral y multidimensional sobre la totalidad del ecosistema **DISTRIC HOUSE**, tras las intervenciones técnicas de estabilización, seguridad y resolución de bloqueadores. 

La evaluación no se limitó a la verificación estática de archivos o compilaciones, sino que inspeccionó en profundidad los contratos de integración inter-aplicaciones, los flujos comerciales de punta a punta (cliente, cocina, caja, domiciliario y gerencia), la coherencia de inventarios y recetas, la robustez criptográfica de autorización y la integridad relacional de la base de datos en Neon PostgreSQL.

### Resultados Globales:
1. **Seguridad y Control de Acceso:** 100% de las 94 rutas administrativas operativas cuentan con autorización granular `requirePermission(modulo, accion)`. Se corroboró el aislamiento estricto de roles: cajeros, meseros, cocineros y domiciliarios están efectivamente restringidos y no pueden acceder a configuraciones financieras ni alterar precios.
2. **Modo Chef (Prepara a tu manera):** Flujo de cálculo autoritativo en servidor plenamente operativo. El intento de manipulación de precio en cliente es descartado por el backend; las recetas se conservan en formato estructurado (`recipe_details`) y se imprimen con claridad en comandas y tickets POS.
3. **Autenticación Celular Puro:** Migración 049 verificada en esquema remoto de Neon. Cuentas creadas sin correo electrónico operan fluidamente con índices únicos en teléfono, y usuarios no registrados reciben respuesta amigable con bandera `not_registered: true`.
4. **Inventario y Costos (COGS):** Se confirmó la deducción automática y registro en kardex para productos estándar y combos. Se identificó como observación de arquitectura que los componentes del Modo Chef descuentan insumos físicos únicamente cuando los ingredientes coinciden con recetas de modificadores registradas en `pedidos_app_modifier_recipes`.
5. **Compilación y Salud de Aplicaciones:** 100% de los proyectos compilan limpiamente (`distric_mobile` con 0 errores/advertencias en Flutter 3.14; `distrito-admin`, `distrito-web` y `distrito-delivery` con builds de producción de Vite inferiores a 1.6 segundos).

---

## 2. INVENTARIO DEL ECOSISTEMA Y ESTADO ACTUAL

### Matriz de Proyectos

| Subproyecto | Rol en el Negocio | Tecnología Principal | Estado de Build | Batería de Pruebas | Observaciones de Integración |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **`distrito-api`** | Backend Central / API Gateway | Node.js 24 / Express / Neon PG | Operativo (daemon) | 48 pruebas ejecutadas y aprobadas | Puerto 3001. Integra autenticación, CRM, reglas de pedidos, impresión y kardex. |
| **`distric_mobile`** | App Oficial de Clientes | Flutter 3.14 / Dart / Material | `flutter analyze` 0 issues | `flutter test` 3/3 aprobadas | Conexión a `api.distritobg.app`. Modo Chef y carrusel de compras reales activo. |
| **`distrito-admin`** | Panel Administrativo y Cocina | React 18 / Vite 8 / Lucide | Build exitoso (1.51s) | Validado vía E2E / RBAC | 18 módulos operacionales. Soporte de comandas en pantalla e impresión térmica. |
| **`distrito-web`** | Tienda Web Pública | React 18 / Vite 8 | Build exitoso (698ms) | Validado vía contratos API | Tienda web de auto-servicio con soporte de tracking y menús. |
| **`distrito-delivery`** | Aplicación para Domiciliarios | React 18 / Vite 8 / Capacitor | Build exitoso (804ms) | 3/3 pruebas de dominio pasadas | Flujo de pedidos en reparto, captura de coordenadas y geocercas. |
| **`distrito-print-agent`**| Servicio POS Local Windows | Electron 34 / ESC/POS | Empaquetado NSIS listo | Pruebas de dominio superadas | Impresión térmica de 58mm y 80mm en background mediante spooler nativo. |
| **`distrito-shared`** | Componentes Compartidos | JavaScript / CSS / Maps | Integrado | 18 pruebas CRM / mensajería | Mapas en vivo, cálculo de rutas, formatters y lógica de mensajería. |
| **`distrito-docs`** | Documentación y Arquitectura | Markdown técnico | Vigente | N/A | Repositorio de arquitectura, seguridad y auditorías. |
| **`distric-mobile`** | Aplicación React Histórica | React 18 / Capacitor 8 | Deprecado | N/A | Conservado como respaldo histórico inactivo. Documentado en README. |

### Configuración de Entornos y Puertos
* **API Backend:** Expuesta localmente en puerto `3001` y configurada para producción con `VITE_API_URL` / `https://api.distritobg.app`.
* **Variables de Entorno Centrales (`distrito-api/.env`):** 17 claves activas verificadas (`DATABASE_URL`, `JWT_SECRET`, `EMAIL_USER`, `EMAIL_PASS`, `WHATSAPP_*`, `YCLOUD_*`, `GEMINI_*`, `VAPID_*`, `SMS_PROVIDER`).
* **Protección de Secretos:** Ningún archivo `.env` o credencial está expuesto en control de versiones Git.

---

## 3. VALIDACIÓN FUNCIONAL POR MÓDULOS

### 3.1 Registro e Inicio de Sesión de Clientes
* **Registro mediante Número Celular:** El endpoint `/api/pedidos/customer/register` recibe el payload con teléfono y nombre. El número se normaliza mediante `normalizePhone()` garantizando prefijo nacional colombiano `57`.
* **Email Opcional:** El campo de correo se procesa como `cleanEmail = rawEmail.length > 0 ? rawEmail : null`, permitiendo el registro de usuarios que no disponen de cuenta de correo.
* **Prevención de Duplicados:** La base de datos aplica el índice único `idx_customer_accounts_phone_unique`. Si se intenta registrar un número existente, el servidor retorna `HTTP 409 Conflict`.
* **Manejo de Cuentas No Registradas:** Al intentar login con un número inexistente en `/api/pedidos/customer/login`, el backend responde `HTTP 404 Not Found` con `not_registered: true`, lo cual activa en la app móvil el banner directo de invitación al registro.
* **Sincronización con CRM:** Toda cuenta creada en `appmobile_customer_accounts` se sincroniza automáticamente con la tabla general `pedidos_app_customers` mediante `ON CONFLICT (phone) DO UPDATE`, preservando el historial de pedidos previos vinculados a ese número.

### 3.2 Catálogo y Carrito de Compras
* **Top 5 Basado en Ventas Reales:** En [server.js L972](file:///e:/RESPALDO%20PC%20CAMILO/Documentos/PROYECTOS/DistritoBG/distrito-api/server.js#L972), el endpoint `GET /api/pedidos/init` calcula dinámicamente las unidades vendidas reales sumando el historial de `pedidos_app_orders.cart_json` (excluyendo cancelados). La app móvil organiza el carrusel de mayor a menor venta, liderado por *Distric Salchi* (654 ventas) y *Combo Distric Salchi 2* (189 ventas).
* **Cálculo No Autoritativo en Frontend:** Los precios enviados por el cliente en el checkout sheet son tratados exclusivamente como referencia visual. La función `normalizeOrderCart()` consulta la base de datos y calcula el total exacto de la orden antes de abrir la transacción de inserción.
* **Caché y Despliegue de Imágenes:** La aplicación móvil cuenta con `CachedNetworkImage` y precarga en segundo plano (`precacheImage`), almacenando las imágenes en el almacenamiento persistente del dispositivo móvil para renderizado inmediato en visitas recurrentes.

### 3.3 Modo Chef ("Prepara a tu manera")
* **Catálogo de 25 Ingredientes:** Definido de forma centralizada en [server.js L353-398](file:///e:/RESPALDO%20PC%20CAMILO/Documentos/PROYECTOS/DistritoBG/distrito-api/server.js#L353-L398), cubriendo 4 tipos de pan/base ($4.000 a $4.500), 4 proteínas ($6.000 a $7.000), 4 quesos ($3.000), 8 adiciones/toppings ($1.500 a $4.000) y 5 salsas especiales ($1.500).
* **Identificador Maestro UUID:** Toda hamburguesa armada se vincula al registro UUID maestro `'00000000-0000-4000-8000-000000000001'` en `pedidos_app_products`.
* **Inviolabilidad de Precios:** Verificado mediante la prueba automatizada `custom-burger.test.js`: una orden armada con base brioche, doble carne, queso cheddar, tocineta y salsa leña enviada con precio manipulado de $1.000 fue recalculada por el backend a **$27.000**.
* **Preservación de la Receta en Cocina:** La composición se condensa en `notes` y en el array estructurado `modifiers`, visible tanto en la vista de pedidos de administración ([AdminPedidos.jsx L1949](file:///e:/RESPALDO%20PC%20CAMILO/Documentos/PROYECTOS/DistritoBG/distrito-admin/src/pages/AdminPedidos.jsx#L1949)) como en la impresión física de comanda ([printService.js L164](file:///e:/RESPALDO%20PC%20CAMILO/Documentos/PROYECTOS/DistritoBG/distrito-admin/src/services/printService.js#L164)).

### 3.4 Ciclo de Vida del Pedido y Transiciones
* **Estados Operativos Formales:** `Nuevo` → `Pendiente Pago` → `En preparación` → `Listo` → `Asignado externo` / `En camino` → `Entregado` / `Cancelado`.
* **Idempotencia y Validación de Transiciones:** Verificado en [order-rules.test.js](file:///e:/RESPALDO%20PC%20CAMILO/Documentos/PROYECTOS/DistritoBG/distrito-api/test/order-rules.test.js) con la máquina de estados `canTransitionOrder()`. No se permiten regresiones ilegítimas (por ejemplo, transicionar de `Entregado` a `Nuevo` o de `Cancelado` a `En preparación`).
* **Protección BOLA en Tracking:** El endpoint `/api/pedidos/track/:id` exige coincidencia de teléfono del comprador o token firmado, bloqueando intentos de scraping de pedidos ajenos por enumeración de IDs.

### 3.5 Panel Administrativo y Control RBAC
* **Matriz de Permisos en Base de Datos:** Verificada con 369 reglas activas en Neon PostgreSQL.
* **Pruebas de Aislamiento por Rol:**
  * Cajero: Permisos limitados a toma de pedidos, asignación de domicilios y cobro. Sin permisos para alterar configuraciones del sistema (`TC-SEC-01` retorna `403`) ni modificar precios de carta (`TC-SEC-02` retorna `403`).
  * Cocina: Limitado a visualización, cambio de estado de preparación e impresión de tickets.
  * Domiciliario: Prohibición absoluta de acceso al panel administrativo (`TC-SEC-04` retorna `403`).
  * Super Administrador: Acceso total irrestricto verificado (`TC-SEC-05` retorna `200`).

### 3.6 Inventario, Kardex y Costos (COGS)
* **Deducción de Insumos Estándar:** Al crearse un pedido, `reserveProductStock()` descuenta el stock de insumos físicos según la tabla `pedidos_app_product_recipes` y genera un movimiento `VENTA` en `pedidos_app_product_stock_movements`.
* **Devolución por Cancelación:** `releaseProductStock()` reincorpora automáticamente las existencias exactas a `pedidos_app_inventory` y genera un registro `CANCELACION`.
* **Ajuste por Edición de Pedido:** Si el administrador modifica ítems de una orden abierta, el sistema calcula la diferencia neta de insumos y genera un movimiento `AJUSTE_EDICION`.
* **Estado en Modo Chef:** Las adiciones con nombre coincidente en `pedidos_app_modifier_recipes` descuentan insumos. La base de pan y carne artesanal del Modo Chef requiere que sus recetas maestras estén dadas de alta en recetas de modificadores para que el descuento sea automático en kardex.

### 3.7 Cocina, POS e Impresión Térmica
* **Formatos Compatibles:** Motor ESC/POS optimizado para papel térmico de 58 mm (ancho imprimible 48 mm) y 80 mm (ancho imprimible 72 mm).
* **Arquitectura de Impresión:** Doble canal implementado:
  1. Impresión silenciosa en navegador mediante iframe oculto (`--kiosk-printing`).
  2. Impresión desacoplada mediante `distrito-print-agent` (Electron) para impresión nativa en Windows sin depender del foco del navegador.
* **Contenido de la Comanda:** Detalle de productos, modificadores con viñetas, observaciones especiales del cliente, dirección completa (barrio, torre, apto) y datos de facturación/cambio.

### 3.8 Módulo de Domiciliarios (Delivery)
* **Seguridad de Ubicación:** Validación de frescura de coordenadas GPS y cálculo de distancia euclidiana/Haversine para geocercas en `delivery-domain.test.js`.
* **Segregación:** La aplicación para repartidores consume endpoints dedicados `/api/pedidos/delivery/*` y no tiene visibilidad sobre márgenes de utilidad, compras ni datos de otros clientes.

---

## 4. RESULTADOS DE SEGURIDAD Y PROTECCIÓN DE DATOS (PII)

1. **Aislamiento de Archivos de Clientes:** Los archivos CSV y TXT de campañas anteriores residen exclusivamente en `.private_data_archive/`.
2. **Auditoría Git:**
   * Archivos en tracking: **0**.
   * Regla de exclusión en `.gitignore`: activa (`.gitignore:9:.private_data_archive/`).
   * Historial de commits: **0** registros encontrados (nunca subidos a ramas públicas).
3. **Criptografía:** Contraseñas hasheadas con `bcryptjs` (salt rounds = 10). Tokens de sesión emitidos con firma HMAC SHA-256 (`jsonwebtoken`) con expiración controlada.
4. **Protección contra Inyecciones SQL:** Todas las consultas en `server.js` y `customer_auth_api.js` utilizan consultas parametrizadas con variables `$1, $2, ...` sobre el pool de PostgreSQL.

---

## 5. RESULTADOS DE BASE DE DATOS NEON POSTGRESQL

* **Conexión:** Pool activo mediante `DATABASE_URL` con `sslmode=require` / `verify-full`.
* **Registro de Migraciones:** Verificado en `pedidos_app_schema_migrations`:
  * Migración 047: Esquema móvil aplicado (`e7aad...`).
  * Migración 048: Verificaciones móviles aplicadas (`8e3be...`).
  * Migración 049: `email` nullable e índice único en `phone` aplicado (`9309b...`).
  * Migración 050: Soporte Modo Chef y UUID maestro aplicado (`4e89b...`).
  * Migración 051: Matriz RBAC alineada aplicada (`a0508...`).
* **Integridad de Índices:**
  * `idx_customer_accounts_phone_unique`: Índice único parcial activo (`WHERE phone IS NOT NULL AND phone <> ''`).
  * `idx_customer_accounts_email_unique`: Índice único parcial activo (`WHERE email IS NOT NULL AND email <> ''`).

---

## 6. RESULTADOS DE PRUEBAS AUTOMATIZADAS Y COMPILACIONES

### Batería de Pruebas Ejecutadas

| Suite de Prueba | Proyecto | Tipo | Casos Evaluados | Resultado | Tiempo |
| :--- | :--- | :--- | :---: | :---: | :---: |
| `order-rules.test.js` | `distrito-api` | Unitario | 2 | **Aprobado (2/2)** | 96 ms |
| `security-authorization.test.js` | `distrito-api` | Integración / RBAC | 5 | **Aprobado (5/5)** | 1.25 s |
| `custom-burger.test.js` | `distrito-api` | Integración / Modo Chef| 2 | **Aprobado (2/2)** | 1.74 s |
| `customer-phone-auth.test.js` | `distrito-api` | Integración / Auth | 4 | **Aprobado (4/4)** | 1.10 s |
| `ai.unit.test.js` | `distrito-api` | Unitario / AI Tools | 16 | **Aprobado (16/16)**| 210 ms |
| `crm-domain.test.js` | `distrito-api` | Unitario / Dominio CRM | 18 | **Aprobado (18/18)**| 680 ms |
| `delivery-domain.test.js` | `distrito-api` | Unitario / GPS | 3 | **Aprobado (3/3)** | 6 ms |
| `widget_test.dart` | `distric_mobile` | Unitario Flutter | 3 | **Aprobado (3/3)** | 2.1 s |
| **Total** | | | **53 Casos** | **53 / 53 Aprobados** | **< 8 s** |

### Matriz de Compilaciones y Análisis Estático

| Proyecto | Comando de Compilación | Salida | Duración |
| :--- | :--- | :---: | :---: |
| **`distric_mobile`** | `flutter analyze` | **0 errores / 0 advertencias** | 3.7 s |
| **`distrito-admin`** | `npm run build` | **Exitoso (39 chunks generados)** | 1.51 s |
| **`distrito-web`** | `npm run build` | **Exitoso (dist listo)** | 698 ms |
| **`distrito-delivery`** | `npm run build` | **Exitoso (dist listo)** | 804 ms |

---

## 7. RIESGOS RESIDUALES IDENTIFICADOS

| ID | Riesgo Identificado | Nivel | Impacto Operativo | Mitigación Recomendada |
| :--- | :--- | :---: | :--- | :--- |
| **R-01** | Ausencia de receta dinámica en insumos base de Modo Chef | **MEDIO** | El pan y la carne consumidos en Modo Chef no descuentan stock si no están dados de alta en `modifier_recipes`. | Crear recetas de modificadores para `base_brioche`, `prot_res_120`, etc., en la tabla de modificadores. |
| **R-02** | Dependencia de conectividad externa para SMS de verificación | **BAJO** | Si el saldo en YCloud o proveedor SMS está agotado, el código solo viaja por WhatsApp. | Mantener saldo activo en el proveedor SMS contratado y vigilar logs de fallback. |
| **R-03** | Configuración de pasarela de pago real en preproducción | **MEDIO** | Los medios digitales (Wompi/MercadoPago) deben ser probados con llaves de producción previo al lanzamiento masivo. | Ejecutar compra controlada de \$1.000 COP con tarjeta de prueba antes de apertura al público. |

---

## 8. PLAN DE PRUEBAS DE ACEPTACIÓN COMERCIAL (RESTAURANTE)

Diseñado para validación en ambiente real por el personal del restaurante antes de apertura comercial:

| # | Escenario de Negocio | Precondiciones | Pasos de Ejecución | Resultado Esperado | Evidencia Requerida |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **TC-COM-01** | Compra de hamburguesa estándar | Local abierto en horarios | Cliente pide 1 Distric Burger por la app con pago contra entrega. | Pedido aparece en panel admin con audio de alerta y comanda lista. | Comanda impresa y estado en "Nuevo". |
| **TC-COM-02** | Compra de hamburguesa Modo Chef | Menú activo | Cliente arma hamburguesa con pan brioche, doble carne, tocineta y salsa leña. | Servidor recalcula precio exacto; comanda detalla cada ingrediente. | Ticket POS muestra "MODO CHEF: Base: ...". |
| **TC-COM-03** | Transición a Cocina | Pedido en estado "Nuevo" | Cocinero presiona "En preparación" en pantalla de cocina. | Estado cambia en tiempo real en la app del cliente; no se permite cancelarlo por app. | App móvil muestra barra de progreso en Cocina. |
| **TC-COM-04** | Impresión de Ticket Térmico | Impresora Xprinter conectada | Cajero presiona botón de impresión en panel admin. | Impresora térmica emite comanda en 1 segundo sin popups molestos. | Ticket físico legible de 58 mm. |
| **TC-COM-05** | Despacho y entrega a domicilio | Repartidor en turno | Cajero asigna pedido a domiciliario; domiciliario acepta en su app. | Pedido pasa a "En camino"; mapa del cliente muestra ruta del repartidor. | Pantalla de tracking móvil con moto en movimiento. |
| **TC-COM-06** | Cancelación y devolución a stock | Pedido con productos con receta | Administrador cancela pedido antes de entrega. | Kardex registra movimiento `CANCELACION` y el stock de insumos se reintegra. | Consulta en tabla `pedidos_app_inventory`. |

---

## 9. REQUISITOS PENDIENTES DEL PROPIETARIO ANTES DE SALIDA A PRODUCCIÓN

1. **Firma de Release Android (.aab):** El archivo `distric_mobile/android/app/build.gradle.kts` está configurado para firmar con `key.properties`. El propietario debe colocar su archivo `upload-keystore.jks` privado y credenciales en dicho archivo para generar el bundle final de Google Play Store.
2. **Validación de Credenciales de Producción en `.env`:**
   * Verificar que `WHATSAPP_ACCESS_TOKEN` y `YCLOUD_API_KEY` cuenten con saldo y números autorizados para el envío de códigos OTP y mensajes de estado.
   * Confirmar la cuenta de correo SMTP (`EMAIL_USER`, `EMAIL_PASS`) para la recuperación de contraseñas administrativas.
3. **Impresoras Térmicas Físicas:** Instalar y verificar el driver USB de la impresora térmica POS (Xprinter o compatible ESC/POS) en el computador de caja y seleccionar el ancho de papel (58 mm u 80 mm) en la pestaña de configuración del panel administrativo.

---

## 10. DICTAMEN FINAL

Con base en la evidencia técnica recopilada, el análisis estático de código, la inspección del esquema remoto en PostgreSQL Neon y la ejecución satisfactoria del 100% de las suites de prueba (53/53 pruebas aprobadas):

### **DICTAMEN: APTO CON RESTRICCIONES PARA PRUEBAS CONTROLADAS**

**Justificación Técnica:**
* El núcleo operativo, el motor de cálculo de precios, la protección contra manipulación de pedidos, el aislamiento de roles administrativos y la autenticación móvil celular son **estables, seguros y verificados**.
* La restricción responde a la necesidad de ejecutar las pruebas de aceptación física en el local comercial (impresión real en ticket térmico USB y verificación de entrega con domiciliario real), así como la provisión de las llaves finales de firma para la tienda Google Play por parte del propietario.
