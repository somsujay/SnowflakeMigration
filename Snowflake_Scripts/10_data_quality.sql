/* ============================================================
   FILE    : 10_data_quality.sql
   PURPOSE : Data cleansing and quality validation framework
   SCHEMA  : GOVERNANCE
   OBJECTS :
       - GOVERNANCE.DATA_QUALITY_LOG    (audit table)
       - GOVERNANCE.Cleanse_Bronze_Data (cleansing procedure)
       - GOVERNANCE.Run_Data_Quality_Checks (validation procedure)
   NOTES   :
       - Run Cleanse_Bronze_Data() BEFORE ETL to fix common issues
       - Run Run_Data_Quality_Checks() AFTER load or ETL to validate
       - Results logged to DATA_QUALITY_LOG for dashboarding
   ============================================================ */


-- ----------------------------------------------------------
-- Data Quality Audit Log Table
-- ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS GOVERNANCE.DATA_QUALITY_LOG (
    log_id              INTEGER AUTOINCREMENT,
    run_id              VARCHAR(50)       NOT NULL,
    check_timestamp     TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP(),
    table_name          VARCHAR(100)      NOT NULL,
    check_name          VARCHAR(100)      NOT NULL,
    severity            VARCHAR(20)       NOT NULL,  -- ERROR, WARNING, INFO
    records_failed      INTEGER           DEFAULT 0,
    sample_ids          VARCHAR(2000),
    details             VARCHAR(4000)
);


-- ----------------------------------------------------------
-- Cleanse_Bronze_Data
-- Fixes common data quality issues in Bronze tables:
--   1. Trims whitespace from all VARCHAR columns
--   2. Lowercases email addresses
--   3. Defaults NULL Currency_Code to 'CAD'
--   4. Removes exact duplicate rows (keeps latest _LOADED_AT)
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOVERNANCE.Cleanse_Bronze_Data()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- 1. Trim whitespace + lowercase email in T_Customer
    UPDATE BRONZE.T_Customer
    SET
        Customer_ID    = TRIM(Customer_ID),
        First_Name     = TRIM(First_Name),
        Last_Name      = TRIM(Last_Name),
        Email_Address  = LOWER(TRIM(Email_Address)),
        Phone_Number   = TRIM(Phone_Number),
        City           = TRIM(City),
        State_Province = TRIM(State_Province),
        Country        = TRIM(Country)
    WHERE
        Customer_ID    <> TRIM(Customer_ID)
     OR First_Name     <> TRIM(First_Name)
     OR Last_Name      <> TRIM(Last_Name)
     OR Email_Address  <> LOWER(TRIM(Email_Address))
     OR Phone_Number   <> TRIM(Phone_Number)
     OR City           <> TRIM(City)
     OR State_Province <> TRIM(State_Province)
     OR Country        <> TRIM(Country);

    -- 2. Trim whitespace in T_Account + default NULL currency
    UPDATE BRONZE.T_Account
    SET
        Account_ID    = TRIM(Account_ID),
        Customer_ID   = TRIM(Customer_ID),
        Account_Type  = TRIM(Account_Type),
        Status        = TRIM(Status),
        Currency_Code = COALESCE(TRIM(Currency_Code), 'CAD')
    WHERE
        Account_ID    <> TRIM(Account_ID)
     OR Customer_ID   <> TRIM(Customer_ID)
     OR Account_Type  <> TRIM(Account_Type)
     OR Status        <> TRIM(Status)
     OR Currency_Code IS NULL
     OR Currency_Code <> TRIM(Currency_Code);

    -- 3. Trim whitespace in T_Transaction
    UPDATE BRONZE.T_Transaction
    SET
        Transaction_ID   = TRIM(Transaction_ID),
        Account_ID       = TRIM(Account_ID),
        Transaction_Type = TRIM(Transaction_Type),
        Description      = TRIM(Description)
    WHERE
        Transaction_ID   <> TRIM(Transaction_ID)
     OR Account_ID       <> TRIM(Account_ID)
     OR Transaction_Type <> TRIM(Transaction_Type)
     OR Description      <> TRIM(Description);

    -- 4. Remove duplicate rows per PK (keep latest _LOADED_AT per PK)
    DELETE FROM BRONZE.T_Customer C
    USING (
        SELECT Customer_ID, MAX(_LOADED_AT) AS max_loaded
        FROM BRONZE.T_Customer
        GROUP BY Customer_ID
        HAVING COUNT(*) > 1
    ) D
    WHERE C.Customer_ID = D.Customer_ID
      AND C._LOADED_AT < D.max_loaded;

    DELETE FROM BRONZE.T_Account A
    USING (
        SELECT Account_ID, MAX(_LOADED_AT) AS max_loaded
        FROM BRONZE.T_Account
        GROUP BY Account_ID
        HAVING COUNT(*) > 1
    ) D
    WHERE A.Account_ID = D.Account_ID
      AND A._LOADED_AT < D.max_loaded;

    DELETE FROM BRONZE.T_Transaction T
    USING (
        SELECT Transaction_ID, MAX(_LOADED_AT) AS max_loaded
        FROM BRONZE.T_Transaction
        GROUP BY Transaction_ID
        HAVING COUNT(*) > 1
    ) D
    WHERE T.Transaction_ID = D.Transaction_ID
      AND T._LOADED_AT < D.max_loaded;

    RETURN 'Cleanse_Bronze_Data completed successfully';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Cleanse_Bronze_Data: ' || SQLCODE || ' - ' || SQLERRM;
END;
$$;


