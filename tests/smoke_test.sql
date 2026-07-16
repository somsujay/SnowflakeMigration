/* ============================================================
   FILE    : smoke_test.sql
   PURPOSE : Post-deployment validation for ECOMM Bookings pipeline
   USAGE   : Executed by scripts/run_smoke_tests.sh after deploy
   NOTE    : {{DATABASE_NAME}} is substituted at runtime by the test runner
   ============================================================ */

USE DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 1: Verify schemas exist
-- ----------------------------------------------------------
SHOW SCHEMAS LIKE 'RAW' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE 'CLEAN' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE 'CONFORMED' IN DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 2: Verify tables exist
-- ----------------------------------------------------------
SELECT 'RAW.STG_ECOMM_BOOKINGS' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME = 'STG_ECOMM_BOOKINGS';

SELECT 'CLEAN.ECOMM_BOOKINGS_TRANSFORMED' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CLEAN'
  AND TABLE_NAME = 'ECOMM_BOOKINGS_TRANSFORMED';

SELECT 'CONFORMED.ECOMM_BOOKINGS_TBL' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CONFORMED'
  AND TABLE_NAME = 'ECOMM_BOOKINGS_TBL';

-- ----------------------------------------------------------
-- TEST 3: Verify procedures exist
-- ----------------------------------------------------------
SELECT 'RAW.USP_LOAD_STG_ECOMM_BOOKINGS' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'RAW'
  AND PROCEDURE_NAME = 'USP_LOAD_STG_ECOMM_BOOKINGS';

SELECT 'CLEAN.USP_TRANSFORM_ECOMM_BOOKINGS' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'CLEAN'
  AND PROCEDURE_NAME = 'USP_TRANSFORM_ECOMM_BOOKINGS';

SELECT 'CONFORMED.USP_ORCHESTRATE_ECOMM_BOOKINGS' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'CONFORMED'
  AND PROCEDURE_NAME = 'USP_ORCHESTRATE_ECOMM_BOOKINGS';

-- ----------------------------------------------------------
-- TEST 4: Verify event table exists
-- ----------------------------------------------------------
SELECT 'RAW.ETL_EVENTS' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME = 'ETL_EVENTS'
  AND TABLE_TYPE = 'EVENT TABLE';

-- ----------------------------------------------------------
-- TEST 5: Verify views exist (sample check)
-- ----------------------------------------------------------
SELECT 'CLEAN.GDS_RCPT_ITEM' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'CLEAN'
  AND TABLE_NAME = 'GDS_RCPT_ITEM';

SELECT 'CLEAN.GDS_RCPTHDR' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'CLEAN'
  AND TABLE_NAME = 'GDS_RCPTHDR';

-- ----------------------------------------------------------
-- TEST 6: Verify scheduled task exists (if deployed)
-- ----------------------------------------------------------
SHOW TASKS LIKE 'TASK_ECOMM_BOOKINGS_DAILY' IN SCHEMA CONFORMED;
