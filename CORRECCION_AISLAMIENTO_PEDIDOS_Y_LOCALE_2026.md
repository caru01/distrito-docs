# DISTRIC HOUSE — INFORME TÉCNICO DE CORRECCIÓN
## AISLAMIENTO DE PEDIDOS (BOLA/IDOR) Y RESILIENCIA DE LOCALIZACIÓN (LOCALE DATA)

**Fecha:** 20 de noviembre de 2026  
**Ecosistema:** DISTRIC HOUSE (Backend Node.js `distrito-api` y App Móvil Flutter `distric_mobile`)  
**Estado:** **CORREGIDO, AUDITADO Y VALIDADO CON PRUEBAS AUTOMATIZADAS Y EN VIVO**

---

## 1. RESUMEN EJECUTIVO

Se ejecutó la corrección integral de dos fallos críticos reportados en la operación:
1. **Fallo de Privacidad y Aislamiento de Pedidos (BOLA/IDOR):** Al autenticarse con una cuenta nueva o cambiar de usuario, la interfaz podía mostrar pedidos de otros clientes debido a una consulta SQL permisiva en el backend y retención de caché/estado local en la aplicación móvil.
2. **Excepción Fatal de Localización (`LocaleDataException`):** La pantalla de seguimiento lanzaba una pantalla roja de Flutter al intentar formatear fechas con `es_CO` antes de que el motor cargara los símbolos regionales.

Ambos problemas han sido resueltos de raíz tanto a nivel de servidor como de cliente, respaldados por pruebas de seguridad automatizadas en backend (`order-isolation.test.js`) y pruebas unitarias de aislamiento en Flutter (`session_and_date_format_test.dart`).

---

## 2. ANÁLISIS DE CAUSA RAÍZ

### A. Vulnerabilidad en Backend (`customer_auth_api.js`)
* **Mecanismo defectuoso:** La consulta `GET /api/pedidos/customer/orders` contenía la cláusula:
  ```sql
  WHERE customer_phone = $1 
     OR customer_phone = $2
     OR regexp_replace(COALESCE(customer_phone, ''), '\D', '', 'g') LIKE '%' || $3
  ```
* **Causa del escape:** Si un usuario se registraba mediante correo o Google sin registrar aún su número celular (o con teléfono en blanco), el parámetro `$3` evaluaba a string vacío `""`.
* En SQL, `LIKE '%' || ''` se expandía a `LIKE '%'`, lo que provocaba un **barrido comodín que retornaba todos los pedidos de la base de datos sin importar el cliente**.

### B. Persistencia Local en Dispositivo (`ActiveOrdersService` / `SharedPreferences`)
* La app almacenaba pedidos locales en `distric_active_orders_v2`.
* Al iniciar sesión con un usuario nuevo (`login`, `register`, `googleLogin`), no se detectaba el cambio de identidad, manteniendo pedidos de cuentas previas en el almacenamiento local del dispositivo.

### C. Retención de Estado en Memoria (`TrackingView`)
* `TrackingView` no estaba suscrita reactivamente al ciclo de autenticación de `AuthProvider`.
* Si un usuario cambiaba de cuenta, las variables de estado `_order`, `_selectedOrderId` y `_activeOrders` retenían los datos del usuario saliente hasta reiniciar la app. Adicionalmente, respuestas de red lentas podían sobreescribir el estado de la nueva sesión.

### D. Excepción de Localización de Fechas (`LocaleDataException`)
* Al acceder a rastreo, `DateFormat(pattern, 'es_CO').format(date)` era invocado directamente o con captura insuficiente, provocando la pantalla roja si los datos de `intl` no se encontraban indexados en la tabla de símbolos del framework.

---

## 3. ARCHIVOS MODIFICADOS Y CAMBIOS IMPLEMENTADOS

### 1. `distrito-api/customer_auth_api.js`
* **Consulta protegida contra BOLA/IDOR:**
  - Se valida obligatoriamente que `req.customer.id` exista en el JWT firmado.
  - Se obtienen los datos frescos y autorizados del cliente directo desde la tabla `appmobile_customer_accounts`.
  - **Filtro estricto de teléfono:** Si el cliente no tiene número o contiene menos de 7 dígitos numéricos, la API responde inmediatamente `orders: []` sin ejecutar ninguna consulta a `pedidos_app_orders`.
  - Se eliminó completamente la concatenación comodín `LIKE '%' || $3`. La consulta ahora evalúa coincidencia exacta de dígitos y sufijo nacional estricto de 10 dígitos únicamente cuando el teléfono cumple con la longitud reglamentaria.

### 2. `distric_mobile/lib/providers/auth_provider.dart`
* **Control de cambio de sesión (`_handleSessionSwitch`):**
  - Se añadió la detección de cambio de identidad en `login()`, `register()` y `googleLogin()`.
  - Si el ID del usuario anterior difiere del nuevo usuario (`prev.id != next.id`), se invoca de inmediato `await ActiveOrdersService.clearAll()` y se resetea `_orderHistory = []`.
  - Si el mismo usuario recupera o renueva su sesión, los pedidos activos locales se conservan intactos.

