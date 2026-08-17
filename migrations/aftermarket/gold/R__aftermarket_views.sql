/* ============================================================
   Domain   : aftermarket
   Layer    : gold
   Purpose  : Repeatable - Business views for aftermarket reporting
   Author   : team-aftermarket
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE OR REPLACE VIEW V_AM_SERVICE_SUMMARY AS
SELECT
    f.CREATED_DATE_KEY,
    st.SERVICE_TYPE_NAME,
    st.CATEGORY,
    f.PRIORITY,
    f.STATUS,
    f.RESOLUTION_DAYS
FROM FACT_AM_SERVICE f
LEFT JOIN {{ database }}.SILVER.DIM_AM_SERVICE_TYPE st
    ON f.SERVICE_TYPE_KEY = st.SERVICE_TYPE_KEY;

CREATE OR REPLACE VIEW V_AM_WARRANTY_ANALYSIS AS
SELECT
    w.CLAIM_DATE_KEY,
    w.CLAIM_TYPE,
    w.STATUS,
    w.CLAIM_AMOUNT,
    p.PART_NAME,
    p.PART_CATEGORY
FROM FACT_AM_WARRANTY w
LEFT JOIN {{ database }}.SILVER.DIM_AM_PARTS p
    ON w.PRODUCT_KEY = p.PART_KEY;
