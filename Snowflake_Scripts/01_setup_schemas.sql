/* ============================================================
   FILE    : 01_setup_schemas.sql
   PURPOSE : Create Medallion Architecture schemas
   LAYERS  :
       BRONZE – Raw ingested data (staging tables)
       SILVER – Cleansed & conformed dimensions
       GOLD   – Business-ready fact tables & aggregates
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS BRONZE
    COMMENT = 'Medallion Bronze layer: raw ingested staging data';

CREATE SCHEMA IF NOT EXISTS SILVER
    COMMENT = 'Medallion Silver layer: cleansed dimensions (SCD-1, SCD-2)';

CREATE SCHEMA IF NOT EXISTS GOLD
    COMMENT = 'Medallion Gold layer: business-ready fact tables and aggregates';
