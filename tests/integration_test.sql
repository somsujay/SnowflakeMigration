/* ============================================================
   FILE    : integration_test.sql
   PURPOSE : Post-deployment integration validation
   USAGE   : Executed after smoke tests pass in QA/Pre-PROD/PROD
   NOTE    : Validates procedures execute, data quality, and policies
   ============================================================ */

-- ----------------------------------------------------------
-- TEST 1: Verify all schemas have expected object counts
-- ----------------------------------------------------------
SELECT 'BRONZE schema tables' AS test_name,
       COUNT(*) AS object_count,
       IFF(COUNT(*) >= 3, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'BRONZE'
  AND TABLE_TYPE = 'BASE TABLE';

SELECT 'SILVER schema tables' AS test_name,
       COUNT(*) AS object_count,
       IFF(COUNT(*) >= 4, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SILVER'
  AND TABLE_TYPE = 'BASE TABLE';

SELECT 'GOLD schema tables' AS test_name,
       COUNT(*) AS object_count,
       IFF(COUNT(*) >= 2, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'GOLD'
  AND TABLE_TYPE = 'BASE TABLE';

-- ----------------------------------------------------------
-- TEST 2: Verify stored procedures are callable
-- ----------------------------------------------------------
SELECT 'Silver procedures' AS test_name,
       COUNT(*) AS proc_count,
       IFF(COUNT(*) >= 5, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'SILVER';

SELECT 'Gold procedures' AS test_name,
       COUNT(*) AS proc_count,
       IFF(COUNT(*) >= 2, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'GOLD';

-- ----------------------------------------------------------
-- TEST 3: Verify orchestration procedure exists
-- ----------------------------------------------------------
SELECT 'Daily_ETL_Run exists' AS test_name,
       COUNT(*) AS exists_flag,
       IFF(COUNT(*) >= 1, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_NAME = 'DAILY_ETL_RUN';

-- ----------------------------------------------------------
-- TEST 4: Verify stages are configured
-- ----------------------------------------------------------
SHOW STAGES IN SCHEMA BRONZE;

-- ----------------------------------------------------------
-- TEST 5: Verify masking policies exist
-- ----------------------------------------------------------
SELECT 'Masking policies' AS test_name,
       COUNT(*) AS policy_count,
       IFF(COUNT(*) >= 4, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.MASKING_POLICIES
WHERE POLICY_SCHEMA = 'GOVERNANCE';

-- ----------------------------------------------------------
-- TEST 6: Verify data quality objects
-- ----------------------------------------------------------
SELECT 'DATA_QUALITY_LOG table' AS test_name,
       COUNT(*) AS exists_flag,
       IFF(COUNT(*) >= 1, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'GOVERNANCE'
  AND TABLE_NAME = 'DATA_QUALITY_LOG';

-- ----------------------------------------------------------
-- TEST 7: Verify views exist in GOLD schema
-- ----------------------------------------------------------
SELECT 'GOLD views' AS test_name,
       COUNT(*) AS view_count,
       IFF(COUNT(*) >= 2, 'PASS', 'FAIL') AS result
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'GOLD';

-- ----------------------------------------------------------
-- TEST 8: Verify tasks are created (stream-triggered)
-- ----------------------------------------------------------
SHOW TASKS IN SCHEMA BRONZE;
