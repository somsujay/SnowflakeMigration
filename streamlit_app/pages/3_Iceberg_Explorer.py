import streamlit as st
import pandas as pd
import os
import datetime

import pyarrow.parquet as pq
from pyiceberg.catalog.sql import SqlCatalog

# ============================================================
# Page Configuration
# ============================================================
st.set_page_config(
    page_title="Iceberg Explorer",
    page_icon=":snowflake:",
    layout="wide",
)

# ============================================================
# Custom Styling
# ============================================================
st.markdown(
    """
    <style>
    /* Main container */
    .block-container { padding-top: 2rem; }

    /* Header banner */
    .page-banner {
        background: linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%);
        padding: 24px 32px;
        border-radius: 12px;
        margin-bottom: 24px;
        border: 1px solid rgba(255,255,255,0.08);
    }
    .page-banner h1 {
        color: #ffffff;
        font-size: 1.8rem;
        margin-bottom: 4px;
    }
    .page-banner p {
        color: #94a3b8;
        font-size: 0.9rem;
        margin: 0;
    }

    /* Metric cards */
    [data-testid="stMetric"] {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        border: 1px solid #2d3748;
        border-radius: 10px;
        padding: 16px 20px;
        box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    }
    [data-testid="stMetric"] label {
        color: #94a3b8 !important;
        font-size: 0.8rem !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }
    [data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: #e2e8f0 !important;
        font-size: 1.6rem !important;
        font-weight: 700;
    }

    /* Tab styling */
    .stTabs [data-baseweb="tab-list"] {
        gap: 8px;
        border-radius: 8px;
        padding: 4px;
    }
    .stTabs [data-baseweb="tab"] {
        border-radius: 6px;
        padding: 10px 24px;
        font-weight: 500;
    }
    .stTabs [aria-selected="true"] {
        background: #2563eb !important;
        color: white !important;
    }
    .stTabs [aria-selected="false"] {
        background: rgba(100, 116, 139, 0.15) !important;
        color: inherit !important;
    }

    /* Section headers */
    .section-header {
        background: linear-gradient(90deg, #1e293b 0%, #0f172a 100%);
        padding: 14px 24px;
        border-radius: 8px;
        margin-bottom: 20px;
        border-left: 4px solid #3b82f6;
        display: flex;
        align-items: center;
        gap: 12px;
    }
    .section-header h3 {
        color: #f1f5f9;
        margin: 0;
        font-size: 1.1rem;
        font-weight: 600;
    }

    /* Dataframe styling */
    .stDataFrame {
        border-radius: 8px;
        overflow: hidden;
        border: 1px solid #2d3748;
    }

    /* Footer */
    .footer-text {
        color: #64748b;
        font-size: 0.75rem;
        text-align: center;
        padding: 12px 0;
        border-top: 1px solid #1e293b;
        margin-top: 32px;
    }
    </style>
    """,
    unsafe_allow_html=True,
)


# ============================================================
# Iceberg Catalog Connection
# ============================================================
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WAREHOUSE_DIR = os.path.join(BASE_DIR, "iceberg_warehouse")
CATALOG_DB = os.path.join(WAREHOUSE_DIR, "catalog.db")
NAMESPACE = "teradata_migration"


@st.cache_resource
def get_catalog():
    return SqlCatalog(
        "local",
        **{
            "uri": f"sqlite:///{CATALOG_DB}",
            "warehouse": f"file://{WAREHOUSE_DIR}",
        },
    )


@st.cache_data(ttl=300)
def load_iceberg_metadata():
    """Load all metadata from the Iceberg catalog."""
    catalog = get_catalog()
    tables_info = []

    for table_id in catalog.list_tables(NAMESPACE):
        table_name = table_id[1]
        full_name = f"{NAMESPACE}.{table_name}"
        table = catalog.load_table(full_name)

        # Get total rows
        total_rows = table.scan().to_arrow().num_rows

        # Get snapshots
        snapshots = table.metadata.snapshots
        history_rows = 0
        incremental_rows = 0

        if len(snapshots) >= 1:
            history_rows = table.scan(snapshot_id=snapshots[0].snapshot_id).to_arrow().num_rows
        if len(snapshots) >= 2:
            full_rows = table.scan(snapshot_id=snapshots[1].snapshot_id).to_arrow().num_rows
            incremental_rows = full_rows - history_rows

        # Get data files info
        data_dir = os.path.join(WAREHOUSE_DIR, NAMESPACE, table_name, "data")
        data_files = []
        if os.path.exists(data_dir):
            for f in sorted(os.listdir(data_dir)):
                fpath = os.path.join(data_dir, f)
                tbl = pq.read_table(fpath)
                row_count = tbl.num_rows
                file_size = os.path.getsize(fpath)
                label = "History" if row_count == history_rows else "Incremental"
                data_files.append({
                    "file_name": f,
                    "rows": row_count,
                    "size_bytes": file_size,
                    "load_type": label,
                })

        # Get schema info
        schema_fields = []
        for field in table.schema().fields:
            schema_fields.append({
                "field_id": field.field_id,
                "name": field.name,
                "type": str(field.field_type),
                "required": field.required,
            })

        # Snapshot details
        snapshot_details = []
        for i, snap in enumerate(snapshots):
            snap_label = "History Load" if i == 0 else "Incremental Load"
            ts = datetime.datetime.fromtimestamp(snap.timestamp_ms / 1000)
            snapshot_details.append({
                "snapshot_id": snap.snapshot_id,
                "timestamp": ts,
                "operation": snap_label,
                "summary": snap.summary if snap.summary else {},
            })

        tables_info.append({
            "table_name": table_name,
            "full_name": full_name,
            "total_rows": total_rows,
            "columns": len(schema_fields),
            "history_rows": history_rows,
            "incremental_rows": incremental_rows,
            "snapshots": snapshot_details,
            "data_files": data_files,
            "schema": schema_fields,
        })

    return tables_info


