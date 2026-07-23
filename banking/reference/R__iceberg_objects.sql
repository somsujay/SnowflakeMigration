/* ============================================================
   schemachange Migration: V1.10.0__iceberg_objects.sql
   PURPOSE : Parquet file format and stage for Iceberg ingestion
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE OR REPLACE FILE FORMAT BRONZE.PARQUET_FORMAT
TYPE = PARQUET;

CREATE OR REPLACE STAGE BRONZE.ICEBERG_STAGE
    FILE_FORMAT = BRONZE.PARQUET_FORMAT
    COMMENT = 'Named stage for Parquet/Iceberg data ingestion';
