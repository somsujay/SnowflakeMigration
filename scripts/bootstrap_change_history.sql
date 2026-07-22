/* ============================================================
   bootstrap_change_history.sql
   PURPOSE : Create the METADATA schema and SCHEMACHANGE_HISTORY
             table for tracking applied migrations.

   Run this ONCE per environment before the first schemachange deploy:
     snow sql -c MY_TRIAL_ACCOUNT --database SSOM_COCO_DB -f scripts/bootstrap_change_history.sql
   ============================================================ */

CREATE SCHEMA IF NOT EXISTS METADATA
COMMENT = 'Metadata and change tracking objects for schemachange';

CREATE TABLE IF NOT EXISTS METADATA.SCHEMACHANGE_HISTORY (
    VERSION VARCHAR(50) NOT NULL,
    DESCRIPTION VARCHAR(200) NOT NULL,
    SCRIPT VARCHAR(500) NOT NULL,
    SCRIPT_TYPE VARCHAR(20) NOT NULL,
    CHECKSUM VARCHAR(64) NOT NULL,
    EXECUTION_TIME INTEGER NOT NULL,
    STATUS VARCHAR(20) NOT NULL,
    INSTALLED_BY VARCHAR(100) NOT NULL,
    INSTALLED_ON TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
