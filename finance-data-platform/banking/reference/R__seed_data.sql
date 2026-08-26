/* ============================================================
   schemachange Migration: V1.7.0__seed_data.sql
   PURPOSE : Stages, streams, and file formats for CSV ingestion
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA {{ raw_schema }};

CREATE OR REPLACE FILE FORMAT {{ raw_schema }}.CSV_FORMAT
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

CREATE OR REPLACE STAGE {{ raw_schema }}.DATA_STAGE
    FILE_FORMAT = {{ raw_schema }}.CSV_FORMAT
    DIRECTORY = (ENABLE = TRUE) -- noqa
    COMMENT = 'Shared named stage for all Bronze CSV ingestion';

CREATE OR REPLACE STREAM {{ raw_schema }}.STREAM_DATA_FILES
    ON STAGE {{ raw_schema }}.DATA_STAGE;
