-- Capa GOLD - modelo dimensional en estrella como MATERIALIZED VIEW (recomputo completo por
-- refresh). Expectations enfocadas en integridad del modelo: metricas no negativas y FKs hacia
-- dimensiones siempre presentes (seccion 6 del enunciado).
--
-- Decisiones de diseno:
--  - Surrogate key = natural key (customer_key = customer_id, etc.): las MATERIALIZED VIEW se
--    recalculan completas en cada refresh, asi que un id autoincremental no seria estable
--    entre corridas y romperia la integridad del modelo estrella entre ejecuciones.
--  - order_id, canal_venta y estado_pedido se agregan a fact_ventas como dimensiones
--    degeneradas (el enunciado dice "junto con las metricas", no exhaustivo) para poder
--    alimentar las consultas del dashboard sin crear una dimension extra para 3 campos
--    categoricos, lo cual seria sobre-ingenieria.
--  - Todos los JOIN hacia dimensiones son LEFT JOIN: si falta una FK, la fila llega con NULL
--    y es la expectation la que la descarta (DROP ROW), dejando evidencia visible en las
--    metricas del pipeline en vez de perder la fila silenciosamente con un INNER JOIN.
--  - monto_total es derivado (cantidad * precio_unitario * (1 - descuento)); no existe en
--    ninguna fuente.

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_cliente (
  CONSTRAINT pk_customer_key_no_nulo EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Gold: dimension cliente, 1 fila por cliente'
AS
SELECT
  customer_id AS customer_key,
  customer_id,
  nombre,
  apellido,
  email,
  ciudad,
  pais,
  fecha_registro,
  segmento
FROM silver.clientes;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_producto (
  CONSTRAINT pk_product_key_no_nulo EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Gold: dimension producto, 1 fila por producto'
AS
SELECT
  product_id AS product_key,
  product_id,
  nombre_producto,
  categoria,
  subcategoria,
  precio_unitario AS precio_lista,
  proveedor,
  stock_actual
FROM silver.productos;

CREATE OR REFRESH MATERIALIZED VIEW gold.dim_fecha (
  CONSTRAINT pk_date_key_no_nulo EXPECT (date_key IS NOT NULL) ON VIOLATION DROP ROW
)
COMMENT 'Gold: dimension fecha, 1 fila por dia, generada a partir del rango de fecha_pedido observado'
AS
WITH rango AS (
  SELECT MIN(fecha_pedido) AS fecha_min, MAX(fecha_pedido) AS fecha_max
  FROM silver.pedidos
),
calendario AS (
  SELECT explode(sequence(fecha_min, fecha_max, interval 1 day)) AS fecha
  FROM rango
)
SELECT
  CAST(date_format(fecha, 'yyyyMMdd') AS INT) AS date_key,
  fecha,
  year(fecha)                                                    AS anio,
  quarter(fecha)                                                 AS trimestre,
  month(fecha)                                                   AS mes,
  date_format(fecha, 'MMMM')                                     AS nombre_mes,
  day(fecha)                                                     AS dia,
  date_format(fecha, 'EEEE')                                     AS nombre_dia,
  CASE WHEN dayofweek(fecha) IN (1, 7) THEN true ELSE false END  AS es_fin_de_semana
FROM calendario;

CREATE OR REFRESH MATERIALIZED VIEW gold.fact_ventas (
  CONSTRAINT fk_customer_key_presente    EXPECT (customer_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT fk_product_key_presente     EXPECT (product_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT fk_date_key_presente        EXPECT (date_key IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT cantidad_positiva           EXPECT (cantidad > 0) ON VIOLATION DROP ROW,
  CONSTRAINT monto_total_no_negativo     EXPECT (monto_total >= 0) ON VIOLATION DROP ROW,
  CONSTRAINT precio_unitario_no_negativo EXPECT (precio_unitario >= 0)
)
COMMENT 'Gold: tabla de hechos de ventas, grano = 1 fila por linea de detalle_pedidos'
AS
SELECT
  dp.order_item_id,
  dp.order_id,                                                        -- dimension degenerada
  p.canal_venta,                                                      -- dimension degenerada
  p.estado_pedido,                                                    -- dimension degenerada
  c.customer_key,
  pr.product_key,
  CAST(date_format(p.fecha_pedido, 'yyyyMMdd') AS INT) AS date_key,
  dp.cantidad,
  dp.precio_unitario,
  dp.descuento,
  ROUND(dp.cantidad * dp.precio_unitario * (1 - dp.descuento), 2) AS monto_total
FROM silver.detalle_pedidos dp
LEFT JOIN silver.pedidos    p  ON dp.order_id   = p.order_id
LEFT JOIN gold.dim_cliente  c  ON p.customer_id = c.customer_key
LEFT JOIN gold.dim_producto pr ON dp.product_id = pr.product_key;
