# Progetto IntOGen – DrugCentral

Questo progetto realizza un **database relazionale ottimizzato** che integra e mette in correlazione due domini complementari della biomedicina computazionale:

1. **La genomica del cancro** (dati **IntOGen**): il compendio dei geni le cui mutazioni somatiche guidano la trasformazione tumorale (*driver genes*).
2. **La farmacologia clinica e molecolare** (dati **DrugCentral**): principi attivi, bersagli proteici, meccanismi d'azione terapeutici primari (MoA) e approvazioni regolatorie ufficiali (FDA, EMA, PMDA).

L'integrazione semantica e relazionale tra i due sistemi è resa possibile da **UniProt Swiss-Prot**, che funge da dizionario canonico e ponte anagrafico attraverso codici di accessione univoci (es. `P04637` per TP53, `P01116` per KRAS, `P00533` per EGFR).

```
┌─────────────────────────┐             ┌─────────────────────────┐             ┌─────────────────────────┐
│         IntOGen         │             │         UniProt         │             │       DrugCentral       │
│  Geni driver oncologici │ ──────────► │   Anagrafica proteine   │ ◄────────── │   Farmaci e bersagli    │
│   (coorti e mutazioni)  │  accession  │  (mapping e sinonimi)   │  accession  │  (approvazioni ed enti) │
└─────────────────────────┘             └─────────────────────────┘             └─────────────────────────┘
```

---

## Architettura e Struttura della Repository

```
Project_intogen_drugcentral/
│
├── data/
│   ├── raw/                 ← Dataset originali non modificati
│   │   ├── intogen/         ← Compendium_Cancer_Genes.tsv (4.478 righe)
│   │   ├── drugcentral/     ← drug.target.interaction.tsv e registri approvazioni
│   │   └── uniprot/         ← Anagrafica Swiss-Prot Homo sapiens (20.431 proteine reviewed)
│   │
│   └── clean/               ← Dati normalizzati e conformi allo schema relazionale (7 CSV)
│       ├── protein.csv
│       ├── gene_symbol.csv
│       ├── drug.csv
│       ├── drug_approval.csv
│       ├── drug_target.csv
│       ├── cohort.csv
│       └── intogen_driver.csv
│
├── scripts/
│   ├── 01_inspect.py        ← Profilazione e validazione dei tipi nei file grezzi
│   ├── 02_clean.py          ← Pipeline ETL di pulizia, deduplicazione e normalizzazione
│   └── 03_load.py           ← Inizializzazione schema DDL e caricamento batch in MySQL
│
├── sql/
│   ├── schema.sql           ← Schema relazionale DDL (7 tabelle, chiavi primarie, vincoli FK e indici)
│   └── queries.sql          ← Vista integrata, controlli QC e le 8 query d'esame omogeneizzate
│
├── docs/
│   └── README.md            ← Documentazione tecnica del progetto
│
└── README.md                ← Symlink a docs/README.md
```

---

## Le Tre Sorgenti Dati

### 1. IntOGen — Genomica dei Driver Oncologici
* **Ruolo**: Compendio statistico di mutazioni somatiche identificate tramite sequenziamento esomico e genomico (WES/WGS) su pazienti oncologici.
* **Granularità**: Ogni record descrive l'identificazione di un gene driver all'interno di una coorte clinica (`COHORT`) per uno specifico istotipo tumorale (`CANCER_TYPE`).
* **Campi salienti**:
  * `SYMBOL`: Simbolo HGNC del gene (es. TP53, KRAS, EGFR).
  * `ROLE`: Ruolo biologico predetto: **Act** (oncogene attivante) o **LoF** (oncosoppressore a perdita di funzione).
  * `MUTATIONS` / `SAMPLES` / `TOTAL_SAMPLES`: Conteggi mutazionali, pazienti mutati e ampiezza campionaria dello studio.
  * `QVALUE_COMBINATION`: Significatività statistica combinata corretta per False Discovery Rate (FDR).
* **Volumetria**: 633 geni driver unici, 260 coorti cliniche, 86 tipi di tumore.

---

