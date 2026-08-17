/* ============================================================
   Domain   : bookings
   Layer    : silver
   Release  : 1
   Sequence : 200
   Purpose  : Create all bookings silver dimension tables
   Author   : team-bookings
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA SILVER;

CREATE TABLE IF NOT EXISTS DIM_BOOKINGS_LOCATION (
    LOCATION_KEY      NUMBER(38,0) AUTOINCREMENT,
    LOCATION_ID       NUMBER(38,0) NOT NULL,
    LOCATION_NAME     VARCHAR(200),
    CITY              VARCHAR(100),
    STATE_PROVINCE    VARCHAR(100),
    COUNTRY           VARCHAR(50),
    REGION            VARCHAR(50),
    LOCATION_TYPE     VARCHAR(30),
    IS_ACTIVE         BOOLEAN DEFAULT TRUE
)
COMMENT = 'Location dimension for bookings';

CREATE TABLE IF NOT EXISTS DIM_BOOKINGS_CHANNEL (
    CHANNEL_KEY       NUMBER(38,0) AUTOINCREMENT,
    CHANNEL_CODE      VARCHAR(30) NOT NULL,
    CHANNEL_NAME      VARCHAR(100),
    CHANNEL_GROUP     VARCHAR(50),
    IS_ONLINE         BOOLEAN,
    IS_ACTIVE         BOOLEAN DEFAULT TRUE
)
COMMENT = 'Booking channel dimension';
