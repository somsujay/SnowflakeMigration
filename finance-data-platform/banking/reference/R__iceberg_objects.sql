/* ============================================================
   schemachange Migration: V1.10.0__iceberg_objects.sql
   PURPOSE : Parquet file format and stage for Iceberg ingestion
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA {{ raw_schema }};

CREATE OR REPLACE FILE FORMAT {{ raw_schema }}.PARQUET_FORMAT
TYPE = PARQUET;

CREATE OR REPLACE STAGE {{ raw_schema }}.ICEBERG_STAGE
    FILE_FORMAT = {{ raw_schema }}.PARQUET_FORMAT
    COMMENT = 'Named stage for Parquet/Iceberg data ingestion';
