/* ============================================================
   Domain   : uds
   Layer    : gold
   Release  : 1
   Sequence : 300
   Purpose  : Create all UDS gold fact tables
   Author   : team-uds
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE TABLE IF NOT EXISTS FACT_UDS_CUSTOMER_360 (
    CUSTOMER_360_KEY    NUMBER(38,0) AUTOINCREMENT,
    MASTER_CUSTOMER_KEY NUMBER(38,0) NOT NULL,
    SNAPSHOT_DATE       DATE NOT NULL,
    -- ecomm metrics
    ECOMM_ORDER_COUNT   NUMBER(10,0) DEFAULT 0,
    ECOMM_TOTAL_SPEND   NUMBER(15,2) DEFAULT 0,
    ECOMM_LAST_ORDER    DATE,
    -- bookings metrics
    BOOKINGS_COUNT      NUMBER(10,0) DEFAULT 0,
    BOOKINGS_TOTAL_SPEND NUMBER(15,2) DEFAULT 0,
    BOOKINGS_LAST_STAY  DATE,
    -- aftermarket metrics
    AM_SERVICE_COUNT    NUMBER(10,0) DEFAULT 0,
    AM_WARRANTY_CLAIMS  NUMBER(10,0) DEFAULT 0,
    AM_LAST_SERVICE     DATE,
    -- combined
    TOTAL_LIFETIME_VALUE NUMBER(15,2),
    ENGAGEMENT_SCORE    NUMBER(5,2),
    CHURN_RISK_SCORE    NUMBER(5,2),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Customer 360 - unified metrics across all domains';

CREATE TABLE IF NOT EXISTS FACT_UDS_CROSS_DOMAIN_METRICS (
    METRIC_DATE         DATE NOT NULL,
    DOMAIN              VARCHAR(30) NOT NULL,
    ACTIVE_CUSTOMERS    NUMBER(10,0),
    NEW_CUSTOMERS       NUMBER(10,0),
    REVENUE             NUMBER(15,2),
    TRANSACTION_COUNT   NUMBER(10,0),
    AVG_TRANSACTION_VALUE NUMBER(10,2),
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Daily cross-domain business metrics';
