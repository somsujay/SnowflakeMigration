/* ============================================================
   schemachange Migration: V1.6.0__orchestration.sql
   PURPOSE : Master ETL orchestration procedure
   ============================================================ */

USE DATABASE {{ database }};

CREATE OR REPLACE PROCEDURE GOLD.Daily_ETL_Run()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    LET current_step STRING := '';

    current_step := 'Cleanse_Bronze_Data';
    CALL GOVERNANCE.Cleanse_Bronze_Data();

    current_step := 'Close_Current_DimCustomer_Record';
    CALL SILVER.Close_Current_DimCustomer_Record();

    current_step := 'Insert_New_DimCustomer_Record';
    CALL SILVER.Insert_New_DimCustomer_Record();

    current_step := 'Load_DimAccount_SCD1';
    CALL SILVER.Load_DimAccount_SCD1();

    current_step := 'Load_DimTransactionType';
    CALL SILVER.Load_DimTransactionType();

    current_step := 'Load_FactDailyTransaction';
    CALL GOLD.Load_FactDailyTransaction(NULL);

    current_step := 'Load_FactDailyAgg';
    CALL GOLD.Load_FactDailyAgg(NULL);

    current_step := 'Run_Data_Quality_Checks';
    CALL GOVERNANCE.Run_Data_Quality_Checks();

    RETURN 'Daily ETL completed successfully at ' || CURRENT_TIMESTAMP();
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Daily_ETL_Run at step [' || current_step || ']: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;
