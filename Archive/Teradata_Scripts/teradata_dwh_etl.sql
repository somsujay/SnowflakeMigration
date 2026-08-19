/* ============================================================
   FILE    : teradata_dwh_etl.sql
   PURPOSE : Data Warehouse DDL and ETL Stored Procedures
   DIALECT : Teradata SQL
   SECTIONS:
       1  – Drop Existing Tables
       2  – Source (OLTP) Table DDL
       3  – Dimension Table DDL
       4  – Fact Table DDL
       5  – Customer SCD-2 Procedures
       6  – Account SCD-1 Procedure
       7  – Transaction Type Dimension Load
       8  – Date Dimension Population
       9  – Raw Fact Load
       10 – Aggregated Fact Load
       11 – Master Daily ETL Orchestration
   ============================================================ */


/* ============================================================
   SECTION 1 – DROP EXISTING TABLES
   Drop order respects dependencies: Facts → Dimensions → Source
   ============================================================ */

-- Fact tables
DROP TABLE FactDailyAgg;
DROP TABLE FactDailyTransaction;

-- Dimension tables
DROP TABLE DimTransactionType;
DROP TABLE DimDate;
DROP TABLE DimAccount;
DROP TABLE DimCustomer;

-- Source (OLTP) staging tables
DROP TABLE T_Transaction;
DROP TABLE T_Account;
DROP TABLE T_Customer;


/* ============================================================
   SECTION 2 – SOURCE (OLTP) TABLE DDL
   These staging tables receive raw OLTP data before ETL
   processing transforms and loads them into the warehouse.
   ============================================================ */

-- ----------------------------------------------------------
-- T_Customer
-- Raw customer master data sourced from the OLTP system.
-- Staged here prior to SCD-2 processing into DimCustomer.
-- Phone_Number and Created_Timestamp are source-only fields
-- not propagated to the dimension.
-- ----------------------------------------------------------
CREATE TABLE T_Customer
(
    Customer_ID         VARCHAR(50)   NOT NULL,
    First_Name          VARCHAR(50),
    Last_Name           VARCHAR(50),
    Email_Address       VARCHAR(100),
    Phone_Number        VARCHAR(20),
    City                VARCHAR(50),
    State_Province      VARCHAR(50),
    Country             VARCHAR(50),
    Created_Timestamp   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
)
PRIMARY INDEX (Customer_ID);


-- ----------------------------------------------------------
-- T_Account
-- Raw account data sourced from the OLTP system.
-- Staged here prior to SCD-1 upsert into DimAccount.
-- Open_Date and Created_Timestamp are source-only fields
-- not propagated to the dimension.
-- ----------------------------------------------------------
CREATE TABLE T_Account
(
    Account_ID          VARCHAR(50)   NOT NULL,
    Customer_ID         VARCHAR(50)   NOT NULL,
    Account_Type        VARCHAR(30),
    Status              VARCHAR(20),
    Currency_Code       VARCHAR(10),
    Open_Date           DATE,
    Created_Timestamp   TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
)
PRIMARY INDEX (Account_ID);


-- ----------------------------------------------------------
-- T_Transaction
-- Raw transaction records sourced from the OLTP system.
-- Staged here prior to loading into FactDailyTransaction
-- and FactDailyAgg. Description is a source-only field
-- not propagated to the fact tables.
-- ----------------------------------------------------------
CREATE TABLE T_Transaction
(
    Transaction_ID      VARCHAR(50)   NOT NULL,
    Account_ID          VARCHAR(50)   NOT NULL,
    Transaction_Date    TIMESTAMP     NOT NULL,
    Transaction_Type    VARCHAR(30),
    Amount              DECIMAL(18,2),
    Description         VARCHAR(255)
)
PRIMARY INDEX (Transaction_ID);


/* ============================================================
   SECTION 3 – DIMENSION TABLE DDL
   ============================================================ */

