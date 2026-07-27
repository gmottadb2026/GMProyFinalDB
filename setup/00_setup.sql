-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Setup — ventas_retail_gmotta
-- MAGIC
-- MAGIC Notebook idempotente (usa `IF NOT EXISTS` en todo). Debe ejecutarse con **Run All**, a
-- MAGIC mano, **una vez, antes del primer `Deploy`** del bundle: Unity Catalog exige que el
-- MAGIC catalogo ya exista para poder crear el Pipeline (si no, el deploy falla con
-- MAGIC `Catalog does not exist`).
-- MAGIC
-- MAGIC Despues de ese primer deploy, este mismo notebook se reutiliza como la tarea `setup`
-- MAGIC del Job (`resources/job.yml`), por lo que las corridas posteriores del Job siguen
-- MAGIC siendo autosuficientes e idempotentes.

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS ventas_retail_gmotta;

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS ventas_retail_gmotta.landing;
CREATE SCHEMA IF NOT EXISTS ventas_retail_gmotta.bronze;
CREATE SCHEMA IF NOT EXISTS ventas_retail_gmotta.silver;
CREATE SCHEMA IF NOT EXISTS ventas_retail_gmotta.gold;

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS ventas_retail_gmotta.landing.raw_data;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Ruta donde deben subirse manualmente (Catalog Explorer, drag-and-drop) los 12 archivos
-- MAGIC de muestra de `data/`, uno por subcarpeta de entidad:
-- MAGIC
-- MAGIC `/Volumes/ventas_retail_gmotta/landing/raw_data/ventas_retail_gmotta/{clientes|productos|pedidos|detalle_pedidos}/`
-- MAGIC
-- MAGIC `ventas_retail_gmotta` aparece dos veces a proposito: la primera es el catalogo, la
-- MAGIC segunda es la carpeta `{nombre_proyecto}` que exige la estructura del enunciado
-- MAGIC (`/Volumes/<catalogo>/<esquema>/<volumen>/{nombre_proyecto}/{entidad}/`). No es un error.

-- COMMAND ----------

SHOW SCHEMAS IN ventas_retail_gmotta;
