/* ============================================================
   FILE    : 11_iceberg_objects.sql
   PURPOSE : Create objects for Iceberg/Parquet-based ingestion
             as an alternative to CSV loading via Named Stage.

   Objects Created:
       - BRONZE.PARQUET_FORMAT    : File format for Parquet files
       - BRONZE.ICEBERG_STAGE     : Named stage for Parquet file uploads

   NOTES:
       - This provides a second ingestion path alongside the CSV
         stage (BRONZE.DATA_STAGE) created in 08_seed_data.sql
       - Parquet files from the local iceberg_warehouse/ directory
         are uploaded here, then COPY INTO loads them into the
         same Bronze tables used by the CSV path
       - Downstream ETL (Silver/Gold) is completely unchanged
   ============================================================ */


-- ----------------------------------------------------------
-- Parquet file format for Iceberg/Parquet ingestion
-- ----------------------------------------------------------
CREATE OR REPLACE FILE FORMAT BRONZE.PARQUET_FORMAT
    TYPE = PARQUET;


/* ============================================================
   NAMED STAGE for Parquet ingestion

   All Parquet files are organized by subdirectory path:
     @BRONZE.ICEBERG_STAGE/customer/    → T_Customer Parquet files
     @BRONZE.ICEBERG_STAGE/account/     → T_Account Parquet files
     @BRONZE.ICEBERG_STAGE/transaction/ → T_Transaction Parquet files
   ============================================================ */

CREATE OR REPLACE STAGE BRONZE.ICEBERG_STAGE
    FILE_FORMAT = BRONZE.PARQUET_FORMAT
    COMMENT = 'Named stage for Parquet/Iceberg data ingestion';


/* ==========================================================
   USAGE INSTRUCTIONS
   ==========================================================

   1. UPLOAD PARQUET FILES:
      ----------------------------------------------------------
      PUT file:///path/to/iceberg_warehouse/teradata_migration/t_customer/data/*.parquet
          @BRONZE.ICEBERG_STAGE/customer/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
      PUT file:///path/to/iceberg_warehouse/teradata_migration/t_account/data/*.parquet
          @BRONZE.ICEBERG_STAGE/account/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;
      PUT file:///path/to/iceberg_warehouse/teradata_migration/t_transaction/data/*.parquet
          @BRONZE.ICEBERG_STAGE/transaction/ AUTO_COMPRESS=FALSE OVERWRITE=TRUE;

   2. LOAD INTO BRONZE TABLES:
      ----------------------------------------------------------
      COPY INTO BRONZE.T_Customer (Customer_ID, First_Name, Last_Name,
          Email_Address, Phone_Number, City, State_Province, Country,
          Created_Timestamp)
      FROM (SELECT $1:Customer_ID::VARCHAR, $1:First_Name::VARCHAR,
                   $1:Last_Name::VARCHAR, $1:Email_Address::VARCHAR,
                   $1:Phone_Number::VARCHAR, $1:City::VARCHAR,
                   $1:State_Province::VARCHAR, $1:Country::VARCHAR,
                   $1:Created_Timestamp::TIMESTAMP_NTZ
            FROM @BRONZE.ICEBERG_STAGE/customer/)
      FILE_FORMAT = (FORMAT_NAME = 'BRONZE.PARQUET_FORMAT');

   3. LIST FILES IN STAGE:
      ----------------------------------------------------------
      LIST @BRONZE.ICEBERG_STAGE;
      LIST @BRONZE.ICEBERG_STAGE/customer/;

   4. CLEAN UP:
      ----------------------------------------------------------
      REMOVE @BRONZE.ICEBERG_STAGE/customer/;
      REMOVE @BRONZE.ICEBERG_STAGE/account/;
      REMOVE @BRONZE.ICEBERG_STAGE/transaction/;

   ========================================================== */
