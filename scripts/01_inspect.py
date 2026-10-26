"""
01_inspect.py
Esplora i file grezzi di IntOGen e DrugCentral prima di progettare le tabelle SQL.
Non modifica nessun dato: stampa solo informazioni a schermo.

Uso (dalla root del progetto):
    python scripts/01_inspect.py
"""
from pathlib import Path

import pandas as pd

# Percorsi calcolati rispetto alla posizione dello script (funziona da qualsiasi cartella)
ROOT = Path(__file__).resolve().parent.parent
INTOGEN = ROOT / "data" / "raw" / "intogen" / "Compendium_Cancer_Genes.tsv"
DRUG = ROOT / "data" / "raw" / "drugcentral" / "drug.target.interaction.tsv"
# In alternativa puoi leggere direttamente il gz:
# DRUG = ROOT / "data" / "raw" / "drugcentral" / "drug.target.interaction.tsv.gz"

pd.set_option("display.width", 200)
pd.set_option("display.max_columns", 50)

# pandas gestisce le virgolette doppie e la compressione .gz in automatico
intogen = pd.read_csv(INTOGEN, sep="\t", low_memory=False)
drug = pd.read_csv(DRUG, sep="\t", low_memory=False)

# --- Ispezione generale -------------------------------------------------------
for name, df in [("IntOGen", intogen), ("DrugCentral", drug)]:
    print(f"\n{'=' * 20} {name} {'=' * 20}")
    print("shape:", df.shape)
    print("columns:", list(df.columns))
    print("\ndtypes:")
    print(df.dtypes)
    print("\nprime righe:")
    print(df.head(3).to_string())
    print("\n% valori nulli (top 15):")
    print((df.isna().mean() * 100).round(1).sort_values(ascending=False).head(15))

# --- Controlli specifici su DrugCentral ---------------------------------------
print("\n" + "=" * 20 + " Colonne chiave DrugCentral " + "=" * 20)
for col in ["ORGANISM", "ACTION_TYPE", "TARGET_CLASS", "MOA"]:
    if col in drug.columns:
        print(f"\n{col}:")
        print(drug[col].dropna().astype(str).value_counts().head(20))

if "GENE" in drug.columns:
    print("\nGENE: nulli =", drug["GENE"].isna().sum(), "| unici =", drug["GENE"].nunique())
    # Alcune righe hanno più geni separati da virgola/spazio: da gestire in fase di pulizia
    multi = drug["GENE"].dropna().astype(str).str.contains(r"[,;\s]")
    print("GENE con più valori nella stessa cella:", multi.sum())

# --- Controlli specifici su IntOGen -------------------------------------------
print("\n" + "=" * 20 + " Colonne chiave IntOGen " + "=" * 20)
for col in ["SYMBOL", "CANCER_TYPE", "ROLE"]:
    if col in intogen.columns:
        print(f"\n{col}: unici = {intogen[col].nunique()}")
        print(intogen[col].dropna().astype(str).value_counts().head(10))

# --- Ponte tra i due dataset: quanti geni in comune? --------------------------
if "SYMBOL" in intogen.columns and "GENE" in drug.columns:
    g_int = set(intogen["SYMBOL"].dropna().astype(str).str.strip().str.upper())
    g_drug = set(drug["GENE"].dropna().astype(str).str.strip().str.upper())
    print("\n" + "=" * 20 + " Geni in comune " + "=" * 20)
    print("geni IntOGen:", len(g_int))
    print("geni DrugCentral:", len(g_drug))
    print("in comune:", len(g_int & g_drug))

# --- UniProt (se il file e' presente in data/raw/uniprot/) ---------------------
uni_files = sorted((ROOT / "data" / "raw" / "uniprot").glob("*.tsv*"))
if uni_files:
    uni = pd.read_csv(uni_files[0], sep="\t", low_memory=False)
    print("\n" + "=" * 20 + f" UniProt ({uni_files[0].name}) " + "=" * 20)
    print("shape:", uni.shape)
    print("columns:", list(uni.columns))
    print(uni.head(3).to_string())
    print("\n% valori nulli:")
    print((uni.isna().mean() * 100).round(1).sort_values(ascending=False))
    if "Entry" in uni.columns:
        print("\nEntry duplicate:", uni["Entry"].duplicated().sum())
    if "Gene Names" in uni.columns:
        n_genes = uni["Gene Names"].dropna().astype(str).str.split().str.len()
        print("Gene Names: nulli =", uni["Gene Names"].isna().sum(),
              "| simboli per proteina (max/medio):", n_genes.max(), "/", round(n_genes.mean(), 2))
    if "Organism" in uni.columns:
        print(uni["Organism"].value_counts().head(5))
    # Quanti accession DrugCentral (umani) sono presenti in UniProt?
    if "Entry" in uni.columns and "ACCESSION" in drug.columns:
        hum = drug[drug["ORGANISM"] == "Homo sapiens"]["ACCESSION"].dropna().astype(str)
        acc = set(hum.str.split(r"[|,;\s]+").explode().str.strip())
        print("\naccession DrugCentral umane:", len(acc),
              "| presenti in UniProt:", len(acc & set(uni["Entry"])))
else:
    print("\n(UniProt non trovato in data/raw/uniprot/: sezione saltata)")