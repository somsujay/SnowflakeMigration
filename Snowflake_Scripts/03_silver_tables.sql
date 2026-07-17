/* ============================================================
   FILE    : 03_silver_tables.sql
   PURPOSE : Silver layer DDL – cleansed & conformed dimensions
   SCHEMA  : SILVER
   NOTES   :
       - DimCustomer: SCD Type 2 (full history)
       - DimAccount: SCD Type 1 (overwrite on change)
       - DimTransactionType: Reference/lookup dimension
       - DimDate: Calendar dimension
   ============================================================ */


-- ----------------------------------------------------------
-- DimCustomer (Slowly Changing Dimension – Type 2)
-- Tracks full history of customer attribute changes.
-- Current record identified by Current_Flag = 'Y'
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DIMCUSTOMER
(
    CUSTOMER_KEY INTEGER AUTOINCREMENT,
    CUSTOMER_ID VARCHAR(50) NOT NULL,
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    EMAIL_ADDRESS VARCHAR(100),
    CITY VARCHAR(50),
    STATE_PROVINCE VARCHAR(50),
    COUNTRY VARCHAR(50),
    START_DATE DATE,
    END_DATE DATE,
    CURRENT_FLAG CHAR(1)
);


-- ----------------------------------------------------------
-- DimAccount (Slowly Changing Dimension – Type 1)
-- Overwrites on change; no history retained.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DIMACCOUNT
(
    ACCOUNT_ID VARCHAR(50) NOT NULL,
    CUSTOMER_ID VARCHAR(50) NOT NULL,
    ACCOUNT_TYPE VARCHAR(30),
    STATUS VARCHAR(20),
    CURRENCY_CODE VARCHAR(10)
);


-- ----------------------------------------------------------
-- DimTransactionType
-- Lookup / reference dimension for transaction categories.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DIMTRANSACTIONTYPE
(
    TRANSACTION_TYPE VARCHAR(30) NOT NULL,
    DESCRIPTION VARCHAR(100)
);


-- ----------------------------------------------------------
-- DimDate
-- Calendar dimension; populated via Populate_DimDate().
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DIMDATE
(
    DATE_KEY DATE NOT NULL,
    YEAR INTEGER,
    MONTH INTEGER,
    DAY INTEGER,
    DAY_OF_WEEK INTEGER
)
CLUSTER BY (DATE_KEY);
