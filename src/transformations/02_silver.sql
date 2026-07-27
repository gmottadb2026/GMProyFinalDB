-- Capa SILVER - limpieza, tipado explicito y deduplicacion sobre las STREAMING TABLE de Bronze.
-- Lee cada bronze.*_raw como STREAM (stream-to-stream), castea tipos reales y aplica
-- expectations de validez estructural/formato (seccion 6 del enunciado). SELECT DISTINCT
-- deduplica registros identicos que pudieran repetirse entre archivos batch.
--
-- Distribucion de severidades de este archivo (cubre las 3 exigidas a nivel de proyecto):
--   DROP  -> clientes.customer_id, clientes.segmento, productos.product_id,
--            productos.precio_unitario, pedidos.order_id, pedidos.estado_pedido,
--            detalle_pedidos.order_item_id, detalle_pedidos.cantidad
--   WARN  -> clientes.email (formato), productos.stock_actual (no negativo),
--            pedidos.total_pedido (no negativo)
--   FAIL  -> detalle_pedidos.fks_no_nulas: una linea de detalle sin ninguna de sus dos FKs
--            indica una falla sistemica upstream (no un dato sucio puntual), por lo que se
--            detiene el pipeline en vez de seguir produciendo un fact_ventas incompleto.

CREATE OR REFRESH STREAMING TABLE silver.clientes (
  CONSTRAINT pk_customer_id_no_nulo EXPECT (customer_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT email_formato_valido   EXPECT (email RLIKE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
  CONSTRAINT segmento_permitido     EXPECT (segmento IN ('Retail', 'Premium')) ON VIOLATION DROP ROW
)
COMMENT 'Silver: clientes tipados, deduplicados y validados'
AS
SELECT DISTINCT
  CAST(customer_id AS INT)           AS customer_id,
  nombre,
  apellido,
  email,
  ciudad,
  pais,
  CAST(fecha_registro AS DATE)       AS fecha_registro,
  segmento,
  CAST(audit_timestamp AS TIMESTAMP) AS audit_timestamp
FROM STREAM(bronze.clientes_raw);

CREATE OR REFRESH STREAMING TABLE silver.productos (
  CONSTRAINT pk_product_id_no_nulo EXPECT (product_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT precio_mayor_a_cero   EXPECT (precio_unitario > 0) ON VIOLATION DROP ROW,
  CONSTRAINT stock_no_negativo     EXPECT (stock_actual >= 0)
)
COMMENT 'Silver: productos tipados, deduplicados y validados'
AS
SELECT DISTINCT
  CAST(product_id AS INT)                AS product_id,
  nombre_producto,
  categoria,
  subcategoria,
  CAST(precio_unitario AS DECIMAL(12,2)) AS precio_unitario,
  proveedor,
  CAST(stock_actual AS INT)              AS stock_actual,
  CAST(audit_timestamp AS TIMESTAMP)     AS audit_timestamp
FROM STREAM(bronze.productos_raw);

CREATE OR REFRESH STREAMING TABLE silver.pedidos (
  CONSTRAINT pk_order_id_no_nulo      EXPECT (order_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT estado_pedido_permitido  EXPECT (estado_pedido IN ('completado', 'en_proceso', 'cancelado')) ON VIOLATION DROP ROW,
  CONSTRAINT total_pedido_no_negativo EXPECT (total_pedido >= 0)
)
COMMENT 'Silver: pedidos tipados, deduplicados y validados'
AS
SELECT DISTINCT
  CAST(order_id AS INT)               AS order_id,
  CAST(customer_id AS INT)            AS customer_id,
  CAST(fecha_pedido AS DATE)          AS fecha_pedido,
  canal_venta,
  estado_pedido,
  CAST(total_pedido AS DECIMAL(12,2)) AS total_pedido,
  CAST(audit_timestamp AS TIMESTAMP)  AS audit_timestamp
FROM STREAM(bronze.pedidos_raw);

CREATE OR REFRESH STREAMING TABLE silver.detalle_pedidos (
  CONSTRAINT pk_order_item_id_no_nulo EXPECT (order_item_id IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT cantidad_mayor_a_cero    EXPECT (cantidad > 0) ON VIOLATION DROP ROW,
  CONSTRAINT fks_no_nulas             EXPECT (order_id IS NOT NULL AND product_id IS NOT NULL) ON VIOLATION FAIL UPDATE
)
COMMENT 'Silver: detalle_pedidos tipado, deduplicado y validado'
AS
SELECT DISTINCT
  CAST(order_item_id AS INT)             AS order_item_id,
  CAST(order_id AS INT)                  AS order_id,
  CAST(product_id AS INT)                AS product_id,
  CAST(cantidad AS INT)                  AS cantidad,
  CAST(precio_unitario AS DECIMAL(12,2)) AS precio_unitario,
  CAST(descuento AS DECIMAL(5,4))        AS descuento,
  CAST(audit_timestamp AS TIMESTAMP)     AS audit_timestamp
FROM STREAM(bronze.detalle_pedidos_raw);