-- ----------------------------------------------------------
-- DimCustomer  (Slowly Changing Dimension – Type 2)
-- Tracks full history of customer attribute changes.
-- Current record identified by Current_Flag = 'Y'
-- ----------------------------------------------------------
CREATE TABLE DimCustomer
(
    Customer_ID     VARCHAR(50)  NOT NULL,
    First_Name      VARCHAR(50),
    Last_Name       VARCHAR(50),
    Email_Address   VARCHAR(100),
    City            VARCHAR(50),
    State_Province  VARCHAR(50),
    Country         VARCHAR(50),
    Start_Date      DATE,
    End_Date        DATE,           -- '9999-12-31' for active records
    Current_Flag    CHAR(1)         -- 'Y' = active, 'N' = historical
)
PRIMARY INDEX (Customer_ID);


-- ----------------------------------------------------------
-- DimAccount  (Slowly Changing Dimension – Type 1)
-- Overwrites on change; no history retained.
-- ----------------------------------------------------------
CREATE TABLE DimAccount
(
    Account_ID      VARCHAR(50)  NOT NULL,
    Customer_ID     VARCHAR(50)  NOT NULL,
    Account_Type    VARCHAR(30),
    Status          VARCHAR(20),
    Currency_Code   VARCHAR(10)
)
PRIMARY INDEX (Account_ID);


-- ----------------------------------------------------------
-- DimTransactionType
-- Lookup / reference dimension for transaction categories.
-- ----------------------------------------------------------
CREATE TABLE DimTransactionType
(
    Transaction_Type    VARCHAR(30)  NOT NULL,
    Description         VARCHAR(100)
)
PRIMARY INDEX (Transaction_Type);


-- ----------------------------------------------------------
-- DimDate
-- Calendar dimension; populated via Populate_DimDate().
-- ----------------------------------------------------------
CREATE TABLE DimDate
(
    Date_Key        DATE     NOT NULL,
    Year            INTEGER,
    Month           INTEGER,
    Day             INTEGER,
    Day_Of_Week     INTEGER          -- 1 = Sunday … 7 = Saturday (Teradata DOW)
)
PRIMARY INDEX (Date_Key);


/* ============================================================
   SECTION 4 – FACT TABLE DDL
   ============================================================ */

-- ----------------------------------------------------------
-- FactDailyTransaction
-- Grain: one row per individual transaction per day.
-- ----------------------------------------------------------
CREATE TABLE FactDailyTransaction
(
    Date_Key            DATE         NOT NULL,
    Customer_ID         VARCHAR(50)  NOT NULL,
    Account_ID          VARCHAR(50)  NOT NULL,
    Transaction_ID      VARCHAR(50)  NOT NULL,
    Transaction_Type    VARCHAR(30),
    Amount              DECIMAL(18,2)
)
PRIMARY INDEX (Date_Key, Transaction_ID);


-- ----------------------------------------------------------
-- FactDailyAgg
-- Grain: pre-aggregated daily summaries.
-- Supports multiple rollup levels:
--   • Customer only
--   • Account only
--   • Customer + Transaction Type
--   • Account   + Transaction Type
-- NULL in a grouping column indicates that dimension is
-- not part of the aggregation key for that row.
-- ----------------------------------------------------------
CREATE TABLE FactDailyAgg
(
    Date_Key            DATE          NOT NULL,
    Customer_ID         VARCHAR(50),       -- NULL when aggregating by Account
    Account_ID          VARCHAR(50),       -- NULL when aggregating by Customer
    Transaction_Type    VARCHAR(30),       -- NULL when not included in group
    Total_Amount        DECIMAL(18,2),
    Transaction_Count   INTEGER
)
PRIMARY INDEX (Date_Key);


/* ============================================================
   SECTION 5 – CUSTOMER SCD-2 PROCEDURES
   ============================================================ */

