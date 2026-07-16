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
CREATE OR REPLACE TABLE SILVER.DimCustomer
(
    Customer_Key    INTEGER AUTOINCREMENT,
    Customer_ID     VARCHAR(50)   NOT NULL,
    First_Name      VARCHAR(50),
    Last_Name       VARCHAR(50),
    Email_Address   VARCHAR(100),
    City            VARCHAR(50),
    State_Province  VARCHAR(50),
    Country         VARCHAR(50),
    Start_Date      DATE,
    End_Date        DATE,
    Current_Flag    CHAR(1)
);


-- ----------------------------------------------------------
-- DimAccount (Slowly Changing Dimension – Type 1)
-- Overwrites on change; no history retained.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DimAccount
(
    Account_ID      VARCHAR(50)   NOT NULL,
    Customer_ID     VARCHAR(50)   NOT NULL,
    Account_Type    VARCHAR(30),
    Status          VARCHAR(20),
    Currency_Code   VARCHAR(10)
);


-- ----------------------------------------------------------
-- DimTransactionType
-- Lookup / reference dimension for transaction categories.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DimTransactionType
(
    Transaction_Type    VARCHAR(30)   NOT NULL,
    Description         VARCHAR(100)
);


-- ----------------------------------------------------------
-- DimDate
-- Calendar dimension; populated via Populate_DimDate().
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE SILVER.DimDate
(
    Date_Key        DATE       NOT NULL,
    Year            INTEGER,
    Month           INTEGER,
    Day             INTEGER,
    Day_Of_Week     INTEGER
)
CLUSTER BY (Date_Key);
