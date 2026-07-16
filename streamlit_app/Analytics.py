import streamlit as st
import snowflake.connector
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

# ============================================================
# Configuration
# ============================================================
st.set_page_config(
    page_title="Gold Layer Analytics",
    page_icon=":chart_with_upwards_trend:",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ============================================================
# Professional Styling
# ============================================================
st.markdown(
    """
    <style>
    /* Main container spacing */
    .block-container { padding-top: 2rem; }

    /* Page banner */
    .page-banner {
        background: linear-gradient(135deg, #0f2027 0%, #203a43 50%, #2c5364 100%);
        padding: 28px 36px;
        border-radius: 12px;
        margin-bottom: 28px;
        border: 1px solid rgba(255,255,255,0.08);
    }
    .page-banner h1 {
        color: #ffffff;
        font-size: 1.8rem;
        margin-bottom: 6px;
        font-weight: 700;
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
        font-size: 0.78rem !important;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }
    [data-testid="stMetric"] [data-testid="stMetricValue"] {
        color: #e2e8f0 !important;
        font-size: 1.5rem !important;
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

    /* Section sub-headers */
    .section-label {
        color: #94a3b8;
        font-size: 0.75rem;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        font-weight: 600;
        margin-bottom: 8px;
    }

    /* Sidebar styling */
    [data-testid="stSidebar"] {
        border-right: 1px solid #2d3748;
    }
    [data-testid="stSidebar"] .stMarkdown h1 {
        font-size: 1.1rem;
        color: #e2e8f0;
    }

    /* Footer */
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


@st.cache_data(ttl=600)
def run_query(query: str) -> pd.DataFrame:
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute(query)
        df = cur.fetch_pandas_all()
        cur.close()
        if df.empty:
            st.cache_data.clear()
        return df
    except Exception as e:
        # Connection may have expired; clear cache and retry
        st.cache_resource.clear()
        st.cache_data.clear()
        st.error(f"Query failed: {e}")
        return pd.DataFrame()


# ============================================================
# Data Queries
# ============================================================
@st.cache_data(ttl=600)
def load_daily_transactions():
    return run_query(
        """
        SELECT Date_Key, Customer_ID, Account_ID, Transaction_ID,
               Transaction_Type, Amount
        FROM GOLD.FactDailyTransaction
        ORDER BY Date_Key
        """
    )


@st.cache_data(ttl=600)
def load_monthly_spend():
    return run_query(
        """
        SELECT Customer_ID, First_Name, Last_Name, City, State_Province,
               Month_Key, Transaction_Type, Transaction_Count,
               Total_Spend, Avg_Transaction, Min_Transaction, Max_Transaction
        FROM GOLD.MonthlySpendProfile
        ORDER BY Month_Key DESC, Total_Spend DESC
        """
    )


@st.cache_data(ttl=600)
def load_txn_type_trend():
    return run_query(
        """
        SELECT Month_Key, Transaction_Type, Transaction_Count,
               Total_Amount, Avg_Amount, Unique_Customers,
               Unique_Accounts, Avg_Spend_Per_Customer
        FROM GOLD.TxnTypeTrend
        ORDER BY Month_Key
        """
    )


@st.cache_data(ttl=600)
def load_daily_agg():
    return run_query(
        """
        SELECT Date_Key, Customer_ID, Account_ID, Transaction_Type,
               Total_Amount, Transaction_Count
        FROM GOLD.FactDailyAgg
        ORDER BY Date_Key DESC
        """
    )


# ============================================================
# Sidebar Filters
# ============================================================
st.sidebar.markdown("### Filters")

df_txn = load_daily_transactions()

if df_txn.empty:
    st.markdown(
        """
        <div class="page-banner">
            <h1>Analytics Dashboard</h1>
            <p>SSOM_COCO_DB &nbsp;|&nbsp; Gold Layer Reporting &nbsp;|&nbsp; Medallion Architecture</p>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.warning(
        "No transaction data available yet. Run the ETL pipeline to populate "
        "the Gold layer, then refresh.\n\n"
        "```bash\n"
        "bash scripts/run_historical.sh --source=csv\n"
        "bash scripts/run_historical.sh --source=iceberg\n"
        "```"
    )
    if st.button("Refresh", type="primary"):
        st.cache_data.clear()
        st.rerun()
    st.stop()

df_txn["DATE_KEY"] = pd.to_datetime(df_txn["DATE_KEY"])

# Date range
min_date = df_txn["DATE_KEY"].min()
max_date = df_txn["DATE_KEY"].max()

if pd.isna(min_date) or pd.isna(max_date):
    st.markdown(
        """
        <div class="page-banner">
            <h1>Analytics Dashboard</h1>
            <p>SSOM_COCO_DB &nbsp;|&nbsp; Gold Layer Reporting &nbsp;|&nbsp; Medallion Architecture</p>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.warning(
        "No transaction data available yet. Run the ETL pipeline "
        "(`CALL Daily_ETL_Run()`) to populate the Gold layer, then refresh."
    )
    st.stop()

date_range = st.sidebar.date_input(
    "Date Range",
    value=(min_date.date() if hasattr(min_date, 'date') else min_date,
           max_date.date() if hasattr(max_date, 'date') else max_date),
    min_value=min_date.date() if hasattr(min_date, 'date') else min_date,
    max_value=max_date.date() if hasattr(max_date, 'date') else max_date,
)

# Transaction type
all_types = sorted(df_txn["TRANSACTION_TYPE"].dropna().unique())
selected_types = st.sidebar.multiselect(
    "Transaction Type", options=all_types, default=all_types
)

# Apply filters
if len(date_range) == 2:
    mask = (
        (df_txn["DATE_KEY"] >= pd.Timestamp(date_range[0]))
        & (df_txn["DATE_KEY"] <= pd.Timestamp(date_range[1]))
        & (df_txn["TRANSACTION_TYPE"].isin(selected_types))
    )
    df_filtered = df_txn[mask]
else:
    df_filtered = df_txn[df_txn["TRANSACTION_TYPE"].isin(selected_types)]


# ============================================================
# Page Header
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>Gold Layer Analytics</h1>
        <p>SSOM_COCO_DB &nbsp;|&nbsp; Medallion Architecture &nbsp;|&nbsp; Bronze &gt; Silver &gt; Gold &nbsp;|&nbsp; Teradata Migration</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ============================================================
# Tabs
# ============================================================
tab1, tab2, tab3, tab4 = st.tabs(
    ["Overview", "Spend Profile", "Type Trends", "Rollup Explorer"]
)


# ============================================================
# Tab 1: Overview
# ============================================================
with tab1:
    st.markdown('<p class="section-label">Key Performance Indicators</p>', unsafe_allow_html=True)

    # KPIs
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Total Transactions", f"{len(df_filtered):,}")
    col2.metric("Total Volume", f"${df_filtered['AMOUNT'].sum():,.2f}")
    col3.metric("Avg Transaction", f"${df_filtered['AMOUNT'].mean():,.2f}")
    col4.metric("Unique Customers", f"{df_filtered['CUSTOMER_ID'].nunique():,}")

    st.markdown("<br>", unsafe_allow_html=True)

    # Daily volume chart
    daily_vol = (
        df_filtered.groupby("DATE_KEY")
        .agg(Transactions=("TRANSACTION_ID", "count"), Volume=("AMOUNT", "sum"))
        .reset_index()
    )

    fig_vol = px.area(
        daily_vol,
        x="DATE_KEY",
        y="Volume",
        title="Daily Transaction Volume",
        labels={"DATE_KEY": "Date", "Volume": "Amount ($)"},
        color_discrete_sequence=["#3b82f6"],
    )
    fig_vol.update_layout(
        template="plotly_dark",
        height=400,
        margin=dict(l=40, r=40, t=60, b=40),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#94a3b8"),
        title_font=dict(size=16, color="#e2e8f0"),
    )
    fig_vol.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
    fig_vol.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
    st.plotly_chart(fig_vol, use_container_width=True)

    # Two charts side by side
    col_left, col_right = st.columns(2)

    with col_left:
        type_counts = (
            df_filtered.groupby("TRANSACTION_TYPE")["TRANSACTION_ID"]
            .count()
            .reset_index(name="Count")
        )
        fig_type = px.pie(
            type_counts,
            values="Count",
            names="TRANSACTION_TYPE",
            title="Distribution by Type",
            hole=0.45,
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        fig_type.update_layout(
            template="plotly_dark",
            height=350,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
            legend=dict(font=dict(size=11)),
        )
        st.plotly_chart(fig_type, use_container_width=True)

    with col_right:
        daily_count = (
            df_filtered.groupby("DATE_KEY")["TRANSACTION_ID"]
            .count()
            .reset_index(name="Count")
        )
        fig_daily_count = px.bar(
            daily_count,
            x="DATE_KEY",
            y="Count",
            title="Daily Transaction Count",
            labels={"DATE_KEY": "Date", "Count": "Transactions"},
            color_discrete_sequence=["#10b981"],
        )
        fig_daily_count.update_layout(
            template="plotly_dark",
            height=350,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
        )
        fig_daily_count.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
        fig_daily_count.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
        st.plotly_chart(fig_daily_count, use_container_width=True)


# ============================================================
# Tab 2: Monthly Spend Profile
# ============================================================
with tab2:
    st.markdown('<p class="section-label">Customer Spend Analysis</p>', unsafe_allow_html=True)

    df_spend = load_monthly_spend()
    df_spend["MONTH_KEY"] = pd.to_datetime(df_spend["MONTH_KEY"])

    # Month filter
    months = sorted(df_spend["MONTH_KEY"].unique(), reverse=True)
    selected_month = st.selectbox("Select Month", months, index=0)

    df_month = df_spend[df_spend["MONTH_KEY"] == selected_month]

    # KPIs for the month
    col1, col2, col3 = st.columns(3)
    col1.metric("Unique Customers", f"{df_month['CUSTOMER_ID'].nunique():,}")
    col2.metric("Total Spend", f"${df_month['TOTAL_SPEND'].sum():,.2f}")
    col3.metric("Avg per Customer", f"${df_month['TOTAL_SPEND'].mean():,.2f}")

    st.markdown("<br>", unsafe_allow_html=True)

    # Top spenders bar chart
    top_spenders = (
        df_month.groupby(["CUSTOMER_ID", "FIRST_NAME", "LAST_NAME"])["TOTAL_SPEND"]
        .sum()
        .reset_index()
        .sort_values("TOTAL_SPEND", ascending=False)
        .head(15)
    )
    top_spenders["Customer"] = (
        top_spenders["FIRST_NAME"] + " " + top_spenders["LAST_NAME"]
    )

    fig_spend = px.bar(
        top_spenders,
        x="TOTAL_SPEND",
        y="Customer",
        orientation="h",
        title="Top 15 Spenders",
        labels={"TOTAL_SPEND": "Total Spend ($)", "Customer": ""},
        color="TOTAL_SPEND",
        color_continuous_scale="blues",
    )
    fig_spend.update_layout(
        template="plotly_dark",
        height=500,
        showlegend=False,
        yaxis=dict(autorange="reversed"),
        margin=dict(l=140, r=40, t=60, b=40),
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#94a3b8"),
        title_font=dict(size=14, color="#e2e8f0"),
        coloraxis_showscale=False,
    )
    st.plotly_chart(fig_spend, use_container_width=True)

    # Detail table
    st.markdown('<p class="section-label">Detailed Breakdown</p>', unsafe_allow_html=True)
    st.dataframe(
        df_month[
            [
                "CUSTOMER_ID",
                "FIRST_NAME",
                "LAST_NAME",
                "CITY",
                "TRANSACTION_TYPE",
                "TRANSACTION_COUNT",
                "TOTAL_SPEND",
                "AVG_TRANSACTION",
            ]
        ].sort_values("TOTAL_SPEND", ascending=False),
        use_container_width=True,
        hide_index=True,
    )


# ============================================================
# Tab 3: Transaction Type Trends
# ============================================================
with tab3:
    st.markdown('<p class="section-label">Monthly Trend Analysis</p>', unsafe_allow_html=True)

    df_trend = load_txn_type_trend()
    df_trend["MONTH_KEY"] = pd.to_datetime(df_trend["MONTH_KEY"])

    # Stacked area - volume over time
    fig_area = px.area(
        df_trend,
        x="MONTH_KEY",
        y="TOTAL_AMOUNT",
        color="TRANSACTION_TYPE",
        title="Monthly Volume by Transaction Type",
        labels={"MONTH_KEY": "Month", "TOTAL_AMOUNT": "Amount ($)"},
        color_discrete_sequence=px.colors.qualitative.Set2,
    )
    fig_area.update_layout(
        template="plotly_dark",
        height=400,
        plot_bgcolor="rgba(0,0,0,0)",
        paper_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#94a3b8"),
        title_font=dict(size=14, color="#e2e8f0"),
    )
    fig_area.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
    fig_area.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
    st.plotly_chart(fig_area, use_container_width=True)

    # Transaction count trend
    col1, col2 = st.columns(2)

    with col1:
        fig_count = px.bar(
            df_trend,
            x="MONTH_KEY",
            y="TRANSACTION_COUNT",
            color="TRANSACTION_TYPE",
            title="Transaction Count by Type",
            barmode="group",
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        fig_count.update_layout(
            template="plotly_dark",
            height=350,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
        )
        fig_count.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
        fig_count.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
        st.plotly_chart(fig_count, use_container_width=True)

    with col2:
        fig_avg = px.line(
            df_trend,
            x="MONTH_KEY",
            y="AVG_SPEND_PER_CUSTOMER",
            color="TRANSACTION_TYPE",
            title="Avg Spend per Customer by Type",
            markers=True,
            color_discrete_sequence=px.colors.qualitative.Set2,
        )
        fig_avg.update_layout(
            template="plotly_dark",
            height=350,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
        )
        fig_avg.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
        fig_avg.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
        st.plotly_chart(fig_avg, use_container_width=True)

    # Summary table
    st.markdown('<p class="section-label">Summary Data</p>', unsafe_allow_html=True)
    st.dataframe(df_trend, use_container_width=True, hide_index=True)


# ============================================================
# Tab 4: Rollup Explorer
# ============================================================
with tab4:
    st.markdown('<p class="section-label">Aggregated Fact Exploration</p>', unsafe_allow_html=True)

    df_agg = load_daily_agg()
    df_agg["DATE_KEY"] = pd.to_datetime(df_agg["DATE_KEY"])

    # Rollup level selector
    rollup = st.radio(
        "Select Rollup Level",
        [
            "By Customer",
            "By Account",
            "By Customer + Type",
            "By Account + Type",
        ],
        horizontal=True,
    )

    if rollup == "By Customer":
        df_view = df_agg[
            df_agg["CUSTOMER_ID"].notna()
            & df_agg["ACCOUNT_ID"].isna()
            & df_agg["TRANSACTION_TYPE"].isna()
        ]
    elif rollup == "By Account":
        df_view = df_agg[
            df_agg["CUSTOMER_ID"].isna()
            & df_agg["ACCOUNT_ID"].notna()
            & df_agg["TRANSACTION_TYPE"].isna()
        ]
    elif rollup == "By Customer + Type":
        df_view = df_agg[
            df_agg["CUSTOMER_ID"].notna()
            & df_agg["ACCOUNT_ID"].isna()
            & df_agg["TRANSACTION_TYPE"].notna()
        ]
    else:
        df_view = df_agg[
            df_agg["CUSTOMER_ID"].isna()
            & df_agg["ACCOUNT_ID"].notna()
            & df_agg["TRANSACTION_TYPE"].notna()
        ]

    # KPIs for selected rollup
    col1, col2, col3 = st.columns(3)
    col1.metric("Rows", f"{len(df_view):,}")
    col2.metric("Total Amount", f"${df_view['TOTAL_AMOUNT'].sum():,.2f}")
    col3.metric("Total Txn Count", f"{df_view['TRANSACTION_COUNT'].sum():,}")

    st.markdown("<br>", unsafe_allow_html=True)

    # Aggregated view by date
    if not df_view.empty:
        agg_by_date = (
            df_view.groupby("DATE_KEY")
            .agg(Total=("TOTAL_AMOUNT", "sum"), Count=("TRANSACTION_COUNT", "sum"))
            .reset_index()
        )
        fig_rollup = px.bar(
            agg_by_date,
            x="DATE_KEY",
            y="Total",
            title=f"Daily Totals - {rollup}",
            labels={"DATE_KEY": "Date", "Total": "Amount ($)"},
            color_discrete_sequence=["#8b5cf6"],
        )
        fig_rollup.update_layout(
            template="plotly_dark",
            height=400,
            plot_bgcolor="rgba(0,0,0,0)",
            paper_bgcolor="rgba(0,0,0,0)",
            font=dict(color="#94a3b8"),
            title_font=dict(size=14, color="#e2e8f0"),
        )
        fig_rollup.update_xaxes(gridcolor="rgba(100,116,139,0.1)")
        fig_rollup.update_yaxes(gridcolor="rgba(100,116,139,0.1)")
        st.plotly_chart(fig_rollup, use_container_width=True)

    # Raw data
    st.markdown('<p class="section-label">Raw Data (Top 100)</p>', unsafe_allow_html=True)
    st.dataframe(df_view.head(100), use_container_width=True, hide_index=True)


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
