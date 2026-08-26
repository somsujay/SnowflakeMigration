import streamlit as st
import snowflake.connector
import pandas as pd

# ============================================================
# Page Configuration
# ============================================================
st.set_page_config(
    page_title="Data Load Stats",
    page_icon=":bar_chart:",
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

    /* Layer badges */
    .badge-bronze {
        background: linear-gradient(135deg, #92400e, #b45309);
        color: white;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .badge-silver {
        background: linear-gradient(135deg, #475569, #64748b);
        color: white;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .badge-gold {
        background: linear-gradient(135deg, #a16207, #ca8a04);
        color: white;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 600;
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
# Snowflake Connection
# ============================================================
@st.cache_resource
def get_connection():
    params = {
        "account": st.secrets["snowflake"]["account"],
        "user": st.secrets["snowflake"]["user"],
        "warehouse": st.secrets["snowflake"]["warehouse"],
        "database": st.secrets["snowflake"]["database"],
        "role": st.secrets["snowflake"]["role"],
    }
    if "authenticator" in st.secrets["snowflake"]:
        params["authenticator"] = st.secrets["snowflake"]["authenticator"]
    if "password" in st.secrets["snowflake"]:
        params["password"] = st.secrets["snowflake"]["password"]
    return snowflake.connector.connect(**params)


def get_row_count(schema: str, table: str) -> int:
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(f"SELECT COUNT(*) FROM SSOM_COCO_DB.{schema}.{table}")
        result = cur.fetchone()[0]
        cur.close()
        return result
    except Exception:
        return 0


# ============================================================
# Baseline Constants (History Load)
# ============================================================
HISTORY_BASELINE = {
    ("Bronze", "T_Customer"): 20,
    ("Bronze", "T_Account"): 35,
    ("Bronze", "T_Transaction"): 100,
    ("Silver", "DimCustomer (SCD-2)"): 20,
    ("Silver", "DimAccount (SCD-1)"): 35,
    ("Silver", "DimTransactionType"): 4,
    ("Silver", "DimDate"): 4018,
    ("Gold", "FactDailyTransaction"): 100,
    ("Gold", "FactDailyAgg"): 375,
}

TABLE_MAP = {
    ("Bronze", "T_Customer"): ("BRONZE", "T_Customer"),
    ("Bronze", "T_Account"): ("BRONZE", "T_Account"),
    ("Bronze", "T_Transaction"): ("BRONZE", "T_Transaction"),
    ("Silver", "DimCustomer (SCD-2)"): ("SILVER", "DimCustomer"),
    ("Silver", "DimAccount (SCD-1)"): ("SILVER", "DimAccount"),
    ("Silver", "DimTransactionType"): ("SILVER", "DimTransactionType"),
    ("Silver", "DimDate"): ("SILVER", "DimDate"),
    ("Gold", "FactDailyTransaction"): ("GOLD", "FactDailyTransaction"),
    ("Gold", "FactDailyAgg"): ("GOLD", "FactDailyAgg"),
}

DELTA_NOTES = {
    ("Bronze", "T_Customer"): "new/changed customers",
    ("Bronze", "T_Account"): "new/changed accounts",
    ("Bronze", "T_Transaction"): "new transactions",
    ("Silver", "DimCustomer (SCD-2)"): "changed + new + closed records",
    ("Silver", "DimAccount (SCD-1)"): "new accounts + in-place updates",
    ("Silver", "DimTransactionType"): "no new types",
    ("Silver", "DimDate"): "no change (static)",
    ("Gold", "FactDailyTransaction"): "new daily transactions",
    ("Gold", "FactDailyAgg"): "new rollup aggregations",
}


# ============================================================
# Load Current Row Counts
# ============================================================
@st.cache_data(ttl=60)
def load_current_counts() -> dict:
    counts = {}
    for key, (schema, table) in TABLE_MAP.items():
        counts[key] = get_row_count(schema, table)
    return counts


# ============================================================
# Page Header
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>Data Load Statistics</h1>
        <p>SSOM_COCO_DB &nbsp;|&nbsp; Teradata-to-Snowflake Migration Pipeline &nbsp;|&nbsp; Medallion Architecture</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# Refresh button (right-aligned)
col_spacer, col_btn = st.columns([5, 1])
with col_btn:
    if st.button("Refresh", type="primary"):
        st.cache_data.clear()
        st.rerun()

current_counts = load_current_counts()

# ============================================================
# Empty State Check
# ============================================================
total_bronze = sum(v for k, v in current_counts.items() if k[0] == "Bronze")
total_silver = sum(v for k, v in current_counts.items() if k[0] == "Silver")
total_gold = sum(v for k, v in current_counts.items() if k[0] == "Gold")
total_all = total_bronze + total_silver + total_gold

if total_all == 0:
    st.markdown(
        """
        <div style="background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
                    border: 1px solid #334155; border-radius: 12px;
                    padding: 48px 32px; text-align: center; margin-top: 24px;">
            <p style="font-size: 2.5rem; margin-bottom: 8px;">📭</p>
            <h2 style="color: #f1f5f9; margin-bottom: 12px;">No Data Loaded</h2>
            <p style="color: #94a3b8; font-size: 1rem; max-width: 500px; margin: 0 auto;">
                The pipeline tables are empty. Run the ETL pipeline first to load data.
            </p>
            <div style="background: #0f172a; border-radius: 8px; padding: 16px 24px;
                        margin-top: 24px; display: inline-block; text-align: left;">
                <code style="color: #a5b4fc; font-size: 0.85rem;">
                    bash scripts/run_historical.sh --source=csv<br>
                    bash scripts/run_historical.sh --source=iceberg
                </code>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.stop()

# ============================================================
# Summary Metrics
# ============================================================

col1, col2, col3, col4 = st.columns(4)
col1.metric("Bronze Layer", f"{total_bronze:,}", delta="3 tables")
col2.metric("Silver Layer", f"{total_silver:,}", delta="4 tables")
col3.metric("Gold Layer", f"{total_gold:,}", delta="2 tables")
col4.metric("Total Pipeline", f"{total_all:,}", delta="9 tables")

st.markdown("<br>", unsafe_allow_html=True)

# ============================================================
# Tabs: Historical Load | Incremental Load
# ============================================================
tab1, tab2 = st.tabs(["Historical Load", "Incremental Load"])

with tab1:
    st.markdown(
        '<div class="section-header"><h3>Initial History Load via Internal Stage</h3></div>',
        unsafe_allow_html=True,
    )

    history_data = []
    for key, rows in HISTORY_BASELINE.items():
        history_data.append({
            "Layer": key[0],
            "Table": key[1],
            "Rows": f"{rows:,}",
        })

    df_history = pd.DataFrame(history_data)

    st.dataframe(
        df_history,
        use_container_width=True,
        hide_index=True,
        height=380,
        column_config={
            "Layer": st.column_config.TextColumn("Layer", width="small"),
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "Rows": st.column_config.TextColumn("Rows", width="small"),
        },
    )

    # Totals row
    total_history = sum(HISTORY_BASELINE.values())
    st.markdown(
        f"""
        <div style="background: #1e293b; border-radius: 8px; padding: 12px 24px;
                    display: flex; justify-content: space-between; align-items: center;
                    border: 1px solid #334155; margin-top: 12px;">
            <span style="color: #94a3b8; font-weight: 500;">Total Rows (History Baseline)</span>
            <span style="color: #f1f5f9; font-size: 1.2rem; font-weight: 700;">{total_history:,}</span>
        </div>
        """,
        unsafe_allow_html=True,
    )

    st.markdown("<br>", unsafe_allow_html=True)
    st.info(
        "Baseline counts from the initial history load of CSV files "
        "via Snowflake internal stages with auto-ingest streams."
    )

with tab2:
    st.markdown(
        '<div class="section-header"><h3>Incremental Load Results</h3></div>',
        unsafe_allow_html=True,
    )

    incr_data = []
    for key in HISTORY_BASELINE:
        before = HISTORY_BASELINE[key]
        after = current_counts.get(key, 0)
        delta = after - before
        delta_str = f"+{delta:,}" if delta >= 0 else f"{delta:,}"
        note = DELTA_NOTES.get(key, "")
        delta_display = f"{delta_str} ({note})" if note else delta_str

        incr_data.append({
            "Layer": key[0],
            "Table": key[1],
            "Before": f"{before:,}",
            "After": f"{after:,}",
            "Delta": delta_display,
        })

    df_incr = pd.DataFrame(incr_data)

    st.dataframe(
        df_incr,
        use_container_width=True,
        hide_index=True,
        height=380,
        column_config={
            "Layer": st.column_config.TextColumn("Layer", width="small"),
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "Before": st.column_config.TextColumn("Before", width="small"),
            "After": st.column_config.TextColumn("After", width="small"),
            "Delta": st.column_config.TextColumn("Delta", width="large"),
        },
    )

    # Summary bar
    total_before = sum(HISTORY_BASELINE.values())
    total_after = sum(current_counts.values())
    total_delta = total_after - total_before

    st.markdown(
        f"""
        <div style="background: linear-gradient(135deg, #064e3b, #065f46);
                    border-radius: 8px; padding: 16px 24px;
                    display: flex; justify-content: space-between; align-items: center;
                    border: 1px solid #10b981; margin-top: 12px;">
            <div>
                <span style="color: #a7f3d0; font-weight: 500; font-size: 0.85rem;">PIPELINE GROWTH</span><br>
                <span style="color: #ecfdf5; font-size: 0.9rem;">
                    {total_before:,} &rarr; {total_after:,} rows
                </span>
            </div>
            <div style="text-align: right;">
                <span style="color: #4ade80; font-size: 1.8rem; font-weight: 700;">+{total_delta:,}</span><br>
                <span style="color: #a7f3d0; font-size: 0.8rem;">total new rows</span>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )


# ============================================================
# Footer
# ============================================================
st.markdown(
    """
    <div class="footer-text">
        Teradata Migration &nbsp;&bull;&nbsp; Medallion Architecture (Bronze &gt; Silver &gt; Gold)
        &nbsp;&bull;&nbsp; SSOM_COCO_DB &nbsp;&bull;&nbsp; Powered by Snowflake
    </div>
    """,
    unsafe_allow_html=True,
)
