"""
02_clean.py
Legge i file grezzi (IntOGen, DrugCentral, UniProt) e produce in data/clean/
un CSV per ogni tabella dello schema MySQL (schema.sql).

Uso (dalla root del progetto):
    python scripts/02_clean.py
"""
import re
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
CLEAN = ROOT / "data" / "clean"
CLEAN.mkdir(parents=True, exist_ok=True)

INTOGEN = RAW / "intogen" / "Compendium_Cancer_Genes.tsv"
DRUG = RAW / "drugcentral" / "drug.target.interaction.tsv"
SEP = r"[|,;\s]+"  # separatori per le celle con piu' valori (accession / geni)


# ---------------------------------------------------------------- utilita'
def find_uniprot():
    files = sorted((RAW / "uniprot").glob("*.tsv*"))
    if not files:
        raise SystemExit("Nessun file .tsv trovato in data/raw/uniprot/")
    print("UniProt:", files[0].name)
    return files[0]


def pick(df, *names):
    for n in names:
        if n in df.columns:
            return n
    raise SystemExit(f"Colonna non trovata tra {names}. Presenti: {list(df.columns)}")


def split_multi(value):
    if not isinstance(value, str):
        return []
    return [x for x in re.split(SEP, value.strip()) if x]


def mode_or_na(s):
    s = s.dropna()
    return s.mode().iloc[0] if len(s) else pd.NA


def save(df, name):
    df.to_csv(CLEAN / f"{name}.csv", index=False)
    print(f"  {name:<16} {len(df):>7} righe")


# ---------------------------------------------------------------- 1. UniProt
print("\n[1/4] UniProt")
uni = pd.read_csv(find_uniprot(), sep="\t", dtype=str)
c_acc = pick(uni, "Entry")
c_name = pick(uni, "Entry Name")
c_gene = pick(uni, "Gene Names")
c_prot = pick(uni, "Protein names")
if "Organism" in uni.columns:
    uni = uni[uni["Organism"].str.contains("Homo sapiens", na=False)]

protein_uni = (
    uni[[c_acc, c_name, c_prot]]
    .rename(columns={c_acc: "accession", c_name: "entry_name", c_prot: "protein_name"})
    .drop_duplicates("accession")
)

# "Gene Names": simboli separati da spazio, il primo e' quello ufficiale
rows = []
for acc, genes in zip(uni[c_acc], uni[c_gene]):
    for i, sym in enumerate(split_multi(genes)):
        rows.append((acc, sym, int(i == 0)))
gene_uni = pd.DataFrame(rows, columns=["accession", "symbol", "is_primary"])

# ------------------------------------------------------------ 2. DrugCentral
print("\n[2/4] DrugCentral")
drug = pd.read_csv(DRUG, sep="\t", dtype=str, low_memory=False)
drug = drug.apply(lambda c: c.str.strip())
n_all = len(drug)
drug = drug[drug["ORGANISM"] == "Homo sapiens"].reset_index(drop=True)
print(f"  righe totali {n_all} -> solo Homo sapiens {len(drug)}")

# una riga per ogni accession (le celle multiple vengono "esplose")
rows = []
for i, (a, g) in enumerate(zip(drug["ACCESSION"], drug["GENE"])):
    accs, genes = split_multi(a), split_multi(g)
    if len(accs) == len(genes):
        pairs = list(zip(accs, genes))
    else:
        pairs = [(x, genes[0] if len(genes) == 1 else None) for x in accs]
    rows += [(i, x, y) for x, y in pairs]
pairs = pd.DataFrame(rows, columns=["row", "acc", "gene"]).set_index("row")
n_before = len(drug)
drug = drug.drop(columns=["ACCESSION", "GENE"]).join(pairs, how="inner")
print(f"  righe senza ACCESSION scartate: {n_before - drug.index.nunique()}")
print(f"  righe dopo l'esplosione delle celle multiple: {len(drug)}")

