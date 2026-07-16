/* ============================================================
   FILE    : 07_orchestration.sql
   PURPOSE : Master ETL orchestration procedure + optional Task
   NOTES   :
       Executes all ETL steps in the correct dependency order
       for a standard daily load across the Medallion layers:
         Bronze (cleansing) -> Silver (dimensions) -> Gold (facts) -> Validation
   ============================================================ */


-- ----------------------------------------------------------
-- Daily_ETL_Run
-- Single entry-point that executes all ETL steps in the
-- correct dependency order for a standard daily load.
--
-- Execution order:
--   0. Cleanse Bronze data                   (Governance)
--   1. Close changed customer records        (Silver SCD-2 Step 1)
--   2. Insert new / updated customer rows    (Silver SCD-2 Step 2)
--   3. Upsert account records                (Silver SCD-1)
--   4. Insert new transaction type codes     (Silver lookup)
--   5. Load raw daily transactions           (Gold fact)
--   6. Load aggregated daily summaries       (Gold fact)
--   7. Run data quality checks               (Governance)
--
-- Schedule: run once per business day after Bronze staging
-- tables have been loaded from the source OLTP system.
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE PUBLIC.Daily_ETL_Run()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    LET current_step STRING := '';

    -- Pre-ETL: Cleanse Bronze data
    current_step := 'Cleanse_Bronze_Data';
    CALL GOVERNANCE.Cleanse_Bronze_Data();

    -- Silver layer: Dimension loads
    current_step := 'Close_Current_DimCustomer_Record';
    CALL SILVER.Close_Current_DimCustomer_Record();

    current_step := 'Insert_New_DimCustomer_Record';
    CALL SILVER.Insert_New_DimCustomer_Record();

    current_step := 'Load_DimAccount_SCD1';
    CALL SILVER.Load_DimAccount_SCD1();

    current_step := 'Load_DimTransactionType';
    CALL SILVER.Load_DimTransactionType();

    -- Gold layer: Fact loads (NULL = load all unloaded dates)
    current_step := 'Load_FactDailyTransaction';
    CALL GOLD.Load_FactDailyTransaction(NULL);

    current_step := 'Load_FactDailyAgg';
    CALL GOLD.Load_FactDailyAgg(NULL);

    -- Post-ETL: Run data quality checks
    current_step := 'Run_Data_Quality_Checks';
    CALL GOVERNANCE.Run_Data_Quality_Checks();

    RETURN 'Daily ETL completed successfully at ' || CURRENT_TIMESTAMP();
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Daily_ETL_Run at step [' || current_step || ']: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


/* ============================================================
   OPTIONAL: Snowflake Task for automated scheduling
   Uncomment and customize warehouse/schedule as needed.
   ============================================================ */

-- CREATE OR REPLACE TASK daily_etl_task
--   WAREHOUSE = 'ETL_WH'
--   SCHEDULE  = 'USING CRON 0 6 * * * America/Toronto'
--   COMMENT   = 'Daily Medallion ETL: Bronze -> Silver -> Gold'
-- AS
--   CALL Daily_ETL_Run();

-- To enable the task after creation:
-- ALTER TASK daily_etl_task RESUME;
