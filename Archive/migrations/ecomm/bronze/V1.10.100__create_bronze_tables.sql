/* ============================================================
   Domain   : ecomm
   Layer    : bronze
   Release  : 1
   Sequence : 100
   Purpose  : Create all ecomm bronze staging tables
   Author   : team-ecomm
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE TABLE IF NOT EXISTS T_ECOMM_ORDERS (
    ORDER_ID          NUMBER(38,0) NOT NULL,
    CUSTOMER_ID       NUMBER(38,0) NOT NULL,
    ORDER_DATE        TIMESTAMP_NTZ,
    ORDER_STATUS      VARCHAR(20),
    TOTAL_AMOUNT      NUMBER(12,2),
    CURRENCY_CODE     VARCHAR(3),
    CHANNEL           VARCHAR(20),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw e-commerce orders from source system';

CREATE TABLE IF NOT EXISTS T_ECOMM_PRODUCTS (
    PRODUCT_ID        NUMBER(38,0) NOT NULL,
    PRODUCT_NAME      VARCHAR(200),
    CATEGORY          VARCHAR(100),
    SUBCATEGORY       VARCHAR(100),
    UNIT_PRICE        NUMBER(10,2),
    IS_ACTIVE         BOOLEAN DEFAULT TRUE,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw product catalog from source system';

CREATE TABLE IF NOT EXISTS T_ECOMM_CUSTOMERS (
    CUSTOMER_ID       NUMBER(38,0) NOT NULL,
    FIRST_NAME        VARCHAR(100),
    LAST_NAME         VARCHAR(100),
    EMAIL             VARCHAR(200),
    PHONE             VARCHAR(30),
    COUNTRY           VARCHAR(50),
    REGION            VARCHAR(50),
    CREATED_DATE      DATE,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw customer data from source system';
