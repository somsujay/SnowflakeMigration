import streamlit as st
import snowflake.connector
import pandas as pd

# ============================================================
# Page Configuration
# ============================================================
st.set_page_config(
    page_title="Data Masking",
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


# ============================================================
# Empty State Check - verify GOVERNANCE schema exists
# ============================================================
def check_objects_exist() -> bool:
    """Check if masking policy objects exist in Snowflake."""
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("DESCRIBE MASKING POLICY SSOM_COCO_DB.GOVERNANCE.MASK_NAME")
        cur.close()
        return True
    except Exception:
        return False


if not check_objects_exist():
    st.markdown(
        """
        <div class="page-banner">
            <h1>Data Masking Policies</h1>
            <p>SSOM_COCO_DB &nbsp;|&nbsp; GOVERNANCE Schema &nbsp;|&nbsp; PII Protection &amp; Financial Data Redaction</p>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.markdown(
        """
        <div style="background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
                    border: 1px solid #334155; border-radius: 12px;
                    padding: 48px 32px; text-align: center; margin-top: 24px;">
            <p style="font-size: 2.5rem; margin-bottom: 8px;">🔒</p>
            <h2 style="color: #f1f5f9; margin-bottom: 12px;">No Masking Policies Found</h2>
            <p style="color: #94a3b8; font-size: 1rem; max-width: 500px; margin: 0 auto;">
                The GOVERNANCE schema or masking policies do not exist yet.
                Deploy the Snowflake objects first.
            </p>
            <div style="background: #0f172a; border-radius: 8px; padding: 16px 24px;
                        margin-top: 24px; display: inline-block; text-align: left;">
                <code style="color: #a5b4fc; font-size: 0.85rem;">
                    bash scripts/create_objects.sh
                </code>
            </div>
        </div>
        """,
        unsafe_allow_html=True,
    )
    st.stop()


# ============================================================
# Data Loading
# ============================================================
POLICY_METADATA = {
    "MASK_NAME": {
        "description": "Partial mask for personal names",
        "style": "First character + '***'",
        "example_input": "James",
        "example_output": "J***",
        "category": "PII - Identity",
    },
    "MASK_EMAIL": {
        "description": "Partial mask for email addresses",
        "style": "First char + '***@' + domain",
        "example_input": "james.anderson@email.com",
        "example_output": "j***@email.com",
        "category": "PII - Contact",
    },
    "MASK_PHONE": {
        "description": "Partial mask for phone numbers",
        "style": "'***-***-' + last 4 digits",
        "example_input": "416-555-0101",
        "example_output": "***-***-0101",
        "category": "PII - Contact",
    },
    "MASK_LOCATION": {
        "description": "Partial mask for geographic data",
        "style": "First character + '***'",
        "example_input": "Toronto",
        "example_output": "T***",
        "category": "PII - Location",
    },
    "MASK_FINANCIAL_ID": {
        "description": "Partial mask for account/customer IDs",
        "style": "Prefix + '-***'",
        "example_input": "ACCT-1001",
        "example_output": "ACCT-***",
        "category": "Financial - Identifier",
    },
    "MASK_AMOUNT": {
        "description": "Full redaction for financial amounts",
        "style": "Zeroed (0.00)",
        "example_input": "2500.00",
        "example_output": "0.00",
        "category": "Financial - Amount",
    },
}

# Column-to-policy assignments (from 09_masking_policies.sql)
POLICY_ASSIGNMENTS = [
    ("Bronze", "T_Customer", "FIRST_NAME", "MASK_NAME"),
    ("Bronze", "T_Customer", "LAST_NAME", "MASK_NAME"),
    ("Bronze", "T_Customer", "EMAIL_ADDRESS", "MASK_EMAIL"),
    ("Bronze", "T_Customer", "PHONE_NUMBER", "MASK_PHONE"),
    ("Bronze", "T_Customer", "CITY", "MASK_LOCATION"),
    ("Bronze", "T_Customer", "STATE_PROVINCE", "MASK_LOCATION"),
    ("Bronze", "T_Account", "ACCOUNT_ID", "MASK_FINANCIAL_ID"),
    ("Bronze", "T_Transaction", "AMOUNT", "MASK_AMOUNT"),
    ("Silver", "DimCustomer", "FIRST_NAME", "MASK_NAME"),
    ("Silver", "DimCustomer", "LAST_NAME", "MASK_NAME"),
    ("Silver", "DimCustomer", "EMAIL_ADDRESS", "MASK_EMAIL"),
    ("Silver", "DimCustomer", "CITY", "MASK_LOCATION"),
    ("Silver", "DimCustomer", "STATE_PROVINCE", "MASK_LOCATION"),
    ("Gold", "FactDailyTransaction", "AMOUNT", "MASK_AMOUNT"),
    ("Gold", "FactDailyAgg", "TOTAL_AMOUNT", "MASK_AMOUNT"),
]


@st.cache_data(ttl=300)
def load_policy_bodies():
    """Load policy bodies from Snowflake via DESCRIBE MASKING POLICY."""
    conn = get_connection()
    cur = conn.cursor()
    bodies = {}
    for policy_name in POLICY_METADATA.keys():
        try:
            cur.execute(f"DESCRIBE MASKING POLICY SSOM_COCO_DB.GOVERNANCE.{policy_name}")
            row = cur.fetchone()
            if row:
                bodies[policy_name] = {
                    "name": row[0],
                    "signature": row[1],
                    "return_type": row[2],
                    "body": row[3],
                }
        except Exception:
            bodies[policy_name] = {
                "name": policy_name,
                "signature": "N/A",
                "return_type": "N/A",
                "body": "Unable to retrieve",
            }
    cur.close()
    return bodies


@st.cache_data(ttl=300)
def load_sample_masked_data():
    """Load sample data showing masked output from Bronze.T_Customer."""
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "SELECT FIRST_NAME, LAST_NAME, EMAIL_ADDRESS, PHONE_NUMBER, CITY, STATE_PROVINCE "
            "FROM SSOM_COCO_DB.BRONZE.T_Customer LIMIT 5"
        )
        columns = [desc[0] for desc in cur.description]
        rows = cur.fetchall()
        cur.close()
        return pd.DataFrame(rows, columns=columns)
    except Exception as e:
        cur.close()
        return pd.DataFrame({"Error": [str(e)]})


# ============================================================
# Page Header
# ============================================================
st.markdown(
    """
    <div class="page-banner">
        <h1>Data Masking Policies</h1>
        <p>SSOM_COCO_DB &nbsp;|&nbsp; GOVERNANCE Schema &nbsp;|&nbsp; PII Protection &amp; Financial Data Redaction</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ============================================================
# Summary Metrics
# ============================================================
total_policies = len(POLICY_METADATA)
total_columns = len(POLICY_ASSIGNMENTS)
protected_tables = len(set((a[0], a[1]) for a in POLICY_ASSIGNMENTS))
layers_covered = len(set(a[0] for a in POLICY_ASSIGNMENTS))

col1, col2, col3, col4 = st.columns(4)
col1.metric("Masking Policies", total_policies)
col2.metric("Protected Columns", total_columns)
col3.metric("Protected Tables", protected_tables)
col4.metric("Layers Covered", layers_covered)

st.markdown("<br>", unsafe_allow_html=True)

# ============================================================
# Tabs
# ============================================================
tab1, tab2, tab3, tab4 = st.tabs([
    "Policy Overview",
    "Column Assignments",
    "Policy Details",
    "Access Control",
])

# ============================================================
# Tab 1: Policy Overview
# ============================================================
with tab1:
    st.markdown(
        '<div class="section-header"><h3>Masking Policy Inventory</h3></div>',
        unsafe_allow_html=True,
    )

    overview_data = []
    for name, meta in POLICY_METADATA.items():
        columns_protected = sum(1 for a in POLICY_ASSIGNMENTS if a[3] == name)
        overview_data.append({
            "Policy": name,
            "Category": meta["category"],
            "Description": meta["description"],
            "Masking Style": meta["style"],
            "Example Input": meta["example_input"],
            "Example Output": meta["example_output"],
            "Columns Protected": columns_protected,
        })

    df_overview = pd.DataFrame(overview_data)
    st.dataframe(
        df_overview,
        use_container_width=True,
        hide_index=True,
        column_config={
            "Policy": st.column_config.TextColumn("Policy", width="medium"),
            "Category": st.column_config.TextColumn("Category", width="medium"),
            "Description": st.column_config.TextColumn("Description", width="large"),
            "Masking Style": st.column_config.TextColumn("Masking Style", width="medium"),
            "Example Input": st.column_config.TextColumn("Input", width="medium"),
            "Example Output": st.column_config.TextColumn("Output", width="small"),
            "Columns Protected": st.column_config.NumberColumn("# Columns", width="small"),
        },
    )

    # Summary by category
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Coverage by Category</h3></div>',
        unsafe_allow_html=True,
    )

    category_counts = {}
    for a in POLICY_ASSIGNMENTS:
        cat = POLICY_METADATA[a[3]]["category"]
        category_counts[cat] = category_counts.get(cat, 0) + 1

    cat_cols = st.columns(len(category_counts))
    for col, (cat, count) in zip(cat_cols, category_counts.items()):
        with col:
            st.metric(cat, f"{count} columns")


# ============================================================
# Tab 2: Column Assignments
# ============================================================
with tab2:
    st.markdown(
        '<div class="section-header"><h3>Policy-to-Column Assignments</h3></div>',
        unsafe_allow_html=True,
    )

    assign_data = []
    for layer, table, column, policy in POLICY_ASSIGNMENTS:
        assign_data.append({
            "Layer": layer,
            "Table": table,
            "Column": column,
            "Policy": policy,
            "Masking Style": POLICY_METADATA[policy]["style"],
        })

    df_assign = pd.DataFrame(assign_data)
    st.dataframe(
        df_assign,
        use_container_width=True,
        hide_index=True,
        height=560,
        column_config={
            "Layer": st.column_config.TextColumn("Layer", width="small"),
            "Table": st.column_config.TextColumn("Table", width="medium"),
            "Column": st.column_config.TextColumn("Column", width="medium"),
            "Policy": st.column_config.TextColumn("Policy", width="medium"),
            "Masking Style": st.column_config.TextColumn("Masking Style", width="large"),
        },
    )

    # Per-layer breakdown
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Assignments by Layer</h3></div>',
        unsafe_allow_html=True,
    )

    for layer in ["Bronze", "Silver", "Gold"]:
        layer_assignments = [a for a in POLICY_ASSIGNMENTS if a[0] == layer]
        if layer_assignments:
            tables = set(a[1] for a in layer_assignments)
            colors = {"Bronze": "#b45309", "Silver": "#64748b", "Gold": "#ca8a04"}
            st.markdown(
                f"""
                <div style="background: {colors[layer]}; border-radius: 8px; padding: 10px 20px;
                            display: inline-block; margin-bottom: 12px;">
                    <span style="color: white; font-weight: 600;">{layer}</span>
                    <span style="color: rgba(255,255,255,0.8); margin-left: 12px;">
                        {len(layer_assignments)} columns across {len(tables)} table(s)
                    </span>
                </div>
                """,
                unsafe_allow_html=True,
            )
            for table in sorted(tables):
                cols = [a[2] for a in layer_assignments if a[1] == table]
                st.text(f"  {table}: {', '.join(cols)}")
            st.markdown("")


