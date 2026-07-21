/* ============================================================
   schemachange Migration: V1.0.0__setup_schemas.sql
   PURPOSE : Create Medallion Architecture schemas
   ============================================================ */

USE DATABASE {{ database }};

CREATE SCHEMA IF NOT EXISTS BRONZE
COMMENT = 'Medallion Bronze layer: raw ingested staging data';

CREATE SCHEMA IF NOT EXISTS SILVER
COMMENT = 'Medallion Silver layer: cleansed dimensions (SCD-1, SCD-2)';

CREATE SCHEMA IF NOT EXISTS GOLD
COMMENT = 'Medallion Gold layer: business-ready fact tables and aggregates';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE
COMMENT = 'Masking policies and data governance objects';

CREATE SCHEMA IF NOT EXISTS METADATA
COMMENT = 'Metadata and change tracking objects';
