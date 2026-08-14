/* ============================================================
   Domain   : orchestration
   Layer    : n/a
   Purpose  : Repeatable - Ingestion tasks for all domains
   Author   : team-platform
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

-- Ecomm ingestion task
CREATE OR REPLACE TASK TSK_INGEST_ECOMM_ORDERS
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON 0 */2 * * * UTC'
    COMMENT = 'Ingest ecomm orders every 2 hours'
AS
    CALL SP_INGEST_ECOMM_ORDERS();

-- Bookings ingestion task
CREATE OR REPLACE TASK TSK_INGEST_BOOKINGS
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON 0 */4 * * * UTC'
    COMMENT = 'Ingest bookings every 4 hours'
AS
    CALL SP_INGEST_BOOKINGS();

-- Aftermarket ingestion task
CREATE OR REPLACE TASK TSK_INGEST_AFTERMARKET
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON 0 6 * * * UTC'
    COMMENT = 'Ingest aftermarket data daily at 6am UTC'
AS
    CALL SP_INGEST_AFTERMARKET();

-- UDS unification task (runs after all domain ingestion)
CREATE OR REPLACE TASK TSK_UDS_UNIFY_CUSTOMERS
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON 0 8 * * * UTC'
    COMMENT = 'Unify customers across domains daily at 8am UTC'
AS
    CALL SP_UDS_UNIFY_CUSTOMERS();
