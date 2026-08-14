/* ============================================================
   Domain   : bookings
   Layer    : gold
   Purpose  : Repeatable - Business views for bookings reporting
   Author   : team-bookings
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOLD;

CREATE OR REPLACE VIEW V_BOOKINGS_SUMMARY AS
SELECT
    f.CHECK_IN_DATE_KEY,
    l.LOCATION_NAME,
    l.CITY,
    l.COUNTRY,
    c.CHANNEL_NAME,
    f.NIGHTS_STAYED,
    f.TOTAL_PRICE,
    f.STATUS
FROM FACT_BOOKINGS f
LEFT JOIN {{ database }}.SILVER.DIM_BOOKINGS_LOCATION l
    ON f.LOCATION_KEY = l.LOCATION_KEY
LEFT JOIN {{ database }}.SILVER.DIM_BOOKINGS_CHANNEL c
    ON f.CHANNEL_KEY = c.CHANNEL_KEY;
