# Diccionario de datos — ventas_retail_gmotta

## 1. Alcance y convención de nombres

Cubre las 4 entidades fuente y las 3 capas del pipeline (Bronze → Silver → Gold), sobre el catálogo
único `ventas_retail_gmotta`, con un esquema por capa: `landing` (solo Volume, sin tablas),
`bronze`, `silver`, `gold`.

## 2. Relaciones entre entidades

```
clientes (1) ──< pedidos (1) ──< detalle_pedidos >── (1) productos
```

- `pedidos.customer_id → clientes.customer_id`
- `detalle_pedidos.order_id → pedidos.order_id`
- `detalle_pedidos.product_id → productos.product_id`

## 3. Nota transversal: `audit_timestamp`

Las 4 fuentes (2 CSV, 2 JSON) incluyen un campo `audit_timestamp` (timestamp de auditoría del
archivo origen) que **no está documentado en `Instrucciones.html`**. Se trata como una columna
real: se preserva en Bronze y se tipa como `TIMESTAMP` en Silver, pero no participa en el modelo
Gold (no aporta al grano ni a las métricas de `fact_ventas`).

## 4. Entidad `clientes` (CSV)

| Campo | Tipo Bronze | Tipo Silver | Descripción | Regla de calidad (Silver) | Severidad |
|---|---|---|---|---|---|
| customer_id | STRING | INT (PK) | Identificador único del cliente | `customer_id IS NOT NULL` | DROP |
| nombre | STRING | STRING | Nombre del cliente | — | — |
| apellido | STRING | STRING | Apellido del cliente | — | — |
| email | STRING | STRING | Correo de contacto | Formato de email válido (regex) | WARN |
| ciudad | STRING | STRING | Ciudad de residencia | — | — |
| pais | STRING | STRING | País de residencia | — | — |
| fecha_registro | STRING | DATE | Fecha de alta del cliente | — | — |
| segmento | STRING | STRING | Retail o Premium | `segmento IN ('Retail','Premium')` | DROP |
| audit_timestamp | STRING | TIMESTAMP | *(no documentado en el enunciado)* | — | — |

## 5. Entidad `productos` (CSV)

| Campo | Tipo Bronze | Tipo Silver | Descripción | Regla de calidad (Silver) | Severidad |
|---|---|---|---|---|---|
| product_id | STRING | INT (PK) | Identificador único del producto | `product_id IS NOT NULL` | DROP |
| nombre_producto | STRING | STRING | Nombre comercial | — | — |
| categoria | STRING | STRING | Categoría del producto | — | — |
| subcategoria | STRING | STRING | Subcategoría del producto | — | — |
| precio_unitario | STRING | DECIMAL(12,2) | Precio unitario de lista | `precio_unitario > 0` | DROP |
| proveedor | STRING | STRING | Proveedor del producto | — | — |
| stock_actual | STRING | INT | Unidades disponibles | `stock_actual >= 0` | WARN |
| audit_timestamp | STRING | TIMESTAMP | *(no documentado en el enunciado)* | — | — |

## 6. Entidad `pedidos` (JSON, array multilínea)

| Campo | Tipo Bronze | Tipo Silver | Descripción | Regla de calidad (Silver) | Severidad |
|---|---|---|---|---|---|
| order_id | STRING | INT (PK) | Identificador único del pedido | `order_id IS NOT NULL` | DROP |
| customer_id | STRING | INT (FK → clientes) | Cliente que hizo el pedido | — | — |
| fecha_pedido | STRING | DATE | Fecha del pedido | — | — |
| canal_venta | STRING | STRING | web / app_movil / tienda_fisica | — | — |
| estado_pedido | STRING | STRING | completado / en_proceso / cancelado | `estado_pedido IN (...)` | DROP |
| total_pedido | STRING | DECIMAL(12,2) | Monto total del pedido | `total_pedido >= 0` | WARN |
| audit_timestamp | STRING | TIMESTAMP | *(no documentado en el enunciado)* | — | — |

## 7. Entidad `detalle_pedidos` (JSON, array multilínea)

Grano de la tabla de hechos `fact_ventas`.

| Campo | Tipo Bronze | Tipo Silver | Descripción | Regla de calidad (Silver) | Severidad |
|---|---|---|---|---|---|
| order_item_id | STRING | INT (PK) | Identificador único de la línea | `order_item_id IS NOT NULL` | DROP |
| order_id | STRING | INT (FK → pedidos) | Pedido al que pertenece | `order_id IS NOT NULL AND product_id IS NOT NULL` | **FAIL** |
| product_id | STRING | INT (FK → productos) | Producto vendido | (misma regla que arriba) | **FAIL** |
| cantidad | STRING | INT | Unidades compradas | `cantidad > 0` | DROP |
| precio_unitario | STRING | DECIMAL(12,2) | Precio aplicado en la venta | — | — |
| descuento | STRING | DECIMAL(5,4) | % de descuento (0 a 1) | — | — |
| audit_timestamp | STRING | TIMESTAMP | *(no documentado en el enunciado)* | — | — |

