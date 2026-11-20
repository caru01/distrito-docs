# ARQUITECTURA, SEGURIDAD Y GUÍA OPERATIVA — DISTRIC HOUSE (2026)

## 1. Topología del Ecosistema

El ecosistema DISTRIC HOUSE está compuesto por los siguientes módulos de software:

1. **`distrito-api`**: Backend central en Node.js 24 y Express 4.18 con pooling hacia PostgreSQL (Neon Database Serverless). Gestiona 297 endpoints, cálculo de pedidos, inventario, costos COGS, nómina, outbox pattern y autenticación JWT.
2. **`distric_mobile`**: Aplicación móvil oficial para clientes en Flutter / Dart. Compatible con Android e iOS. Incluye navegación reactiva, Modo Chef, suite de juegos Distric Club, tracking en vivo y notificaciones.
3. **`distrito-admin`**: Panel web de administración y ERP en React 18, Vite y Tailwind. Brinda control en tiempo real de pedidos, catálogo, inventario, nómina, finanzas, CRM y configuración.
4. **`distrito-web`**: Tienda web pública para clientes construida en React 18 y Vite.
5. **`distrito-delivery`**: PWA y aplicación móvil en Capacitor 8 para repartidores de la flota propia con telemetría GPS y geocercas automáticas.
6. **`distrito-print-agent`**: Demonio de escritorio en Electron 34 para Windows que comanda impresoras térmicas ESC/POS (Xprinter de 58mm y 80mm).
7. **`distrito-shared`**: Librería compartida de utilitarios transversales y cargador de Google Maps.
8. **`distric-mobile`**: Subproyecto histórico (React/Capacitor). Aislado y conservado como referencia legacy.

---

## 2. Matriz de Roles y Control de Acceso Granular (RBAC)

El acceso administrativo (`/api/pedidos/admin/*`) implementa una doble barrera de seguridad:
- **Barrera 1:** `authenticateToken` + `requireAdministrativeUser`: Bloquea clientes y domiciliarios (`DELIVERY_ROLE`).
- **Barrera 2:** `requirePermission(module, action)`: Verifica en la tabla `pedidos_app_role_permissions` que el rol del usuario tenga el permiso asignado.

### Perfil de Roles Operativos:
- **Super Administrador (ID 2):** Acceso total sin restricciones (115 permisos). Bypass automático en middleware.
- **Administrador (ID 1):** Acceso total al sistema (115 permisos).
- **Gerente (ID 9):** Control operativo amplio (Dashboard, Pedidos, Productos, Categorías, Inventario, Clientes, Cierre Contable, Gastos, Reportes, Nómina, Horarios, Anuncios).
- **Cajero (ID 10):** Gestión de pedidos, domicilios, horarios, impresión y arqueo básico. No puede borrar pedidos ni alterar configuraciones de la tienda ni precios.
- **Mesero (ID 11):** Toma y consulta de pedidos en salón.
- **Cocina (ID 12):** Visualización de comandas, avance de estados de preparación y reimpresión de tickets. Prohibido acceso a configuraciones financieras o reportes.
- **Inventario (ID 13):** Kardex, ajustes de stock, recetas y rentabilidad de insumos.
- **Compras (ID 14):** Registro de compras y gastos a proveedores.
- **Contabilidad (ID 16):** Cierre contable, conciliación de caja, auditoría, reportes financieros y nómina.
- **Domiciliario (ID 17):** Exclusivo para la aplicación `distrito-delivery`. Bloqueado de administración.

---

## 3. Arquitectura del "Modo Chef" (Hamburguesas Personalizadas)

Para evitar la manipulación de precios desde el cliente y garantizar la persistencia de las recetas:

1. El frontend móvil (`distric_mobile`) compila las selecciones del cliente y asigna el producto maestro de sistema (`id: 00000000-0000-4000-8000-000000000001`), preservando el identificador local en `custom_id` y enviando `adiciones`.
2. El validador del backend (`normalizeOrderCart` en `server.js`):
   - Detecta si el producto es personalizado (`isCustomBurgerItem`).
   - Valida cada ingrediente contra el catálogo autoritativo `CHEF_INGREDIENTS_CATALOG`.
   - Calcula el precio total del ítem estrictamente en el servidor:
     $$\text{Precio Final} = \text{Precio Base (Pan)} + \sum (\text{Precio Ingrediente} \times \text{Cantidad})$$
   - Ignora cualquier precio enviado por el cliente si difiere del cálculo del servidor.
   - Genera un resumen legible de la receta para cocina en `notes` (ej: *"Base: Pan Brioche Dorado | 2x Carne Artesanal 120g, Queso Cheddar, Tocineta Ahumada, Salsa Distric Leña"*).
   - Genera el snapshot estructurado en `recipe_details`.

---

## 4. Autenticación Exclusiva por Celular

Mediante la migración `049_allow_phone_only_customer_accounts.sql`:
- La columna `email` en `appmobile_customer_accounts` ya no es obligatoria (`DROP NOT NULL`).
- Se mantiene índice único parcial sobre `email` para usuarios que sí registren correo:
  ```sql
  CREATE UNIQUE INDEX idx_customer_accounts_email_unique ON appmobile_customer_accounts (LOWER(email)) WHERE email IS NOT NULL AND email <> '';
  ```
- Se asegura la unicidad estricta del número de teléfono:
  ```sql
  CREATE UNIQUE INDEX idx_customer_accounts_phone_unique ON appmobile_customer_accounts (phone) WHERE phone IS NOT NULL AND phone <> '';
  ```
- El endpoint `/api/pedidos/customer/register` permite el registro con celular, nombre y contraseña, y `/api/pedidos/customer/login` autentica fluidamente tanto por teléfono como por correo.

---

## 5. Resiliencia de Mensajería: Patrón Outbox

Las notificaciones de WhatsApp Cloud API y SMS no se despachan sincrónicamente dentro de la transacción de compra.
1. La orden se registra e inserta un evento en `pedidos_app_domain_events` de forma atómica.
2. El despachador Outbox (`src/outbox.js`) procesa los eventos pendientes mediante `FOR UPDATE SKIP LOCKED`.
3. Si el proveedor de mensajería experimenta caídas o intermitencias, el pedido NO se aborta y la notificación se reintenta automáticamente con retroceso exponencial.

---

## 6. Procedimiento para Firma de Producción en Android (`distric_mobile`)

1. Genere el keystore privado:
   ```bash
   keytool -genkey -v -keystore distric-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias distric_key
   ```
2. Cree el archivo `distric_mobile/android/key.properties` (excluido de Git):
   ```properties
   storePassword=SU_PASSWORD_DEL_KEYSTORE
   keyPassword=SU_PASSWORD_DEL_ALIAS
   keyAlias=distric_key
   storeFile=../distric-release-key.jks
   ```
3. Genere el paquete de producción (AAB) para Google Play Store:
   ```bash
   cd distric_mobile
   flutter build appbundle --release
   ```
   El binario optimizado quedará en `build/app/outputs/bundle/release/app-release.aab`.
