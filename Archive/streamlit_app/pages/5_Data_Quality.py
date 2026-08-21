import streamlit as st
import snowflake.connector
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# ============================================================
# Page Configuration
# ============================================================
st.set_page_config(
    page_title="Data Quality",
    page_icon=":shield:",
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

    /* Severity badges */
    .badge-error {
        background: linear-gradient(135deg, #991b1b, #dc2626);
        color: white;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .badge-warning {
        background: linear-gradient(135deg, #92400e, #f59e0b);
        color: white;
        padding: 3px 10px;
        border-radius: 12px;
        font-size: 0.75rem;
        font-weight: 600;
    }
    .badge-info {
        background: linear-gradient(135deg, #1e40af, #3b82f6);
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


def run_query(sql: str) -> pd.DataFrame:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql)
    columns = [desc[0] for desc in cur.description]
    data = cur.fetchall()
    cur.close()
    return pd.DataFrame(data, columns=columns)


def run_procedure(proc_name: str) -> str:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(f"CALL {proc_name}()")
    result = cur.fetchone()[0]
    cur.close()
    return result


# ============================================================
# Page Header
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>Data Quality Dashboard</h1>
        <p>SSOM_COCO_DB &nbsp;|&nbsp; Cleansing &amp; Validation Framework &nbsp;|&nbsp; GOVERNANCE Schema</p>
    </div>
    """,
    unsafe_allow_html=True,
)


# ============================================================
# Load DQ Log Data
# ============================================================
@st.cache_data(ttl=30)
def load_dq_log() -> pd.DataFrame:
    sql = """
    SELECT
        log_id, run_id, check_timestamp, table_name,
        check_name, severity, records_failed, sample_ids, details
    FROM GOVERNANCE.DATA_QUALITY_LOG
    ORDER BY check_timestamp DESC, log_id DESC
    """
    return run_query(sql)


@st.cache_data(ttl=30)
def get_latest_run_id() -> str:
    sql = """
    SELECT run_id
    FROM GOVERNANCE.DATA_QUALITY_LOG
    ORDER BY check_timestamp DESC
    LIMIT 1
    """
    df = run_query(sql)
    if len(df) > 0:
        return df.iloc[0]["RUN_ID"]
    return None


# ============================================================
# Action Buttons
# ============================================================
col_spacer, col_btn1, col_btn2, col_btn3 = st.columns([3, 1, 1, 1])

with col_btn1:
    run_cleanse = st.button("Run Cleansing", type="secondary")
with col_btn2:
    run_checks = st.button("Run Checks", type="primary")
with col_btn3:
    if st.button("Refresh", type="secondary"):
        st.cache_data.clear()
        st.rerun()

# Execute actions
if run_cleanse:
    with st.spinner("Running data cleansing..."):
        result = run_procedure("GOVERNANCE.Cleanse_Bronze_Data")
    st.success(f"Cleansing result: {result}")
    st.cache_data.clear()

if run_checks:
    with st.spinner("Running data quality checks..."):
        result = run_procedure("GOVERNANCE.Run_Data_Quality_Checks")
    st.success(f"Validation result: {result}")
    st.cache_data.clear()
    st.rerun()


# ============================================================
# Summary Metrics
# ============================================================
try:
    df_log = load_dq_log()
    latest_run = get_latest_run_id()

    if latest_run and len(df_log) > 0:
        df_latest = df_log[df_log["RUN_ID"] == latest_run]

        total_checks = len(df_latest)
        errors = len(df_latest[df_latest["SEVERITY"] == "ERROR"])
        warnings = len(df_latest[df_latest["SEVERITY"] == "WARNING"])
        passed = len(df_latest[df_latest["RECORDS_FAILED"] == 0])

        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Total Checks", total_checks)
        col2.metric("Passed", passed, delta=f"{passed}/{total_checks}")
        col3.metric("Warnings", warnings, delta=None if warnings == 0 else f"-{warnings}", delta_color="inverse")
        col4.metric("Errors", errors, delta=None if errors == 0 else f"-{errors}", delta_color="inverse")

        st.markdown("<br>", unsafe_allow_html=True)

        # ============================================================
        # Tabs
        # ============================================================
        tab1, tab2, tab3 = st.tabs(["Latest Results", "History & Trends", "By Table"])

        with tab1:
            st.markdown(
                f'<div class="section-header"><h3>Latest Run: {latest_run}</h3></div>',
                unsafe_allow_html=True,
            )

            # Sidebar-style filters within the tab
            filter_col1, filter_col2 = st.columns(2)
            with filter_col1:
                severity_filter = st.multiselect(
                    "Filter by Severity",
                    options=["ERROR", "WARNING", "INFO"],
                    default=["ERROR", "WARNING", "INFO"],
                )
            with filter_col2:
                table_options = sorted(df_latest["TABLE_NAME"].unique().tolist())
                table_filter = st.multiselect(
                    "Filter by Table",
                    options=table_options,
                    default=table_options,
                )

            df_filtered = df_latest[
                (df_latest["SEVERITY"].isin(severity_filter)) &
                (df_latest["TABLE_NAME"].isin(table_filter))
            ]

            # Color-code the severity column
            def color_severity(val):
                colors = {
                    "ERROR": "background-color: #991b1b; color: white;",
                    "WARNING": "background-color: #92400e; color: white;",
                    "INFO": "background-color: #1e40af; color: white;",
                }
                return colors.get(val, "")

            display_cols = ["CHECK_NAME", "TABLE_NAME", "SEVERITY", "RECORDS_FAILED", "DETAILS"]
            df_display = df_filtered[display_cols].reset_index(drop=True)

            st.dataframe(
                df_display.style.map(color_severity, subset=["SEVERITY"]),
                use_container_width=True,
                hide_index=True,
                height=450,
            )

            # Summary bar
            failed_records_total = df_latest["RECORDS_FAILED"].sum()
            st.markdown(
                f"""
                <div style="background: {'linear-gradient(135deg, #064e3b, #065f46)' if errors == 0 else 'linear-gradient(135deg, #7f1d1d, #991b1b)'};
                            border-radius: 8px; padding: 16px 24px;
                            display: flex; justify-content: space-between; align-items: center;
                            border: 1px solid {'#10b981' if errors == 0 else '#f87171'}; margin-top: 12px;">
                    <div>
                        <span style="color: {'#a7f3d0' if errors == 0 else '#fca5a5'}; font-weight: 500; font-size: 0.85rem;">
                            DATA QUALITY STATUS
                        </span><br>
                        <span style="color: {'#ecfdf5' if errors == 0 else '#fef2f2'}; font-size: 0.9rem;">
                            {total_checks} checks executed &bull; {int(failed_records_total)} total records flagged
                        </span>
                    </div>
                    <div style="text-align: right;">
                        <span style="color: {'#4ade80' if errors == 0 else '#f87171'}; font-size: 1.8rem; font-weight: 700;">
                            {'PASS' if errors == 0 else 'FAIL'}
                        </span><br>
                        <span style="color: {'#a7f3d0' if errors == 0 else '#fca5a5'}; font-size: 0.8rem;">
                            {errors} errors, {warnings} warnings
                        </span>
                    </div>
                </div>
                """,
                unsafe_allow_html=True,
            )

        with tab2:
            st.markdown(
                '<div class="section-header"><h3>Check Results Over Time</h3></div>',
                unsafe_allow_html=True,
            )

            # Aggregate by run_id and severity
            df_trend = df_log.groupby(["RUN_ID", "SEVERITY"]).size().reset_index(name="COUNT")

            if len(df_trend) > 0:
                fig_trend = px.bar(
                    df_trend,
                    x="RUN_ID",
                    y="COUNT",
                    color="SEVERITY",
                    color_discrete_map={"ERROR": "#dc2626", "WARNING": "#f59e0b", "INFO": "#3b82f6"},
                    title="Check Results by Run",
                    barmode="stack",
                )
                fig_trend.update_layout(
                    template="plotly_dark",
                    height=400,
                    plot_bgcolor="rgba(0,0,0,0)",
                    paper_bgcolor="rgba(0,0,0,0)",
                    font=dict(color="#94a3b8"),
                    title_font=dict(size=14, color="#e2e8f0"),
                    xaxis_title="Run ID",
                    yaxis_title="Number of Checks",
                )
                st.plotly_chart(fig_trend, use_container_width=True)

            # Failed records over time
            df_failures = df_log.groupby("RUN_ID")["RECORDS_FAILED"].sum().reset_index()
            if len(df_failures) > 0:
                fig_fail = px.line(
                    df_failures,
                    x="RUN_ID",
                    y="RECORDS_FAILED",
                    title="Total Records Flagged per Run",
                    markers=True,
                )
                fig_fail.update_layout(
                    template="plotly_dark",
                    height=300,
                    plot_bgcolor="rgba(0,0,0,0)",
                    paper_bgcolor="rgba(0,0,0,0)",
                    font=dict(color="#94a3b8"),
                    title_font=dict(size=14, color="#e2e8f0"),
                )
                fig_fail.update_traces(line_color="#f59e0b")
                st.plotly_chart(fig_fail, use_container_width=True)

        with tab3:
            st.markdown(
                '<div class="section-header"><h3>Quality by Table</h3></div>',
                unsafe_allow_html=True,
            )

            # Group latest run by table
            df_by_table = df_latest.groupby("TABLE_NAME").agg(
                total_checks=("CHECK_NAME", "count"),
                errors=("SEVERITY", lambda x: (x == "ERROR").sum()),
                warnings=("SEVERITY", lambda x: (x == "WARNING").sum()),
                records_flagged=("RECORDS_FAILED", "sum"),
            ).reset_index()

            df_by_table.columns = ["Table", "Total Checks", "Errors", "Warnings", "Records Flagged"]

            st.dataframe(
                df_by_table,
                use_container_width=True,
                hide_index=True,
            )

            # Donut chart of severity distribution
            if len(df_latest) > 0:
                severity_counts = df_latest["SEVERITY"].value_counts().reset_index()
                severity_counts.columns = ["Severity", "Count"]

                fig_donut = px.pie(
                    severity_counts,
                    values="Count",
                    names="Severity",
                    color="Severity",
                    color_discrete_map={"ERROR": "#dc2626", "WARNING": "#f59e0b", "INFO": "#3b82f6"},
                    hole=0.5,
                    title="Check Severity Distribution",
                )
                fig_donut.update_layout(
                    template="plotly_dark",
                    height=350,
                    plot_bgcolor="rgba(0,0,0,0)",
                    paper_bgcolor="rgba(0,0,0,0)",
                    font=dict(color="#94a3b8"),
                    title_font=dict(size=14, color="#e2e8f0"),
                )
                st.plotly_chart(fig_donut, use_container_width=True)

    else:
        st.info(
            "No data quality checks have been run yet. "
            "Click **Run Checks** above to execute the validation suite."
        )

except Exception as e:
    if "does not exist" in str(e).lower():
        st.warning(
            "Data Quality objects not yet deployed. "
            "Run `Snowflake_Scripts/10_data_quality.sql` to create the GOVERNANCE.DATA_QUALITY_LOG table "
            "and validation procedures, then click **Run Checks**."
        )
    else:
        st.error(f"Error loading data quality results: {e}")


# ============================================================
# Footer
# ============================================================
st.markdown(
    """
    <div class="footer-text">
        Teradata Migration &nbsp;&bull;&nbsp; Data Quality Framework
        &nbsp;&bull;&nbsp; GOVERNANCE Schema &nbsp;&bull;&nbsp; Powered by Snowflake
    </div>
    """,
    unsafe_allow_html=True,
)