-- ----------------------------------------------------------
-- Close_Current_DimCustomer_Record
-- Step 1 of 2 for SCD-2 processing.
-- Expires the active DimCustomer record when any tracked
-- attribute has changed since the last load.
-- Sets End_Date = CURRENT_DATE - 1 and Current_Flag = 'N'.
-- Source staging table: T_Customer
-- ----------------------------------------------------------
REPLACE PROCEDURE Close_Current_DimCustomer_Record()
BEGIN
    UPDATE DimCustomer D
    FROM   T_Customer S
    WHERE  D.Customer_ID  = S.Customer_ID
      AND  D.Current_Flag = 'Y'
      AND
      (
          D.First_Name      <> S.First_Name
       OR D.Last_Name       <> S.Last_Name
       OR D.Email_Address   <> S.Email_Address
       OR D.City            <> S.City
       OR D.State_Province  <> S.State_Province
       OR D.Country         <> S.Country
      )
    SET
        D.End_Date      = CURRENT_DATE - 1,
        D.Current_Flag  = 'N';
END;
;


-- ----------------------------------------------------------
-- Insert_New_DimCustomer_Record
-- Step 2 of 2 for SCD-2 processing.
-- Inserts a new active row for:
--   a) Net-new customers (no existing DimCustomer record), or
--   b) Existing customers whose attributes have changed
--      (previous record was just closed by Step 1).
-- New records receive Start_Date = CURRENT_DATE,
-- End_Date = '9999-12-31', Current_Flag = 'Y'.
-- ----------------------------------------------------------
REPLACE PROCEDURE Insert_New_DimCustomer_Record()
BEGIN
    INSERT INTO DimCustomer
    (
        Customer_ID,
        First_Name,
        Last_Name,
        Email_Address,
        City,
        State_Province,
        Country,
        Start_Date,
        End_Date,
        Current_Flag
    )
    SELECT
        S.Customer_ID,
        S.First_Name,
        S.Last_Name,
        S.Email_Address,
        S.City,
        S.State_Province,
        S.Country,
        CURRENT_DATE       AS Start_Date,
        DATE '9999-12-31'  AS End_Date,
        'Y'                AS Current_Flag
    FROM       T_Customer  S
    LEFT JOIN  DimCustomer D
           ON  S.Customer_ID  = D.Customer_ID
          AND  D.Current_Flag = 'Y'
    WHERE
        D.Customer_ID IS NULL           -- Net-new customer
     OR D.First_Name      <> S.First_Name
     OR D.Last_Name       <> S.Last_Name
     OR D.Email_Address   <> S.Email_Address
     OR D.City            <> S.City
     OR D.State_Province  <> S.State_Province
     OR D.Country         <> S.Country;
END;
;


/* ============================================================
   SECTION 6 – ACCOUNT SCD-1 PROCEDURE
   ============================================================ */

-- ----------------------------------------------------------
-- Load_DimAccount_SCD1
-- Upserts account records using MERGE.
-- Matched rows: overwrite all tracked attributes (SCD-1).
-- Unmatched rows: insert as new account.
-- Source staging table: T_Account
-- ----------------------------------------------------------
REPLACE PROCEDURE Load_DimAccount_SCD1()
BEGIN
    MERGE INTO DimAccount AS D
    USING      T_Account  AS S
           ON  D.Account_ID = S.Account_ID

    WHEN MATCHED THEN
        UPDATE SET
            D.Customer_ID   = S.Customer_ID,
            D.Account_Type  = S.Account_Type,
            D.Status        = S.Status,
            D.Currency_Code = S.Currency_Code

    WHEN NOT MATCHED THEN
        INSERT
        (
            Account_ID,
            Customer_ID,
            Account_Type,
            Status,
            Currency_Code
        )
        VALUES
        (
            S.Account_ID,
            S.Customer_ID,
            S.Account_Type,
            S.Status,
            S.Currency_Code
        );
END;
;


