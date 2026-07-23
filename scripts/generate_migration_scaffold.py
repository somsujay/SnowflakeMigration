#!/usr/bin/env python3
"""
generate_migration_scaffold.py

Reads the SCHEMACHANGE_HISTORY table from a Snowflake environment and generates
the corresponding V/R/A file structure locally. Useful for:
  - Bootstrapping a new project from an existing deployed state
  - Verifying local file structure matches what's been applied
  - Recovering migration file layout after accidental deletion

Usage:
    python scripts/generate_migration_scaffold.py --env=dev
    python scripts/generate_migration_scaffold.py --env=preprod --output-dir=./recovered
    python scripts/generate_migration_scaffold.py --env=prod --dry-run
"""

import argparse
import os
import sys
from pathlib import Path

import yaml

try:
    import snowflake.connector
except ImportError:
    sys.exit("ERROR: snowflake-connector-python is required. Install with: pip install snowflake-connector-python")


# Default mapping of script names to subdirectories within banking/
SCRIPT_TO_SUBDIR = {
    "V1.0.0__setup_schemas.sql": "_platform",
    "V1.1.0__bronze_tables.sql": "bronze/retail",
    "V1.2.0__silver_tables.sql": "silver/retail",
    "V1.3.0__gold_tables.sql": "gold/retail",
    "V1.4.0__silver_procedures.sql": "silver/retail",
    "V1.5.0__gold_procedures.sql": "gold/retail",
    "V1.6.0__orchestration.sql": "orchestration",
    "V1.7.0__seed_data.sql": "reference",
    "V1.7.1__ingestion_tasks.sql": "orchestration",
    "V1.8.0__masking_policies.sql": "governance",
    "V1.9.0__data_quality.sql": "governance",
    "V1.10.0__iceberg_objects.sql": "reference",
    "R__gold_views.sql": "gold/retail",
    "A__grants.sql": "governance",
}

# Heuristic rules for auto-classifying unknown scripts
SUBDIR_RULES = [
    (["schema", "setup", "platform"], "_platform"),
    (["bronze"], "bronze/retail"),
    (["silver"], "silver/retail"),
    (["gold", "fact", "dim_date"], "gold/retail"),
    (["orchestration", "task", "ingestion"], "orchestration"),
    (["seed", "reference", "iceberg", "parquet"], "reference"),
    (["grant", "mask", "policy", "quality", "governance"], "governance"),
]


def classify_script(script_name: str) -> str:
    """Determine the subdirectory for a script based on known mappings or heuristics."""
    if script_name in SCRIPT_TO_SUBDIR:
        return SCRIPT_TO_SUBDIR[script_name]

    name_lower = script_name.lower()
    for keywords, subdir in SUBDIR_RULES:
        if any(kw in name_lower for kw in keywords):
            return subdir

    return "_unclassified"


def get_connection_params(env: str, project_dir: Path) -> dict:
    """Read connection parameters from environments.yml and local Snowflake config."""
    env_file = project_dir / "environments.yml"
    if not env_file.exists():
        sys.exit(f"ERROR: {env_file} not found")

    with open(env_file) as f:
        envs = yaml.safe_load(f)

    if env not in envs:
        sys.exit(f"ERROR: Environment '{env}' not found in {env_file}. Available: {list(envs.keys())}")

    env_config = envs[env]
    database = env_config["database"]
    warehouse = env_config["warehouse"]
    connection_name = env_config["connection"]

    # Try to read connection details from ~/.snowflake/connections.toml
    conn_file = Path.home() / ".snowflake" / "connections.toml"
    if not conn_file.exists():
        sys.exit(f"ERROR: {conn_file} not found. Configure your Snowflake connection.")

    # Parse TOML (simple parser for connections.toml)
    try:
        import tomlkit
        with open(conn_file) as f:
            connections = tomlkit.load(f)
    except ImportError:
        # Fallback: basic parsing
        connections = _parse_toml_basic(conn_file, connection_name)

    if connection_name not in connections:
        sys.exit(f"ERROR: Connection '{connection_name}' not found in {conn_file}")

    conn = connections[connection_name]

    params = {
        "account": conn.get("account", ""),
        "user": conn.get("user", ""),
        "warehouse": warehouse,
        "database": database,
    }

    # Determine auth method
    if conn.get("authenticator") == "SNOWFLAKE_JWT" and conn.get("private_key_path"):
        params["private_key_path"] = conn["private_key_path"]
    elif conn.get("password"):
        params["password"] = conn["password"]
    elif conn.get("authenticator") == "externalbrowser":
        params["authenticator"] = "externalbrowser"
    else:
        params["authenticator"] = "externalbrowser"

    return params


def _parse_toml_basic(conn_file: Path, connection_name: str) -> dict:
    """Basic TOML parser fallback when tomlkit is not available."""
    connections = {}
    current_section = None

    with open(conn_file) as f:
        for line in f:
            line = line.strip()
            if line.startswith("[") and line.endswith("]"):
                current_section = line[1:-1]
                connections[current_section] = {}
            elif "=" in line and current_section:
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                connections[current_section][key] = value

    return connections