### 3. `distric_mobile/lib/screens/tracking_view.dart`
* **Suscripción a `AuthProvider` y descarte de respuestas obsoletas:**
  - Se implementó `didChangeDependencies()` con seguimiento de `_observedCustomerId` y `_observedIsLoggedIn`.
  - Al detectar un cambio de sesión, se ejecuta `_onAuthIdentityChanged()`:
    1. Incrementa el contador de generación `_requestGeneration++`.
    2. Limpia inmediatamente las variables en memoria: `_order = null`, `_selectedOrderId = null`, `_activeOrders = []`.
    3. Carga exclusivamente los pedidos de la nueva identidad.
  - Cada solicitud asíncrona valida `generation == _requestGeneration` antes de mutar el estado, garantizando que respuestas HTTP rezagadas de la sesión anterior sean descartadas.
* **Formateador seguro con triple respaldo (`_formatDateSafe`):**
  - Paso 1: Intento con `es_CO`.
  - Paso 2: Intento con `es`.
  - Paso 3: Intento con locale por defecto del sistema.
  - Paso 4: Fallback manual nativo (`$d/$m/$y, $h:$min`) que nunca arroja excepciones ante fechas nulas o entornos sin localización.

### 4. `distric_mobile/lib/main.dart`
* Se reforzó la inicialización en el arranque de la app:
  ```dart
  await initializeDateFormatting('es_CO', null);
  await initializeDateFormatting('es', null);
  await initializeDateFormatting(null, null);
  Intl.defaultLocale = 'es_CO';
  ```

---

## 4. MATRIZ DE PRUEBAS Y RESULTADOS

### A. Pruebas Automatizadas de Backend (`distrito-api/test/order-isolation.test.js`)
| Caso de Prueba | Descripción | Resultado |
| :--- | :--- | :--- |
| **TC-SEC-01** | Usuario A consulta sus pedidos y recibe exclusivamente su pedido (Pedido 1107). | **PASÓ** |
| **TC-SEC-02** | Usuario B consulta sus pedidos y recibe exclusivamente su pedido (Pedido 1108); nunca los de A. | **PASÓ** |
| **TC-SEC-03** | Usuario sin teléfono (Google o correo nuevo) recibe `orders: []` sin barrido comodín. | **PASÓ** |
| **TC-SEC-04** | Parámetros query maliciosos (`?phone=...`) son ignorados en favor de la identidad autenticada. | **PASÓ** |
| **TC-SEC-05** | Cliente con teléfono inválido (< 7 dígitos) recibe lista vacía de inmediato. | **PASÓ** |

### B. Pruebas Automatizadas en Flutter (`distric_mobile/test/session_and_date_format_test.dart`)
| Caso de Prueba | Descripción | Resultado |
| :--- | :--- | :--- |
| **TC-FLUTTER-01** | Fecha nula retorna string vacío sin excepción. | **PASÓ** |
| **TC-FLUTTER-02** | Fecha válida formatea en español con mes en texto (`d MMM, yyyy`). | **PASÓ** |
| **TC-FLUTTER-03** | Patrón de hora seguro (`hh:mm:ss a`) formatea correctamente. | **PASÓ** |
| **TC-FLUTTER-04** | Formato manual de respaldo genera salida matemática consistente. | **PASÓ** |
| **TC-FLUTTER-05** | `ActiveOrdersService` aísla pedidos estrictamente por número telefónico. | **PASÓ** |
| **TC-FLUTTER-06** | Cambio de identidad (Usuario A $\to$ Usuario B) purga la persistencia con `clearAll()`. | **PASÓ** |
| **TC-FLUTTER-07** | Mismo usuario renovando sesión conserva sus pedidos activos locales. | **PASÓ** |
| **TC-FLUTTER-08** | Request Generation descarta respuestas asíncronas tardías del usuario anterior. | **PASÓ** |

**Resultado total de la suite Flutter:** **11/11 pruebas aprobadas (100%)**.

---

## 5. VALIDACIÓN EN DISPOSITIVO / EMULADOR EN VIVO

* **Análisis estático:** `flutter analyze` reportó `No issues found!`.
* **Hot Restart:** Ejecutado en el emulador `emulator-5554` (PID 4185).
* **Navegación en vivo a Rastrear:**
  - La pantalla cargó de manera fluida e instantánea.
  - **Cero excepciones `LocaleDataException`:** Eliminación total de la pantalla roja.
  - La hora se muestra limpia: `"Actualizado a las: 02:12:38 p. m."`.
  - Se visualizaron únicamente los pedidos asociados al usuario conectado (`#1107` y `#1106`), sin mostrar el `#1108` perteneciente a otra cuenta.
  - Mapa de ruta y progreso de entrega activos y renderizados.
