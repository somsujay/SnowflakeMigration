"""
Create Apache Iceberg tables from sample CSV files using PyIceberg + PyArrow.

This script reads the 6 CSV files (history + incremental for Customer, Account,
Transaction) and writes them as proper Apache Iceberg tables with a local
SQLite file catalog.

Output: iceberg_warehouse/ directory with Parquet data files and Iceberg metadata.
"""

import os
import shutil

import pyarrow as pa
import pyarrow.csv as pcsv
from pyiceberg.catalog.sql import SqlCatalog
from pyiceberg.schema import Schema
from pyiceberg.types import (
    DoubleType,
    NestedField,
    StringType,
    TimestampType,
    DateType,
)
from pyiceberg.partitioning import PartitionSpec

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "sample_data_file")
WAREHOUSE_DIR = os.path.join(BASE_DIR, "iceberg_warehouse")
CATALOG_DB = os.path.join(WAREHOUSE_DIR, "catalog.db")

# ---------------------------------------------------------------------------
# CSV file mapping
# ---------------------------------------------------------------------------
CSV_FILES = {
    "t_customer": [
        os.path.join(DATA_DIR, "T_Customer_history.csv"),
        os.path.join(DATA_DIR, "T_Customer_incremental.csv"),
    ],
    "t_account": [
        os.path.join(DATA_DIR, "T_Account_history.csv"),
        os.path.join(DATA_DIR, "T_Account_incremental.csv"),
    ],
    "t_transaction": [
        os.path.join(DATA_DIR, "T_Transaction_history.csv"),
        os.path.join(DATA_DIR, "T_Transaction_incremental.csv"),
    ],
}

# ---------------------------------------------------------------------------
# Iceberg schemas
# ---------------------------------------------------------------------------
CUSTOMER_SCHEMA = Schema(
    NestedField(1, "Customer_ID", StringType(), required=False),
    NestedField(2, "First_Name", StringType(), required=False),
    NestedField(3, "Last_Name", StringType(), required=False),
    NestedField(4, "Email_Address", StringType(), required=False),
    NestedField(5, "Phone_Number", StringType(), required=False),
    NestedField(6, "City", StringType(), required=False),
    NestedField(7, "State_Province", StringType(), required=False),
    NestedField(8, "Country", StringType(), required=False),
    NestedField(9, "Created_Timestamp", TimestampType(), required=False),
)

ACCOUNT_SCHEMA = Schema(
    NestedField(1, "Account_ID", StringType(), required=False),
    NestedField(2, "Customer_ID", StringType(), required=False),
    NestedField(3, "Account_Type", StringType(), required=False),
    NestedField(4, "Status", StringType(), required=False),
    NestedField(5, "Currency_Code", StringType(), required=False),
    NestedField(6, "Open_Date", DateType(), required=False),
    NestedField(7, "Created_Timestamp", TimestampType(), required=False),
)

TRANSACTION_SCHEMA = Schema(
    NestedField(1, "Transaction_ID", StringType(), required=False),
    NestedField(2, "Account_ID", StringType(), required=False),
    NestedField(3, "Transaction_Date", TimestampType(), required=False),
    NestedField(4, "Transaction_Type", StringType(), required=False),
    NestedField(5, "Amount", DoubleType(), required=False),
    NestedField(6, "Description", StringType(), required=False),
)

TABLE_SCHEMAS = {
    "t_customer": CUSTOMER_SCHEMA,
    "t_account": ACCOUNT_SCHEMA,
    "t_transaction": TRANSACTION_SCHEMA,
}

# ---------------------------------------------------------------------------
# PyArrow schemas for reading CSVs with correct types
# ---------------------------------------------------------------------------
PA_CUSTOMER_SCHEMA = pa.schema([
    ("Customer_ID", pa.string()),
    ("First_Name", pa.string()),
    ("Last_Name", pa.string()),
    ("Email_Address", pa.string()),
    ("Phone_Number", pa.string()),
    ("City", pa.string()),
    ("State_Province", pa.string()),
    ("Country", pa.string()),
    ("Created_Timestamp", pa.timestamp("us")),
])

PA_ACCOUNT_SCHEMA = pa.schema([
    ("Account_ID", pa.string()),
    ("Customer_ID", pa.string()),
    ("Account_Type", pa.string()),
    ("Status", pa.string()),
    ("Currency_Code", pa.string()),
    ("Open_Date", pa.date32()),
    ("Created_Timestamp", pa.timestamp("us")),
])

