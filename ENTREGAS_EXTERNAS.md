# Entregas propias y operadores externos

Este documento describe el contrato logístico incorporado en la migración
`014_external_delivery_companies.sql`.

## Proveedores

- `own`: domiciliario de Distrito BG. Puede emitir GPS desde la PWA.
- `external_manual`: empresa aliada operada manualmente desde el ERP.
- `external_api`: reserva arquitectónica para una integración futura. La versión
  actual no realiza solicitudes a servicios externos ni almacena sus secretos.

La empresa, tarifa, ETA y datos del conductor externo se administran en
**Empresas de Domicilios**. Sus estadísticas se agregan desde los pedidos para no
duplicar cifras.

## Flujo externo

```text
Recibido → En cocina → Listo para despacho
         → Operador asignado
         → Entregado al operador
         → En reparto
         → Entregado
```

Desde el detalle de un pedido listo, **Asignar entrega** permite elegir un
domiciliario propio conectado con cupo o una empresa activa. Una asignación
externa guarda operador, conductor, teléfono, placa/identificación, costo, ETA,
observaciones y usuario administrativo.

La entrega externa debe confirmar por separado:

1. Asignación del operador.
2. Entrega física al operador.
3. Salida hacia el cliente.
4. Confirmación manual de entrega.

Cada hito se registra en `pedidos_app_delivery_events` y en la auditoría general.

## Contrato financiero

- `delivery_fee`: valor cobrado al cliente. Proviene de Configuración y forma
  parte del total del pedido.
- `external_delivery_cost`: costo pagado por Distrito BG al operador aliado.
- Margen logístico: `delivery_fee - external_delivery_cost`.

El costo externo nunca modifica el total del cliente.

## Seguimiento

El mapa solo se renderiza si un domiciliario propio tiene coordenadas GPS reales.
Un operador externo manual utiliza una línea de estados, nombre de la empresa y
ETA cuando están disponibles. La tienda indica de forma explícita que el aliado
no comparte GPS y no crea marcadores ni recorridos simulados.

Los mensajes de WhatsApp usan el mismo tipo de proveedor: para terceros informan
que la entrega está a cargo de un operador logístico aliado y enlazan al avance
por estados, sin prometer rastreo GPS.

## API administrativa

Todas las rutas parten de `/api/pedidos` y requieren los permisos existentes de
`Domicilios`:

- `GET|POST /admin/delivery-companies`
- `GET|PUT /admin/delivery-companies/:id`
- `GET /admin/delivery/orders/:id/events`
- `POST /admin/delivery/orders/:id/assign-external`
- `POST /admin/delivery/orders/:id/external-handoff`
- `POST /admin/delivery/orders/:id/external-start`
- `POST /admin/delivery/orders/:id/external-complete`

## Pruebas cubiertas

La suite transaccional valida y revierte automáticamente:

1. Domiciliario propio con GPS real.
2. Operador externo manual sin puntos GPS y con margen independiente.
3. Reasignación de un pedido propio pendiente hacia una empresa externa.

