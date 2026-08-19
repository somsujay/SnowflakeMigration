/* ============================================================
   Domain   : uds
   Layer    : bronze
   Release  : 1
   Sequence : 100
   Purpose  : Create all UDS bronze staging tables
   Author   : team-uds
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE TABLE IF NOT EXISTS T_UDS_UNIFIED_CUSTOMER (
    UNIFIED_CUSTOMER_ID NUMBER(38,0) AUTOINCREMENT,
    SOURCE_DOMAIN       VARCHAR(30) NOT NULL,
    SOURCE_CUSTOMER_ID  NUMBER(38,0) NOT NULL,
    FIRST_NAME          VARCHAR(100),
    LAST_NAME           VARCHAR(100),
    EMAIL               VARCHAR(200),
    PHONE               VARCHAR(30),
    COUNTRY             VARCHAR(50),
    MATCH_CONFIDENCE    NUMBER(3,2),
    LOADED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Unified customer identities across ecomm, bookings, aftermarket';

CREATE TABLE IF NOT EXISTS T_UDS_UNIFIED_EVENTS (
    EVENT_ID            NUMBER(38,0) AUTOINCREMENT,
    UNIFIED_CUSTOMER_ID NUMBER(38,0),
    SOURCE_DOMAIN       VARCHAR(30) NOT NULL,
    EVENT_TYPE          VARCHAR(50) NOT NULL,
    EVENT_TIMESTAMP     TIMESTAMP_NTZ NOT NULL,
    EVENT_DETAILS       VARIANT,
    SOURCE_RECORD_ID    NUMBER(38,0),
    LOADED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Cross-domain customer activity events';
