/* ============================================================
   Domain   : aftermarket
   Layer    : silver
   Release  : 1
   Sequence : 200
   Purpose  : Create all aftermarket silver dimension tables
   Author   : team-aftermarket
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS DIM_AM_PARTS (
    PART_KEY          NUMBER(38,0) AUTOINCREMENT,
    PART_ID           NUMBER(38,0) NOT NULL,
    PART_NAME         VARCHAR(200),
    PART_CATEGORY     VARCHAR(100),
    UNIT_COST         NUMBER(10,2),
    SUPPLIER_ID       NUMBER(38,0),
    IS_ACTIVE         BOOLEAN DEFAULT TRUE
)
COMMENT = 'Parts dimension for aftermarket analysis';

CREATE TABLE IF NOT EXISTS DIM_AM_SERVICE_TYPE (
    SERVICE_TYPE_KEY  NUMBER(38,0) AUTOINCREMENT,
    SERVICE_TYPE_CODE VARCHAR(30) NOT NULL,
    SERVICE_TYPE_NAME VARCHAR(100),
    CATEGORY          VARCHAR(50),
    AVG_RESOLUTION_DAYS NUMBER(5,1),
    IS_ACTIVE         BOOLEAN DEFAULT TRUE
)
COMMENT = 'Service type dimension for aftermarket';
