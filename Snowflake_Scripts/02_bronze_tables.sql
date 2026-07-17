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
CREATE OR REPLACE TABLE BRONZE.T_CUSTOMER
(
    CUSTOMER_ID VARCHAR(50) NOT NULL,
    FIRST_NAME VARCHAR(50),
    LAST_NAME VARCHAR(50),
    EMAIL_ADDRESS VARCHAR(100),
    PHONE_NUMBER VARCHAR(20),
    CITY VARCHAR(50),
    STATE_PROVINCE VARCHAR(50),
    COUNTRY VARCHAR(50),
    CREATED_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


-- ----------------------------------------------------------
-- T_Account
-- Raw account data sourced from the OLTP system.
-- Staged here prior to SCD-1 upsert into SILVER.DimAccount.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.T_ACCOUNT
(
    ACCOUNT_ID VARCHAR(50) NOT NULL,
    CUSTOMER_ID VARCHAR(50) NOT NULL,
    ACCOUNT_TYPE VARCHAR(30),
    STATUS VARCHAR(20),
    CURRENCY_CODE VARCHAR(10),
    OPEN_DATE DATE,
    CREATED_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);


-- ----------------------------------------------------------
-- T_Transaction
-- Raw transaction records sourced from the OLTP system.
-- Staged here prior to loading into GOLD fact tables.
-- ----------------------------------------------------------
CREATE OR REPLACE TABLE BRONZE.T_TRANSACTION
(
    TRANSACTION_ID VARCHAR(50) NOT NULL,
    ACCOUNT_ID VARCHAR(50) NOT NULL,
    TRANSACTION_DATE TIMESTAMP_NTZ NOT NULL,
    TRANSACTION_TYPE VARCHAR(30),
    AMOUNT DECIMAL(18, 2),
    DESCRIPTION VARCHAR(255),
    _LOADED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
