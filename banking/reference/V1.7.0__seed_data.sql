/* ============================================================
   schemachange Migration: V1.7.0__seed_data.sql
   PURPOSE : Stages, streams, and file formats for CSV ingestion
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE OR REPLACE FILE FORMAT BRONZE.CSV_FORMAT
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE OR REPLACE STAGE BRONZE.DATA_STAGE
    FILE_FORMAT = BRONZE.CSV_FORMAT
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Shared named stage for all Bronze CSV ingestion';

CREATE OR REPLACE STREAM BRONZE.STREAM_DATA_FILES
    ON STAGE BRONZE.DATA_STAGE;