-- ----------------------------------------------------------
-- Run_Data_Quality_Checks
-- Validates data across all layers and logs results.
-- Checks:
--   1. NULL checks on required fields
--   2. Duplicate primary keys
--   3. Email format validation
--   4. Referential integrity (FK relationships)
--   5. Domain validation (allowed values)
--   6. Amount validation (> 0)
--   7. Date sanity (no future dates)
--   8. SCD-2 integrity (one active record per customer)
--   9. Fact-Dimension join integrity (no orphan keys)
-- ----------------------------------------------------------
CREATE OR REPLACE PROCEDURE GOVERNANCE.Run_Data_Quality_Checks()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    LET run_id VARCHAR := TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
    LET total_checks INTEGER := 0;
    LET total_failures INTEGER := 0;
    LET failed_count INTEGER := 0;

    -- ======================================================
    -- CHECK 1: NULL values in required fields
    -- ======================================================

    -- Customer_ID NULLs
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Customer WHERE Customer_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'NULL_CHECK_Customer_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Customer_ID', 'All records have Customer_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- Account_ID NULLs
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account WHERE Account_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'NULL_CHECK_Account_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Account_ID', 'All records have Account_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- Transaction_ID NULLs
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction WHERE Transaction_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'NULL_CHECK_Transaction_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Transaction_ID', 'All records have Transaction_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 2: Duplicate primary keys
    -- ======================================================

    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Customer_ID FROM BRONZE.T_Customer GROUP BY Customer_ID HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'DUPLICATE_PK', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' duplicate Customer_IDs found', 'No duplicate Customer_IDs'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Account_ID FROM BRONZE.T_Account GROUP BY Account_ID HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'DUPLICATE_PK', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' duplicate Account_IDs found', 'No duplicate Account_IDs'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Transaction_ID FROM BRONZE.T_Transaction GROUP BY Transaction_ID HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'DUPLICATE_PK', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' duplicate Transaction_IDs found', 'No duplicate Transaction_IDs'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 3: Email format validation
    -- ======================================================

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Customer
    WHERE Email_Address IS NOT NULL
      AND NOT RLIKE(Email_Address, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'EMAIL_FORMAT', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with invalid email format', 'All email addresses are valid'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 4: Referential integrity
    -- ======================================================

    -- Accounts referencing non-existent Customers
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account A
    LEFT JOIN BRONZE.T_Customer C ON A.Customer_ID = C.Customer_ID
    WHERE C.Customer_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'FK_CUSTOMER_REF', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' accounts reference non-existent customers', 'All accounts reference valid customers'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- Transactions referencing non-existent Accounts
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction T
    LEFT JOIN BRONZE.T_Account A ON T.Account_ID = A.Account_ID
    WHERE A.Account_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'FK_ACCOUNT_REF', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' transactions reference non-existent accounts', 'All transactions reference valid accounts'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 5: Domain validation
    -- ======================================================

    -- Account_Type must be in allowed values
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account
    WHERE Account_Type NOT IN ('Chequing', 'Savings', 'Investment', 'Credit');
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'DOMAIN_ACCOUNT_TYPE', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' accounts with invalid Account_Type', 'All Account_Type values are valid'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- Status must be in allowed values
    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account
    WHERE Status NOT IN ('Active', 'Suspended', 'Closed');
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'DOMAIN_STATUS', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' accounts with invalid Status', 'All Status values are valid'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 6: Amount validation
    -- ======================================================

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction
    WHERE Amount IS NULL OR Amount <= 0;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'AMOUNT_POSITIVE', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' transactions with non-positive amount', 'All transaction amounts are positive'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 7: Date sanity (no future dates)
    -- ======================================================

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction
    WHERE Transaction_Date > CURRENT_TIMESTAMP();
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'FUTURE_DATE', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' transactions with future dates', 'No future-dated transactions'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account
    WHERE Open_Date > CURRENT_DATE();
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'FUTURE_OPEN_DATE', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' accounts with future open dates', 'No future-dated accounts'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 8: SCD-2 integrity (Silver layer)
    -- ======================================================

    -- Each Customer_ID should have exactly one Current_Flag='Y' record
    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Customer_ID
        FROM SILVER.DimCustomer
        WHERE Current_Flag = 'Y'
        GROUP BY Customer_ID
        HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'SILVER.DimCustomer', 'SCD2_SINGLE_ACTIVE', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' customers with multiple active records', 'SCD-2 integrity OK - one active record per customer'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- ======================================================
    -- CHECK 9: Fact-Dimension join integrity (Gold layer)
    -- ======================================================

    -- FactDailyTransaction references valid accounts in DimAccount
    SELECT COUNT(*) INTO :failed_count
    FROM GOLD.FactDailyTransaction F
    LEFT JOIN SILVER.DimAccount D ON F.Account_ID = D.Account_ID
    WHERE D.Account_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'GOLD.FactDailyTransaction', 'FK_DIM_ACCOUNT', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' fact records with orphan Account_ID', 'All fact records join to DimAccount'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    -- FactDailyTransaction references valid customers in DimCustomer
    SELECT COUNT(*) INTO :failed_count
    FROM GOLD.FactDailyTransaction F
    LEFT JOIN SILVER.DimCustomer D ON F.Customer_ID = D.Customer_ID AND D.Current_Flag = 'Y'
    WHERE D.Customer_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'GOLD.FactDailyTransaction', 'FK_DIM_CUSTOMER', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' fact records with orphan Customer_ID', 'All fact records join to DimCustomer'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    RETURN 'Data Quality Checks completed: ' || :total_checks || ' checks, ' || :total_failures || ' total failures. Run ID: ' || :run_id;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Run_Data_Quality_Checks: ' || SQLCODE || ' - ' || SQLERRM;
END;
$$;