## 8. Modelo Gold (esquema estrella)

### `dim_cliente` — 1 fila por cliente
`customer_key` (= `customer_id`), `customer_id`, `nombre`, `apellido`, `email`, `ciudad`, `pais`,
`fecha_registro`, `segmento`.

### `dim_producto` — 1 fila por producto
`product_key` (= `product_id`), `product_id`, `nombre_producto`, `categoria`, `subcategoria`,
`precio_lista`, `proveedor`, `stock_actual`.

### `dim_fecha` — 1 fila por día
Generada por calendario (`sequence` + `explode`) sobre el rango de `fecha_pedido` observado en
`silver.pedidos`. `date_key` (INT, `yyyyMMdd`), `fecha`, `anio`, `trimestre`, `mes`, `nombre_mes`,
`dia`, `nombre_dia`, `es_fin_de_semana`.

### `fact_ventas` — 1 fila por línea de `detalle_pedidos`
- FKs: `customer_key`, `product_key`, `date_key`.
- Dimensiones degeneradas: `order_id`, `canal_venta`, `estado_pedido` (provienen de `pedidos`, se
  incluyen directamente en el fact en vez de crear una dimensión adicional para 3 campos
  categóricos — el enunciado no exige que sea la lista exhaustiva de columnas del fact).
- Métricas: `cantidad`, `precio_unitario`, `descuento`, `monto_total` (derivada:
  `cantidad * precio_unitario * (1 - descuento)`, no existe en ninguna fuente).

Surrogate keys = natural keys (`customer_key = customer_id`, etc.): las `MATERIALIZED VIEW` se
recalculan por completo en cada refresh, por lo que un id autoincremental no sería estable entre
corridas.

## 9. Resumen de expectations

| Capa | Tabla | Constraint | Condición | ON VIOLATION |
|---|---|---|---|---|
| Silver | clientes | pk_customer_id_no_nulo | `customer_id IS NOT NULL` | DROP ROW |
| Silver | clientes | email_formato_valido | regex de email | *(warn, sin ON VIOLATION)* |
| Silver | clientes | segmento_permitido | `segmento IN ('Retail','Premium')` | DROP ROW |
| Silver | productos | pk_product_id_no_nulo | `product_id IS NOT NULL` | DROP ROW |
| Silver | productos | precio_mayor_a_cero | `precio_unitario > 0` | DROP ROW |
| Silver | productos | stock_no_negativo | `stock_actual >= 0` | *(warn)* |
| Silver | pedidos | pk_order_id_no_nulo | `order_id IS NOT NULL` | DROP ROW |
| Silver | pedidos | estado_pedido_permitido | `estado_pedido IN (...)` | DROP ROW |
| Silver | pedidos | total_pedido_no_negativo | `total_pedido >= 0` | *(warn)* |
| Silver | detalle_pedidos | pk_order_item_id_no_nulo | `order_item_id IS NOT NULL` | DROP ROW |
| Silver | detalle_pedidos | cantidad_mayor_a_cero | `cantidad > 0` | DROP ROW |
| Silver | detalle_pedidos | fks_no_nulas | `order_id IS NOT NULL AND product_id IS NOT NULL` | **FAIL UPDATE** |
| Gold | dim_cliente | pk_customer_key_no_nulo | `customer_key IS NOT NULL` | DROP ROW |
| Gold | dim_producto | pk_product_key_no_nulo | `product_key IS NOT NULL` | DROP ROW |
| Gold | dim_fecha | pk_date_key_no_nulo | `date_key IS NOT NULL` | DROP ROW |
| Gold | fact_ventas | fk_customer_key_presente | `customer_key IS NOT NULL` | DROP ROW |
| Gold | fact_ventas | fk_product_key_presente | `product_key IS NOT NULL` | DROP ROW |
| Gold | fact_ventas | fk_date_key_presente | `date_key IS NOT NULL` | DROP ROW |
| Gold | fact_ventas | cantidad_positiva | `cantidad > 0` | DROP ROW |
| Gold | fact_ventas | monto_total_no_negativo | `monto_total >= 0` | DROP ROW |
| Gold | fact_ventas | precio_unitario_no_negativo | `precio_unitario >= 0` | *(warn)* |

El proyecto cubre las 3 severidades exigidas por el enunciado: al menos una regla `warn` (ej.
`email_formato_valido`), varias `drop` y una `fail` (`fks_no_nulas`).