drug["struct_id"] = drug["STRUCT_ID"].astype(int)
drug["act_value"] = pd.to_numeric(drug["ACT_VALUE"], errors="coerce")
drug["moa"] = (pd.to_numeric(drug["MOA"], errors="coerce").fillna(0) > 0).astype(int)

# --- drug
d_names = drug.groupby("struct_id")["DRUG_NAME"].agg(["first", "nunique"])
print(f"  STRUCT_ID con piu' nomi diversi: {(d_names['nunique'] > 1).sum()}")
drug_t = d_names["first"].rename("drug_name").reset_index()

# --- info sul bersaglio (una riga per accession)
targets = drug.groupby("acc").agg(
    target_name=("TARGET_NAME", "first"),
    swissprot=("SWISSPROT", "first"),
    target_class=("TARGET_CLASS", "first"),
    tdl=("TDL", "first"),
)

# --- protein = UniProt + "stub" per le accession DrugCentral assenti in UniProt
missing = targets[~targets.index.isin(protein_uni["accession"])]
print(f"  accession DrugCentral assenti in UniProt (creo stub): {len(missing)}")
stubs = pd.DataFrame(
    {
        "accession": missing.index,
        "entry_name": missing["swissprot"].values,
        "protein_name": missing["target_name"].values,
    }
)
protein = pd.concat([protein_uni, stubs], ignore_index=True).merge(
    targets[["target_class", "tdl"]], left_on="accession", right_index=True, how="left"
)

# --- gene_symbol = UniProt + geni DrugCentral delle accession "stub"
stub_genes = (
    drug[drug["acc"].isin(missing.index) & drug["gene"].notna()][["acc", "gene"]]
    .drop_duplicates()
    .rename(columns={"acc": "accession", "gene": "symbol"})
)
stub_genes["is_primary"] = (~stub_genes.duplicated("accession")).astype(int)
gene_symbol = pd.concat([gene_uni, stub_genes], ignore_index=True).drop_duplicates(
    ["accession", "symbol"]
)

# --- drug_target: coppie uniche farmaco-bersaglio
conf = drug.groupby(["struct_id", "acc"])["ACTION_TYPE"].nunique()
print(f"  coppie con ACTION_TYPE in conflitto (uso il piu' frequente): {(conf > 1).sum()}")
drug_target = (
    drug.groupby(["struct_id", "acc"])
    .agg(
        moa=("moa", "max"),
        action_type=("ACTION_TYPE", mode_or_na),
        moa_source=("MOA_SOURCE", mode_or_na),
    )
    .reset_index()
    .rename(columns={"acc": "accession"})
)

# --- activity: solo le righe con un valore di attivita' misurato
activity = drug[drug["act_value"].notna()][
    ["struct_id", "acc", "ACT_TYPE", "act_value", "RELATION", "ACT_SOURCE", "ACT_COMMENT"]
].rename(
    columns={
        "acc": "accession",
        "ACT_TYPE": "act_type",
        "RELATION": "relation",
        "ACT_SOURCE": "act_source",
        "ACT_COMMENT": "act_comment",
    }
)

# --------------------------------------------------------------- 3. IntOGen
print("\n[3/4] IntOGen")
ig = pd.read_csv(INTOGEN, sep="\t", low_memory=False)
ig = ig.rename(
    columns={
        "SYMBOL": "symbol",
        "TRANSCRIPT": "transcript",
        "COHORT": "cohort",
        "METHODS": "methods",
        "MUTATIONS": "mutations",
        "SAMPLES": "samples",
        "%_SAMPLES_COHORT": "pct_samples_cohort",
        "QVALUE_COMBINATION": "qvalue_combination",
        "ROLE": "role",
        "DOMAINS": "domains",
        "2D_CLUSTERS": "clusters_2d",
        "3D_CLUSTERS": "clusters_3d",
        "EXCESS_MIS": "excess_mis",
        "EXCESS_NON": "excess_non",
        "EXCESS_SPL": "excess_spl",
        "IS_DRIVER": "is_driver",
    }
)
ig["symbol"] = ig["symbol"].str.strip()
ig["is_driver"] = ig["is_driver"].astype(str).str.lower().eq("true").astype(int)
for c in ["mutations", "samples", "TOTAL_SAMPLES"]:
    ig[c] = ig[c].round().astype("Int64")

