-- Capa BRONZE - ingesta incremental cruda desde el Volume (STREAMING TABLE + STREAM read_files).
-- Sin transformaciones de negocio: todos los campos se leen como STRING (schema explicito,
-- SIN inferencia) mas metadata de ingesta. audit_timestamp (no documentado en el enunciado)
-- se preserva como columna real.
--
-- Los archivos JSON de pedidos/detalle_pedidos son un array "pretty" multilinea (no NDJSON):
-- cada objeto ocupa varias lineas fisicas del archivo, por lo que multiLine => true es
-- obligatorio; sin esa opcion, read_files falla con CF_FAILED_TO_INFER_SCHEMA.OTHER incluso
-- con schema explicito.

CREATE OR REFRESH STREAMING TABLE bronze.clientes_raw
COMMENT 'Bronze: ingesta cruda de clientes (CSV), 1:1 con el archivo fuente + metadata de ingesta'
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp()  AS _ingested_at
FROM STREAM read_files(
  '/Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/clientes/',
  format => 'csv',
  header => true,
  schema => '
    customer_id STRING,
    nombre STRING,
    apellido STRING,
    email STRING,
    ciudad STRING,
    pais STRING,
    fecha_registro STRING,
    segmento STRING,
    audit_timestamp STRING
  '
);

CREATE OR REFRESH STREAMING TABLE bronze.productos_raw
COMMENT 'Bronze: ingesta cruda de productos (CSV)'
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp()  AS _ingested_at
FROM STREAM read_files(
  '/Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/productos/',
  format => 'csv',
  header => true,
  schema => '
    product_id STRING,
    nombre_producto STRING,
    categoria STRING,
    subcategoria STRING,
    precio_unitario STRING,
    proveedor STRING,
    stock_actual STRING,
    audit_timestamp STRING
  '
);

CREATE OR REFRESH STREAMING TABLE bronze.pedidos_raw
COMMENT 'Bronze: ingesta cruda de pedidos (JSON array multilinea)'
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp()  AS _ingested_at
FROM STREAM read_files(
  '/Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/pedidos/',
  format    => 'json',
  multiLine => true,
  schema    => '
    order_id STRING,
    customer_id STRING,
    fecha_pedido STRING,
    canal_venta STRING,
    estado_pedido STRING,
    total_pedido STRING,
    audit_timestamp STRING
  '
);

CREATE OR REFRESH STREAMING TABLE bronze.detalle_pedidos_raw
COMMENT 'Bronze: ingesta cruda de detalle_pedidos (JSON array multilinea)'
AS
SELECT
  *,
  _metadata.file_path AS _source_file,
  current_timestamp()  AS _ingested_at
FROM STREAM read_files(
  '/Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/detalle_pedidos/',
  format    => 'json',
  multiLine => true,
  schema    => '
    order_item_id STRING,
    order_id STRING,
    product_id STRING,
    cantidad STRING,
    precio_unitario STRING,
    descuento STRING,
    audit_timestamp STRING
  '
);
