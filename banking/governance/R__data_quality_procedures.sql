/* ============================================================
   schemachange Repeatable: R__data_quality_procedures.sql
   PURPOSE : Data cleansing and quality validation procedures
   Re-runs automatically when this file changes.
   NOTE: The DATA_QUALITY_LOG table DDL remains in V1.9.0.
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOVERNANCE;

CREATE OR REPLACE PROCEDURE GOVERNANCE.Cleanse_Bronze_Data()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
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

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Customer WHERE Customer_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'NULL_CHECK_Customer_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Customer_ID', 'All records have Customer_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account WHERE Account_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'NULL_CHECK_Account_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Account_ID', 'All records have Account_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction WHERE Transaction_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'NULL_CHECK_Transaction_ID', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with NULL Transaction_ID', 'All records have Transaction_ID'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Customer_ID FROM BRONZE.T_Customer GROUP BY Customer_ID HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'DUPLICATE_PK', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' duplicate Customer_IDs found', 'No duplicate Customer_IDs'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Customer
    WHERE Email_Address IS NOT NULL
      AND NOT RLIKE(Email_Address, '^[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}$');
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Customer', 'EMAIL_FORMAT', IFF(:failed_count > 0, 'WARNING', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' records with invalid email format', 'All email addresses are valid'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Account A
    LEFT JOIN BRONZE.T_Customer C ON A.Customer_ID = C.Customer_ID
    WHERE C.Customer_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Account', 'FK_CUSTOMER_REF', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' accounts reference non-existent customers', 'All accounts reference valid customers'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count
    FROM BRONZE.T_Transaction T
    LEFT JOIN BRONZE.T_Account A ON T.Account_ID = A.Account_ID
    WHERE A.Account_ID IS NULL;
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'BRONZE.T_Transaction', 'FK_ACCOUNT_REF', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' transactions reference non-existent accounts', 'All transactions reference valid accounts'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    SELECT COUNT(*) INTO :failed_count FROM (
        SELECT Customer_ID
        FROM SILVER.DimCustomer
        WHERE Current_Flag = 'Y'
        GROUP BY Customer_ID
        HAVING COUNT(*) > 1
    );
    INSERT INTO GOVERNANCE.DATA_QUALITY_LOG (run_id, table_name, check_name, severity, records_failed, details)
    VALUES (:run_id, 'SILVER.DimCustomer', 'SCD2_SINGLE_ACTIVE', IFF(:failed_count > 0, 'ERROR', 'INFO'), :failed_count,
            IFF(:failed_count > 0, :failed_count || ' customers with multiple active records', 'SCD-2 integrity OK'));
    total_checks := total_checks + 1;
    total_failures := total_failures + :failed_count;

    RETURN 'Data Quality Checks completed: ' || :total_checks || ' checks, ' || :total_failures || ' total failures. Run ID: ' || :run_id;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'ERROR in Run_Data_Quality_Checks: ' || SQLCODE || ' - ' || SQLERRM;
END;
$$;
