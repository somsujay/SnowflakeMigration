/* ============================================================
   Domain   : orchestration
   Layer    : n/a
   Release  : 1
   Sequence : 100
   Purpose  : Create orchestration framework (parent task + DAG)
   Author   : team-platform
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;

-- Master orchestration task - parent of all domain pipelines
CREATE TASK IF NOT EXISTS TSK_MASTER_PIPELINE
    WAREHOUSE = '{{ warehouse }}'
    SCHEDULE = 'USING CRON 0 1 * * * UTC'
    COMMENT = 'Master pipeline trigger - runs daily at 1am UTC'
AS
    SELECT CURRENT_TIMESTAMP();
