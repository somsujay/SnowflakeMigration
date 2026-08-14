/* ============================================================
   schemachange Migration: V1.1.1__bronze_tables.sql
   PURPOSE : Bronze layer DDL - raw staging tables
   ============================================================ */

USE DATABASE {{ database }};
USE SCHEMA BRONZE;
ALTER TABLE BRONZE.T_CUSTOMER
    ADD COLUMN COUNTRY1 VARCHAR(50);