# ============================================================
# Page Header
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>Apache Iceberg Explorer</h1>
        <p>Local Iceberg Warehouse &nbsp;|&nbsp; PyIceberg + PyArrow &nbsp;|&nbsp; Parquet Data + Iceberg Metadata</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# Load data
tables_info = load_iceberg_metadata()

# ============================================================
# Summary Metrics
# ============================================================
total_tables = len(tables_info)
total_rows = sum(t["total_rows"] for t in tables_info)
total_snapshots = sum(len(t["snapshots"]) for t in tables_info)
total_files = sum(len(t["data_files"]) for t in tables_info)

col1, col2, col3, col4 = st.columns(4)
col1.metric("Tables", total_tables)
col2.metric("Total Rows", f"{total_rows:,}")
col3.metric("Snapshots", total_snapshots)
col4.metric("Data Files", total_files)

st.markdown("<br>", unsafe_allow_html=True)

# ============================================================
# Tabs
# ============================================================
tab1, tab2, tab3, tab4 = st.tabs([
    "Table Overview",
    "Snapshot Timeline",
    "Data Files",
    "Schema Details",
])

# ============================================================
# Tab 1: Table Overview
# ============================================================
with tab1:
    st.markdown(
        '<div class="section-header"><h3>Iceberg Tables Summary</h3></div>',
        unsafe_allow_html=True,
    )

    overview_data = []
    for t in tables_info:
        overview_data.append({
            "Table": t["table_name"],
            "Columns": t["columns"],
            "Total Rows": f"{t['total_rows']:,}",
            "History Rows": f"{t['history_rows']:,}",
            "Incremental Rows": f"{t['incremental_rows']:,}",
            "Snapshots": len(t["snapshots"]),
            "Data Files": len(t["data_files"]),
        })

    df_overview = pd.DataFrame(overview_data)
    st.dataframe(
        df_overview,
        use_container_width=True,
        hide_index=True,
        column_config={
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "Columns": st.column_config.NumberColumn("Columns", width="small"),
            "Total Rows": st.column_config.TextColumn("Total Rows", width="small"),
            "History Rows": st.column_config.TextColumn("History Rows", width="small"),
            "Incremental Rows": st.column_config.TextColumn("Incremental Rows", width="small"),
            "Snapshots": st.column_config.NumberColumn("Snapshots", width="small"),
            "Data Files": st.column_config.NumberColumn("Data Files", width="small"),
        },
    )

    # Per-table detail expanders
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Per-Table Details</h3></div>',
        unsafe_allow_html=True,
    )

    for t in tables_info:
        with st.expander(f"{t['table_name']} — {t['total_rows']:,} rows, {t['columns']} columns"):
            col_a, col_b, col_c = st.columns(3)
            col_a.metric("History", f"{t['history_rows']:,} rows")
            col_b.metric("Incremental", f"{t['incremental_rows']:,} rows")
            col_c.metric("Total", f"{t['total_rows']:,} rows")

            st.markdown("**Columns:**")
            col_names = [f["name"] for f in t["schema"]]
            st.code(", ".join(col_names))

            st.markdown("**Data Files:**")
            for df_info in t["data_files"]:
                size_kb = df_info["size_bytes"] / 1024
                st.text(
                    f"  {df_info['file_name']}\n"
                    f"    Rows: {df_info['rows']:,}  |  Size: {size_kb:.1f} KB  |  Type: {df_info['load_type']}"
                )


