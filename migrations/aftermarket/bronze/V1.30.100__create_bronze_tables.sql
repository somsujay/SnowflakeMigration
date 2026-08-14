/* ============================================================
   Domain   : aftermarket
   Layer    : bronze
   Release  : 1
   Sequence : 100
   Purpose  : Create all aftermarket bronze staging tables
   Author   : team-aftermarket
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE TABLE IF NOT EXISTS T_AM_SERVICE_ORDERS (
    SERVICE_ORDER_ID  NUMBER(38,0) NOT NULL,
    CUSTOMER_ID       NUMBER(38,0) NOT NULL,
    ORIGINAL_ORDER_ID NUMBER(38,0),
    SERVICE_TYPE      VARCHAR(30),
    STATUS            VARCHAR(20),
    PRIORITY          VARCHAR(10),
    DESCRIPTION       VARCHAR(500),
    CREATED_DATE      TIMESTAMP_NTZ,
    RESOLVED_DATE     TIMESTAMP_NTZ,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw service orders - references ecomm orders via ORIGINAL_ORDER_ID';

CREATE TABLE IF NOT EXISTS T_AM_PARTS_INVENTORY (
    PART_ID           NUMBER(38,0) NOT NULL,
    PART_NAME         VARCHAR(200),
    PART_CATEGORY     VARCHAR(100),
    UNIT_COST         NUMBER(10,2),
    QUANTITY_ON_HAND  NUMBER(10,0),
    REORDER_POINT     NUMBER(10,0),
    SUPPLIER_ID       NUMBER(38,0),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw parts inventory from aftermarket system';

CREATE TABLE IF NOT EXISTS T_AM_WARRANTY_CLAIMS (
    CLAIM_ID          NUMBER(38,0) NOT NULL,
    SERVICE_ORDER_ID  NUMBER(38,0),
    PRODUCT_ID        NUMBER(38,0),
    CUSTOMER_ID       NUMBER(38,0),
    CLAIM_DATE        DATE,
    CLAIM_TYPE        VARCHAR(30),
    CLAIM_AMOUNT      NUMBER(10,2),
    STATUS            VARCHAR(20),
    RESOLUTION        VARCHAR(200),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw warranty claims from aftermarket system';
