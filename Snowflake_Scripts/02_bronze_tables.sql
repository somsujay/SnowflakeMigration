/* ============================================================
   FILE    : 02_bronze_tables.sql
   PURPOSE : Bronze layer DDL – raw staging tables
   SCHEMA  : BRONZE
   NOTES   :
       - Direct landing zone for OLTP source data
       - _LOADED_AT metadata column tracks ingestion time
       - No PRIMARY INDEX (Snowflake uses micro-partitions)
   ============================================================ */


-- ----------------------------------------------------------
-- T_Customer
-- Raw customer master data sourced from the OLTP system.
-- Staged here prior to SCD-2 processing into SILVER.DimCustomer.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.T_Customer
(
    Customer_ID         VARCHAR(50)       NOT NULL,
    First_Name          VARCHAR(50),
    Last_Name           VARCHAR(50),
    Email_Address       VARCHAR(100),
    Phone_Number        VARCHAR(20),
    City                VARCHAR(50),
    State_Province      VARCHAR(50),
    Country             VARCHAR(50),
    Created_Timestamp   TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP(),
    _LOADED_AT          TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP()
);


-- ----------------------------------------------------------
-- T_Account
-- Raw account data sourced from the OLTP system.
-- Staged here prior to SCD-1 upsert into SILVER.DimAccount.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.T_Account
(
    Account_ID          VARCHAR(50)       NOT NULL,
    Customer_ID         VARCHAR(50)       NOT NULL,
    Account_Type        VARCHAR(30),
    Status              VARCHAR(20),
    Currency_Code       VARCHAR(10),
    Open_Date           DATE,
    Created_Timestamp   TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP(),
    _LOADED_AT          TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP()
);


-- ----------------------------------------------------------
-- T_Transaction
-- Raw transaction records sourced from the OLTP system.
-- Staged here prior to loading into GOLD fact tables.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.T_Transaction
(
    Transaction_ID      VARCHAR(50)       NOT NULL,
    Account_ID          VARCHAR(50)       NOT NULL,
    Transaction_Date    TIMESTAMP_NTZ     NOT NULL,
    Transaction_Type    VARCHAR(30),
    Amount              DECIMAL(18,2),
    Description         VARCHAR(255),
    _LOADED_AT          TIMESTAMP_NTZ     DEFAULT CURRENT_TIMESTAMP()
);
