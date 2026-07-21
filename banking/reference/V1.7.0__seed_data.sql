/* ============================================================
   schemachange Migration: V1.7.0__seed_data.sql
   PURPOSE : Stages, streams, and tasks for CSV/Parquet ingestion
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

CREATE OR REPLACE TASK BRONZE.TASK_LOAD_CUSTOMER
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest customer CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Customer
    (Customer_ID, First_Name, Last_Name, Email_Address, Phone_Number,
     City, State_Province, Country, Created_Timestamp)
FROM @BRONZE.DATA_STAGE/customer/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');

CREATE OR REPLACE TASK BRONZE.TASK_LOAD_ACCOUNT
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest account CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Account
    (Account_ID, Customer_ID, Account_Type, Status, Currency_Code,
     Open_Date, Created_Timestamp)
FROM @BRONZE.DATA_STAGE/account/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');

CREATE OR REPLACE TASK BRONZE.TASK_LOAD_TRANSACTION
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest transaction CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Transaction
    (Transaction_ID, Account_ID, Transaction_Date, Transaction_Type,
     Amount, Description)
FROM @BRONZE.DATA_STAGE/transaction/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');

ALTER TASK BRONZE.TASK_LOAD_CUSTOMER RESUME;
ALTER TASK BRONZE.TASK_LOAD_ACCOUNT RESUME;
ALTER TASK BRONZE.TASK_LOAD_TRANSACTION RESUME;