# ============================================================
# Tab 2: Snapshot Timeline
# ============================================================
with tab2:
    st.markdown(
        '<div class="section-header"><h3>Snapshot History</h3></div>',
        unsafe_allow_html=True,
    )

    snapshot_data = []
    for t in tables_info:
        prev_rows = 0
        for i, snap in enumerate(t["snapshots"]):
            if i == 0:
                rows_added = t["history_rows"]
            else:
                rows_added = t["incremental_rows"]
            prev_rows += rows_added

            snapshot_data.append({
                "Table": t["table_name"],
                "Snapshot #": i + 1,
                "Operation": snap["operation"],
                "Timestamp": snap["timestamp"].strftime("%Y-%m-%d %H:%M:%S"),
                "Rows Added": f"+{rows_added:,}",
                "Cumulative Rows": f"{prev_rows:,}",
                "Snapshot ID": str(snap["snapshot_id"]),
            })

    df_snapshots = pd.DataFrame(snapshot_data)
    st.dataframe(
        df_snapshots,
        use_container_width=True,
        hide_index=True,
        column_config={
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "Snapshot #": st.column_config.NumberColumn("#", width="small"),
            "Operation": st.column_config.TextColumn("Operation", width="medium"),
            "Timestamp": st.column_config.TextColumn("Timestamp", width="medium"),
            "Rows Added": st.column_config.TextColumn("Rows Added", width="small"),
            "Cumulative Rows": st.column_config.TextColumn("Cumulative", width="small"),
            "Snapshot ID": st.column_config.TextColumn("Snapshot ID", width="large"),
        },
    )

    # Visual timeline
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Visual Timeline</h3></div>',
        unsafe_allow_html=True,
    )

    for t in tables_info:
        st.markdown(f"**{t['table_name']}**")
        cols = st.columns(len(t["snapshots"]))
        for i, (col, snap) in enumerate(zip(cols, t["snapshots"])):
            with col:
                rows = t["history_rows"] if i == 0 else t["incremental_rows"]
                color = "#3b82f6" if i == 0 else "#10b981"
                st.markdown(
                    f"""
                    <div style="background: {color}; border-radius: 8px; padding: 12px 16px;
                                text-align: center; color: white;">
                        <div style="font-size: 0.75rem; opacity: 0.8;">{snap['operation']}</div>
                        <div style="font-size: 1.4rem; font-weight: 700;">+{rows:,}</div>
                        <div style="font-size: 0.7rem; opacity: 0.7;">{snap['timestamp'].strftime('%H:%M:%S')}</div>
                    </div>
                    """,
                    unsafe_allow_html=True,
                )
        st.markdown("<br>", unsafe_allow_html=True)


# ============================================================
# Tab 3: Data Files
# ============================================================
with tab3:
    st.markdown(
        '<div class="section-header"><h3>Parquet Data Files</h3></div>',
        unsafe_allow_html=True,
    )

    files_data = []
    for t in tables_info:
        for df_info in t["data_files"]:
            size_kb = df_info["size_bytes"] / 1024
            files_data.append({
                "Table": t["table_name"],
                "File Name": df_info["file_name"],
                "Load Type": df_info["load_type"],
                "Rows": f"{df_info['rows']:,}",
                "Size (KB)": f"{size_kb:.1f}",
            })

    df_files = pd.DataFrame(files_data)
    st.dataframe(
        df_files,
        use_container_width=True,
        hide_index=True,
        column_config={
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "File Name": st.column_config.TextColumn("File Name", width="large"),
            "Load Type": st.column_config.TextColumn("Load Type", width="small"),
            "Rows": st.column_config.TextColumn("Rows", width="small"),
            "Size (KB)": st.column_config.TextColumn("Size (KB)", width="small"),
        },
    )

    # File preview section
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Data Preview</h3></div>',
        unsafe_allow_html=True,
    )

    for t in tables_info:
        for df_info in t["data_files"]:
            label = f"{t['table_name']} / {df_info['load_type']} ({df_info['rows']:,} rows)"
            with st.expander(label):
                fpath = os.path.join(
                    WAREHOUSE_DIR, NAMESPACE, t["table_name"], "data", df_info["file_name"]
                )
                preview = pq.read_table(fpath).to_pandas().head(5)
                st.dataframe(preview, use_container_width=True, hide_index=True)


# ============================================================
# Tab 4: Schema Details
# ============================================================
with tab4:
    st.markdown(
        '<div class="section-header"><h3>Iceberg Table Schemas</h3></div>',
        unsafe_allow_html=True,
    )

    for t in tables_info:
        st.markdown(f"#### {t['table_name']}")

        schema_data = []
        for field in t["schema"]:
            schema_data.append({
                "ID": field["field_id"],
                "Column Name": field["name"],
                "Iceberg Type": field["type"],
                "Required": "Yes" if field["required"] else "No",
            })

        df_schema = pd.DataFrame(schema_data)
        st.dataframe(
            df_schema,
            use_container_width=True,
            hide_index=True,
            column_config={
                "ID": st.column_config.NumberColumn("ID", width="small"),
                "Column Name": st.column_config.TextColumn("Column Name", width="medium"),
                "Iceberg Type": st.column_config.TextColumn("Iceberg Type", width="medium"),
                "Required": st.column_config.TextColumn("Required", width="small"),
            },
        )
        st.markdown("<br>", unsafe_allow_html=True)


# ============================================================
# Footer
# ============================================================
st.markdown(
    """
    <div class="footer-text">
        Apache Iceberg &nbsp;&bull;&nbsp; PyIceberg + PyArrow &nbsp;&bull;&nbsp;
        Local SQLite Catalog &nbsp;&bull;&nbsp; Parquet Data Format
    </div>
    """,
    unsafe_allow_html=True,
)
