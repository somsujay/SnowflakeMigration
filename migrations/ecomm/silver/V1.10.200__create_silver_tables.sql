/* ============================================================
   Domain   : ecomm
   Layer    : silver
   Release  : 1
   Sequence : 200
   Purpose  : Create all ecomm silver dimension tables
   Author   : team-ecomm
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS DIM_ECOMM_PRODUCT (
    PRODUCT_KEY       NUMBER(38,0) AUTOINCREMENT,
    PRODUCT_ID        NUMBER(38,0) NOT NULL,
    PRODUCT_NAME      VARCHAR(200),
    CATEGORY          VARCHAR(100),
    SUBCATEGORY       VARCHAR(100),
    UNIT_PRICE        NUMBER(10,2),
    IS_ACTIVE         BOOLEAN,
    EFFECTIVE_FROM    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EFFECTIVE_TO      TIMESTAMP_NTZ,
    IS_CURRENT        BOOLEAN DEFAULT TRUE
)
COMMENT = 'SCD-2 product dimension';

CREATE TABLE IF NOT EXISTS DIM_ECOMM_CUSTOMER (
    CUSTOMER_KEY      NUMBER(38,0) AUTOINCREMENT,
    CUSTOMER_ID       NUMBER(38,0) NOT NULL,
    FIRST_NAME        VARCHAR(100),
    LAST_NAME         VARCHAR(100),
    FULL_NAME         VARCHAR(201),
    EMAIL             VARCHAR(200),
    COUNTRY           VARCHAR(50),
    REGION            VARCHAR(50),
    CUSTOMER_SEGMENT  VARCHAR(20),
    EFFECTIVE_FROM    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EFFECTIVE_TO      TIMESTAMP_NTZ,
    IS_CURRENT        BOOLEAN DEFAULT TRUE
)
COMMENT = 'SCD-2 customer dimension';
