/* ============================================================
   FILE    : 05_silver_procedures.sql
   PURPOSE : Silver layer procedures – dimension loading
   SCHEMA  : SILVER (reads from BRONZE, writes to SILVER)
   PROCS   :
       1. Close_Current_DimCustomer_Record  (SCD-2 Step 1)
       2. Insert_New_DimCustomer_Record     (SCD-2 Step 2)
       3. Load_DimAccount_SCD1              (SCD-1 MERGE)
       4. Load_DimTransactionType           (insert-only MERGE)
       5. Populate_DimDate                  (generator-based)
   ============================================================ */


-- ----------------------------------------------------------
-- Close_Current_DimCustomer_Record
-- SCD-2 Step 1: Expire the active DimCustomer record when
-- any tracked attribute has changed since the last load.
-- Sets End_Date = CURRENT_DATE - 1 and Current_Flag = 'N'.
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.Close_Current_DimCustomer_Record()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    UPDATE SILVER.DimCustomer D
    SET
        D.End_Date     = CURRENT_DATE - 1,
        D.Current_Flag = 'N'
    FROM BRONZE.T_Customer S
    WHERE D.Customer_ID  = S.Customer_ID
      AND D.Current_Flag = 'Y'
      AND (
              D.First_Name      <> S.First_Name
           OR D.Last_Name       <> S.Last_Name
           OR D.Email_Address   <> S.Email_Address
           OR D.City            <> S.City
           OR D.State_Province  <> S.State_Province
           OR D.Country         <> S.Country
          );

    RETURN 'Close_Current_DimCustomer_Record completed';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Close_Current_DimCustomer_Record: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


-- ----------------------------------------------------------
-- Insert_New_DimCustomer_Record
-- SCD-2 Step 2: Insert a new active row for:
--   a) Net-new customers (no existing DimCustomer record), or
--   b) Existing customers whose attributes changed (closed in Step 1).
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.Insert_New_DimCustomer_Record()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO SILVER.DimCustomer
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
        CURRENT_DATE            AS Start_Date,
        '9999-12-31'::DATE      AS End_Date,
        'Y'                     AS Current_Flag
    FROM       BRONZE.T_Customer  S
    LEFT JOIN  SILVER.DimCustomer D
           ON  S.Customer_ID  = D.Customer_ID
          AND  D.Current_Flag = 'Y'
    WHERE
        D.Customer_ID IS NULL
     OR D.First_Name      <> S.First_Name
     OR D.Last_Name       <> S.Last_Name
     OR D.Email_Address   <> S.Email_Address
     OR D.City            <> S.City
     OR D.State_Province  <> S.State_Province
     OR D.Country         <> S.Country;

    RETURN 'Insert_New_DimCustomer_Record completed';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Insert_New_DimCustomer_Record: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


-- ----------------------------------------------------------
-- Load_DimAccount_SCD1
-- Upserts account records using MERGE (SCD Type 1).
-- Matched rows: overwrite all tracked attributes.
-- Unmatched rows: insert as new account.
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.Load_DimAccount_SCD1()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO SILVER.DimAccount AS D
    USING      BRONZE.T_Account  AS S
           ON  D.Account_ID = S.Account_ID

    WHEN MATCHED THEN
        UPDATE SET
            D.Customer_ID   = S.Customer_ID,
            D.Account_Type  = S.Account_Type,
            D.Status        = S.Status,
            D.Currency_Code = S.Currency_Code

    WHEN NOT MATCHED THEN
        INSERT (Account_ID, Customer_ID, Account_Type, Status, Currency_Code)
        VALUES (S.Account_ID, S.Customer_ID, S.Account_Type, S.Status, S.Currency_Code);

    RETURN 'Load_DimAccount_SCD1 completed';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_DimAccount_SCD1: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


-- ----------------------------------------------------------
-- Load_DimTransactionType
-- Inserts any new transaction types found in staging.
-- No updates are performed (insert-only, no overwrites).
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.Load_DimTransactionType()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    MERGE INTO SILVER.DimTransactionType AS D
    USING (
        SELECT DISTINCT
            Transaction_Type,
            Transaction_Type AS Description
        FROM BRONZE.T_Transaction
    ) AS S
    ON D.Transaction_Type = S.Transaction_Type

    WHEN NOT MATCHED THEN
        INSERT (Transaction_Type, Description)
        VALUES (S.Transaction_Type, S.Description);

    RETURN 'Load_DimTransactionType completed';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Load_DimTransactionType: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;


-- ----------------------------------------------------------
-- Populate_DimDate
-- Populates the date dimension using a generator (set-based).
-- Parameters:
--   StartDate DATE – First date to populate
--   EndDate   DATE – Last date to populate
-- Usage:
--   CALL SILVER.Populate_DimDate('2020-01-01'::DATE, '2030-12-31'::DATE);
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE SILVER.Populate_DimDate(StartDate DATE, EndDate DATE)
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO SILVER.DimDate (Date_Key, Year, Month, Day, Day_Of_Week)
    SELECT
        DATEADD(DAY, seq.seq_val, :StartDate)           AS Date_Key,
        YEAR(Date_Key)                                  AS Year,
        MONTH(Date_Key)                                 AS Month,
        DAY(Date_Key)                                   AS Day,
        DAYOFWEEK(Date_Key)                             AS Day_Of_Week
    FROM (
        SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS seq_val
        FROM TABLE(GENERATOR(ROWCOUNT => DATEDIFF(DAY, :StartDate, :EndDate) + 1))
    ) AS seq;

    RETURN 'Populate_DimDate completed: ' || :StartDate || ' to ' || :EndDate;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Populate_DimDate: ' || SQLCODE || ' - ' || SQLERRM || ' (SQLSTATE: ' || SQLSTATE || ')';
END;
$$;