PA_TRANSACTION_SCHEMA = pa.schema([
    ("Transaction_ID", pa.string()),
    ("Account_ID", pa.string()),
    ("Transaction_Date", pa.timestamp("us")),
    ("Transaction_Type", pa.string()),
    ("Amount", pa.float64()),
    ("Description", pa.string()),
])

PA_SCHEMAS = {
    "t_customer": PA_CUSTOMER_SCHEMA,
    "t_account": PA_ACCOUNT_SCHEMA,
    "t_transaction": PA_TRANSACTION_SCHEMA,
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    # Clean previous output
    if os.path.exists(WAREHOUSE_DIR):
        shutil.rmtree(WAREHOUSE_DIR)
    os.makedirs(WAREHOUSE_DIR, exist_ok=True)

    # Create SQLite catalog
    catalog = SqlCatalog(
        "local",
        **{
            "uri": f"sqlite:///{CATALOG_DB}",
            "warehouse": f"file://{WAREHOUSE_DIR}",
        },
    )

    # Create namespace
    namespace = "teradata_migration"
    catalog.create_namespace(namespace)
    print(f"Created namespace: {namespace}")
    print(f"Warehouse path: {WAREHOUSE_DIR}")
    print("-" * 60)

    # Create tables and load data
    for table_name, csv_files in CSV_FILES.items():
        full_table_name = f"{namespace}.{table_name}"
        iceberg_schema = TABLE_SCHEMAS[table_name]
        pa_schema = PA_SCHEMAS[table_name]

        # Create Iceberg table
        table = catalog.create_table(
            full_table_name,
            schema=iceberg_schema,
            partition_spec=PartitionSpec(),
        )
        print(f"\nCreated table: {full_table_name}")

        total_rows = 0
        for csv_file in csv_files:
            # Read CSV with explicit schema
            convert_options = pcsv.ConvertOptions(column_types=pa_schema)
            arrow_table = pcsv.read_csv(
                csv_file,
                convert_options=convert_options,
            )

            # Cast to match the PyArrow schema exactly
            arrow_table = arrow_table.cast(pa_schema)

            # Append to Iceberg table
            table.append(arrow_table)

            file_label = "history" if "history" in csv_file else "incremental"
            print(f"  Loaded {file_label}: {arrow_table.num_rows} rows from {os.path.basename(csv_file)}")
            total_rows += arrow_table.num_rows

        print(f"  Total rows in {table_name}: {total_rows}")

    # Verification — identify history vs incremental files via snapshots
    print("\n" + "=" * 60)
    print("VERIFICATION - Reading back from Iceberg catalog")
    print("=" * 60)

    for table_name in CSV_FILES.keys():
        full_table_name = f"{namespace}.{table_name}"
        table = catalog.load_table(full_table_name)
        scan = table.scan()
        result = scan.to_arrow()
        print(f"\n  {table_name}: {result.num_rows} rows, {len(result.schema)} columns")
        print(f"    Columns: {result.schema.names}")

        # Identify history vs incremental using snapshots
        snapshots = table.metadata.snapshots
        print(f"    Snapshots: {len(snapshots)}")

        if len(snapshots) >= 2:
            # Snapshot 1 = history load only
            history_scan = table.scan(snapshot_id=snapshots[0].snapshot_id)
            history_rows = history_scan.to_arrow().num_rows

            # Snapshot 2 = history + incremental (full table)
            full_scan = table.scan(snapshot_id=snapshots[1].snapshot_id)
            full_rows = full_scan.to_arrow().num_rows
            incremental_rows = full_rows - history_rows

            print(f"    [Snapshot 1 - HISTORY]      : {history_rows} rows")
            print(f"    [Snapshot 2 - INCREMENTAL]  : {incremental_rows} new rows (total: {full_rows})")

        # Map data files to their snapshot (history vs incremental)
        print(f"    Data files:")
        data_dir = os.path.join(WAREHOUSE_DIR, namespace, table_name, "data")
        if os.path.exists(data_dir):
            import pyarrow.parquet as pq

            files = sorted(os.listdir(data_dir))
            # Get the file added in snapshot 1 (history) by reading snapshot 1 manifest
            history_data = table.scan(snapshot_id=snapshots[0].snapshot_id).to_arrow()
            history_count = history_data.num_rows

            for f in files:
                fpath = os.path.join(data_dir, f)
                tbl = pq.read_table(fpath)
                row_count = tbl.num_rows
                # Identify by row count matching
                if row_count == history_count:
                    label = "HISTORY"
                else:
                    label = "INCREMENTAL"
                print(f"      {f}  ->  {row_count} rows  [{label}]")

    print("\n" + "=" * 60)
    print("SUCCESS - All Iceberg tables created!")
    print(f"Output directory: {WAREHOUSE_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
