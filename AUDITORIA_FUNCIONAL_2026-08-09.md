# Auditoría funcional de Admin y Delivery

> Este documento conserva la fotografía del 9 de agosto de 2026. Los pendientes de
> Delivery relativos a estados, concurrencia, turnos, GPS nativo y SSE multiinstancia
> ya fueron abordados; consulta el [README vigente de Delivery](../distrito-delivery/README.md).

Fecha: 9 de agosto de 2026. Entorno auditado: servicios locales conectados a la
base PostgreSQL configurada, sin copiar ni mostrar secretos.

## Resultado ejecutivo

El sistema tiene una base funcional sólida: checkout y stock transaccionales,
sesiones por dispositivo, operación en hora Colombia, PWA, SSE, GPS, geocerca,
mapas compartidos, CRM, inventario, reportes y cierres. Los contratos existentes
pasaron 24/24 pruebas y los tres frontends compilaron correctamente.

Durante la auditoría se corrigieron cuatro defectos verificables:

1. Los nombres y colores de estados estaban duplicados y no coincidían entre
   Dashboard, Pedidos, Delivery y seguimiento.
2. Delivery mostraba el enlace **Estadísticas**, pero `/estadisticas` no renderizaba
   el módulo y regresaba a Pedidos.
3. El endpoint genérico de pedidos permitía saltos arbitrarios, incluso reabrir
   pedidos entregados o cancelados.
4. Una cuenta de reparto autenticada podía intentar consumir rutas administrativas
   que solo verificaban JWT. Ahora la API contrasta el rol real y devuelve `403`.

## Estados vigentes

Los valores de PostgreSQL no se renombraron para evitar una migración riesgosa. La
presentación está centralizada en `distrito-shared/src/orderFlow.js`.

| Valor de API/DB | Nombre operativo | Color | Significado |
| --- | --- | --- | --- |
| `Nuevo` | Recibido | Azul | Pendiente de enviar a cocina |
| `En preparación` | En cocina | Naranja | Preparación activa |
| `Listo` | Listo para despacho | Cian | Disponible para un domiciliario |
| `Listo` + recoger | Listo para recoger | Cian | El cliente puede ir al local |
| `En camino` | En reparto | Dorado | Entrega en curso |
| `Entregado`/`Completado` | Entregado | Verde | Flujo terminado correctamente |
| `Pendiente Pago` | Pago pendiente | Violeta | Requiere confirmar el pago |
| `Cancelado` | Cancelado | Rojo | Pedido fuera del flujo |

Delivery refleja el proceso real actual:

```text
Disponible → En reparto → Entregado
```

`Aceptado` y `Recogido` siguen admitidos para leer datos históricos, pero la
aceptación nueva asigna el pedido e inicia el reparto en la misma transacción.

Las transiciones comerciales autorizadas viven en
`distrito-api/src/order-rules.js`. Entregado, Completado y Cancelado son terminales.
Pago pendiente puede volver a Recibido o En cocina una vez confirmado.

## Pruebas realizadas

| Control | Resultado |
| --- | --- |
| Pruebas Node de esquema, contratos, DB y reglas | 24 aprobadas, 0 fallidas |
| Validación sintáctica de API y routers | Aprobada |
| Build Admin | Aprobado |
| Build Delivery | Aprobado |
| Build tienda/seguimiento | Aprobado |
| Auditoría completa de dependencias | 0 vulnerabilidades conocidas |
| Smoke HTTP de módulos | 25 respuestas exitosas; 1 rechazo esperado por parámetros faltantes |
| Login y recuperación Admin | Render y apertura del formulario verificados |
| Login y recuperación Delivery | Render y cambio de formulario verificados |
| Dashboard autenticado | Render, navegación visible y datos agregados verificados |
| Aislamiento Delivery → Admin | `403` confirmado para `/admin/orders` |
| Configuración visual de Delivery | `200` confirmado para lectura de `/admin/settings` |
| Salto Entregado → Nuevo | `409 INVALID_ORDER_TRANSITION` confirmado |

Los smoke tests cubrieron Dashboard, Pedidos, Categorías, Productos, Inventario,
Configuración, Anuncios, Reportes, Gastos, Cierre contable, Perfil, Auditoría,
Sesiones, Usuarios, Roles, Clientes, Mapa de Domicilios, Horarios y los cinco
endpoints de lectura de Delivery. No se crearon pedidos ni movimientos contables.
Se usaron dos cuentas temporales de auditoría; ambas y sus sesiones fueron
eliminadas al terminar.

No se generaron métricas Lighthouse/Core Web Vitals: el trazador Chrome DevTools
no estuvo disponible en este entorno. Los tamaños de build y tiempos HTTP se
registraron, pero no se presentan como sustituto de LCP, INP o CLS.

## Integridad observada en PostgreSQL

Fotografía durante la auditoría:

- 234 pedidos: 210 entregados, 15 cancelados, 7 recibidos, 1 listo y 1 con pago
  pendiente.
