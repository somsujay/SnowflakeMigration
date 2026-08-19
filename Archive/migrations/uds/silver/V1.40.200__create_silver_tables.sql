/* ============================================================
   Domain   : uds
   Layer    : silver
   Release  : 1
   Sequence : 200
   Purpose  : Create all UDS silver dimension tables
   Author   : team-uds
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS DIM_UDS_MASTER_CUSTOMER (
    MASTER_CUSTOMER_KEY NUMBER(38,0) AUTOINCREMENT,
    UNIFIED_CUSTOMER_ID NUMBER(38,0) NOT NULL,
    FIRST_NAME          VARCHAR(100),
    LAST_NAME           VARCHAR(100),
    FULL_NAME           VARCHAR(201),
    PRIMARY_EMAIL       VARCHAR(200),
    PRIMARY_PHONE       VARCHAR(30),
    COUNTRY             VARCHAR(50),
    REGION              VARCHAR(50),
    FIRST_SEEN_DATE     DATE,
    LAST_ACTIVITY_DATE  DATE,
    LIFETIME_VALUE      NUMBER(15,2),
    CUSTOMER_SEGMENT    VARCHAR(30),
    DOMAINS_ACTIVE      VARIANT,
    IS_ACTIVE           BOOLEAN DEFAULT TRUE
)
COMMENT = 'Golden record - single view of customer across all domains';

CREATE TABLE IF NOT EXISTS DIM_UDS_CUSTOMER_TIMELINE (
    TIMELINE_KEY        NUMBER(38,0) AUTOINCREMENT,
    MASTER_CUSTOMER_KEY NUMBER(38,0),
    ACTIVITY_DATE       DATE NOT NULL,
    SOURCE_DOMAIN       VARCHAR(30),
    EVENT_TYPE          VARCHAR(50),
    EVENT_COUNT         NUMBER(10,0),
    REVENUE_AMOUNT      NUMBER(12,2)
)
COMMENT = 'Daily activity summary per customer per domain';