# ============================================================
# Tab 3: Policy Details
# ============================================================
with tab3:
    st.markdown(
        '<div class="section-header"><h3>Policy Logic & Implementation</h3></div>',
        unsafe_allow_html=True,
    )

    policy_bodies = load_policy_bodies()

    for policy_name, meta in POLICY_METADATA.items():
        with st.expander(f"{policy_name} — {meta['description']}"):
            col_a, col_b = st.columns([2, 1])

            with col_a:
                st.markdown("**Policy Body (CASE Logic):**")
                body_info = policy_bodies.get(policy_name, {})
                body_text = body_info.get("body", "N/A")
                signature = body_info.get("signature", "N/A")
                return_type = body_info.get("return_type", "N/A")
                st.code(body_text, language="sql")

                st.markdown(f"**Signature:** `{signature}` → `{return_type}`")

            with col_b:
                st.markdown("**Masking Example:**")
                st.markdown(
                    f"""
                    <div style="background: #1e293b; border-radius: 8px; padding: 16px;
                                border: 1px solid #334155;">
                        <div style="color: #94a3b8; font-size: 0.75rem; text-transform: uppercase;">
                            Original
                        </div>
                        <div style="color: #f1f5f9; font-size: 1.1rem; font-weight: 600; margin-bottom: 12px;">
                            {meta['example_input']}
                        </div>
                        <div style="color: #94a3b8; font-size: 0.75rem; text-transform: uppercase;">
                            Masked
                        </div>
                        <div style="color: #f87171; font-size: 1.1rem; font-weight: 600;">
                            {meta['example_output']}
                        </div>
                    </div>
                    """,
                    unsafe_allow_html=True,
                )

                st.markdown("<br>", unsafe_allow_html=True)
                st.markdown("**Applied to:**")
                applied_cols = [
                    f"{a[0]}.{a[1]}.{a[2]}"
                    for a in POLICY_ASSIGNMENTS if a[3] == policy_name
                ]
                for col in applied_cols:
                    st.text(f"  {col}")


