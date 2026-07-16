/* ============================================================
   FILE    : 06_gold_procedures.sql
   PURPOSE : Gold layer procedures – fact table loading
   SCHEMA  : GOLD (reads from BRONZE + SILVER, writes to GOLD)
   PROCS   :
       1. Load_FactDailyTransaction  (transaction-level detail)
       2. Load_FactDailyAgg          (pre-aggregated rollups)
   ============================================================ */


-- ----------------------------------------------------------
-- Load_FactDailyTransaction
-- Loads one day of transaction-level detail into the fact
-- table by joining staging transactions to staging accounts
-- to resolve Customer_ID.
-- Parameter:
--   p_ReportDate DATE – The business date to load.
--   Pass NULL to load ALL unloaded dates (backfill mode).
-- Idempotency: caller must delete the date partition before
--   re-running to avoid duplicate rows.
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOLD.Load_FactDailyTransaction(p_ReportDate DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO GOLD.FactDailyTransaction
    (
        Date_Key,
        Customer_ID,
        Account_ID,
        Transaction_ID,
        Transaction_Type,
        Amount
    )
    SELECT
        t.Transaction_Date::DATE    AS Date_Key,
        a.Customer_ID,
        t.Account_ID,
        t.Transaction_ID,
        t.Transaction_Type,
        t.Amount
    FROM       BRONZE.T_Transaction  t
    JOIN       BRONZE.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
      AND  t.Transaction_Date::DATE NOT IN (SELECT DISTINCT Date_Key FROM GOLD.FactDailyTransaction);

    RETURN 'Load_FactDailyTransaction completed for ' || COALESCE(TO_VARCHAR(:p_ReportDate), 'ALL dates');
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_FactDailyTransaction: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


-- ----------------------------------------------------------
-- Load_FactDailyAgg
-- Populates GOLD.FactDailyAgg with four pre-aggregated
-- rollups for the given report date.
-- Parameter:
--   p_ReportDate DATE – The business date to aggregate.
--   Pass NULL to load ALL dates (backfill mode).
-- Idempotency: truncates target for NULL, deletes date for
--   specific date before re-inserting.
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOLD.Load_FactDailyAgg(p_ReportDate DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Clear existing data for idempotency
    IF (:p_ReportDate IS NULL) THEN
        TRUNCATE TABLE GOLD.FactDailyAgg;
    ELSE
        DELETE FROM GOLD.FactDailyAgg WHERE Date_Key = :p_ReportDate;
    END IF;

    /* --------------------------------------------------
       Rollup 1 of 4: Daily summary by Customer
       Grain: Date + Customer (Account and Type = NULL)
       -------------------------------------------------- */
    INSERT INTO GOLD.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       BRONZE.T_Transaction  t
    JOIN       BRONZE.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 2;


    /* --------------------------------------------------
       Rollup 2 of 4: Daily summary by Account
       Grain: Date + Account (Customer and Type = NULL)
       -------------------------------------------------- */
    INSERT INTO GOLD.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   BRONZE.T_Transaction  t
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 3;


    /* --------------------------------------------------
       Rollup 3 of 4: Daily summary by Customer + Transaction Type
       Grain: Date + Customer + Type (Account = NULL)
       -------------------------------------------------- */
    INSERT INTO GOLD.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       BRONZE.T_Transaction  t
    JOIN       BRONZE.T_Account      a
           ON t.Account_ID = a.Account_ID
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 2, 4;


    /* --------------------------------------------------
       Rollup 4 of 4: Daily summary by Account + Transaction Type
       Grain: Date + Account + Type (Customer = NULL)
       -------------------------------------------------- */
    INSERT INTO GOLD.FactDailyAgg
    SELECT
        t.Transaction_Date::DATE AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   BRONZE.T_Transaction  t
    WHERE  (:p_ReportDate IS NULL OR t.Transaction_Date::DATE = :p_ReportDate)
    GROUP BY 1, 3, 4;

    RETURN 'Load_FactDailyAgg completed for ' || COALESCE(TO_VARCHAR(:p_ReportDate), 'ALL dates');
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_FactDailyAgg: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;
