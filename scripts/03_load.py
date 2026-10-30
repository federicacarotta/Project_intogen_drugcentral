"""
03_load.py
Carica gli 8 file CSV puliti presenti in data/clean/ nel database MySQL intogen_drugcentral.

Utilizzo:
    python scripts/03_load.py [--user root] [--password MIA_PASSWORD] [--init-schema]
"""

import os
import sys
import time
import getpass
import argparse
import numpy as np
import pandas as pd
import mysql.connector
from mysql.connector import errorcode

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data", "clean")
SCHEMA_FILE = os.path.join(BASE_DIR, "sql", "schema.sql")

# Ordine gerarchico obbligatorio per rispettare i vincoli di Foreign Key
TABLE_CONFIGS = [
    {
        "table": "protein",
        "file": "protein.csv",
        "columns": ["accession", "entry_name", "protein_name", "target_class", "tdl"],
    },
    {
        "table": "drug",
        "file": "drug.csv",
        "columns": ["struct_id", "drug_name"],
    },
    {
        "table": "cohort",
        "file": "cohort.csv",
        "columns": ["cohort", "cancer_type", "total_samples"],
    },
    {
        "table": "gene_symbol",
        "file": "gene_symbol.csv",
        "columns": ["accession", "symbol", "is_primary"],
    },
    {
        "table": "drug_approval",
        "file": "drug_approval.csv",
        "columns": ["struct_id", "agency"],
    },
    {
        "table": "drug_target",
        "file": "drug_target.csv",
        "columns": ["struct_id", "accession", "moa", "action_type", "moa_source"],
    },
    {
        "table": "activity",
        "file": "activity.csv",
        "columns": [
            "struct_id", "accession", "act_type", "act_value", 
            "relation", "act_source", "act_comment"
        ],
    },
    {
        "table": "intogen_driver",
        "file": "intogen_driver.csv",
        "columns": [
            "symbol", "cohort", "accession", "transcript", "methods",
            "mutations", "samples", "pct_samples_cohort", "qvalue_combination",
            "role", "domains", "clusters_2d", "clusters_3d",
            "excess_mis", "excess_non", "excess_spl", "is_driver"
        ],
    },
]

def parse_args():
    parser = argparse.ArgumentParser(description="Carica dati puliti in MySQL")
    parser.add_argument("--host", default="localhost", help="Host MySQL (default: localhost)")
    parser.add_argument("--port", type=int, default=3306, help="Porta MySQL (default: 3306)")
    parser.add_argument("--user", default="root", help="Utente MySQL (default: root)")
    parser.add_argument("--password", default=None, help="Password MySQL")
    parser.add_argument("--database", default="intogen_drugcentral", help="Nome DB")
    parser.add_argument("--init-schema", action="store_true", help="Esegue sql/schema.sql prima del caricamento")
    parser.add_argument("--batch-size", type=int, default=5000, help="Dimensione batch per inserimento (default: 5000)")
    return parser.parse_args()

def connect_mysql(host, port, user, password, database=None):
    kwargs = {
        "host": host,
        "port": port,
        "user": user,
        "password": password,
        "autocommit": False,
    }
    if database:
        kwargs["database"] = database
    return mysql.connector.connect(**kwargs)

def execute_schema_sql(conn, schema_path):
    print(f"\n[1/3] Creazione schema da {os.path.basename(schema_path)}...")
    cursor = conn.cursor()
    with open(schema_path, "r", encoding="utf-8") as f:
        sql_content = f.read()

    # Rimuove commenti su riga intera e divide per statement
    statements = []
    current_stmt = []
    for line in sql_content.splitlines():
        trimmed = line.strip()
        if trimmed.startswith("--") or not trimmed:
            continue
        current_stmt.append(line)
        if trimmed.endswith(";"):
            stmt_text = "\n".join(current_stmt).strip()
            if stmt_text:
                statements.append(stmt_text)
            current_stmt = []

    for stmt in statements:
        cursor.execute(stmt)

    conn.commit()
    cursor.close()
    print("      ✓ Database e 8 tabelle create con successo.")

