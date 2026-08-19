/* ============================================================
   schemachange Migration: V1.000.100__setup_schemas.sql
   PURPOSE : Create environment-specific schemas (RAW, CLEAN, CONFORMED, GOVERNANCE)
             and shared METADATA schema.
   ============================================================ */

USE DATABASE {{ database }};

CREATE SCHEMA IF NOT EXISTS {{ raw_schema }}
COMMENT = 'Raw layer: raw ingested staging data ({{ environment }})';

CREATE SCHEMA IF NOT EXISTS {{ clean_schema }}
COMMENT = 'Clean layer: cleansed dimensions and transforms ({{ environment }})';

CREATE SCHEMA IF NOT EXISTS {{ conformed_schema }}
COMMENT = 'Conformed layer: business-ready fact tables and aggregates ({{ environment }})';

CREATE SCHEMA IF NOT EXISTS {{ governance_schema }}
COMMENT = 'Masking policies and data governance objects ({{ environment }})';

CREATE SCHEMA IF NOT EXISTS METADATA
COMMENT = 'Metadata and change tracking objects (shared across environments)';
