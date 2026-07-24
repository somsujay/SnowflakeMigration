import streamlit as st
import snowflake.connector
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# ============================================================
# Page Configuration
# ============================================================
st.set_page_config(
    page_title="DevOps Dashboard",
    page_icon=":rocket:",
    layout="wide",
)

# ============================================================
# Custom Styling
# ============================================================
st.markdown(
    """
    <style>
    .block-container { padding-top: 2rem; }

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

    [data-testid="stMetric"] {
        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        border: 1px solid #2d3748;
        border-radius: 10px;
        padding: 16px 20px;
        box-shadow: 0 4px 6px rgba(0,0,0,0.3);
    }
    [data-testid="stMetric"] label {
        color: #94a3b8 !important;
        font-size: 0.78rem !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }
    [data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: #e2e8f0 !important;
        font-size: 1.5rem !important;
        font-weight: 700;
    }

    .section-label {
        color: #94a3b8;
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-weight: 600;
        margin-bottom: 8px;
    }

    .footer-text {
        color: #64748b;
        font-size: 0.75rem;
        text-align: center;
        padding: 16px 0;
        border-top: 1px solid rgba(100, 116, 139, 0.2);
        margin-top: 40px;
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


@st.cache_data(ttl=300)
def run_query(query: str) -> pd.DataFrame:
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(query)
        df = cur.fetch_pandas_all()
        cur.close()
        return df
    except Exception as e:
        st.cache_resource.clear()
        st.cache_data.clear()
        st.error(f"Query failed: {e}")
        return pd.DataFrame()


# ============================================================
# Banner
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>DevOps Dashboard</h1>
        <p>Deployment history, migration status, environment health & data quality trends</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ============================================================
# Data Queries
# ============================================================
@st.cache_data(ttl=300)
def load_deployment_history():
    return run_query("""
        SELECT VERSION, SCRIPT, SCRIPT_TYPE, STATUS,
               INSTALLED_ON, EXECUTION_TIME,
               CHECKSUM
        FROM METADATA.SCHEMACHANGE_HISTORY
        ORDER BY INSTALLED_ON DESC
    """)


@st.cache_data(ttl=300)
def load_object_counts():
    return run_query("""
        SELECT TABLE_SCHEMA AS SCHEMA_NAME,
               TABLE_TYPE,
               COUNT(*) AS OBJECT_COUNT
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
        GROUP BY TABLE_SCHEMA, TABLE_TYPE
        ORDER BY TABLE_SCHEMA, TABLE_TYPE
    """)


@st.cache_data(ttl=300)
def load_procedure_counts():
    return run_query("""
        SELECT PROCEDURE_SCHEMA AS SCHEMA_NAME,
               COUNT(*) AS PROC_COUNT
        FROM INFORMATION_SCHEMA.PROCEDURES
        WHERE PROCEDURE_SCHEMA NOT IN ('INFORMATION_SCHEMA')
        GROUP BY PROCEDURE_SCHEMA
        ORDER BY PROCEDURE_SCHEMA
    """)


@st.cache_data(ttl=300)
def load_quality_trend():
    return run_query("""
        SELECT RUN_ID, CHECK_TIMESTAMP, SEVERITY,
               COUNT(*) AS CHECK_COUNT,
               SUM(RECORDS_FAILED) AS TOTAL_FAILURES
        FROM GOVERNANCE.DATA_QUALITY_LOG
        GROUP BY RUN_ID, CHECK_TIMESTAMP, SEVERITY
        ORDER BY CHECK_TIMESTAMP DESC
        LIMIT 200
    """)


# ============================================================
# Section 1: Migration Metrics
# ============================================================
st.markdown('<p class="section-label">Migration Status</p>', unsafe_allow_html=True)

df_history = load_deployment_history()

if not df_history.empty:
    total_migrations = len(df_history)
    last_deploy = df_history["INSTALLED_ON"].iloc[0] if "INSTALLED_ON" in df_history.columns else "N/A"

    # Count by script type
    type_counts = df_history["SCRIPT_TYPE"].value_counts() if "SCRIPT_TYPE" in df_history.columns else pd.Series()
    v_count = type_counts.get("V", 0)
    r_count = type_counts.get("R", 0)
    a_count = type_counts.get("A", 0)

    col1, col2, col3, col4, col5 = st.columns(5)
    col1.metric("Total Migrations", total_migrations)
    col2.metric("Last Deployment", str(last_deploy)[:19] if last_deploy != "N/A" else "N/A")
    col3.metric("Versioned (V)", v_count)
    col4.metric("Repeatable (R)", r_count)
    col5.metric("Always (A)", a_count)

    # ============================================================
    # Section 2: Deployment Timeline
    # ============================================================
    st.markdown('<p class="section-label">Deployment Timeline</p>', unsafe_allow_html=True)

    if "INSTALLED_ON" in df_history.columns:
        df_timeline = df_history.copy()
        df_timeline["INSTALLED_ON"] = pd.to_datetime(df_timeline["INSTALLED_ON"])

        fig_timeline = px.scatter(
            df_timeline,
            x="INSTALLED_ON",
            y="SCRIPT_TYPE",
            color="SCRIPT_TYPE",
            hover_data=["SCRIPT", "VERSION", "STATUS"],
            color_discrete_map={"V": "#29b6f6", "R": "#66bb6a", "A": "#ffa726"},
            title="Migrations Over Time",
        )
        fig_timeline.update_layout(
            template="plotly_dark",
            height=300,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
            xaxis_title="Deployed At",
            yaxis_title="Script Type",
        )
        st.plotly_chart(fig_timeline, use_container_width=True)

    # ============================================================
    # Section 3: Deployment History Table
    # ============================================================
    st.markdown('<p class="section-label">Deployment History</p>', unsafe_allow_html=True)
    st.dataframe(
        df_history[["VERSION", "SCRIPT", "SCRIPT_TYPE", "STATUS", "INSTALLED_ON", "EXECUTION_TIME"]].head(50),
        use_container_width=True,
        hide_index=True,
    )
else:
    st.info("No deployment history found. Run a deployment first.")

# ============================================================
# Section 4: Environment Object Inventory
# ============================================================
st.markdown("---")
st.markdown('<p class="section-label">Environment Object Inventory</p>', unsafe_allow_html=True)

df_objects = load_object_counts()
df_procs = load_procedure_counts()

if not df_objects.empty:
    col1, col2 = st.columns(2)

    with col1:
        fig_obj = px.bar(
            df_objects,
            x="SCHEMA_NAME",
            y="OBJECT_COUNT",
            color="TABLE_TYPE",
            barmode="group",
            color_discrete_map={"BASE TABLE": "#29b6f6", "VIEW": "#66bb6a"},
            title="Tables & Views by Schema",
        )
        fig_obj.update_layout(
            template="plotly_dark",
            height=350,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
        )
        st.plotly_chart(fig_obj, use_container_width=True)

    with col2:
        if not df_procs.empty:
            fig_proc = px.bar(
                df_procs,
                x="SCHEMA_NAME",
                y="PROC_COUNT",
                color_discrete_sequence=["#ab47bc"],
                title="Procedures by Schema",
            )
            fig_proc.update_layout(
                template="plotly_dark",
                height=350,
                plot_bgcolor="rgba(0,0,0,0)",
                paper_bgcolor="rgba(0,0,0,0)",
                font=dict(color="#94a3b8"),
                title_font=dict(size=14, color="#e2e8f0"),
            )
            st.plotly_chart(fig_proc, use_container_width=True)
        else:
            st.info("No procedures found.")
else:
    st.info("No objects found in INFORMATION_SCHEMA.")

# ============================================================
# Section 5: Data Quality Trend
# ============================================================
st.markdown("---")
st.markdown('<p class="section-label">Data Quality Trend</p>', unsafe_allow_html=True)

df_quality = load_quality_trend()

if not df_quality.empty:
    df_quality["CHECK_TIMESTAMP"] = pd.to_datetime(df_quality["CHECK_TIMESTAMP"])

    col1, col2, col3 = st.columns(3)
    total_runs = df_quality["RUN_ID"].nunique()
    total_failures = df_quality["TOTAL_FAILURES"].sum()
    error_count = len(df_quality[df_quality["SEVERITY"] == "ERROR"])

    col1.metric("Total DQ Runs", total_runs)
    col2.metric("Total Failures", int(total_failures))
    col3.metric("Error Checks", error_count)

    fig_quality = px.bar(
        df_quality,
        x="CHECK_TIMESTAMP",
        y="TOTAL_FAILURES",
        color="SEVERITY",
        color_discrete_map={"ERROR": "#ef5350", "WARNING": "#ffa726", "INFO": "#66bb6a"},
        title="Failures by Severity Over Time",
    )
    fig_quality.update_layout(
        template="plotly_dark",
        height=350,
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#94a3b8"),
        title_font=dict(size=14, color="#e2e8f0"),
        xaxis_title="Run Timestamp",
        yaxis_title="Failed Records",
    )
    st.plotly_chart(fig_quality, use_container_width=True)
else:
    st.info("No data quality logs found. Run Data Quality Checks first.")

# ============================================================
# Footer
# ============================================================
st.markdown(
    """
    <div class="footer-text">
        DevOps Dashboard &nbsp;&bull;&nbsp; Schemachange Migrations
        &nbsp;&bull;&nbsp; Powered by Snowflake
    </div>
    """,
    unsafe_allow_html=True,
)