def load_table(conn, table_cfg, batch_size=5000):
    table = table_cfg["table"]
    filename = table_cfg["file"]
    columns = table_cfg["columns"]
    filepath = os.path.join(DATA_DIR, filename)

    if not os.path.exists(filepath):
        print(f"      [ERRORE] File non trovato: {filepath}")
        return 0, 0

    df = pd.read_csv(filepath)
    csv_rows = len(df)

    # Assicurati che le colonne richieste esistano nel dataframe
    missing_cols = [c for c in columns if c not in df.columns]
    if missing_cols:
        raise ValueError(f"Colonne mancanti in {filename}: {missing_cols}")

    df_subset = df[columns].copy()

    # Converti NaN in None per MySQL
    df_subset = df_subset.replace({np.nan: None})

    cursor = conn.cursor()

    col_names = ", ".join(columns)
    placeholders = ", ".join(["%s"] * len(columns))
    insert_sql = f"INSERT INTO {table} ({col_names}) VALUES ({placeholders})"

    # Converti in lista di tuple
    data_tuples = [tuple(row) for row in df_subset.to_numpy()]

    start_time = time.time()
    for i in range(0, len(data_tuples), batch_size):
        batch = data_tuples[i : i + batch_size]
        cursor.executemany(insert_sql, batch)

    conn.commit()
    elapsed = time.time() - start_time
    cursor.close()

    print(f"      ✓ {table:<16}: {csv_rows:>6} righe caricate ({elapsed:.2f}s)")
    return csv_rows, elapsed

def verify_counts(conn):
    print("\n[3/3] Verifica dei conteggi su MySQL...")
    cursor = conn.cursor()
    print(f"      {'Tabella':<18} | {'Righe MySQL':>12} | {'Stato':>10}")
    print("      " + "-" * 46)
    
    all_ok = True
    for cfg in TABLE_CONFIGS:
        table = cfg["table"]
        csv_file = os.path.join(DATA_DIR, cfg["file"])
        expected_rows = len(pd.read_csv(csv_file)) if os.path.exists(csv_file) else None

        cursor.execute(f"SELECT COUNT(*) FROM {table}")
        actual_rows = cursor.fetchone()[0]

        status = "OK" if actual_rows == expected_rows else "DISCORDANZA"
        if status != "OK":
            all_ok = False
        print(f"      {table:<18} | {actual_rows:>12} | {status:>10}")

    cursor.close()
    if all_ok:
        print("\n      Tutti i record sono perfettamente allineati con i CSV puliti!")
    else:
        print("\n      Attenzione: rilevate discordanze tra CSV e MySQL.")

def main():
    args = parse_args()

    password = args.password or os.environ.get("MYSQL_PWD")
    if password is None:
        try:
            password = getpass.getpass(f"Inserisci la password MySQL per '{args.user}': ")
        except (EOFError, KeyboardInterrupt):
            print("\nOperazione annullata.")
            sys.exit(1)

    print("=" * 60)
    print(" CARICAMENTO DATI INTOGEN - DRUGCENTRAL IN MYSQL")
    print("=" * 60)

    # 1. Se richiesto, crea schema collegandosi al server (senza specificare il DB)
    if args.init_schema:
        try:
            conn_admin = connect_mysql(args.host, args.port, args.user, password)
            execute_schema_sql(conn_admin, SCHEMA_FILE)
            conn_admin.close()
        except mysql.connector.Error as err:
            print(f"[ERRORE MySQL durante la creazione dello schema]: {err}")
            sys.exit(1)

    # 2. Connessione al database intogen_drugcentral
    try:
        conn = connect_mysql(args.host, args.port, args.user, password, database=args.database)
    except mysql.connector.Error as err:
        if err.errno == errorcode.ER_BAD_DB_ERROR:
            print(f"[AVVISO] Il database '{args.database}' non esiste ancora.")
            print("         Lo creo eseguendo automaticamente sql/schema.sql...")
            conn_admin = connect_mysql(args.host, args.port, args.user, password)
            execute_schema_sql(conn_admin, SCHEMA_FILE)
            conn_admin.close()
            conn = connect_mysql(args.host, args.port, args.user, password, database=args.database)
        else:
            print(f"[ERRORE di connessione]: {err}")
            sys.exit(1)

    print("\n[2/3] Inserimento dati dagli 8 CSV puliti...")
    total_start = time.time()
    for cfg in TABLE_CONFIGS:
        load_table(conn, cfg, batch_size=args.batch_size)
    total_elapsed = time.time() - total_start
    print(f"      Tempo totale caricamento: {total_elapsed:.2f}s")

    # 3. Verifica
    verify_counts(conn)
    conn.close()
    print("\n" + "=" * 60)
    print(" CARICAMENTO COMPLETATO CON SUCCESSO!")
    print("=" * 60)

if __name__ == "__main__":
    main()
