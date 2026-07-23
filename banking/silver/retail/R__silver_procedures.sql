/* ============================================================
   schemachange Repeatable: R__silver_procedures.sql
   PURPOSE : Silver layer procedures - dimension loading
   Re-runs automatically when this file changes.
   ============================================================ */

USE DATABASE {{ database }};

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

CREATE OR REPLACE PROCEDURE SILVER.Insert_New_DimCustomer_Record()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    INSERT INTO SILVER.DimCustomer
    (
        Customer_ID, First_Name, Last_Name, Email_Address,
        City, State_Province, Country, Start_Date, End_Date, Current_Flag
    )
    SELECT
        S.Customer_ID, S.First_Name, S.Last_Name, S.Email_Address,
        S.City, S.State_Province, S.Country,
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
