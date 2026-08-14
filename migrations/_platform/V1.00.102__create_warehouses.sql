/* ============================================================
   Domain   : _platform
   Layer    : infrastructure
   Release  : 1
   Sequence : 102
   Purpose  : Create compute warehouses
   Author   : team-platform
   ============================================================ */

CREATE WAREHOUSE IF NOT EXISTS {{ warehouse }}
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
