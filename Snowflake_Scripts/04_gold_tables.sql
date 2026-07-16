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
CREATE OR REPLACE TABLE GOLD.FactDailyTransaction
(
    Date_Key            DATE          NOT NULL,
    Customer_ID         VARCHAR(50)   NOT NULL,
    Account_ID          VARCHAR(50)   NOT NULL,
    Transaction_ID      VARCHAR(50)   NOT NULL,
    Transaction_Type    VARCHAR(30),
    Amount              DECIMAL(18,2)
)
CLUSTER BY (Date_Key);


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
CREATE OR REPLACE TABLE GOLD.FactDailyAgg
(
    Date_Key            DATE          NOT NULL,
    Customer_ID         VARCHAR(50),
    Account_ID          VARCHAR(50),
    Transaction_Type    VARCHAR(30),
    Total_Amount        DECIMAL(18,2),
    Transaction_Count   INTEGER
)
CLUSTER BY (Date_Key);


-- ----------------------------------------------------------
-- MonthlySpendProfile
-- Monthly spending summary per customer per transaction type.
-- Joins FactDailyTransaction with current DimCustomer records.
-- Masking policies on underlying columns apply automatically.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW GOLD.MonthlySpendProfile AS
SELECT
    c.Customer_ID,
    c.First_Name,
    c.Last_Name,
    c.City,
    c.State_Province,
    DATE_TRUNC('MONTH', f.Date_Key)         AS Month_Key,
    f.Transaction_Type,
    COUNT(*)                                 AS Transaction_Count,
    SUM(f.Amount)                            AS Total_Spend,
    AVG(f.Amount)                            AS Avg_Transaction,
    MIN(f.Amount)                            AS Min_Transaction,
    MAX(f.Amount)                            AS Max_Transaction
FROM GOLD.FactDailyTransaction f
JOIN SILVER.DimCustomer c
    ON f.Customer_ID = c.Customer_ID
   AND c.Current_Flag = 'Y'
GROUP BY
    c.Customer_ID,
    c.First_Name,
    c.Last_Name,
    c.City,
    c.State_Province,
    DATE_TRUNC('MONTH', f.Date_Key),
    f.Transaction_Type;


-- ----------------------------------------------------------
-- TxnTypeTrend
-- Monthly transaction type trends across the entire portfolio.
-- Shows volume, spend, and customer reach per type over time.
-- ----------------------------------------------------------
CREATE OR REPLACE VIEW GOLD.TxnTypeTrend AS
SELECT
    DATE_TRUNC('MONTH', f.Date_Key)         AS Month_Key,
    f.Transaction_Type,
    COUNT(*)                                 AS Transaction_Count,
    SUM(f.Amount)                            AS Total_Amount,
    AVG(f.Amount)                            AS Avg_Amount,
    COUNT(DISTINCT f.Customer_ID)            AS Unique_Customers,
    COUNT(DISTINCT f.Account_ID)             AS Unique_Accounts,
    SUM(f.Amount) / NULLIF(COUNT(DISTINCT f.Customer_ID), 0) AS Avg_Spend_Per_Customer
FROM GOLD.FactDailyTransaction f
GROUP BY
    DATE_TRUNC('MONTH', f.Date_Key),
    f.Transaction_Type;
