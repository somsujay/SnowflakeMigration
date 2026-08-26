/* ============================================================
   schemachange Migration: V1.6.0__orchestration.sql
   PURPOSE : Master ETL orchestration procedure - Sujay Som
   ============================================================ */

USE DATABASE {{ database }};

CREATE OR REPLACE PROCEDURE {{ conformed_schema }}.Daily_ETL_Run()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    LET current_step STRING := '';

    current_step := 'Cleanse_Bronze_Data';
    CALL {{ governance_schema }}.Cleanse_Bronze_Data();

    current_step := 'Close_Current_DimCustomer_Record';
    CALL {{ clean_schema }}.Close_Current_DimCustomer_Record();

    current_step := 'Insert_New_DimCustomer_Record';
    CALL {{ clean_schema }}.Insert_New_DimCustomer_Record();

    current_step := 'Load_DimAccount_SCD1';
    CALL {{ clean_schema }}.Load_DimAccount_SCD1();

    current_step := 'Load_DimTransactionType';
    CALL {{ clean_schema }}.Load_DimTransactionType();

    current_step := 'Load_FactDailyTransaction';
    CALL {{ conformed_schema }}.Load_FactDailyTransaction(NULL);

    current_step := 'Load_FactDailyAgg';
    CALL {{ conformed_schema }}.Load_FactDailyAgg(NULL);

    current_step := 'Run_Data_Quality_Checks';
    CALL {{ governance_schema }}.Run_Data_Quality_Checks();

    RETURN 'Daily ETL completed successfully at ' || CURRENT_TIMESTAMP();
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Daily_ETL_Run at step [' || current_step || ']: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;
