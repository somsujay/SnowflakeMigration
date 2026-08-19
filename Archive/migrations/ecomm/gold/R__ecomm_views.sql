/* ============================================================
   Domain   : ecomm
   Layer    : gold
   Purpose  : Repeatable - Business views for ecomm reporting
   Author   : team-ecomm
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE OR REPLACE VIEW V_ECOMM_ORDER_SUMMARY AS
SELECT
    f.ORDER_DATE_KEY,
    c.FULL_NAME AS CUSTOMER_NAME,
    c.COUNTRY,
    c.CUSTOMER_SEGMENT,
    p.PRODUCT_NAME,
    p.CATEGORY,
    f.TOTAL_AMOUNT,
    f.CHANNEL
FROM FACT_ECOMM_ORDERS f
LEFT JOIN {{ database }}.SILVER.DIM_ECOMM_CUSTOMER c
    ON f.CUSTOMER_KEY = c.CUSTOMER_KEY AND c.IS_CURRENT = TRUE
LEFT JOIN {{ database }}.SILVER.DIM_ECOMM_PRODUCT p
    ON f.PRODUCT_KEY = p.PRODUCT_KEY AND p.IS_CURRENT = TRUE;

CREATE OR REPLACE VIEW V_ECOMM_DAILY_REVENUE AS
SELECT
    REVENUE_DATE,
    CHANNEL,
    COUNTRY,
    ORDER_COUNT,
    TOTAL_REVENUE,
    AVG_ORDER_VALUE
FROM FACT_ECOMM_REVENUE
ORDER BY REVENUE_DATE DESC;
