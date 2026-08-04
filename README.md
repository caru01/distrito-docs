# Documentación técnica de Distrito BG

Índice de documentación y fotografía del estado técnico posterior a la alineación de
frontend, backend y base de datos realizada en agosto de 2026.

## Documentos principales

- [Visión general del sistema](../README.md)
- [API, base de datos y operación](../distrito-api/README.md)
- [Decisiones de arquitectura](../distrito-api/ARCHITECTURE.md)
- [Tienda pública](../distrito-web/README.md)
- [Panel administrativo](../distrito-admin/README.md)
- [PWA de domiciliarios](../Distrito-delivery/README.md)
- [Componentes compartidos](../distrito-shared/README.md)

## Estado de referencia

| Indicador | Estado validado |
| --- | --- |
| Migraciones aplicadas | 10 |
| Tests de API y contratos | 21 aprobados |
| Pedidos existentes | 214 |
| Carrito promedio | Aproximadamente 160 bytes |
| Tamaño de pedidos | Aproximadamente 1.6 MB |
| Tamaño de tablas de aplicación | Aproximadamente 25 MB |
| Índices operativos agregados | 17 |
| Permisos definidos | 68 |
| Build tienda | Aprobado, 192 KB JS sin comprimir |
| Build administración | Aprobado, 189 KB JS inicial; módulos diferidos aparte |
| Build Delivery | Aprobado, 169 KB JS inicial; módulos diferidos aparte |

Estas cifras describen la base configurada durante la intervención. Pueden cambiar a
medida que se creen nuevos pedidos, productos, inventario y auditorías.

## Decisiones vigentes

1. PostgreSQL es la fuente de verdad de datos y precios.
2. Las migraciones SQL son la fuente de verdad del esquema.
3. `src/db.js` es la fuente de verdad de conexiones PostgreSQL.
4. La API valida totales, horario colombiano, stock, estados, sesiones y permisos.
5. Los frontends comparten el contrato HTTP; los componentes que deben ser idénticos
   se extraen a `distrito-shared` en vez de copiarse.
6. La tienda pública, la administración y Delivery permanecen en aplicaciones separadas.
7. Las imágenes se consultan mediante endpoints de medios y no se copian en carritos.
8. Configuración es la fuente central de identidad, contacto, logo y temas visuales.
9. Las credenciales permanecen fuera del código versionado.

## Capacidades consolidadas en agosto de 2026

- Horario semanal y excepciones, evaluados en `America/Bogota` también para turnos que cruzan medianoche.
- Checkout transaccional: crea el pedido y reserva stock como una sola operación.
- Seguimiento público limitado por número de pedido y teléfono.
- Inventario directo de productos con entradas, salidas, ajustes, costo y umbral.
- Consulta manual de códigos de barras contra Open Food Facts; el dato externo es solo una sugerencia.
- Tres dispositivos simultáneos por usuario y caducidad tras 60 minutos sin actividad.
- Administración de dispositivos propios desde Perfil.
- Usuarios, roles y matriz de permisos conectados a PostgreSQL.
- Temas separados para tienda y administración, publicados desde Configuración.
- PWA Delivery sobre el JWT y la API existentes, con aceptación atómica, GPS solo
  en ruta, notificaciones push, historial, estadísticas y dispositivos.
- Mapa de Domicilios en el ERP y ubicación en vivo en el seguimiento del cliente.
- Un único `LiveDeliveryMap` compartido muestra sede, destinos y motocicletas con
  nombre tanto al cliente como al administrador; SSE actualiza los marcadores.
- El punto exacto del restaurante vive en Configuración y se incorporó al esquema
  mediante `009_restaurant_geolocation.sql`.
- La ubicación operativa se presenta como **cocina**, con dirección, Place ID y
  coordenadas centrales; `010_delivery_capacity_and_kitchen.sql` también habilita
  de uno a cinco pedidos simultáneos por domiciliario.
- Dirección de entrega con sugerencias de Google, mapa, marcador movible,
  coordenadas, Place ID y datos complementarios persistidos en el pedido.
- Navegación del domiciliario hacia las coordenadas confirmadas, con compatibilidad
  para pedidos históricos que solo tienen dirección escrita.
- Enlace temporal firmado en WhatsApp, mapa público del domiciliario y caducidad
  posterior a la entrega sin exponer el teléfono en la URL.
- Flujo de cocina y reparto alineado: preparar imprime, listo publica, aceptar
  inicia `En camino` y entregar fija la duración visible en administración.
- Tienda y Tomar pedido usan una única implementación de Places/mapa/marcador; la
  edición administrativa persiste el mismo destino exacto y datos complementarios.
- Checkout protegido contra pantallas blancas: React renderiza el campo y la lista
  a partir de Place Autocomplete Data API, sin depender del DOM interno de Google.
- Delivery sin caducidad por inactividad para roles de reparto, con renovación de
  token, alertas sonoras/visuales, scroll táctil basado en `100dvh` y recuperación
  explícita ante errores de interfaz.
- Finalización de entrega independiente de la disponibilidad del GPS; el recorrido
  se transmite solo desde un contexto HTTPS/localhost con permiso de ubicación.
- Onboarding inicial de Delivery para instalación, GPS y sonido, con seguimiento
  global de todos los pedidos activos desde cualquier módulo de la PWA.
- El detalle administrativo se cierra después de confirmar preparar, listo,
  entregar, pendiente de pago o cancelar.

## Próximas mejoras recomendadas

- Migrar imágenes históricas desde PostgreSQL a almacenamiento de objetos y guardar
  únicamente la URL, cuando se defina proveedor y política de respaldo.
- Extraer dominios de `server.js` a routers y servicios gradualmente, manteniendo los
  contratos automatizados.
- Incorporar pruebas HTTP de autenticación, checkout e inventario sobre una base de
  integración aislada.
- Planificar la migración de React Router 6 después de validar la rama 7 y sus
  dependencias.
- Completar el módulo visual de Clientes y notificaciones de cambios de estado.
- Para escalar la API a varias instancias, propagar SSE mediante PostgreSQL
  `LISTEN/NOTIFY` o Redis y mover evidencias fotográficas a almacenamiento de objetos.
- Automatizar `check`, tests, builds y migraciones en CI/CD.

## Cómo documentar cambios futuros

Al cambiar una función:

1. Actualiza el README del componente afectado.
2. Si cambia una regla transversal, actualiza el README raíz y `ARCHITECTURE.md`.
3. Si cambia el esquema, crea una migración nueva y documenta su propósito en el
   README de la API.
4. Registra métricas solo cuando hayan sido verificadas; indica si representan una
   fotografía temporal.
5. Nunca incluyas tokens, contraseñas, cadenas de conexión ni claves privadas.
