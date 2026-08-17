/* ============================================================
   schemachange Migration: V1.9.0__data_quality.sql
   PURPOSE : Data quality log table creation
   NOTE: Procedures are in R__data_quality_procedures.sql
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA GOVERNANCE;

CREATE TABLE IF NOT EXISTS GOVERNANCE.DATA_QUALITY_LOG (
    LOG_ID INTEGER AUTOINCREMENT,
    RUN_ID VARCHAR(50) NOT NULL,
    CHECK_TIMESTAMP TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TABLE_NAME VARCHAR(100) NOT NULL,
    CHECK_NAME VARCHAR(100) NOT NULL,
    SEVERITY VARCHAR(20) NOT NULL,
    RECORDS_FAILED INTEGER DEFAULT 0,
    SAMPLE_IDS VARCHAR(2000),
    DETAILS VARCHAR(4000)
);