/* ============================================================
   SECTION 7 – TRANSACTION TYPE DIMENSION LOAD
   ============================================================ */

-- ----------------------------------------------------------
-- Load_DimTransactionType
-- Inserts any new transaction types found in staging.
-- No updates are performed (insert-only, no overwrites).
-- Source staging table: T_Transaction
-- NOTE: Description defaults to the Transaction_Type value;
--       update manually if business descriptions are required.
-- ----------------------------------------------------------
REPLACE PROCEDURE Load_DimTransactionType()
BEGIN
    MERGE INTO DimTransactionType AS D
    USING
    (
        SELECT DISTINCT
            Transaction_Type,
            Transaction_Type AS Description   -- placeholder; refine as needed
        FROM T_Transaction
    ) AS S
    ON D.Transaction_Type = S.Transaction_Type

    WHEN NOT MATCHED THEN
        INSERT
        (
            Transaction_Type,
            Description
        )
        VALUES
        (
            S.Transaction_Type,
            S.Description
        );
END;
;


/* ============================================================
   SECTION 8 – DATE DIMENSION POPULATION
   ============================================================ */

-- ----------------------------------------------------------
-- Populate_DimDate
-- Iterates day-by-day from StartDate to EndDate (inclusive)
-- and inserts a calendar row for each date.
-- Parameters:
--   StartDate  DATE  – First date to populate
--   EndDate    DATE  – Last  date to populate
-- Usage example:
--   CALL Populate_DimDate(DATE '2020-01-01', DATE '2030-12-31');
-- ----------------------------------------------------------
REPLACE PROCEDURE Populate_DimDate
(
    StartDate  DATE,
    EndDate    DATE
)
BEGIN
    DECLARE CurrDate DATE;
    SET CurrDate = StartDate;

    WHILE CurrDate <= EndDate DO

        INSERT INTO DimDate
        SELECT
            CurrDate                            AS Date_Key,
            EXTRACT(YEAR  FROM CurrDate)        AS Year,
            EXTRACT(MONTH FROM CurrDate)        AS Month,
            EXTRACT(DAY   FROM CurrDate)        AS Day,
            EXTRACT(DOW   FROM CurrDate)        AS Day_Of_Week;

        SET CurrDate = CurrDate + INTERVAL '1' DAY;

    END WHILE;
END;
;


/* ============================================================
   SECTION 9 – RAW FACT LOAD
   ============================================================ */

-- ----------------------------------------------------------
-- Load_FactDailyTransaction
-- Loads one day of transaction-level detail into the fact
-- table by joining staging transactions to staging accounts
-- to resolve Customer_ID.
-- Parameter:
--   p_ReportDate  DATE  – The business date to load
-- Idempotency: caller must delete/truncate the date partition
--   before re-running to avoid duplicate rows.
-- ----------------------------------------------------------
REPLACE PROCEDURE Load_FactDailyTransaction
(
    p_ReportDate  DATE
)
BEGIN
    INSERT INTO FactDailyTransaction
    (
        Date_Key,
        Customer_ID,
        Account_ID,
        Transaction_ID,
        Transaction_Type,
        Amount
    )
    SELECT
        DATE(t.Transaction_Date)    AS Date_Key,
        a.Customer_ID,
        t.Account_ID,
        t.Transaction_ID,
        t.Transaction_Type,
        t.Amount
    FROM       T_Transaction  t
    JOIN       T_Account       a
           ON  t.Account_ID = a.Account_ID
    WHERE  DATE(t.Transaction_Date) = p_ReportDate;
END;
;


/* ============================================================
   SECTION 10 – AGGREGATED FACT LOAD
   ============================================================ */

