/* ============================================================
   FILE    : 08_seed_data.sql
   PURPOSE : Load CSV data into Bronze staging tables using a
             single shared Named Stage with Directory Table
             Stream + Tasks for automated incremental ingestion
   NOTES   :
       - Single named stage (BRONZE.DATA_STAGE) with path-based
         subdirectories for each entity
       - Directory Table enabled for automatic file detection
       - Stream on the stage detects new files in all subdirs
       - Tasks fire only when new files land (per-table routing)
       - COPY INTO is idempotent (skips already-loaded files)
       - Works with internal stages without S3/GCS/Azure events
   ============================================================ */


-- ----------------------------------------------------------
-- Create a shared file format for CSV ingestion
-- ----------------------------------------------------------
CREATE OR REPLACE FILE FORMAT BRONZE.CSV_FORMAT
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;


/* ============================================================
   SINGLE SHARED NAMED STAGE (with Directory Table enabled)

   All CSV files are organized by subdirectory path:
     @BRONZE.DATA_STAGE/customer/    → T_Customer files
     @BRONZE.DATA_STAGE/account/     → T_Account files
     @BRONZE.DATA_STAGE/transaction/ → T_Transaction files
   ============================================================ */

CREATE OR REPLACE STAGE BRONZE.DATA_STAGE
    FILE_FORMAT = BRONZE.CSV_FORMAT
    DIRECTORY = (ENABLE = TRUE) -- noqa: PRS
    COMMENT = 'Shared named stage for all Bronze CSV ingestion';


/* ============================================================
   DIRECTORY TABLE STREAM
   Detects new files landing in any subdirectory of the stage.
   ============================================================ */

CREATE OR REPLACE STREAM BRONZE.STREAM_DATA_FILES
    ON STAGE BRONZE.DATA_STAGE;


/* ============================================================
   TASKS – Incremental Load (fires only when new files exist)
   Schedule: every 5 minutes; only runs if stream has data.
   Each task loads from its subdirectory path within the
   single shared named stage.
   ============================================================ */

-- ----------------------------------------------------------
-- Task: Load T_Customer
-- Loads CSV files from @BRONZE.DATA_STAGE/customer/
-- ----------------------------------------------------------
CREATE OR REPLACE TASK BRONZE.TASK_LOAD_CUSTOMER
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest customer CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Customer
    (Customer_ID, First_Name, Last_Name, Email_Address, Phone_Number,
     City, State_Province, Country, Created_Timestamp)
FROM @BRONZE.DATA_STAGE/customer/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');


-- ----------------------------------------------------------
-- Task: Load T_Account
-- Loads CSV files from @BRONZE.DATA_STAGE/account/
-- ----------------------------------------------------------
CREATE OR REPLACE TASK BRONZE.TASK_LOAD_ACCOUNT
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest account CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Account
    (Account_ID, Customer_ID, Account_Type, Status, Currency_Code,
     Open_Date, Created_Timestamp)
FROM @BRONZE.DATA_STAGE/account/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');


-- ----------------------------------------------------------
-- Task: Load T_Transaction
-- Loads CSV files from @BRONZE.DATA_STAGE/transaction/
-- ----------------------------------------------------------
CREATE OR REPLACE TASK BRONZE.TASK_LOAD_TRANSACTION
    WAREHOUSE = 'COMPUTE_WH'
    SCHEDULE = 'USING CRON */5 * * * * America/Toronto'
    COMMENT = 'Auto-ingest transaction CSVs from named stage'
    WHEN SYSTEM$STREAM_HAS_DATA('BRONZE.STREAM_DATA_FILES')
AS
COPY INTO BRONZE.T_Transaction
    (Transaction_ID, Account_ID, Transaction_Date, Transaction_Type,
     Amount, Description)
FROM @BRONZE.DATA_STAGE/transaction/
FILE_FORMAT = (FORMAT_NAME = 'BRONZE.CSV_FORMAT');


/* ============================================================
   ENABLE TASKS
   Tasks are created in SUSPENDED state by default.
   ============================================================ */

