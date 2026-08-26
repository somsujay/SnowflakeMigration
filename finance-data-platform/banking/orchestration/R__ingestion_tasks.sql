/* ============================================================
   schemachange Migration: V1.7.1__ingestion_tasks.sql
   PURPOSE : Scheduled tasks for auto-ingesting CSVs from stage
   DEPENDS : V1.7.0 (stage, stream, file format must exist) -- Sujay Som
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA {{ raw_schema }};

CREATE OR REPLACE TASK {{ raw_schema }}.TASK_LOAD_CUSTOMER
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest customer CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('{{ raw_schema }}.STREAM_DATA_FILES')
AS
COPY INTO {{ raw_schema }}.T_CUSTOMER
    (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL_ADDRESS, PHONE_NUMBER,
     CITY, STATE_PROVINCE, COUNTRY, CREATED_TIMESTAMP)
FROM @{{ raw_schema }}.DATA_STAGE/customer/
FILE_FORMAT = (FORMAT_NAME = '{{ raw_schema }}.CSV_FORMAT');

CREATE OR REPLACE TASK {{ raw_schema }}.TASK_LOAD_ACCOUNT
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest account CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('{{ raw_schema }}.STREAM_DATA_FILES')
AS
COPY INTO {{ raw_schema }}.T_ACCOUNT
    (ACCOUNT_ID, CUSTOMER_ID, ACCOUNT_TYPE, STATUS, CURRENCY_CODE,
     OPEN_DATE, CREATED_TIMESTAMP)
FROM @{{ raw_schema }}.DATA_STAGE/account/
FILE_FORMAT = (FORMAT_NAME = '{{ raw_schema }}.CSV_FORMAT');

CREATE OR REPLACE TASK {{ raw_schema }}.TASK_LOAD_TRANSACTION
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest transaction CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('{{ raw_schema }}.STREAM_DATA_FILES')
AS
COPY INTO {{ raw_schema }}.T_TRANSACTION
    (TRANSACTION_ID, ACCOUNT_ID, TRANSACTION_DATE, TRANSACTION_TYPE,
     AMOUNT, DESCRIPTION)
FROM @{{ raw_schema }}.DATA_STAGE/transaction/
FILE_FORMAT = (FORMAT_NAME = '{{ raw_schema }}.CSV_FORMAT');
ALTER TASK {{ raw_schema }}.TASK_LOAD_CUSTOMER RESUME;
ALTER TASK {{ raw_schema }}.TASK_LOAD_ACCOUNT RESUME;
ALTER TASK {{ raw_schema }}.TASK_LOAD_TRANSACTION RESUME;
