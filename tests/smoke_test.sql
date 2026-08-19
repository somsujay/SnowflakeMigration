/* ============================================================
   FILE    : smoke_test.sql
   PURPOSE : Post-deployment validation for Teradata Migration pipeline
   USAGE   : Executed by scripts/run_smoke_tests.sh after deploy
   NOTE    : {{DATABASE_NAME}}, {{RAW_SCHEMA}}, {{CLEAN_SCHEMA}},
             {{CONFORMED_SCHEMA}}, {{GOVERNANCE_SCHEMA}} are substituted
             at runtime by the test runner
   ============================================================ */

USE DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 1: Verify schemas exist
-- ----------------------------------------------------------
SHOW SCHEMAS LIKE '{{RAW_SCHEMA}}' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE '{{CLEAN_SCHEMA}}' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE '{{CONFORMED_SCHEMA}}' IN DATABASE {{DATABASE_NAME}};
SHOW SCHEMAS LIKE '{{GOVERNANCE_SCHEMA}}' IN DATABASE {{DATABASE_NAME}};

-- ----------------------------------------------------------
-- TEST 2: Verify Raw tables exist
-- ----------------------------------------------------------
SELECT '{{RAW_SCHEMA}}.T_CUSTOMER' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{RAW_SCHEMA}}'
  AND TABLE_NAME = 'T_CUSTOMER';

SELECT '{{RAW_SCHEMA}}.T_ACCOUNT' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{RAW_SCHEMA}}'
  AND TABLE_NAME = 'T_ACCOUNT';

SELECT '{{RAW_SCHEMA}}.T_TRANSACTION' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{RAW_SCHEMA}}'
  AND TABLE_NAME = 'T_TRANSACTION';

-- ----------------------------------------------------------
-- TEST 3: Verify Clean tables exist
-- ----------------------------------------------------------
SELECT '{{CLEAN_SCHEMA}}.DIMCUSTOMER' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CLEAN_SCHEMA}}'
  AND TABLE_NAME = 'DIMCUSTOMER';

SELECT '{{CLEAN_SCHEMA}}.DIMACCOUNT' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CLEAN_SCHEMA}}'
  AND TABLE_NAME = 'DIMACCOUNT';

SELECT '{{CLEAN_SCHEMA}}.DIMTRANSACTIONTYPE' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CLEAN_SCHEMA}}'
  AND TABLE_NAME = 'DIMTRANSACTIONTYPE';

SELECT '{{CLEAN_SCHEMA}}.DIMDATE' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CLEAN_SCHEMA}}'
  AND TABLE_NAME = 'DIMDATE';

-- ----------------------------------------------------------
-- TEST 4: Verify Conformed tables exist
-- ----------------------------------------------------------
SELECT '{{CONFORMED_SCHEMA}}.FACTDAILYTRANSACTION' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CONFORMED_SCHEMA}}'
  AND TABLE_NAME = 'FACTDAILYTRANSACTION';

SELECT '{{CONFORMED_SCHEMA}}.FACTDAILYAGG' AS object_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = '{{CONFORMED_SCHEMA}}'
  AND TABLE_NAME = 'FACTDAILYAGG';

-- ----------------------------------------------------------
-- TEST 5: Verify Conformed views exist
-- ----------------------------------------------------------
SELECT '{{CONFORMED_SCHEMA}}.MONTHLYSPENDPROFILE' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = '{{CONFORMED_SCHEMA}}'
  AND TABLE_NAME = 'MONTHLYSPENDPROFILE';

SELECT '{{CONFORMED_SCHEMA}}.TXNTYPETREND' AS view_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = '{{CONFORMED_SCHEMA}}'
  AND TABLE_NAME = 'TXNTYPETREND';

-- ----------------------------------------------------------
-- TEST 6: Verify procedures exist
-- ----------------------------------------------------------
SELECT '{{CLEAN_SCHEMA}}.LOAD_DIMACCOUNT_SCD1' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = '{{CLEAN_SCHEMA}}'
  AND PROCEDURE_NAME = 'LOAD_DIMACCOUNT_SCD1';

SELECT '{{CONFORMED_SCHEMA}}.LOAD_FACTDAILYTRANSACTION' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = '{{CONFORMED_SCHEMA}}'
  AND PROCEDURE_NAME = 'LOAD_FACTDAILYTRANSACTION';

SELECT 'PUBLIC.DAILY_ETL_RUN' AS proc_name,
       COUNT(*) AS exists_flag
FROM INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_SCHEMA = 'PUBLIC'
  AND PROCEDURE_NAME = 'DAILY_ETL_RUN';

-- ----------------------------------------------------------
-- TEST 7: Verify stages exist
-- ----------------------------------------------------------
SHOW STAGES LIKE 'DATA_STAGE' IN SCHEMA {{RAW_SCHEMA}};
SHOW STAGES LIKE 'ICEBERG_STAGE' IN SCHEMA {{RAW_SCHEMA}};

-- ----------------------------------------------------------
-- TEST 8: Verify tasks exist
-- ----------------------------------------------------------
SHOW TASKS LIKE 'TASK_LOAD_CUSTOMER' IN SCHEMA {{RAW_SCHEMA}};
SHOW TASKS LIKE 'TASK_LOAD_ACCOUNT' IN SCHEMA {{RAW_SCHEMA}};
SHOW TASKS LIKE 'TASK_LOAD_TRANSACTION' IN SCHEMA {{RAW_SCHEMA}};
