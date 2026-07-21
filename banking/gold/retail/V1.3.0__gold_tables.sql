/* ============================================================
   schemachange Migration: V1.3.0__gold_tables.sql
   PURPOSE : Gold layer DDL - business-ready fact tables and views
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE OR REPLACE TABLE GOLD.FACTDAILYTRANSACTION
(
    DATE_KEY DATE NOT NULL,
    CUSTOMER_ID VARCHAR(50) NOT NULL,
    ACCOUNT_ID VARCHAR(50) NOT NULL,
    TRANSACTION_ID VARCHAR(50) NOT NULL,
    TRANSACTION_TYPE VARCHAR(30),
    AMOUNT DECIMAL(18, 2)
)
CLUSTER BY (DATE_KEY);

CREATE OR REPLACE TABLE GOLD.FACTDAILYAGG
(
    DATE_KEY DATE NOT NULL,
    CUSTOMER_ID VARCHAR(50),
    ACCOUNT_ID VARCHAR(50),
    TRANSACTION_TYPE VARCHAR(30),
    TOTAL_AMOUNT DECIMAL(18, 2),
    TRANSACTION_COUNT INTEGER
)
CLUSTER BY (DATE_KEY);
