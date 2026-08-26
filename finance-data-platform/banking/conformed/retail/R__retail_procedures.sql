/* ============================================================
   schemachange Repeatable: R__gold_procedures.sql
   PURPOSE : Gold layer procedures - fact table loading
   Re-runs automatically when this file changes. Sujay Som Again
   ============================================================ */

USE DATABASE {{ database }};

CREATE OR REPLACE PROCEDURE {{ conformed_schema }}.Load_FactDailyTransaction(p_ReportDate DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO {{ conformed_schema }}.FactDailyTransaction
    (
        Date_Key, Customer_ID, Account_ID, Transaction_ID, Transaction_Type, Amount
    )
    SELECT
        t.Transaction_Date::DATE    AS Date_Key,
        a.Customer_ID,
        t.Account_ID,
        t.Transaction_ID,
        t.Transaction_Type,
        t.Amount
    FROM       {{ raw_schema }}.T_Transaction  t
    JOIN       {{ raw_schema }}.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
      AND  t.Transaction_Date::DATE NOT IN (SELECT DISTINCT Date_Key FROM {{ conformed_schema }}.FactDailyTransaction);

    RETURN 'Load_FactDailyTransaction completed for ' || COALESCE(TO_VARCHAR(:p_ReportDate), 'ALL dates');
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_FactDailyTransaction: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;

CREATE OR REPLACE PROCEDURE {{ conformed_schema }}.Load_FactDailyAgg(p_ReportDate DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    IF (:p_ReportDate IS NULL) THEN
        TRUNCATE TABLE {{ conformed_schema }}.FactDailyAgg;
    ELSE
        DELETE FROM {{ conformed_schema }}.FactDailyAgg WHERE Date_Key = :p_ReportDate;
    END IF;

    INSERT INTO {{ conformed_schema }}.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       {{ raw_schema }}.T_Transaction  t
    JOIN       {{ raw_schema }}.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 2;

    INSERT INTO {{ conformed_schema }}.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   {{ raw_schema }}.T_Transaction  t
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 3;

    INSERT INTO {{ conformed_schema }}.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       {{ raw_schema }}.T_Transaction  t
    JOIN       {{ raw_schema }}.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 2, 4;

    INSERT INTO {{ conformed_schema }}.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   {{ raw_schema }}.T_Transaction  t
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 3, 4;

    RETURN 'Load_FactDailyAgg completed for ' || COALESCE(TO_VARCHAR(:p_ReportDate), 'ALL dates');
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_FactDailyAgg: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;

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

CREATE OR REPLACE PROCEDURE {{ conformed_schema }}.Daily_ETL_Run_2()
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