-- ----------------------------------------------------------
-- Load_FactDailyAgg
-- Populates FactDailyAgg with four pre-aggregated rollups
-- for the given report date. Each INSERT represents a
-- different grouping key combination.
-- Parameter:
--   p_ReportDate  DATE  – The business date to aggregate
-- ----------------------------------------------------------
REPLACE PROCEDURE Load_FactDailyAgg
(
    p_ReportDate  DATE
)
BEGIN

    /* --------------------------------------------------
       Rollup 1 of 4: Daily summary by Customer
       Grain: Date + Customer (Account and Type = NULL)
       -------------------------------------------------- */
    INSERT INTO FactDailyAgg
    SELECT
        p_ReportDate            AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       T_Transaction  t
    JOIN       T_Account       a
           ON  t.Account_ID = a.Account_ID
    WHERE  DATE(t.Transaction_Date) = p_ReportDate
    GROUP BY
        1,          -- Date_Key  (constant)
        2;          -- Customer_ID


    /* --------------------------------------------------
       Rollup 2 of 4: Daily summary by Account
       Grain: Date + Account (Customer and Type = NULL)
       -------------------------------------------------- */
    INSERT INTO FactDailyAgg
    SELECT
        p_ReportDate            AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        NULL                    AS Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   T_Transaction  t
    WHERE  DATE(t.Transaction_Date) = p_ReportDate
    GROUP BY
        1,          -- Date_Key  (constant)
        3;          -- Account_ID


    /* --------------------------------------------------
       Rollup 3 of 4: Daily summary by Customer + Transaction Type
       Grain: Date + Customer + Type (Account = NULL)
       -------------------------------------------------- */
    INSERT INTO FactDailyAgg
    SELECT
        p_ReportDate            AS Date_Key,
        a.Customer_ID,
        NULL                    AS Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM       T_Transaction  t
    JOIN       T_Account       a
           ON  t.Account_ID = a.Account_ID
    WHERE  DATE(t.Transaction_Date) = p_ReportDate
    GROUP BY
        1,          -- Date_Key         (constant)
        2,          -- Customer_ID
        4;          -- Transaction_Type


    /* --------------------------------------------------
       Rollup 4 of 4: Daily summary by Account + Transaction Type
       Grain: Date + Account + Type (Customer = NULL)
       -------------------------------------------------- */
    INSERT INTO FactDailyAgg
    SELECT
        p_ReportDate            AS Date_Key,
        NULL                    AS Customer_ID,
        t.Account_ID,
        t.Transaction_Type,
        SUM(t.Amount)           AS Total_Amount,
        COUNT(*)                AS Transaction_Count
    FROM   T_Transaction  t
    WHERE  DATE(t.Transaction_Date) = p_ReportDate
    GROUP BY
        1,          -- Date_Key         (constant)
        3,          -- Account_ID
        4;          -- Transaction_Type

END;
;


/* ============================================================
   SECTION 11 – MASTER DAILY ETL ORCHESTRATION
   ============================================================ */

-- ----------------------------------------------------------
-- Daily_ETL_Run
-- Single entry-point that executes all ETL steps in the
-- correct dependency order for a standard daily load.
--
-- Execution order:
--   1. Close changed customer records       (SCD-2 Step 1)
--   2. Insert new / updated customer rows   (SCD-2 Step 2)
--   3. Upsert account records               (SCD-1)
--   4. Insert new transaction type codes
--   5. Load raw daily transactions
--   6. Load aggregated daily summaries
--
-- Schedule: run once per business day after staging tables
-- (T_Customer, T_Account, T_Transaction) have been loaded.
-- ----------------------------------------------------------
REPLACE PROCEDURE Daily_ETL_Run()
BEGIN
    CALL Close_Current_DimCustomer_Record();
    CALL Insert_New_DimCustomer_Record();
    CALL Load_DimAccount_SCD1();
    CALL Load_DimTransactionType();
    CALL Load_FactDailyTransaction(CURRENT_DATE);
    CALL Load_FactDailyAgg(CURRENT_DATE);
END;
;


/* ============================================================
   END OF FILE – teradata_dwh_etl.sql
   ============================================================ */