# --- cohort
co = ig.groupby("cohort").agg(
    cancer_type=("CANCER_TYPE", "first"),
    ct_n=("CANCER_TYPE", "nunique"),
    total_samples=("TOTAL_SAMPLES", "first"),
    ts_n=("TOTAL_SAMPLES", "nunique"),
)
print(f"  coorti con valori incoerenti: {((co['ct_n'] > 1) | (co['ts_n'] > 1)).sum()}")
cohort = co[["cancer_type", "total_samples"]].reset_index()

# --- intogen_driver (+ collegamento a protein tramite simbolo)
dups = ig.duplicated(["symbol", "cohort"]).sum()
print(f"  duplicati (symbol, cohort) scartati: {dups}")
ig = ig.drop_duplicates(["symbol", "cohort"])

key = gene_symbol.assign(key=gene_symbol["symbol"].str.upper()).sort_values(
    "is_primary", ascending=False, kind="stable"
)
n_acc = key.groupby("key")["accession"].nunique()
ambiguous = set(n_acc[n_acc > 1].index)
sym2acc = key.drop_duplicates("key").set_index("key")["accession"]

ig["accession"] = ig["symbol"].str.upper().map(sym2acc)
uniq = ig.drop_duplicates("symbol")
n_unmatched = uniq["accession"].isna().sum()
print(f"  simboli IntOGen: {len(uniq)} | senza accession: {n_unmatched}")
print(f"  simboli con piu' accession possibili (scelta la primaria): "
      f"{uniq['symbol'].str.upper().isin(ambiguous).sum()}")
if n_unmatched:
    print("  esempi senza match:", list(uniq[uniq['accession'].isna()]['symbol'])[:15])

intogen_driver = ig[
    [
        "symbol", "cohort", "accession", "transcript", "methods", "mutations", "samples",
        "pct_samples_cohort", "qvalue_combination", "role", "domains", "clusters_2d",
        "clusters_3d", "excess_mis", "excess_non", "excess_spl", "is_driver",
    ]
]

# ---------------------------------------------- controlli lunghezza vs schema
LIMITS = [
    (protein, "accession", 10), (protein, "entry_name", 30), (protein, "protein_name", 500),
    (protein, "target_class", 50), (protein, "tdl", 10), (gene_symbol, "symbol", 50),
    (drug_t, "drug_name", 255), (drug_target, "action_type", 50),
    (drug_target, "moa_source", 50), (activity, "act_type", 20), (activity, "relation", 5),
    (activity, "act_source", 50), (intogen_driver, "methods", 255),
    (intogen_driver, "transcript", 20), (cohort, "cohort", 60), (cohort, "cancer_type", 20),
]
print("\nControllo lunghezze rispetto a schema.sql:")
problems = 0
for df, col, limit in LIMITS:
    longest = df[col].dropna().astype(str).str.len().max()
    if pd.notna(longest) and longest > limit:
        problems += 1
        print(f"  ATTENZIONE {col}: max {longest} > VARCHAR({limit})")
print("  tutto ok" if not problems else "  -> allarga i VARCHAR indicati in schema.sql")

# ---------------------------------------------------------------- 4. scrittura
print("\n[4/4] Scrittura in data/clean/")
save(protein, "protein")
save(gene_symbol, "gene_symbol")
save(drug_t, "drug")
save(drug_target, "drug_target")
save(activity, "activity")
save(cohort, "cohort")
save(intogen_driver, "intogen_driver")

with_drug = set(intogen_driver["accession"].dropna()) & set(drug_target["accession"])
print(f"\nGeni driver IntOGen con almeno un farmaco in DrugCentral: "
      f"{intogen_driver[intogen_driver['accession'].isin(with_drug)]['symbol'].nunique()}")