/* ============================================================
   Domain   : ecomm
   Layer    : gold
   Release  : 1
   Sequence : 300
   Purpose  : Create all ecomm gold fact tables
   Author   : team-ecomm
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE TABLE IF NOT EXISTS FACT_ECOMM_ORDERS (
    ORDER_KEY         NUMBER(38,0) AUTOINCREMENT,
    ORDER_ID          NUMBER(38,0) NOT NULL,
    CUSTOMER_KEY      NUMBER(38,0),
    PRODUCT_KEY       NUMBER(38,0),
    ORDER_DATE_KEY    NUMBER(8,0),
    ORDER_STATUS      VARCHAR(20),
    TOTAL_AMOUNT      NUMBER(12,2),
    CURRENCY_CODE     VARCHAR(3),
    CHANNEL           VARCHAR(20),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Grain: one row per order line';

CREATE TABLE IF NOT EXISTS FACT_ECOMM_REVENUE (
    REVENUE_DATE      DATE NOT NULL,
    CHANNEL           VARCHAR(20),
    COUNTRY           VARCHAR(50),
    ORDER_COUNT       NUMBER(10,0),
    TOTAL_REVENUE     NUMBER(15,2),
    AVG_ORDER_VALUE   NUMBER(10,2),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Daily revenue aggregation by channel and country';