def connect_snowflake(params: dict):
    """Create a Snowflake connection."""
    connect_args = {
        "account": params["account"],
        "user": params["user"],
        "warehouse": params["warehouse"],
        "database": params["database"],
    }

    if "private_key_path" in params:
        from cryptography.hazmat.primitives import serialization
        key_path = os.path.expanduser(params["private_key_path"])
        with open(key_path, "rb") as f:
            private_key = serialization.load_pem_private_key(f.read(), password=None)
        connect_args["private_key"] = private_key.private_bytes(
            encoding=serialization.Encoding.DER,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    elif "password" in params:
        connect_args["password"] = params["password"]
    elif "authenticator" in params:
        connect_args["authenticator"] = params["authenticator"]

    return snowflake.connector.connect(**connect_args)


def fetch_history(conn, database: str) -> list[dict]:
    """Query SCHEMACHANGE_HISTORY and return unique successful migrations."""
    query = f"""
        SELECT VERSION, DESCRIPTION, SCRIPT, SCRIPT_TYPE, CHECKSUM, INSTALLED_ON
        FROM {database}.METADATA.SCHEMACHANGE_HISTORY
        WHERE STATUS = 'Success'
        ORDER BY INSTALLED_ON ASC
    """
    cursor = conn.cursor()
    cursor.execute(query)
    columns = [col[0].lower() for col in cursor.description]
    rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    cursor.close()

    # Deduplicate: keep only the latest entry per script name
    seen = {}
    for row in rows:
        seen[row["script"]] = row

    return list(seen.values())


def generate_scaffold(migrations: list[dict], output_dir: Path, dry_run: bool) -> None:
    """Create the directory structure and placeholder migration files."""
    print(f"\n{'[DRY-RUN] ' if dry_run else ''}Generating migration scaffold in: {output_dir}\n")
    print(f"  Found {len(migrations)} unique migration(s) in history\n")

    created_files = []

    for mig in migrations:
        script_name = mig["script"]
        script_type = mig["script_type"]
        version = mig.get("version", "")
        description = mig.get("description", "")
        checksum = mig.get("checksum", "")

        subdir = classify_script(script_name)
        file_path = output_dir / subdir / script_name

        # Build placeholder content
        header = f"/* {'=' * 60}\n"
        header += f"   schemachange Migration: {script_name}\n"
        header += f"   TYPE        : {script_type} ({'Versioned' if script_type == 'V' else 'Repeatable' if script_type == 'R' else 'Always-run'})\n"
        if version:
            header += f"   VERSION     : {version}\n"
        header += f"   DESCRIPTION : {description}\n"
        header += f"   CHECKSUM    : {checksum}\n"
        header += f"   {'=' * 60} */\n\n"
        header += "USE DATABASE {{ database }};\n\n"
        header += f"-- TODO: Add SQL content for {description}\n"

        print(f"  {'[DRY-RUN] ' if dry_run else ''}{'CREATE' if not file_path.exists() else 'EXISTS'}: {file_path.relative_to(output_dir)}")

        if not dry_run:
            file_path.parent.mkdir(parents=True, exist_ok=True)
            if not file_path.exists():
                with open(file_path, "w") as f:
                    f.write(header)
                created_files.append(file_path)
            else:
                print(f"           (skipped — file already exists)")

    print(f"\n{'[DRY-RUN] Would create' if dry_run else 'Created'} {len(created_files) if not dry_run else len([m for m in migrations if not (output_dir / classify_script(m['script']) / m['script']).exists()])} new file(s)")

    if not dry_run and created_files:
        print("\nGenerated files (placeholders — replace TODO with actual SQL):")
        for f in created_files:
            print(f"  {f.relative_to(output_dir)}")


def print_summary(migrations: list[dict]) -> None:
    """Print a summary table of discovered migrations."""
    print("\n  Migration History Summary:")
    print(f"  {'─' * 70}")
    print(f"  {'Type':<6} {'Version':<10} {'Script':<40} {'Subdir'}")
    print(f"  {'─' * 70}")
    for mig in migrations:
        script = mig["script"]
        print(f"  {mig['script_type']:<6} {mig.get('version', ''):<10} {script:<40} {classify_script(script)}")
    print(f"  {'─' * 70}")


def main():
    parser = argparse.ArgumentParser(
        description="Generate schemachange V/R/A file structure from SCHEMACHANGE_HISTORY"
    )
    parser.add_argument("--env", required=True, help="Environment to read from (dev, qa, preprod, prod)")
    parser.add_argument("--output-dir", default=None, help="Output directory (default: ./banking)")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be created without writing files")
    parser.add_argument("--summary-only", action="store_true", help="Only print migration summary, don't generate files")

    args = parser.parse_args()

    # Resolve project directory
    script_dir = Path(__file__).resolve().parent
    project_dir = script_dir.parent

    # Default output to banking/ in project root
    output_dir = Path(args.output_dir) if args.output_dir else project_dir / "banking"
    output_dir = output_dir.resolve()

    print(f"Environment: {args.env}")
    print(f"Output dir:  {output_dir}")

    # Connect and fetch history
    params = get_connection_params(args.env, project_dir)
    print(f"Database:    {params['database']}")
    print(f"Connecting to Snowflake...")

    conn = connect_snowflake(params)
    print("Connected.")

    migrations = fetch_history(conn, params["database"])
    conn.close()

    if not migrations:
        print("\nNo migrations found in SCHEMACHANGE_HISTORY. Is the table populated?")
        sys.exit(0)

    print_summary(migrations)

    if not args.summary_only:
        generate_scaffold(migrations, output_dir, args.dry_run)

    print("\nDone.")


if __name__ == "__main__":
    main()
