/* ============================================================
   Domain   : _platform
   Layer    : infrastructure
   Release  : 1
   Sequence : 101
   Purpose  : Create schemas for medallion architecture
   Author   : team-platform
   ============================================================ */

USE DATABASE {{ database }};

CREATE SCHEMA IF NOT EXISTS BRONZE COMMENT = 'Medallion Bronze layer: raw ingested staging data';
CREATE SCHEMA IF NOT EXISTS SILVER COMMENT = 'Medallion Silver layer: cleansed dimensions';
CREATE SCHEMA IF NOT EXISTS GOLD COMMENT = 'Medallion Gold layer: business-ready facts and aggregates';
CREATE SCHEMA IF NOT EXISTS GOVERNANCE COMMENT = 'Masking policies and data governance objects';
CREATE SCHEMA IF NOT EXISTS METADATA COMMENT = 'Schemachange tracking and operational metadata';
