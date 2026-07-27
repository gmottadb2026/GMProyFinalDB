# ventas_retail_gmotta — Pipeline End-to-End con Spark Declarative Pipelines (SQL)

Proyecto final del curso de Databricks: pipeline de datos end-to-end sobre un dominio de ventas
retail, implementado 100% en **SQL** con **Spark Declarative Pipelines** (Lakeflow Declarative
Pipelines), desde la ingesta incremental en un Volume hasta un modelo dimensional en estrella
consumido por un dashboard de Databricks.

## Arquitectura

Medallion clásica, con ingesta streaming desde archivos en un Volume:

| Capa | Tipo de tabla | Contenido |
|---|---|---|
| 🥉 Bronze | `STREAMING TABLE` (`STREAM read_files`) | Ingesta cruda, todo `STRING`, sin transformación |
| 🥈 Silver | `STREAMING TABLE` (`STREAM`) | Tipado, deduplicación, expectations de formato |
| 🥇 Gold | `MATERIALIZED VIEW` | Modelo dimensional en estrella, listo para BI |

Todo el flujo Bronze→Silver→Gold vive en **un único Declarative Pipeline serverless** (Databricks
Free Edition permite solo una pipeline activa por tipo), definido en `resources/pipeline.yml`.

## Modelo de datos

4 entidades relacionadas (`clientes`, `productos` en CSV; `pedidos`, `detalle_pedidos` en JSON),
3 batches por entidad simulando llegada incremental. Diccionario de datos completo, con el
detalle de cada campo y regla de calidad aplicada, en [`docs/diccionario_datos.md`](docs/diccionario_datos.md).

Relaciones: `pedidos.customer_id → clientes.customer_id` · `detalle_pedidos.order_id →
pedidos.order_id` · `detalle_pedidos.product_id → productos.product_id`.

> Las 4 fuentes incluyen un campo `audit_timestamp` que **no está documentado en el enunciado del
> curso**; se preserva y se tipa igualmente (ver diccionario de datos).

## Estructura del repositorio

```
.
├── databricks.yml               # Definición del Databricks Asset Bundle
├── resources/
│   ├── pipeline.yml              # Declarative Pipeline (serverless, catalog+schema, libraries)
│   └── job.yml                   # Job: setup -> run_pipeline (2 tasks serverless)
├── setup/
│   └── 00_setup.sql               # Notebook SQL idempotente: catálogo, esquemas, Volume
├── src/transformations/
│   ├── 01_bronze.sql              # 4x CREATE OR REFRESH STREAMING TABLE (*_raw)
│   ├── 02_silver.sql              # 4x CREATE OR REFRESH STREAMING TABLE (limpias + expectations)
│   └── 03_gold.sql                # dim_cliente, dim_producto, dim_fecha, fact_ventas
├── docs/
│   └── diccionario_datos.md       # Diccionario de datos completo
├── dashboard/                     # .lvdash.json (se puebla vía "Commit to Git" desde la UI)
└── data/                          # 12 archivos de muestra (4 entidades x 3 batches)
```

## Catálogo, esquemas y Volume

- Catálogo único: **`ventas_retail_gmotta`**.
- Un esquema por capa: `landing` (solo Volume, sin tablas), `bronze`, `silver`, `gold`.
- Volume de aterrizaje: `ventas_retail_gmotta.landing.raw_data`, con la estructura exigida por el
  enunciado:

  ```
  /Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/{entidad}/
  ```

  `ventas_retail_gmotta` aparece dos veces a propósito: la primera es el **catálogo**, la segunda
  es la carpeta `{nombre_proyecto}` que exige la estructura del enunciado
  (`/Volumes/<catalogo>/<esquema>/<volumen>/{nombre_proyecto}/{entidad}/`). No es un error.

## Calidad de datos (expectations)

Reglas de validez estructural/formato en Silver e integridad del modelo estrella en Gold,
cubriendo las 3 severidades exigidas (`warn`, `drop`, `fail`). Tabla completa en la sección 9 de
[`docs/diccionario_datos.md`](docs/diccionario_datos.md).

## Pipeline y Job

- **Pipeline** (`resources/pipeline.yml`): serverless, catálogo `ventas_retail_gmotta`, esquema
  por defecto `bronze`, 3 archivos SQL planos como libraries (`01_bronze.sql`, `02_silver.sql`,
  `03_gold.sql`).
- **Job** (`resources/job.yml`): 2 tareas serverless — `setup` (notebook `setup/00_setup.sql`,
  idempotente) → `run_pipeline` (dispara el Declarative Pipeline).

## Dashboard

4 visualizaciones construidas sobre las tablas `gold.*`:

| # | Dataset | Consulta (resumen) | Visualización |
|---|---|---|---|
| 1 | Ticket promedio por pedido | `AVG` del monto agregado por `order_id` | Counter |
| 2 | Ventas por segmento de cliente | `fact_ventas` + `dim_cliente`, `GROUP BY segmento` | Bar chart vertical |
| 3 | Ventas por canal de venta | `fact_ventas`, `GROUP BY canal_venta` | Bar chart vertical |
| 4 | Top 10 productos por cantidad vendida | `fact_ventas` + `dim_producto`, `ORDER BY unidades DESC LIMIT 10` | Bar chart vertical |

El dashboard se construyó directamente en la UI de Databricks (no reconstruyendo el `.lvdash.json`
a mano) y se guardó en `dashboard/` mediante "Commit to Git".

## Repositorio

<https://github.com/gmottadb2026/GMProyFinalDB>