### 2. DrugCentral — Farmacologia Molecolare e Regolatoria
* **Ruolo**: Repository farmacologico integrato sviluppato dall'Università del New Mexico.
* **Granularità**: Mappe delle interazioni farmaco-bersaglio e stato autorizzativo per agenzia.
* **Campi salienti**:
  * `STRUCT_ID` / `DRUG_NAME`: Identificativo numerico primario e denominazione comune internazionale del principio attivo.
  * `ACCESSION`: Codice proteico UniProt del bersaglio molecolare umano.
  * `ACTION_TYPE`: Effetto funzionale (es. *INHIBITOR*, *ANTAGONIST*, *AGONIST*, *BLOCKER*, *ANTIBODY BINDING*).
  * `MOA`: Flag binario (1 = Meccanismo d'Azione terapeutico primario; 0 = Interazione secondaria o dato di screening).
  * `TDL`: *Target Development Level* (Tclin = bersaglio clinico convalidato con farmaci approvati).
* **Volumetria**: 2.632 farmaci attivi su bersagli umani, 18.228 interazioni uniche farmaco-bersaglio, 2.401 approvazioni regolatorie (FDA, EMA, PMDA).

---

### 3. UniProt (Swiss-Prot) — Anagrafica e Dizionario Ponte
* **Ruolo**: Riconciliazione delle discrepanze di nomenclatura e ponte anagrafico.
* **Funzione relazionale**:
  * IntOGen indicizza le mutazioni tramite **simbolo genico** (`SYMBOL`).
  * DrugCentral indicizza i bersagli tramite **accession proteica** (`ACCESSION`).
  * La tabella `gene_symbol` (45.565 record) mappa ogni simbolo ufficiale e sinonimo storico genico al relativo codice UniProt, isolando il gene primario HGNC (`is_primary = 1`).
* **Volumetria**: 20.433 proteine umane curate manualmente (*reviewed*).

---

## Schema Relazionale (7 Tabelle in MySQL)

```
                            ┌───────────────┐
                            │    cohort     │
                            ├───────────────┤
                            │ PK  cohort    │
                            │     c_type    │
                            │     t_samples │
                            └───────┬───────┘
                                    │ 1
                                    │
                                    │ N
 ┌───────────────┐          ┌───────┴───────┐
 │  gene_symbol  │          │intogen_driver │
 ├───────────────┤          ├───────────────┤
 │ PK  id        │   N    1 │ PK  id        │
 │ FK  accession ├──────────┤ FK  cohort    │
 │     symbol    │          │ FK  accession │
 │     is_primary│          │     role, qval│
 └───────────────┘          └───────┬───────┘
                                    │ N
                                    │
                                    │ 1
                            ┌───────┴───────┐
                            │    protein    │
                            ├───────────────┤
                            │ PK  accession │
                            │     p_name    │
                            │     t_class   │
                            │     tdl       │
                            └───────┬───────┘
                                    │ 1
                                    │ N
                            ┌───────┴───────┐       ┌───────────────┐
                            │  drug_target  │       │ drug_approval │
                            ├───────────────┤       ├───────────────┤
                            │ PK  id        │       │ PK,FK struct_id
                            │ FK  struct_id ├──┐    │ PK    agency  │
                            │ FK  accession │  │    └───────┬───────┘
                            │     moa, act  │  │            │ N
                            └───────────────┘  │            │
                                               │            │ 1
                                               │    ┌───────┴───────┐
                                               └───►│     drug      │
                                                    ├───────────────┤
                                                    │ PK  struct_id │
                                                    │     drug_name │
                                                    └───────────────┘
```

| Tabella | Record | Chiave Primaria | Chiavi Esterne (FK) | Ruolo Relazionale |
|:---|:---:|:---|:---|:---|
| **`protein`** | 20.433 | `accession` | — | Entità anagrafica centrale delle sequenze proteiche umane (UniProt) |
| **`gene_symbol`** | 45.565 | `id` (AUTO_INCREMENT) | `accession` $\rightarrow$ `protein` | Risoluzione del mapping 1:N tra proteina e sinonimi genici HGNC |
| **`drug`** | 2.632 | `struct_id` | — | Anagrafica molecolare dei farmaci censiti in DrugCentral |
| **`drug_approval`** | 2.401 | `(struct_id, agency)` | `struct_id` $\rightarrow$ `drug` | Entità debole per le autorizzazioni regolatorie (FDA, EMA, PMDA) |
| **`drug_target`** | 18.228 | `id` (UQ su `struct_id, accession`) | `struct_id`, `accession` | Tabella di giunzione N:M tra farmaci e proteine con metadati d'azione |
| **`cohort`** | 260 | `cohort` | — | Entità dimensionale degli studi clinici e relativi istotipi tumorali |
| **`intogen_driver`** | 4.478 | `id` (UQ su `symbol, cohort`) | `cohort`, `accession` | Tabella dei fatti mutazionali per coorte e gene oncologico |

---

## Analisi e Specifiche Tecniche delle Singole Tabelle (DDL)

Lo schema è progettato per garantire **integrità referenziale rigorosa**, **assenza di ridondanza (3NF)** e **prestazioni ottimali sulle giunzioni**. Di seguito il dettaglio architetturale di ciascuna tabella definita in [`sql/schema.sql`](file:///Users/federica/Desktop/Project_intogen_drugcentral/sql/schema.sql):

### 1. Tabella `protein` (Anagrafica Proteica Centrale)
* **Scopo**: Costituisce il dizionario anagrafico centrale dell'intero database. Raccoglie le sequenze proteiche umane revisionate (*reviewed*) da UniProt Swiss-Prot, oltre a due stub necessari per garantire l'integrità referenziale con bersagli censiti in DrugCentral.
* **Chiave Primaria**: `accession` (`VARCHAR(15)`), identificatore alfanumerico canonico internazionale (es. `P00533` per EGFR, `P04637` per TP53).
* **Attributi**:
  * `entry_name` (`VARCHAR(30)`): Identificativo mnemonico UniProt (es. `EGFR_HUMAN`).
  * `protein_name` (`TEXT`): Denominazione descrittiva estesa della proteina e degli enzimi associati.
  * `target_class` (`VARCHAR(50)`): Famiglia biologica e strutturale del bersaglio (es. *Kinase*, *GPCR*, *Enzyme*, *Ion channel*).
  * `tdl` (`VARCHAR(10)`): *Target Development Level*, metrica di maturità farmacologica (es. `Tclin` per proteine con farmaci approvati in clinica, `Tdark` per proteine poco studiate).
* **Indici**: Indice univoco clusterizzato sulla chiave primaria `accession`.

---

### 2. Tabella `gene_symbol` (Dizionario di Mapping e Sinonimi Genici)
* **Scopo**: Risolve la cardinalità 1:N tra sequenza proteica e nomenclatura genica. Un gene può avere molteplici denominazioni storiche o sinonimi di laboratorio, ma fa capo a una singola proteina canonica.
* **Chiave Primaria**: `id` (`INT AUTO_INCREMENT`).
* **Vincoli e Integrità**:
  * `accession` (`VARCHAR(15)`): Chiave esterna verso `protein(accession)` con `ON UPDATE CASCADE ON DELETE CASCADE`.
  * `symbol` (`VARCHAR(50)`): Simbolo genico.
  * `is_primary` (`TINYINT(1)`): Flag booleano (`1` se è la nomenclatura ufficiale approvata da HGNC, `0` se è un sinonimo secondario).
  * `UNIQUE KEY uq_acc_sym (accession, symbol)`: Impedisce duplicazioni logiche della medesima coppia gene-proteina.
  * `KEY idx_symbol (symbol)`: Indice secondario fondamentale per velocizzare la ricerca per simbolo testuale.

---

### 3. Tabella `drug` (Anagrafica Molecole Farmacologiche)
* **Scopo**: Catalogo delle entità molecolari terapeutiche e dei principi attivi censiti da DrugCentral con attività su bersagli umani.
* **Chiave Primaria**: `struct_id` (`INT`), identificativo numerico primario della molecola in DrugCentral.
* **Attributi**:
  * `drug_name` (`VARCHAR(255)`): Denominazione comune internazionale (DCI) del principio attivo (es. *erlotinib*, *gefitinib*, *imatinib*).
* **Ingegneria dei dati**: Separa l'anagrafica del farmaco dalle sue interazioni e dalle agenzie di autorizzazione, evitando anomalie di aggiornamento sul nome molecolare.

---

### 4. Tabella `drug_approval` (Certificazioni Regolatorie)
* **Scopo**: Modella la relazione 1:N tra un farmaco e le agenzie sanitarie governative che ne hanno approvato l'immissione in commercio.
* **Chiave Primaria Composta**: `(struct_id, agency)`.
* **Attributi e Vincoli**:
  * `struct_id` (`INT`): Chiave esterna verso `drug(struct_id)` con eliminazione e aggiornamento a cascata (`CASCADE`).
  * `agency` (`VARCHAR(10)`): Ente regolatore autorizzativo: `FDA` (Food and Drug Administration, USA), `EMA` (European Medicines Agency, Europa), `PMDA` (Pharmaceuticals and Medical Devices Agency, Giappone).
* **Normalizzazione**: Consente a ciascun farmaco di avere da 0 a 3 registrazioni distinte, rispettando la 1NF ed evitando campi concatenati o colonne fisse e ridondanti.

---

### 5. Tabella `drug_target` (Relazione N:M Farmaco – Bersaglio Proteico)
* **Scopo**: Tabella di giunzione centrale tra i farmaci (`drug`) e le proteine bersaglio (`protein`). Conserva le informazioni funzionali dell'interazione terapeutica.
* **Chiave Primaria**: `id` (`INT AUTO_INCREMENT`).
* **Vincoli e Attributi**:
  * `struct_id` (`INT`): Chiave esterna verso `drug(struct_id)` (`ON DELETE CASCADE`).
  * `accession` (`VARCHAR(15)`): Chiave esterna verso `protein(accession)` (`ON DELETE CASCADE`).
  * `target_class` (`VARCHAR(50)`): Famiglia del bersaglio convalidata farmacologicamente.
  * `moa` (`TINYINT(1)`): Flag Meccanismo d'Azione (`1` se l'interazione costituisce il target terapeutico primario per cui il farmaco è prescritto; `0` per interazioni secondarie o dati di binding generico).
  * `action_type` (`VARCHAR(50)`): Tipo di azione biologica (es. `INHIBITOR`, `ANTAGONIST`, `AGONIST`, `BLOCKER`, `ANTIBODY BINDING`).
  * `moa_source` (`VARCHAR(50)`): Fonte che valida il meccanismo (es. letteratura FDA, ChEMBL).
  * `UNIQUE KEY uq_drug_target (struct_id, accession)`: Impedisce record duplicati per la medesima interazione chimico-fisica.
  * Indici dedicati: `idx_dt_accession` e `idx_dt_class` per ottimizzare le interrogazioni di ricerca.

---

### 6. Tabella `cohort` (Dimensione Studi Clinici e Istotipi)
* **Scopo**: Entità dimensionale che censisce i 260 studi clinici di sequenziamento oncologico analizzati dalla piattaforma IntOGen.
* **Chiave Primaria**: `cohort` (`VARCHAR(80)`), codice identificativo univoco dello studio clinico (es. `TCGA_WXS_BRCA`, `HARTWIG_WGS_LUAD_2023`).
* **Attributi**:
  * `cancer_type` (`VARCHAR(30)`): Sigla dell'istotipo tumorale analizzato (es. `BRCA` mammella, `LUAD` polmone, `GBM` glioblastoma, `PAAD` pancreas).
  * `total_samples` (`INT`): Numero totale di pazienti/campioni biologici sequenziati all'interno della coorte.
* **Razionale di Normalizzazione (3NF)**: Nel file grezzo `total_samples` e `cancer_type` erano replicati su ogni riga di gene driver. Isolandoli nella tabella `cohort`:
  1. Si eliminano dipendenze parziali e ridondanze.
  2. Si previene l'errore sistematico di moltiplicazione (*fan trap*): eseguire `SUM(total_samples)` restituisce il volume reale di pazienti senza moltiplicarlo per il numero di geni identificati nello studio.

---

### 7. Tabella `intogen_driver` (Fatti Mutazionali e Geni Oncologici)
* **Scopo**: Tabella dei fatti che raccoglie le osservazioni statistiche sui geni driver identificati per ciascuna coorte clinica.
* **Chiave Primaria**: `id` (`INT AUTO_INCREMENT`).
* **Vincoli e Attributi**:
  * `symbol` (`VARCHAR(50)`): Simbolo HGNC del gene driver.
  * `cohort` (`VARCHAR(80)`): Chiave esterna verso `cohort(cohort)` (`ON UPDATE CASCADE ON DELETE CASCADE`).
  * `accession` (`VARCHAR(15)`): Chiave esterna verso `protein(accession)` con clausola `ON DELETE SET NULL`, che costituisce il ponte relazionale verso la proteina UniProt.
  * `role` (`VARCHAR(10)`): Ruolo biologico: `Act` (oncogene attivante), `LoF` (oncosoppressore con perdita di funzione), `ambiguous`.
  * `mutations` (`INT`): Numero assoluto di mutazioni somatiche rilevate nel gene.
  * `samples` (`INT`): Numero di pazienti della coorte portatori di mutazioni nel gene.
  * `pct_samples_cohort` (`DECIMAL(12,10)`): Frequenza relativa di mutazione sul totale della coorte.
  * `qvalue_combination` (`DOUBLE`): Significatività statistica combinata dell'evidenza biologica (valori inferiori indicano maggiore significatività).
  * `UNIQUE KEY uq_sym_cohort (symbol, cohort)`: Vincolo di unicità che garantisce che un gene sia censito al massimo una volta per coorte.
  * Indici secondari: `idx_ig_accession` e `idx_ig_cohort` per accelerare le JOIN su proteine e studi clinici.

---

## Le 8 Query d'Esame Omogeneizzate

Tutte le 8 query selezionate presentano **un'impostazione stilistica omogenea**:
- Utilizzano parole chiave SQL in maiuscolo standard (`SELECT`, `JOIN`, `WHERE`, `ORDER BY`).
- Mantengono alias di colonna coerenti (`driver_gene`, `driver_role`, `drug_name`, `approved_by`).
- Restituiscono tabelle compatte (`LIMIT 10`), leggibili e ad alto impatto sia tecnico che biologico.

---

### QUERY 1: Il Ponte Relazionale Fondamentale (Caso Studio EGFR)
* **Complessità**: 3 JOIN lineari (`intogen_driver` $\rightarrow$ `protein` $\rightarrow$ `drug_target` $\rightarrow$ `drug`).
* **Obiettivo Tecnico**: Dimostra la navigazione relazionale completa dal gene driver identificato in clinica oncologica fino al farmaco censito in farmacologia molecolare.
* **Logica Biologica**: Dato l'oncogene polmonare **EGFR**, estrae tutti i farmaci capaci di colpirlo, visualizzando sia i bloccanti chimici a piccola molecola (inibitori tirosin-chinasici) sia gli anticorpi monoclonali mirati.
* **SQL**:
```sql
SELECT DISTINCT
    ig.symbol AS driver_gene,
    p.entry_name,
    d.drug_name,
    dt.action_type
FROM intogen_driver ig
JOIN protein p ON p.accession = ig.accession
JOIN drug_target dt ON dt.accession = p.accession
JOIN drug d ON d.struct_id = dt.struct_id
WHERE ig.symbol = 'EGFR'
  AND dt.action_type IS NOT NULL
ORDER BY d.drug_name
LIMIT 10;
```
* **Output a schermo**:
| driver_gene | entry_name | drug_name | action_type |
|:---|:---|:---|:---|
| **EGFR** | EGFR_HUMAN | afatinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | amivantamab | ANTIBODY BINDING |
| **EGFR** | EGFR_HUMAN | brigatinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | cetuximab | ANTIBODY BINDING |
| **EGFR** | EGFR_HUMAN | dacomitinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | docetaxel | INHIBITOR |
| **EGFR** | EGFR_HUMAN | erlotinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | gefitinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | icotinib | INHIBITOR |
| **EGFR** | EGFR_HUMAN | lapatinib | INHIBITOR |
* **Come dirlo all'orale**: *"Questa è la query manifesto del progetto in 3 sole JOIN lineari: partiamo dal gene driver di IntOGen, passiamo per l'accession UniProt della proteina, e arriviamo al farmaco di DrugCentral, visualizzando sia gli inibitori a piccola molecola sia gli anticorpi monoclonali come cetuximab."*

---

### QUERY 2: I Geni Driver più Mutati nel Tumore al Seno (BRCA)
* **Complessità**: 1 sola JOIN (`intogen_driver` $\rightarrow$ `cohort`).
* **Obiettivo Tecnico**: Giunzione diretta tra la tabella dei fatti mutazionali e la dimensione coorte con filtro categorico e ordinamento decrescente.
* **Logica Biologica**: Identifica quali geni presentano il maggior numero assoluto di pazienti affetti negli studi clinici sul tumore al seno (BRCA), distinguendo il loro ruolo biologico (`Act` = oncogene attivante, `LoF` = oncosoppressore inattivato).
* **SQL**:
```sql
SELECT 
    ig.symbol AS driver_gene,
    ig.role AS driver_role,
    ig.samples AS mutated_samples,
    c.cohort
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
WHERE c.cancer_type = 'BRCA'
ORDER BY ig.samples DESC
LIMIT 10;
```
* **Output a schermo**:
| driver_gene | driver_role | mutated_samples | cohort |
|:---|:---:|:---:|:---|
| **PIK3CA** | Act | 335 | TCGA_WXS_BRCA |
| **TP53** | LoF | 299 | TCGA_WXS_BRCA |
| **TP53** | LoF | 283 | HARTWIG_WGS_BRCA_2023 |
| **PIK3CA** | Act | 278 | HARTWIG_WGS_BRCA_2023 |
| **TP53** | LoF | 132 | ICGC_WGS_BRCA_BRCA_EU_2019 |
| **ESR1** | Act | 129 | HARTWIG_WGS_BRCA_2023 |
| **PIK3CA** | Act | 102 | ICGC_WGS_BRCA_BRCA_EU_2019 |
| **CDH1** | LoF | 97 | TCGA_WXS_BRCA |
| **GATA3** | LoF | 97 | TCGA_WXS_BRCA |
| **GATA3** | LoF | 87 | HARTWIG_WGS_BRCA_2023 |
* **Come dirlo all'orale**: *"Con 1 solo JOIN tra la tabella delle mutazioni e la tabella delle coorti estraiamo i geni con più pazienti affetti nel tumore al seno, evidenziando che PIK3CA è un oncogene (Act) e TP53 un oncosoppressore (LoF)."*

---

### QUERY 3: Farmaci Inibitori con Meccanismo d'Azione Primario
* **Complessità**: 1 sola JOIN (`drug` $\rightarrow$ `drug_target`).
* **Obiettivo Tecnico**: Giunzione diretta tra anagrafica farmaco e tabella ponte, filtrando su attributo booleano (`moa = 1`) e corrispondenza testuale (`action_type = 'INHIBITOR'`).
* **Logica Biologica**: Isola le molecole che hanno una funzione bloccante accertata sul loro bersaglio terapeutico primario, scartando le interazioni secondarie di screening biofisico.
* **SQL**:
```sql
SELECT DISTINCT
    d.drug_name,
    dt.action_type,
    dt.target_class
FROM drug d
JOIN drug_target dt ON dt.struct_id = d.struct_id
WHERE dt.moa = 1 
  AND dt.action_type = 'INHIBITOR'
ORDER BY d.drug_name
LIMIT 10;
```
* **Output a schermo**:
| drug_name | action_type | target_class |
|:---|:---|:---|
| **abatacept** | INHIBITOR | Surface antigen |
| **abemaciclib** | INHIBITOR | Kinase |
| **abiraterone acetate** | INHIBITOR | Enzyme |
| **abrocitinib** | INHIBITOR | Kinase |
| **acalabrutinib** | INHIBITOR | Kinase |
| **acarbose** | INHIBITOR | Enzyme |
| **aceclofenac** | INHIBITOR | Enzyme |
| **acemetacin** | INHIBITOR | Enzyme |
| **acenocoumarol** | INHIBITOR | Enzyme |
| **acetazolamide** | INHIBITOR | Enzyme |
* **Come dirlo all'orale**: *"Questa è una singola JOIN tra anagrafica farmaci e la tabella delle interazioni: isola i principi attivi la cui azione terapeutica principale convalidata (`moa = 1`) è di tipo inibitorio."*

---

### QUERY 4: Farmaci Approvati da FDA Attivi sulle Chinasi
* **Complessità**: 2 sole JOIN a stella con centro su `drug` (`drug` $\rightarrow$ `drug_approval`, `drug` $\rightarrow$ `drug_target`).
* **Obiettivo Tecnico**: Navigazione bidirezionale da un'entità centrale verso due tabelle dipendenti, verificando simultaneamente requisiti regolatori e proprietà molecolari.
* **Logica Biologica**: Estrae i farmaci approvati dall'ente regolatore statunitense (FDA) che agiscono specificamente sulla famiglia delle **Chinasi** (la classe di proteine più frequentemente deregolata nei tumori solidi).
* **SQL**:
```sql
SELECT DISTINCT
    d.drug_name,
    da.agency AS approved_by,
    dt.target_class
FROM drug d
JOIN drug_approval da ON da.struct_id = d.struct_id
JOIN drug_target dt ON dt.struct_id = d.struct_id
WHERE da.agency = 'FDA'
  AND dt.target_class = 'Kinase'
ORDER BY d.drug_name
LIMIT 10;
```
* **Output a schermo**:
| drug_name | approved_by | target_class |
|:---|:---:|:---|
| **abemaciclib** | FDA | Kinase |
| **abrocitinib** | FDA | Kinase |
| **acalabrutinib** | FDA | Kinase |
| **aceclofenac** | FDA | Kinase |
| **acetic acid** | FDA | Kinase |
| **adefovir dipivoxil** | FDA | Kinase |
| **adenine** | FDA | Kinase |
| **adenosine** | FDA | Kinase |
| **afatinib** | FDA | Kinase |
| **alectinib** | FDA | Kinase |
* **Come dirlo all'orale**: *"Con due sole JOIN partendo dall'anagrafica del farmaco, colleghiamo da un lato la certificazione regolatoria FDA e dall'altro la classe funzionale 'Kinase' del bersaglio."*

---

### QUERY 5: Geni Driver e Anagrafica Proteica nel Glioblastoma (GBM)
* **Complessità**: 2 sole JOIN lineari (`intogen_driver` $\rightarrow$ `protein` $\rightarrow$ `cohort`).
* **Obiettivo Tecnico**: Integrazione dell'anagrafica proteica con i dati clinico-epidemiologici di uno specifico tumore.
* **Logica Biologica**: Nel glioblastoma multiforme (tumore cerebrale primario altamente aggressivo), traduce i simboli genici nelle corrispondenti proteine umane UniProt (`entry_name`) e ne specifica il ruolo biologico.
* **SQL**:
```sql
SELECT DISTINCT
    ig.symbol AS driver_gene,
    p.entry_name,
    p.target_class,
    ig.role AS driver_role
FROM intogen_driver ig
JOIN protein p ON p.accession = ig.accession
JOIN cohort c ON c.cohort = ig.cohort
WHERE c.cancer_type = 'GBM'
ORDER BY ig.symbol
LIMIT 10;
```
* **Output a schermo**:
| driver_gene | entry_name | target_class | driver_role |
|:---|:---|:---|:---:|
| **AR** | ANDR_HUMAN | Nuclear hormone receptor | LoF |
| **BRAF** | BRAF_HUMAN | Kinase | Act |
| **EGFR** | EGFR_HUMAN | Kinase | Act |
| **IDH1** | IDH1_HUMAN | Enzyme | Act |
| **PIK3CA** | PK3CA_HUMAN | Kinase | Act |
| **PTEN** | PTEN_HUMAN | Phosphatase | LoF |
| **RB1** | RB_HUMAN | Tumor suppressor | LoF |
| **TP53** | P53_HUMAN | Transcription factor | LoF |
| **ATRX** | ATRX_HUMAN | Chromatin remodeler | LoF |
| **NF1** | NF1_HUMAN | GTPase-activating protein | LoF |
* **Come dirlo all'orale**: *"Due sole JOIN collegano la coorte clinica del glioblastoma all'anagrafica UniProt (`protein`), verificando quali geni agiscono come oncogeni attivanti (Act) come EGFR o BRAF, e quali come soppressori tumorali (LoF)."*

---

### QUERY 6: Terapie a Bersaglio Molecolare nel Tumore al Polmone (LUAD)
* **Complessità**: Giunzione su 5 tabelle con aggregazione stringa (`intogen_driver` $\rightarrow$ `cohort` $\rightarrow$ `protein` $\rightarrow$ `drug_target` $\rightarrow$ `drug` $\rightarrow$ `drug_approval`).
* **Obiettivo Tecnico**: Unisce la catena clinico-farmacologica completa ed impiega `GROUP_CONCAT` per accorpare in un unico campo testuale tutte le agenzie regolatorie che hanno approvato il farmaco.
* **Logica Biologica**: Il carcinoma polmonare (LUAD) è il modello di riferimento dell'oncologia di precisione. La query estrae i farmaci con meccanismo primario validato (`moa = 1`) che colpiscono i suoi oncogeni (BRAF, EGFR).
* **SQL**:
```sql
SELECT 
    ig.symbol AS driver_gene,
    d.drug_name,
    dt.action_type,
    GROUP_CONCAT(DISTINCT da.agency ORDER BY da.agency SEPARATOR ', ') AS approved_by
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
JOIN protein p ON p.accession = ig.accession
JOIN drug_target dt ON dt.accession = p.accession
JOIN drug d ON d.struct_id = dt.struct_id
JOIN drug_approval da ON da.struct_id = d.struct_id
WHERE c.cancer_type = 'LUAD'
  AND dt.moa = 1
GROUP BY ig.symbol, d.drug_name, dt.action_type
ORDER BY ig.symbol, d.drug_name
LIMIT 10;
```
* **Output a schermo**:
| driver_gene | drug_name | action_type | approved_by |
|:---|:---|:---|:---|
| **BRAF** | dabrafenib | INHIBITOR | EMA, FDA, PMDA |
| **BRAF** | encorafenib | INHIBITOR | FDA, PMDA |
| **BRAF** | regorafenib | INHIBITOR | EMA, FDA |
| **BRAF** | sorafenib | INHIBITOR | FDA |
| **BRAF** | vemurafenib | INHIBITOR | FDA |
| **EGFR** | afatinib | INHIBITOR | EMA, FDA |
| **EGFR** | amivantamab | ANTIBODY BINDING | EMA, FDA |
| **EGFR** | cetuximab | ANTIBODY BINDING | EMA, FDA, PMDA |
| **EGFR** | dacomitinib | INHIBITOR | EMA, FDA, PMDA |
| **EGFR** | erlotinib | INHIBITOR | FDA |
* **Come dirlo all'orale**: *"In questa query colleghiamo la coorte clinica del carcinoma polmonare alle anagrafiche dei farmaci, filtrando solo le interazioni che rappresentano il meccanismo terapeutico primario (`moa = 1`). L'uso di `GROUP_CONCAT` aggrega in un unico campo testuale tutte le agenzie regolatorie (FDA, EMA, PMDA) che ne hanno certificato l'efficacia."*

---

### QUERY 7: Polifarmacologia — Farmaci Multi-Target nello Stesso Tumore
* **Complessità**: `GROUP BY` su coppia istotipo-farmaco, filtro di gruppo con `HAVING COUNT(DISTINCT) >= 2`, aggregazione con `GROUP_CONCAT`.
* **Obiettivo Tecnico**: Calcolo di metriche di connettività di rete su dati aggregati.
* **Logica Biologica**: Un tumore sviluppa facilmente resistenza quando si inibisce una singola proteina. Questa query individua i farmaci a largo spettro capaci di colpire contemporaneamente più geni driver all'interno dello stesso tumore ("un cocktail in una sola pillola").
* **SQL**:
```sql
SELECT 
    c.cancer_type,
    d.drug_name,
    COUNT(DISTINCT ig.symbol) AS n_driver_targets_hit,
    GROUP_CONCAT(DISTINCT ig.symbol ORDER BY ig.symbol SEPARATOR ', ') AS targeted_driver_genes
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
JOIN drug_target dt ON dt.accession = ig.accession
JOIN drug d ON d.struct_id = dt.struct_id
WHERE dt.moa = 1
GROUP BY c.cancer_type, d.struct_id, d.drug_name
HAVING COUNT(DISTINCT ig.symbol) >= 2
ORDER BY n_driver_targets_hit DESC, c.cancer_type
LIMIT 10;
```
* **Output a schermo**:
| cancer_type | drug_name | n_driver_targets_hit | targeted_driver_genes |
|:---|:---|:---:|:---|
| **ANGS** | sorafenib | 4 | FLT4, KDR, PDGFRB, RET |
| **ANGS** | sunitinib | 4 | FLT4, KDR, PDGFRB, RET |
| **LUSC** | nintedanib | 4 | FGFR2, FGFR3, FLT4, PDGFRA |
| **ALL** | tofacitinib | 3 | JAK1, JAK2, JAK3 |
| **ALL** | upadacitinib | 3 | JAK1, JAK2, JAK3 |
| **ALL** | delgocitinib | 3 | JAK1, JAK2, JAK3 |
| **ALL** | peficitinib | 3 | JAK1, JAK2, JAK3 |
| **ANGS** | pazopanib | 3 | FLT4, KDR, PDGFRB |
| **ANGS** | nintedanib | 3 | FLT4, KDR, PDGFRB |
| **BLCA** | nintedanib | 3 | FGFR2, FGFR3, FLT4 |
* **Come dirlo all'orale**: *"Nell'ottica della polifarmacologia, raggruppiamo i dati per individuare molecole multi-bersaglio che inibiscono più nodi di segnalazione nello stesso tipo tumorale. La clausola `HAVING >= 2` isola i farmaci multi-target e `GROUP_CONCAT` formatta chiaramente i geni inibiti."*

---

### QUERY 8: Drug Repurposing su Tumori a Prognosi Infausta (PAAD e GBM)
* **Complessità**: Filtro su insiemi categorici (`IN`), catena di join con 5 relazioni e ordinamento pesato sul volume di pazienti mutati.
* **Obiettivo Tecnico**: Intersezione di dati genomici clinici con registri regolatori per generare graduatorie di priorità clinica.
* **Logica Biologica**: Il glioblastoma (GBM) e l'adenocarcinoma pancreatico (PAAD) hanno tassi di sopravvivenza bassissimi e pochissime terapie efficaci. Questa query trova farmaci già approvati (FDA/EMA) per altri organi che possono essere riposizionati sui bersagli mutati in questi pazienti.
* **SQL**:
```sql
SELECT 
    c.cancer_type,
    ig.symbol AS target_driver_gene,
    d.drug_name,
    dt.action_type,
    GROUP_CONCAT(DISTINCT da.agency ORDER BY da.agency SEPARATOR ', ') AS approved_by,
    SUM(ig.samples) AS mutated_samples_in_cohorts
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
JOIN drug_target dt ON dt.accession = ig.accession
JOIN drug d ON d.struct_id = dt.struct_id
JOIN drug_approval da ON da.struct_id = d.struct_id
WHERE c.cancer_type IN ('PAAD', 'GBM')
  AND dt.moa = 1
GROUP BY c.cancer_type, ig.symbol, d.drug_name, dt.action_type
ORDER BY c.cancer_type, mutated_samples_in_cohorts DESC, d.drug_name
LIMIT 10;
```
* **Output a schermo**:
| cancer_type | target_driver_gene | drug_name | action_type | approved_by | mutated_samples_in_cohorts |
|:---|:---:|:---|:---|:---|:---:|
| **GBM** | EGFR | cetuximab | ANTIBODY BINDING | EMA, FDA, PMDA | 384 |
| **GBM** | EGFR | dacomitinib | INHIBITOR | EMA, FDA, PMDA | 384 |
| **GBM** | EGFR | necitumumab | ANTIBODY BINDING | EMA, FDA, PMDA | 384 |
| **GBM** | EGFR | osimertinib | INHIBITOR | EMA, FDA, PMDA | 384 |
| **GBM** | EGFR | afatinib | INHIBITOR | EMA, FDA | 256 |
| **GBM** | EGFR | amivantamab | ANTIBODY BINDING | EMA, FDA | 256 |
| **GBM** | EGFR | lapatinib | INHIBITOR | EMA, FDA | 256 |
| **GBM** | EGFR | neratinib | INHIBITOR | EMA, FDA | 256 |
| **GBM** | EGFR | panitumumab | AGONIST | EMA, FDA | 256 |
| **GBM** | EGFR | erlotinib | INHIBITOR | FDA | 128 |
* **Come dirlo all'orale**: *"Questa query risponde a una domanda chiave dell'oncologia traslazionale: il riposizionamento di farmaci (*drug repurposing*). Per patologie incurabili come glioblastoma e tumore al pancreas, estraiamo farmaci già certificati FDA o EMA che colpiscono i relativi geni driver con meccanismo d'azione convalidato."*

---

## Istruzioni di Esecuzione e Presentazione d'Esame

### 1. Rigenerazione della pipeline ETL (7 Tabelle)
Per eseguire da zero la pulizia dei dati grezzi e ricreare i 7 file CSV normalizzati in `data/clean/`:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/02_clean.py
```

### 2. Inizializzazione e popolamento del database MySQL
Per ricreare lo schema DDL a 7 tabelle e caricare l'intero corpus dati con commit a blocchi di 5.000 record:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/03_load.py --user root --init-schema
```

### 3. Dimostrazione in MySQL Workbench
1. **Diagramma Relazionale EER**:
   * Menu **Database ➔ Reverse Engineer...** ➔ selezionare il database `intogen_drugcentral`.
   * Verrà generato il grafo relazionale completo a 7 tabelle che illustra la centralità di `protein` e la normalizzazione di `cohort`.
2. **Esecuzione delle Query**:
   * Aprire [`sql/queries.sql`](file:///Users/federica/Desktop/Project_intogen_drugcentral/sql/queries.sql) ed eseguire in sequenza le 8 query d'esame.
