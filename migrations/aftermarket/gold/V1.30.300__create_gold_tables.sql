/* ============================================================
   Domain   : aftermarket
   Layer    : gold
   Release  : 1
   Sequence : 300
   Purpose  : Create all aftermarket gold fact tables
   Author   : team-aftermarket
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE TABLE IF NOT EXISTS FACT_AM_SERVICE (
    SERVICE_KEY       NUMBER(38,0) AUTOINCREMENT,
    SERVICE_ORDER_ID  NUMBER(38,0) NOT NULL,
    CUSTOMER_KEY      NUMBER(38,0),
    ORIGINAL_ORDER_KEY NUMBER(38,0),
    SERVICE_TYPE_KEY  NUMBER(38,0),
    CREATED_DATE_KEY  NUMBER(8,0),
    RESOLVED_DATE_KEY NUMBER(8,0),
    PRIORITY          VARCHAR(10),
    STATUS            VARCHAR(20),
    RESOLUTION_DAYS   NUMBER(5,0),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Grain: one row per service order';

CREATE TABLE IF NOT EXISTS FACT_AM_WARRANTY (
    WARRANTY_KEY      NUMBER(38,0) AUTOINCREMENT,
    CLAIM_ID          NUMBER(38,0) NOT NULL,
    CUSTOMER_KEY      NUMBER(38,0),
    PRODUCT_KEY       NUMBER(38,0),
    SERVICE_ORDER_KEY NUMBER(38,0),
    CLAIM_DATE_KEY    NUMBER(8,0),
    CLAIM_TYPE        VARCHAR(30),
    CLAIM_AMOUNT      NUMBER(10,2),
    STATUS            VARCHAR(20),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Grain: one row per warranty claim';