- 0 estados comerciales inválidos.
- 0 estados Delivery inválidos.
- 0 carritos vacíos o con tipo JSON incorrecto.
- 0 pares de coordenadas incompletos.
- 0 pedidos en reparto sin domiciliario.
- 0 inconsistencias entre estados finales comercial/Delivery.
- 0 saldos negativos en lotes.
- 0 sesiones activas huérfanas o por encima del límite.
- 0 perfiles Delivery fuera del cupo de 1 a 5.
- 0 periodos contables cerrados que se crucen.
- 1 fila central de Configuración, como exige la arquitectura.

Hallazgo de calidad de datos: cinco domicilios todavía activos no tienen destino
georreferenciado (dos Web, dos Presencial y uno WhatsApp). La API conserva este
modo para compatibilidad y la PWA usa la dirección escrita, pero esos pedidos no
pueden aprovechar geocerca exacta. Deben corregirse desde Tomar pedido antes de
salir a reparto.

## Rendimiento observado

La primera consulta a Dashboard tardó entre 690 y 830 ms y Reportes alrededor de
630 ms. Después de activar la conexión, las lecturas simples estuvieron en el
rango aproximado de 80 a 250 ms. Esto apunta principalmente a latencia/cold start
de la base remota y al coste de agregados, no a errores de respuesta.

Los artefactos más relevantes del build son:

- Admin Reportes: aproximadamente 109 KB gzip, cargado solo al abrir el módulo.
- Delivery Estadísticas: aproximadamente 109 KB gzip, cargado solo al abrirlo.
- Logo horizontal de la tienda: 686 KB sin optimizar.

## Mejoras recomendadas pendientes

### Prioridad 0 — antes de producción con volumen

1. **Completar autorización fina del backend.** Ya se aisló Admin de Delivery, pero
   aún se debe exigir `módulo:acción` de forma uniforme en cada ruta de Pedidos,
   Productos, Categorías, Configuración, Reportes, Cierre y Anuncios. La interfaz
   oculta opciones, pero la API debe ser la autoridad en todas las operaciones.
2. **Eliminar el borrado físico de pedidos.** El botón y `DELETE /admin/orders/:id`
   pueden romper trazabilidad contable. Sustituir por cancelación/anulación con
   motivo, actor, fecha y auditoría; reservar el borrado para datos de prueba.
3. **Pruebas E2E con una base aislada.** Automatizar pedido Web → cocina → listo →
   aceptación concurrente → GPS → geocerca → entrega, más recogida, cancelación,
   pago pendiente y sesión caducada. La suite actual valida contratos y DB, pero no
   ejecuta todo el recorrido en un navegador real.

### Prioridad 1 — robustez operativa

4. **Paginación real de Pedidos.** La API descarga hasta 300/500 órdenes y la UI
   muestra controles de página sin función. Agregar cursor o `page/limit`, total,
   filtros y búsqueda en servidor. Reutilizar el contrato ya usado por Clientes.
5. **Corregir destinos históricos.** Crear una vista “Dirección pendiente de
   confirmar” y bloquear la publicación a Delivery cuando un domicilio nuevo no
   tenga coordenadas, salvo excepción explícita y auditada.
6. **Idempotencia de acciones.** Añadir claves idempotentes a checkout, aceptación,
   movimientos de inventario y cierre contable para tolerar doble toque, reintentos
   de red y reconexiones móviles.
7. **SSE multiinstancia.** El hub actual vive en memoria del proceso. Si se escala la
   API horizontalmente, usar PostgreSQL `LISTEN/NOTIFY`, Redis o un broker para que
   todos los clientes reciban los mismos eventos.
8. **Observabilidad.** Centralizar errores frontend/backend, latencia por endpoint,
   reconexiones SSE, entregas sin GPS, push fallidos y transiciones rechazadas;
   configurar alertas con datos anonimizados.
9. **Un cliente HTTP común.** Admin todavía repite `fetch`, token, parseo y `alert()`
   en varias páginas. Extraer reintentos, sesión, errores y toasts accesibles para
   evitar comportamientos distintos entre módulos.

### Prioridad 2 — rendimiento y experiencia

10. Comprimir logos a WebP/AVIF y generar tamaños responsivos.
11. Reducir los chunks de gráficas o cargar cada gráfico bajo demanda dentro de
    Reportes/Estadísticas.
12. Ejecutar Lighthouse y trazas de Core Web Vitals en móvil y escritorio contra
    un build de producción, no contra Vite de desarrollo.
13. Añadir cola local únicamente para telemetría GPS no crítica; aceptación,
    entrega, dinero e inventario deben seguir confirmándose en línea.
14. Homogeneizar avisos, confirmaciones y estados vacíos con componentes compartidos
    y retirar diálogos nativos `alert/confirm` del panel.
15. Agregar pruebas de accesibilidad con teclado, lector de pantalla, contraste,
    zoom 200 % y `prefers-reduced-motion` en todos los módulos.

## Comandos de regresión

```powershell
Set-Location .\distrito-api
npm run check
npm test

Set-Location ..\distrito-admin
npm run build

Set-Location ..\distrito-delivery
npm run build

Set-Location ..\distrito-web
npm run build
```

Para la operación local completa:

```powershell
Set-Location ..
.\start-local.ps1
```
