/* ============================================================
   FILE    : 04_gold_tables.sql
   PURPOSE : Gold layer DDL – business-ready fact tables
   SCHEMA  : GOLD
   NOTES   :
       - FactDailyTransaction: grain = one row per transaction per day
       - FactDailyAgg: pre-aggregated daily summaries at multiple rollup levels
       - Clustered by Date_Key for partition pruning on date-range queries
   ============================================================ */


-- ----------------------------------------------------------
-- FactDailyTransaction
-- Grain: one row per individual transaction per day.
-- ----------------------------------------------------------
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


-- ----------------------------------------------------------
-- FactDailyAgg
-- Grain: pre-aggregated daily summaries.
-- Supports multiple rollup levels:
--   - Customer only
--   - Account only
--   - Customer + Transaction Type
--   - Account + Transaction Type
-- NULL in a grouping column indicates that dimension is
-- not part of the aggregation key for that row.
-- ----------------------------------------------------------
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


-- ----------------------------------------------------------
-- MonthlySpendProfile
-- Monthly spending summary per customer per transaction type.
-- Joins FactDailyTransaction with current DimCustomer records.
-- Masking policies on underlying columns apply automatically.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW GOLD.MONTHLYSPENDPROFILE AS
SELECT
    C.CUSTOMER_ID,
    C.FIRST_NAME,
    C.LAST_NAME,
    C.CITY,
    C.STATE_PROVINCE,
    F.TRANSACTION_TYPE,
    DATE_TRUNC('MONTH', F.DATE_KEY) AS MONTH_KEY,
    COUNT(*) AS TRANSACTION_COUNT,
    SUM(F.AMOUNT) AS TOTAL_SPEND,
    AVG(F.AMOUNT) AS AVG_TRANSACTION,
    MIN(F.AMOUNT) AS MIN_TRANSACTION,
    MAX(F.AMOUNT) AS MAX_TRANSACTION
FROM GOLD.FACTDAILYTRANSACTION AS F
INNER JOIN SILVER.DIMCUSTOMER AS C
    ON
        F.CUSTOMER_ID = C.CUSTOMER_ID
        AND C.CURRENT_FLAG = 'Y'
GROUP BY
    C.CUSTOMER_ID,
    C.FIRST_NAME,
    C.LAST_NAME,
    C.CITY,
    C.STATE_PROVINCE,
    DATE_TRUNC('MONTH', F.DATE_KEY),
    F.TRANSACTION_TYPE;


-- ----------------------------------------------------------
-- TxnTypeTrend
-- Monthly transaction type trends across the entire portfolio.
-- Shows volume, spend, and customer reach per type over time.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW GOLD.TXNTYPETREND AS
SELECT
    F.TRANSACTION_TYPE,
    DATE_TRUNC('MONTH', F.DATE_KEY) AS MONTH_KEY,
    COUNT(*) AS TRANSACTION_COUNT,
    SUM(F.AMOUNT) AS TOTAL_AMOUNT,
    AVG(F.AMOUNT) AS AVG_AMOUNT,
    COUNT(DISTINCT F.CUSTOMER_ID) AS UNIQUE_CUSTOMERS,
    COUNT(DISTINCT F.ACCOUNT_ID) AS UNIQUE_ACCOUNTS,
    SUM(F.AMOUNT) / NULLIF(COUNT(DISTINCT F.CUSTOMER_ID), 0) AS AVG_SPEND_PER_CUSTOMER
FROM GOLD.FACTDAILYTRANSACTION AS F
GROUP BY
    DATE_TRUNC('MONTH', F.DATE_KEY),
    F.TRANSACTION_TYPE;
