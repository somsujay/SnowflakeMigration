/* ============================================================
   Domain   : bookings
   Layer    : bronze
   Release  : 1
   Sequence : 100
   Purpose  : Create all bookings bronze staging tables
   Author   : team-bookings
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

CREATE TABLE IF NOT EXISTS T_BOOKINGS_RESERVATIONS (
    RESERVATION_ID    NUMBER(38,0) NOT NULL,
    CUSTOMER_ID       NUMBER(38,0) NOT NULL,
    LOCATION_ID       NUMBER(38,0),
    CHECK_IN_DATE     DATE,
    CHECK_OUT_DATE    DATE,
    STATUS            VARCHAR(20),
    TOTAL_PRICE       NUMBER(12,2),
    BOOKING_CHANNEL   VARCHAR(30),
    BOOKED_AT         TIMESTAMP_NTZ,
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Raw reservation data from booking system';

CREATE TABLE IF NOT EXISTS T_BOOKINGS_AVAILABILITY (
    LOCATION_ID       NUMBER(38,0) NOT NULL,
    AVAILABLE_DATE    DATE NOT NULL,
    TOTAL_CAPACITY    NUMBER(10,0),
    BOOKED_COUNT      NUMBER(10,0),
    AVAILABLE_COUNT   NUMBER(10,0),
    PRICE_PER_UNIT    NUMBER(10,2),
    LOADED_AT         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Daily availability snapshot from booking system';
