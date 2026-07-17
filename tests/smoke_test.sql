/* ============================================================
   FILE    : smoke_test.sql
   PURPOSE : Post-deployment validation for Teradata Migration pipeline
   USAGE   : Executed by scripts/run_smoke_tests.sh after deploy
   NOTE    : {{DATABASE_NAME}} is substituted at runtime by the test runner
   ============================================================ */

USE DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 1: Verify schemas exist
-- ----------------------------------------------------------
SHOW SCHEMAS LIKE 'BRONZE' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE 'SILVER' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE 'GOLD' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE 'GOVERNANCE' IN DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 2: Verify Bronze tables exist
-- ----------------------------------------------------------
SELECT 'BRONZE.T_CUSTOMER' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'BRONZE'
  AND TABLE_NAME = 'T_CUSTOMER';

SELECT 'BRONZE.T_ACCOUNT' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'BRONZE'
  AND TABLE_NAME = 'T_ACCOUNT';

SELECT 'BRONZE.T_TRANSACTION' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'BRONZE'
  AND TABLE_NAME = 'T_TRANSACTION';

-- ----------------------------------------------------------
-- TEST 3: Verify Silver tables exist
-- ----------------------------------------------------------
SELECT 'SILVER.DIMCUSTOMER' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SILVER'
  AND TABLE_NAME = 'DIMCUSTOMER';

SELECT 'SILVER.DIMACCOUNT' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SILVER'
  AND TABLE_NAME = 'DIMACCOUNT';

SELECT 'SILVER.DIMTRANSACTIONTYPE' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SILVER'
  AND TABLE_NAME = 'DIMTRANSACTIONTYPE';

SELECT 'SILVER.DIMDATE' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'SILVER'
  AND TABLE_NAME = 'DIMDATE';

-- ----------------------------------------------------------
-- TEST 4: Verify Gold tables exist
-- ----------------------------------------------------------
SELECT 'GOLD.FACTDAILYTRANSACTION' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'GOLD'
  AND TABLE_NAME = 'FACTDAILYTRANSACTION';

SELECT 'GOLD.FACTDAILYAGG' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'GOLD'
  AND TABLE_NAME = 'FACTDAILYAGG';

-- ----------------------------------------------------------
-- TEST 5: Verify Gold views exist
-- ----------------------------------------------------------
SELECT 'GOLD.MONTHLYSPENDPROFILE' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'GOLD'
  AND TABLE_NAME = 'MONTHLYSPENDPROFILE';

SELECT 'GOLD.TXNTYPETREND' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'GOLD'
  AND TABLE_NAME = 'TXNTYPETREND';

-- ----------------------------------------------------------
-- TEST 6: Verify procedures exist
-- ----------------------------------------------------------
SELECT 'SILVER.LOAD_DIMACCOUNT_SCD1' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'SILVER'
  AND PROCEDURE_NAME = 'LOAD_DIMACCOUNT_SCD1';

SELECT 'GOLD.LOAD_FACTDAILYTRANSACTION' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'GOLD'
  AND PROCEDURE_NAME = 'LOAD_FACTDAILYTRANSACTION';

SELECT 'PUBLIC.DAILY_ETL_RUN' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'PUBLIC'
  AND PROCEDURE_NAME = 'DAILY_ETL_RUN';

-- ----------------------------------------------------------
-- TEST 7: Verify stages exist
-- ----------------------------------------------------------
SHOW STAGES LIKE 'DATA_STAGE' IN SCHEMA BRONZE;
SHOW STAGES LIKE 'ICEBERG_STAGE' IN SCHEMA BRONZE;

-- ----------------------------------------------------------
-- TEST 8: Verify tasks exist
-- ----------------------------------------------------------
SHOW TASKS LIKE 'TASK_LOAD_CUSTOMER' IN SCHEMA BRONZE;
SHOW TASKS LIKE 'TASK_LOAD_ACCOUNT' IN SCHEMA BRONZE;
SHOW TASKS LIKE 'TASK_LOAD_TRANSACTION' IN SCHEMA BRONZE;