ALTER TASK BRONZE.TASK_LOAD_CUSTOMER RESUME;
ALTER TASK BRONZE.TASK_LOAD_ACCOUNT RESUME;
ALTER TASK BRONZE.TASK_LOAD_TRANSACTION RESUME;


/* ==========================================================
   USAGE INSTRUCTIONS
   ==========================================================

   1. INITIAL / HISTORICAL LOAD:
      ----------------------------------------------------------
      -- PUT files to the named stage (organized by subdirectory):
      PUT file:///path/to/sample_data_file/T_Customer_history.csv @BRONZE.DATA_STAGE/customer/;
      PUT file:///path/to/sample_data_file/T_Customer_incremental.csv @BRONZE.DATA_STAGE/customer/;
      PUT file:///path/to/sample_data_file/T_Account_history.csv @BRONZE.DATA_STAGE/account/;
      PUT file:///path/to/sample_data_file/T_Account_incremental.csv @BRONZE.DATA_STAGE/account/;
      PUT file:///path/to/sample_data_file/T_Transaction_history.csv @BRONZE.DATA_STAGE/transaction/;
      PUT file:///path/to/sample_data_file/T_Transaction_incremental.csv @BRONZE.DATA_STAGE/transaction/;

      -- Refresh directory table so streams detect the files:
      ALTER STAGE BRONZE.DATA_STAGE REFRESH;

      -- Tasks will fire within 5 minutes automatically.
      -- Or execute manually for immediate load:
      EXECUTE TASK BRONZE.TASK_LOAD_CUSTOMER;
      EXECUTE TASK BRONZE.TASK_LOAD_ACCOUNT;
      EXECUTE TASK BRONZE.TASK_LOAD_TRANSACTION;

   2. ONGOING / INCREMENTAL LOADS:
      ----------------------------------------------------------
      -- Simply PUT new CSV files into the appropriate subdirectory:
      PUT file:///path/to/new_customers.csv @BRONZE.DATA_STAGE/customer/;
      PUT file:///path/to/new_accounts.csv @BRONZE.DATA_STAGE/account/;
      PUT file:///path/to/new_transactions.csv @BRONZE.DATA_STAGE/transaction/;

      -- Refresh directory table:
      ALTER STAGE BRONZE.DATA_STAGE REFRESH;

      -- The tasks auto-fire within 5 minutes (stream detects new files).
      -- No manual intervention needed after the stage refresh.

   3. LIST FILES IN STAGE:
      ----------------------------------------------------------
      -- View all files in the stage
      LIST @BRONZE.DATA_STAGE;

      -- View files in a specific subdirectory
      LIST @BRONZE.DATA_STAGE/customer/;
      LIST @BRONZE.DATA_STAGE/account/;
      LIST @BRONZE.DATA_STAGE/transaction/;

   4. MONITOR TASKS:
      ----------------------------------------------------------
      -- Check task status
      SHOW TASKS IN SCHEMA BRONZE;

      -- View task execution history
      SELECT *
      FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
          TASK_NAME => 'TASK_LOAD_CUSTOMER',
          SCHEDULED_TIME_RANGE_START => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
      ))
      ORDER BY SCHEDULED_TIME DESC;

   5. CHECK LOAD HISTORY:
      ----------------------------------------------------------
      SELECT *
      FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
          TABLE_NAME => 'BRONZE.T_CUSTOMER',
          START_TIME => DATEADD(HOUR, -24, CURRENT_TIMESTAMP())
      ));

   6. CLEAN UP LOADED FILES:
      ----------------------------------------------------------
      -- Remove files after successful load (optional)
      REMOVE @BRONZE.DATA_STAGE/customer/;
      REMOVE @BRONZE.DATA_STAGE/account/;
      REMOVE @BRONZE.DATA_STAGE/transaction/;

   7. SUSPEND TASKS (if needed):
      ----------------------------------------------------------
      ALTER TASK BRONZE.TASK_LOAD_CUSTOMER SUSPEND;
      ALTER TASK BRONZE.TASK_LOAD_ACCOUNT SUSPEND;
      ALTER TASK BRONZE.TASK_LOAD_TRANSACTION SUSPEND;

   ========================================================== */
