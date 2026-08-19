/* ============================================================
   Domain   : bookings
   Layer    : gold
   Release  : 1
   Sequence : 300
   Purpose  : Create all bookings gold fact tables
   Author   : team-bookings
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE TABLE IF NOT EXISTS FACT_BOOKINGS (
    BOOKING_KEY       NUMBER(38,0) AUTOINCREMENT,
    RESERVATION_ID    NUMBER(38,0) NOT NULL,
    CUSTOMER_KEY      NUMBER(38,0),
    LOCATION_KEY      NUMBER(38,0),
    CHANNEL_KEY       NUMBER(38,0),
    CHECK_IN_DATE_KEY NUMBER(8,0),
    CHECK_OUT_DATE_KEY NUMBER(8,0),
    NIGHTS_STAYED     NUMBER(5,0),
    TOTAL_PRICE       NUMBER(12,2),
    STATUS            VARCHAR(20),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Grain: one row per reservation';

CREATE TABLE IF NOT EXISTS FACT_BOOKINGS_OCCUPANCY (
    OCCUPANCY_DATE    DATE NOT NULL,
    LOCATION_KEY      NUMBER(38,0),
    TOTAL_CAPACITY    NUMBER(10,0),
    BOOKED_COUNT      NUMBER(10,0),
    OCCUPANCY_RATE    NUMBER(5,2),
    REVENUE           NUMBER(12,2),
    CREATED_AT        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Daily occupancy metrics by location';