# ============================================================
# Tab 4: Access Control
# ============================================================
with tab4:
    st.markdown(
        '<div class="section-header"><h3>Role-Based Access Control</h3></div>',
        unsafe_allow_html=True,
    )

    # Access control matrix
    st.markdown("#### Access Matrix")

    access_data = [
        {"Role": "SYSADMIN", "Access Level": "Full (Unmasked)", "Sees Real Data": "Yes"},
        {"Role": "ACCOUNTADMIN", "Access Level": "Full (Unmasked)", "Sees Real Data": "Yes"},
        {"Role": "All Other Roles", "Access Level": "Masked", "Sees Real Data": "No"},
    ]

    df_access = pd.DataFrame(access_data)
    st.dataframe(
        df_access,
        use_container_width=True,
        hide_index=True,
        column_config={
            "Role": st.column_config.TextColumn("Role", width="medium"),
            "Access Level": st.column_config.TextColumn("Access Level", width="medium"),
            "Sees Real Data": st.column_config.TextColumn("Sees Real Data", width="small"),
        },
    )

    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Live Data Preview (Current Role)</h3></div>',
        unsafe_allow_html=True,
    )

    st.info(
        "The data below is shown as your current role sees it. "
        "If you're connected as SYSADMIN, you'll see unmasked data. "
        "Non-admin roles would see masked values."
    )

    df_sample = load_sample_masked_data()
    st.dataframe(df_sample, use_container_width=True, hide_index=True)

    # Show what masked data would look like
    st.markdown("<br>", unsafe_allow_html=True)
    st.markdown(
        '<div class="section-header"><h3>Masked View (Non-Admin Perspective)</h3></div>',
        unsafe_allow_html=True,
    )

    masked_preview = [
        {
            "FIRST_NAME": "J***",
            "LAST_NAME": "A***",
            "EMAIL_ADDRESS": "j***@email.com",
            "PHONE_NUMBER": "***-***-0101",
            "CITY": "T***",
            "STATE_PROVINCE": "O***",
        },
        {
            "FIRST_NAME": "S***",
            "LAST_NAME": "T***",
            "EMAIL_ADDRESS": "s***@email.com",
            "PHONE_NUMBER": "***-***-0202",
            "CITY": "V***",
            "STATE_PROVINCE": "B***",
        },
        {
            "FIRST_NAME": "M***",
            "LAST_NAME": "C***",
            "EMAIL_ADDRESS": "m***@email.com",
            "PHONE_NUMBER": "***-***-0303",
            "CITY": "M***",
            "STATE_PROVINCE": "Q***",
        },
    ]

    df_masked = pd.DataFrame(masked_preview)
    st.dataframe(df_masked, use_container_width=True, hide_index=True)

    st.caption("Simulated masked output for non-admin roles (PUBLIC, ANALYST, etc.)")


# ============================================================
# Footer
# ============================================================
st.markdown(
    """
    <div class="footer-text">
        Data Governance &nbsp;&bull;&nbsp; GOVERNANCE Schema &nbsp;&bull;&nbsp;
        Dynamic Masking Policies &nbsp;&bull;&nbsp; SSOM_COCO_DB &nbsp;&bull;&nbsp; Powered by Snowflake
    </div>
    """,
    unsafe_allow_html=True,
)
