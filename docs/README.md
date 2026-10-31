# Progetto IntOGen – DrugCentral

Questo progetto realizza un **database relazionale ottimizzato** che integra e mette in correlazione due domini complementari della biomedicina computazionale:

1. **La genomica del cancro** (dati **IntOGen**): il compendio dei geni le cui mutazioni somatiche guidano la trasformazione tumorale (*driver genes*).
2. **La farmacologia clinica e molecolare** (dati **DrugCentral**): principi attivi, bersagli proteici, meccanismi d'azione (MoA), affinità sperimentali e approvazioni regolatorie (FDA, EMA, PMDA).

L'integrazione semantica e relazionale tra i due sistemi è resa possibile da **UniProt Swiss-Prot**, che funge da dizionario canonico e ponte anagrafico attraverso codici di accessione univoci (es. `P04637` per TP53, `P01116` per KRAS, `P00533` per EGFR).

```
┌─────────────────────────┐             ┌─────────────────────────┐             ┌─────────────────────────┐
│         IntOGen         │             │         UniProt         │             │       DrugCentral       │
│  Geni driver oncologici │ ──────────► │    Anagrafica proteine  │ ◄────────── │    Farmaci e bersagli   │
│   (coorti e mutazioni)  │   accession │   (mapping e sinonimi)  │   accession │  (attività e agenzie)   │
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
│   └── clean/               ← Dati normalizzati e conformi allo schema relazionale (8 CSV)
│       ├── protein.csv
│       ├── gene_symbol.csv
│       ├── drug.csv
│       ├── drug_approval.csv
│       ├── drug_target.csv
│       ├── activity.csv
│       ├── cohort.csv
│       └── intogen_driver.csv
│
├── scripts/
│   ├── 01_inspect.py        ← Profilazione e validazione dei tipi nei file grezzi
│   ├── 02_clean.py          ← Pipeline ETL di pulizia, deduplicazione e normalizzazione
│   └── 03_load.py           ← Inizializzazione schema DDL e caricamento batch in MySQL
│
├── sql/
│   ├── schema.sql           ← Schema relazionale DDL (8 tabelle, chiavi primarie, vincoli FK e indici)
│   └── queries.sql          ← Vista integrata, controlli QC e le 9 query d'esame (3 livelli)
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
  * `SYMBOL`: Simbolo HGNC del gene.
  * `ROLE`: Ruolo biologico predetto: **Act** (oncogene attivante) o **LoF** (oncosoppressore a perdita di funzione).
  * `MUTATIONS` / `SAMPLES` / `TOTAL_SAMPLES`: Conteggi mutazionali, pazienti mutati e ampiezza campionaria dello studio.
  * `QVALUE_COMBINATION`: Significatività statistica combinata corretta per False Discovery Rate (FDR).
* **Volumetria**: 633 geni driver unici, 260 coorti cliniche, 86 tipi di tumore.

---

### 2. DrugCentral — Farmacologia Molecolare e Regolatoria
* **Ruolo**: Repository farmacologico integrato sviluppato dall'Università del New Mexico.
* **Granularità**: Mappe delle interazioni farmaco-bersaglio, proprietà biofisiche e stato autorizzativo.
* **Campi salienti**:
  * `STRUCT_ID` / `DRUG_NAME`: Identificativo primario e denominazione del farmaco.
  * `ACCESSION`: Codice proteico UniProt del bersaglio.
  * `ACTION_TYPE`: Effetto funzionale (es. *INHIBITOR*, *ANTAGONIST*, *AGONIST*, *BLOCKER*).
  * `MOA`: Flag binario (1 = Meccanismo d'Azione terapeutico primario; 0 = Interazione secondaria o dato di screening).
  * `ACT_VALUE` / `ACT_TYPE`: Misura quantitativa di affinità espressa in scala $-\log_{10} M$ ($pIC_{50}$, $pK_i$, $pK_d$).
  * `TDL`: *Target Development Level* (Tclin = clinico validato, Tchem = chimicamente esplorato, Tbio = solo annotazione biologica, Tdark = orfano).
* **Volumetria**: 2.632 farmaci attivi su bersagli umani, 18.228 interazioni uniche farmaco-bersaglio, 2.401 approvazioni regolatorie (FDA, EMA, PMDA).

---

### 3. UniProt (Swiss-Prot) — Anagrafica e Dizionario Ponte
* **Ruolo**: Riconciliazione delle discrepanze di nomenclatura.
* **Funzione relazionale**:
  * IntOGen indicizza le mutazioni tramite **simbolo genico** (`SYMBOL`).
  * DrugCentral indicizza i bersagli tramite **accession proteica** (`ACCESSION`).
  * La tabella `gene_symbol` (45.565 record) mappa ogni simbolo ufficiale e sinonimo storico genico al relativo codice UniProt, isolando il gene primario HGNC (`is_primary = 1`).
* **Volumetria**: 20.433 proteine umane curate manualmente (*reviewed*).

---

## Schema Relazionale (8 Tabelle in MySQL)

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
            ┌───────────────────────┼───────────────────────┐
            │ N                     │ N                     │
    ┌───────┴───────┐       ┌───────┴───────┐       ┌───────┴───────┐
    │  drug_target  │       │   activity    │       │ drug_approval │
    ├───────────────┤       ├───────────────┤       ├───────────────┤
    │ PK  id        │       │ PK  id        │       │ PK,FK struct_id
    │ FK  struct_id ├──┐    │ FK  struct_id ├──┐    │ PK    agency  │
    │ FK  accession │  │    │ FK  accession │  │    └───────┬───────┘
    │     moa, act  │  │    │     act_val   │  │            │ N
    └───────────────┘  │    └───────────────┘  │            │
                       │                       │            │ 1
                       │    ┌───────────────┐  │    ┌───────┴───────┐
                       └───►│     drug      │◄─┴────┤     drug      │
                            ├───────────────┤       ├───────────────┤
                            │ PK  struct_id │       │ PK  struct_id │
                            │     drug_name │       │     drug_name │
                            └───────────────┘       └───────────────┘
```

| Tabella | Record | Chiave Primaria | Chiavi Esterne (FK) | Scopo Ingegneristico |
|:---|:---:|:---|:---|:---|
| **`protein`** | 20.433 | `accession` | — | Entità anagrafica centrale delle proteine umane |
| **`gene_symbol`** | 45.565 | `id` | `accession` $\rightarrow$ `protein` | Mappatura 1:N tra proteina e sinonimi genici |
| **`drug`** | 2.632 | `struct_id` | — | Entità anagrafica dei farmaci e composti chimici |
| **`drug_approval`** | 2.401 | `(struct_id, agency)` | `struct_id` $\rightarrow$ `drug` | Certificazioni regolatorie (FDA, EMA, PMDA) |
| **`drug_target`** | 18.228 | `id` (UQ su `struct_id, accession`) | `struct_id`, `accession` | Relazione N:M farmaco-bersaglio con metadati funzionali |
| **`activity`** | 16.716 | `id` | `struct_id`, `accession` | Misure quantitative biofisiche ($IC_{50}$, $K_i$, $K_d$) |
| **`cohort`** | 260 | `cohort` | — | Entità dimensionale degli studi clinici e istotipi |
| **`intogen_driver`** | 4.478 | `id` (UQ su `symbol, cohort`) | `cohort`, `accession` | Tabella dei fatti mutazionali per studio e gene |

---

## Difesa delle Scelte di Modellazione Relazionale

### 1. Perché `target_class` compare sia in `protein` sia in `drug_target`?
* **Motivazione relazionale pura (3NF)**: La classe biologica (es. *Kinase*, *GPCR*, *Ion channel*) è un attributo funzionale intrinseco della proteina (`accession`), indipendentemente dal farmaco con cui interagisce. Nella tabella `protein` rappresenta l'annotazione tassonomica formale.
* **Motivazione pratica e analitica in `drug_target`**: Nel dataset grezzo di DrugCentral, `TARGET_CLASS` è valorizzato al **100% per tutti i target umani censiti**. Al contrario, UniProt copre oltre 20.000 proteine (di cui la grande maggioranza non farmacologica e priva di classificazione industriale esplicita). Mantenere la colonna denormalizzata in `drug_target`:
  1. Ottimizza le prestazioni analitiche evitando JOIN obbligatorie su interrogazioni massive focalizzate sulle sole interazioni chimiche.
  2. Garantisce l'integrità contestuale dell'interazione farmaco-bersaglio così come validata dalla fonte farmacologica.

---

### 2. Perché preservare `action_type` in `drug_target` nonostante il 73.4% di valori nulli?
La sparsità globale del campo è ingannevole se non esaminata tramite segmentazione analitica:
* **Nei dati di screening secondario (`moa = 0`)**: `action_type` è presente solo nell'8.4% dei casi, poiché i saggi biofisici ad alto rendimento misurano solo il legame fisico (*binding*) senza determinare la modulazione biologica a valle.
* **Nei veri meccanismi d'azione clinici (`moa = 1`)**: `action_type` è popolato nel **99.6% dei casi** (praticamente nel 100% dei farmaci approvati).
* **Valenza clinico-ingegneristica**: In oncologia è imperativo conoscere il **vettore funzionale**:
  * Un oncogene attivante (`role = 'Act'`) impone un **inibitore**, **antagonista** o **bloccante**.
  * Somministrare un agonista o attivatore stimolerebbe ulteriormente la proliferazione cellulare.
  * Preservare `action_type` consente di filtrare le interazioni clinicamente pericolose (come mostrato nella **Query 2**).

---

### 3. Perché isolare la tabella `cohort` da `intogen_driver`?
Nel file sorgente `Compendium_Cancer_Genes.tsv`, ogni riga replicava i dati del gene driver e i metadati della coorte clinica (`COHORT`, `CANCER_TYPE`, `TOTAL_SAMPLES`).
1. **Rispetto della 2NF e 3NF**: `cancer_type` e `total_samples` dipendono funzionalmente solo dalla coorte (`cohort` $\rightarrow$ `cancer_type, total_samples`) e non dal gene driver. Inserirli in `intogen_driver` avrebbe costituito una dipendenza parziale su chiave composta, generando ridondanza sistematica.
2. **Prevenzione del Fan Trap e dell'Aggregation Bias**: Se volessimo calcolare i pazienti totali sequenziati per il carcinoma mammario (`BRCA`), eseguire `SUM(total_samples)` su una tabella unica moltiplicherebbe la dimensione della coorte per ciascun gene driver identificato in quello studio clinico (sovrastimando il campione da 20 a 100 volte). Con la tabella `cohort`, il calcolo riflette l'esatta dimensione epidemiologica (dimostrato nella **Query 3**).
3. **Eliminazione delle anomalie relazionali**: È possibile registrare una nuova coorte sequenziata prima che gli algoritmi abbiano isolato i driver, o conservare i dati di una coorte negativa senza violare vincoli di integrità.

---

## Le 5 Query Lineari Base (Max 1-3 JOIN, Nessuna Complessità)

Queste 5 query sono le più immediate e intuitive dell'intero progetto: utilizzano **da 1 a un massimo di 3 JOIN lineari**, nessuna sottoquery, nessuna CTE, nessuna formula o raggruppamento complesso. Sono ideali da mostrare per prime durante il colloquio per spiegare come dialogano le tabelle senza sovraccaricare l'esposizione.

---

### BASE 1 (1 JOIN): I geni driver più mutati nel tumore al seno (BRCA)
* **Tabelle**: `intogen_driver` $\leftrightarrow$ `cohort` (1 sola JOIN sulla chiave `cohort`).
* **Concetto biologico**: Identifica quali geni contano il maggior numero di pazienti mutati negli studi clinici sul carcinoma mammario (BRCA), distinguendo il loro ruolo biologico (`Act` = oncogene attivante, `LoF` = oncosoppressore inattivato).
* **SQL**:
  ```sql
  SELECT 
      ig.symbol AS gene,
      ig.role AS biological_role,
      ig.samples AS mutated_patients,
      c.cohort
  FROM intogen_driver ig
  JOIN cohort c ON c.cohort = ig.cohort
  WHERE c.cancer_type = 'BRCA'
  ORDER BY ig.samples DESC
  LIMIT 8;
  ```
* **Output reale**:
  | gene | biological_role | mutated_patients | cohort |
  |:---|:---:|:---:|:---|
  | **PIK3CA** | Act | 335 | TCGA_WXS_BRCA |
  | **TP53** | LoF | 299 | TCGA_WXS_BRCA |
  | **TP53** | LoF | 283 | HARTWIG_WGS_BRCA_2023 |
  | **PIK3CA** | Act | 278 | HARTWIG_WGS_BRCA_2023 |
  | **ESR1** | Act | 129 | HARTWIG_WGS_BRCA_2023 |
* **Come dirlo all'orale**: *"Con 1 sola JOIN tra la tabella delle mutazioni e la tabella delle coorti, estraiamo i geni con più pazienti affetti nel tumore al seno, evidenziando che PIK3CA è un oncogene (Act) e TP53 un oncosoppressore (LoF)."*

---

### BASE 2 (1 JOIN): Farmaci inibitori con meccanismo d'azione primario
* **Tabelle**: `drug` $\leftrightarrow$ `drug_target` (1 sola JOIN sulla chiave `struct_id`).
* **Concetto biologico**: Isola i farmaci che agiscono come inibitori accertati (`INHIBITOR`) sul loro bersaglio terapeutico primario (`moa = 1`), scartando legami secondari di screening.
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
  LIMIT 8;
  ```
* **Output reale**:
  | drug_name | action_type | target_class |
  |:---|:---|:---|
  | **abemaciclib** | INHIBITOR | Kinase |
  | **abiraterone acetate** | INHIBITOR | Enzyme |
  | **abrocitinib** | INHIBITOR | Kinase |
  | **acalabrutinib** | INHIBITOR | Kinase |
* **Come dirlo all'orale**: *"Con una singola JOIN tra anagrafica farmaci e la tabella ponte delle interazioni, mostriamo i farmaci che hanno un'azione inibitoria validata clinicamente come meccanismo d'azione principale."*

---

### BASE 3 (2 JOIN): Farmaci approvati FDA attivi sulla famiglia delle Chinasi
* **Tabelle**: `drug` $\leftrightarrow$ `drug_approval` $\leftrightarrow$ `drug_target` (2 sole JOIN centrate su `drug`).
* **Concetto biologico**: Mostra quali molecole certificate dall'ente regolatore statunitense (FDA) sono specificamente dirette contro le chinasi (la classe proteica cardine delle terapie oncologiche).
* **SQL**:
  ```sql
  SELECT DISTINCT
      d.drug_name,
      da.agency,
      dt.target_class
  FROM drug d
  JOIN drug_approval da ON da.struct_id = d.struct_id
  JOIN drug_target dt ON dt.struct_id = d.struct_id
  WHERE da.agency = 'FDA'
    AND dt.target_class = 'Kinase'
  ORDER BY d.drug_name
  LIMIT 8;
  ```
* **Output reale**:
  | drug_name | agency | target_class |
  |:---|:---:|:---|
  | **abemaciclib** | FDA | Kinase |
  | **abrocitinib** | FDA | Kinase |
  | **acalabrutinib** | FDA | Kinase |
  | **alpelisib** | FDA | Kinase |
* **Come dirlo all'orale**: *"Colleghiamo con due sole JOIN il farmaco alla sua approvazione regolatoria e alla classe molecolare del suo bersaglio, filtrando solo le approvazioni FDA per la famiglia delle chinasi."*

---

### BASE 4 (2 JOIN): Geni driver e anagrafica proteica nel glioblastoma (GBM)
* **Tabelle**: `intogen_driver` $\leftrightarrow$ `protein` $\leftrightarrow$ `cohort` (2 sole JOIN).
* **Concetto biologico**: Per il glioblastoma (tumore cerebrale aggressivo), traduce i simboli genici nelle corrispondenti proteine umane UniProt con relativa classe funzionale.
* **SQL**:
  ```sql
  SELECT DISTINCT
      ig.symbol AS driver_gene,
      p.entry_name,
      p.target_class,
      ig.role
  FROM intogen_driver ig
  JOIN protein p ON p.accession = ig.accession
  JOIN cohort c ON c.cohort = ig.cohort
  WHERE c.cancer_type = 'GBM'
  ORDER BY ig.symbol
  LIMIT 8;
  ```
* **Output reale**:
  | driver_gene | entry_name | target_class | role |
  |:---|:---|:---|:---:|
  | **AR** | ANDR_HUMAN | Nuclear hormone receptor | LoF |
  | **BRAF** | BRAF_HUMAN | Kinase | Act |
  | **EGFR** | EGFR_HUMAN | Kinase | Act |
  | **IDH1** | IDH1_HUMAN | Enzyme | Act |
* **Come dirlo all'orale**: *"Due sole JOIN collegano la coorte clinica di glioblastoma all'anagrafica UniProt della proteina, verificando se il gene agisce come oncogene attivante (Act) come EGFR o IDH1."*

---

### BASE 5 (3 JOIN): Il ponte relazionale completo per un oncogene chiave (EGFR)
* **Tabelle**: `intogen_driver` $\leftrightarrow$ `protein` $\leftrightarrow$ `drug_target` $\leftrightarrow$ `drug` (3 sole JOIN lineari).
* **Concetto biologico**: È il nucleo logico di tutto il database: dato l'oncogene polmonare EGFR, attraversa il ponte UniProt ed elenca tutti i farmaci di DrugCentral con il loro tipo di azione.
* **SQL**:
  ```sql
  SELECT DISTINCT
      ig.symbol AS gene,
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
  LIMIT 8;
  ```
* **Output reale**:
  | gene | entry_name | drug_name | action_type |
  |:---|:---|:---|:---|
  | **EGFR** | EGFR_HUMAN | afatinib | INHIBITOR |
  | **EGFR** | EGFR_HUMAN | amivantamab | ANTIBODY BINDING |
  | **EGFR** | EGFR_HUMAN | brigatinib | INHIBITOR |
  | **EGFR** | EGFR_HUMAN | cetuximab | ANTIBODY BINDING |
  | **EGFR** | EGFR_HUMAN | erlotinib | INHIBITOR |
  | **EGFR** | EGFR_HUMAN | osimertinib | INHIBITOR |
* **Come dirlo all'orale**: *"Questa è la query manifesto del progetto in 3 sole JOIN lineari: partiamo dal gene driver di IntOGen, passiamo per l'accession UniProt della proteina, e arriviamo al farmaco di DrugCentral, visualizzando sia i bloccanti chimici (inibitori) sia gli anticorpi monoclonali."*

---

## Le 9 Query Analitiche Strutturate (Divise in 3 Livelli)

Tutte le query sono state progettate per essere **sintetiche, robuste e d'impatto visivo immediato**: non restituiscono migliaia di righe anonime, ma tabelle compatte di 10-15 record con correlazioni logiche nitide che un professore di estrazione ingegneristica può apprezzare all'istante.

---

### LIVELLO 1: Query Base (Filtri Semantici, Join Dirette, Proiezioni Mirate)

#### Query 1: Terapie a Bersaglio Molecolare nel Tumore al Polmone (LUAD)
* **Obiettivo SQL**: INNER JOIN su 5 tabelle con filtri mirati, ordinamento e aggregazione stringa (`GROUP_CONCAT`) delle agenzie regolatorie su riga singola per farmaco.
* **Concetto biologico per l'ingegnere**: Il tumore al polmone (LUAD) è il caso studio dell'oncologia di precisione. La query estrae i farmaci approvati con Meccanismo d'Azione primario convalidato (`moa = 1`) attivi contro i suoi geni driver.
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
  LIMIT 12;
  ```
* **Output d'esempio**:
  | driver_gene | drug_name | action_type | approved_by |
  |:---|:---|:---|:---|
  | **BRAF** | dabrafenib | INHIBITOR | EMA, FDA, PMDA |
  | **BRAF** | encorafenib | INHIBITOR | FDA, PMDA |
  | **BRAF** | regorafenib | INHIBITOR | EMA, FDA |
  | **EGFR** | afatinib | INHIBITOR | EMA, FDA |
  | **EGFR** | erlotinib | INHIBITOR | FDA |
  | **EGFR** | gefitinib | INHIBITOR | FDA |
  | **EGFR** | osimertinib | INHIBITOR | EMA, FDA, PMDA |
* **Come dirlo all'orale**: *"In questa query colleghiamo la coorte clinica del carcinoma polmonare alle anagrafiche dei farmaci, filtrando solo le interazioni che rappresentano il meccanismo terapeutico primario (`moa = 1`). L'uso di `GROUP_CONCAT` aggrega in un unico campo testuale tutte le agenzie regolatorie (FDA, EMA, PMDA) che ne hanno certificato l'efficacia."*

---

#### Query 2: Match Meccanicistico Oncogene ↔ Farmaco Inibitore
* **Obiettivo SQL**: Pattern matching con operatore `LIKE`, combinazione logica booleana `AND` / `OR`, proiezione di regole di business sul modello dati.
* **Concetto biologico per l'ingegnere**: Principio fondamentale di controllo: se un gene è un oncogene attivante (`role = 'Act'`), il sistema biologico è in iper-attivazione (come un acceleratore bloccato). La terapia deve fungere da freno (inibitore, antagonista o bloccante). Se somministrassimo un agonista, accelereremmo il tumore.
* **SQL**:
  ```sql
  SELECT DISTINCT 
      c.cancer_type,
      ig.symbol AS oncogene,
      p.target_class,
      d.drug_name,
      dt.action_type
  FROM intogen_driver ig
  JOIN cohort c ON c.cohort = ig.cohort
  JOIN protein p ON p.accession = ig.accession
  JOIN drug_target dt ON dt.accession = p.accession
  JOIN drug d ON d.struct_id = dt.struct_id
  WHERE ig.role = 'Act'
    AND (
        dt.action_type LIKE '%INHIBITOR%' 
        OR dt.action_type LIKE '%ANTAGONIST%' 
        OR dt.action_type LIKE '%BLOCKER%'
    )
  ORDER BY c.cancer_type, ig.symbol, d.drug_name
  LIMIT 10;
  ```
* **Output d'esempio**:
  | cancer_type | oncogene | target_class | drug_name | action_type |
  |:---|:---|:---|:---|:---|
  | **ACYC** | PIK3CA | Kinase | alpelisib | INHIBITOR |
  | **ACYC** | PIK3CA | Kinase | copanlisib | INHIBITOR |
  | **ALL** | AKT1 | Kinase | capivasertib | INHIBITOR |
  | **ALL** | EZH2 | Enzyme | tazemetostat | INHIBITOR |
* **Come dirlo all'orale**: *"Questa query dimostra come il database relazionale implementi logiche di coerenza biofisica. Filtriamo i geni marcati come attivanti (`role = 'Act'`) per accoppiarli solo con farmaci ad azione inibitoria, scartando interazioni potenzialmente dannose o non terapeutiche."*

---

#### Query 3: Validazione Epidemiologica e Pesi Campionari (Giustificazione 3NF)
* **Obiettivo SQL**: `LEFT JOIN` tra entità dimensionale (`cohort`) ed entità dei fatti (`intogen_driver`), funzioni aggregate multiple (`COUNT`, `SUM`, `AVG`), raggruppamento per istotipo.
* **Concetto biologico/ingegneristico**: Evidenzia la solidità campionaria degli studi. Se non avessimo normalizzato separando la tabella `cohort`, calcolare `SUM(total_samples)` avrebbe moltiplicato i pazienti per ogni gene driver della coorte (errore sistematico).
* **SQL**:
  ```sql
  SELECT 
      c.cancer_type,
      COUNT(DISTINCT c.cohort) AS n_cohorts,
      SUM(c.total_samples) AS total_patients_sequenced,
      COUNT(DISTINCT ig.symbol) AS unique_driver_genes,
      ROUND(SUM(c.total_samples) / COUNT(DISTINCT c.cohort), 0) AS avg_patients_per_cohort
  FROM cohort c
  LEFT JOIN intogen_driver ig ON ig.cohort = c.cohort
  GROUP BY c.cancer_type
  ORDER BY total_patients_sequenced DESC
  LIMIT 10;
  ```
* **Output d'esempio**:
  | cancer_type | n_cohorts | total_patients_sequenced | unique_driver_genes | avg_patients_per_cohort |
  |:---|:---:|:---:|:---:|:---:|
  | **BRCA** (Seno) | 14 | 126.945 | 118 | 9.068 |
  | **PRAD** (Prostata) | 12 | 61.841 | 95 | 5.153 |
  | **COADREAD** (Colon-Retto) | 7 | 52.747 | 82 | 7.535 |
  | **HCC** (Fegato) | 11 | 42.672 | 111 | 3.879 |
  | **LUAD** (Polmone) | 6 | 36.631 | 77 | 6.105 |
* **Come dirlo all'orale**: *"Questa query è la prova ingegneristica dell'utilità della normalizzazione: calcola il totale esatto dei pazienti sequenziati per ciascun tumore senza incappare nell'effetto moltiplicativo (Fan Trap) che si avrebbe se i metadati della coorte fossero rimasti replicati in ogni record di gene driver."*

---

### LIVELLO 2: Query Intermedie (Aggregazioni Complesse, HAVING, GROUP_CONCAT)

#### Query 4: Druggability Ranking dei Driver Oncologici
* **Obiettivo SQL**: Raggruppamento multidimensionale, filtro post-aggregazione tramite clausola `HAVING`, conteggi condizionali distinti per confrontare composti totali vs farmaci già autorizzati.
* **Concetto biologico per l'ingegnere**: Classifica le proteine mutate in base alla ricchezza del loro armamentario terapeutico (*druggability*). Distingue chiaramente i target ad altissima saturazione farmacologica (es. recettori tirosin-chinasici).
* **SQL**:
  ```sql
  SELECT 
      ig.symbol AS driver_gene,
      p.target_class,
      p.tdl,
      COUNT(DISTINCT dt.struct_id) AS total_molecules,
      COUNT(DISTINCT da.struct_id) AS approved_drugs,
      COUNT(DISTINCT c.cancer_type) AS cancer_types_involved
  FROM intogen_driver ig
  JOIN protein p ON p.accession = ig.accession
  JOIN drug_target dt ON dt.accession = p.accession
  JOIN cohort c ON c.cohort = ig.cohort
  LEFT JOIN drug_approval da ON da.struct_id = dt.struct_id
  GROUP BY ig.symbol, p.target_class, p.tdl
  HAVING COUNT(DISTINCT dt.struct_id) >= 15
  ORDER BY total_molecules DESC
  LIMIT 10;
  ```
* **Output d'esempio**:
  | driver_gene | target_class | tdl | total_molecules | approved_drugs | cancer_types_involved |
  |:---|:---|:---:|:---:|:---:|:---:|
  | **EGFR** | Kinase | Tclin | 80 | 64 | 13 |
  | **AR** | Nuclear hormone receptor | Tclin | 59 | 44 | 14 |
  | **ESR1** | Nuclear hormone receptor | Tclin | 56 | 40 | 7 |
  | **ERBB2** | Kinase | Tclin | 49 | 41 | 14 |
  | **RET** | Kinase | Tclin | 46 | 39 | 10 |
  | **FLT3** | Kinase | Tclin | 40 | 37 | 7 |
* **Come dirlo all'orale**: *"Con questa query produciamo un indice di 'druggability' per ogni oncoproteina, aggregando il numero di molecole sperimentali e il sottoinsieme di quelle già autorizzate da FDA o EMA. La clausola `HAVING >= 15` isola i nodi molecolari clinicamente più maturi."*

---

#### Query 5: Polifarmacologia — Farmaci Multi-Target nello Stesso Tumore
* **Obiettivo SQL**: `GROUP BY` su coppia istotipo-farmaco, filtro di soglia con `HAVING COUNT(DISTINCT) >= 2`, e serializzazione pulita dei simboli bersagliati con `GROUP_CONCAT`.
* **Concetto biologico per l'ingegnere**: Un tumore sviluppa facilmente resistenza clonale quando si blocca un solo gene. Questa query individua i farmaci ad ampio spettro capaci di colpire contemporaneamente più geni driver dello stesso tumore ("un cocktail terapeutico in una sola pillola").
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
* **Output d'esempio**:
  | cancer_type | drug_name | n_driver_targets_hit | targeted_driver_genes |
  |:---|:---|:---:|:---|
  | **BRCA** | fostamatinib | 7 | ABL2, CSF1R, EGFR, FLT3, JAK1, JAK2, RET |
  | **BRCA** | midostaurin | 7 | ABL2, AKT1, CSF1R, EGFR, FLT3, KDR, RET |
  | **BRCA** | regorafenib | 7 | ABL2, BRAF, CSF1R, FLT3, KDR, KIT, RET |
  | **COADREAD** | sunitinib | 6 | CSF1R, FLT3, KDR, KIT, PDGFRA, RET |
* **Come dirlo all'orale**: *"Nell'ottica della polifarmacologia, raggruppiamo i dati per rilevare molecole multi-bersaglio che agiscono su più geni driver all'interno dello stesso istotipo tumorale. `GROUP_CONCAT` sintetizza con chiarezza la lista dei geni coinvolti in un'unica stringa leggibile."*

---

#### Query 6: Panorama delle Classi Funzionali dei Bersagli (Target Landscape)
* **Obiettivo SQL**: `LEFT JOIN` a più rami su anagrafica proteica, gestione di valori non mappati con `COALESCE`, aggregazioni comparative indipendenti.
* **Concetto biologico per l'ingegnere**: Fornisce una macro-visione architetturale del database. Mostra come si suddividono le classi funzionali dei bersagli e rivela un contrasto evidente: mentre i recettori GPCR dominano la farmacologia generale, in campo oncologico sono le **Chinasi** a rappresentare la stragrande maggioranza dei bersagli terapeutici.
* **SQL**:
  ```sql
  SELECT 
      COALESCE(p.target_class, 'Non classificata') AS target_class,
      COUNT(DISTINCT p.accession) AS total_human_proteins,
      COUNT(DISTINCT ig.symbol) AS driver_genes_count,
      COUNT(DISTINCT dt.struct_id) AS total_targeting_drugs
  FROM protein p
  LEFT JOIN intogen_driver ig ON ig.accession = p.accession
  LEFT JOIN drug_target dt ON dt.accession = p.accession
  GROUP BY p.target_class
  ORDER BY total_targeting_drugs DESC
  LIMIT 8;
  ```
* **Output d'esempio**:
  | target_class | total_human_proteins | driver_genes_count | total_targeting_drugs |
  |:---|:---:|:---:|:---:|
  | **Enzyme** | 656 | 31 | 1.168 |
  | **GPCR** | 201 | 7 | 981 |
  | **Ion channel** | 195 | 2 | 579 |
  | **Transporter** | 96 | 2 | 561 |
  | **Kinase** | 435 | **76** | 313 |
  | **Nuclear hormone receptor** | 28 | 4 | 306 |
* **Come dirlo all'orale**: *"Questa interrogazione fornisce una sintesi di alto livello della distribuzione funzionale: evidenzia che, pur essendoci moltissimi farmaci diretti contro enzimi generici o GPCR, le Chinasi rappresentano il nucleo portante dei driver oncologici (76 geni driver identificati)."*

---

### LIVELLO 3: Query Avanzate (CTE, Anti-Join, Riposizionamento Clinico, Calcoli Matematici)

#### Query 7: Target Discovery — Geni Driver "Orfani" ad Alta Ricorrenza (Anti-Join)
* **Obiettivo SQL**: Anti-Join relazionale realizzata mediante `LEFT JOIN` combinata con filtro `WHERE dt.struct_id IS NULL`, aggregando per rilevanza clinica decrescente.
* **Concetto biologico per l'ingegnere**: Individua il cosiddetto "Dark Genome" oncologico. Identifica geni che mutano sistematicamente in decine di coorti e in migliaia di pazienti, ma per i quali **non esiste alcun farmaco censito in DrugCentral**. È la query fondamentale per individuare nuove opportunità di investimento in ricerca farmaceutica (*unmet medical need*).
* **SQL**:
  ```sql
  SELECT 
      ig.symbol AS undrugged_driver_gene,
      p.accession AS uniprot_accession,
      COALESCE(p.target_class, 'Non classificata') AS target_class,
      COALESCE(p.tdl, 'Tdark') AS target_development_level,
      COUNT(DISTINCT ig.cohort) AS detected_in_n_cohorts,
      SUM(ig.samples) AS total_mutated_patients
  FROM intogen_driver ig
  JOIN protein p ON p.accession = ig.accession
  LEFT JOIN drug_target dt ON dt.accession = p.accession
  WHERE dt.struct_id IS NULL
  GROUP BY ig.symbol, p.accession, p.target_class, p.tdl
  ORDER BY detected_in_n_cohorts DESC, total_mutated_patients DESC
  LIMIT 10;
  ```
* **Output d'esempio**:
  | undrugged_driver_gene | uniprot_accession | target_class | target_development_level | detected_in_n_cohorts | total_mutated_patients |
  |:---|:---:|:---:|:---:|:---:|:---:|
  | **TP53** | P04637 | Non classificata | Tdark | **212** | **9.192** |
  | **KMT2D** | O14686 | Non classificata | Tdark | 91 | 1.342 |
  | **ARID1A** | O14497 | Non classificata | Tdark | 90 | 1.169 |
  | **KMT2C** | Q8NEZ4 | Non classificata | Tdark | 79 | 1.049 |
  | **PTEN** | P60484 | Non classificata | Tdark | 78 | 1.073 |
  | **CDKN2A** | P42771 | Non classificata | Tdark | 70 | 846 |
* **Come dirlo all'orale**: *"Con questa Anti-Join mostriamo l'applicazione del database alla Drug Discovery: intersecando i dati con una `LEFT JOIN` e cercando i valori nulli, isoliamo i geni driver ad altissimo impatto clinico — primo fra tutti TP53, mutato in oltre 9.000 pazienti — per i quali l'industria farmacologica non dispone ancora di principi attivi approvati."*

---

#### Query 8: Drug Repurposing su Tumori a Prognosi Infausta (Pancreas PAAD e Glioblastoma GBM)
* **Obiettivo SQL**: Sottoinsiemi categorici tramite operatore `IN`, join a cascata su 5 tabelle, aggregazione con calcolo del carico mutazionale associato.
* **Concetto biologico per l'ingegnere**: Patologie come il glioblastoma cerebrale e il cancro al pancreas presentano un tasso di mortalità elevatissimo e pochissime terapie efficaci. La query esplora la medicina traslazionale: trovare farmaci già certificati per altri organi (FDA/EMA) che agiscono sui geni driver mutati nei pazienti di questi due tumori.
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
* **Output d'esempio**:
  | cancer_type | target_driver_gene | drug_name | action_type | approved_by | mutated_samples_in_cohorts |
  |:---|:---:|:---|:---|:---|:---:|
  | **GBM** | EGFR | cetuximab | ANTIBODY BINDING | EMA, FDA, PMDA | 384 |
  | **GBM** | EGFR | dacomitinib | INHIBITOR | EMA, FDA, PMDA | 384 |
  | **GBM** | EGFR | osimertinib | INHIBITOR | EMA, FDA, PMDA | 384 |
  | **GBM** | EGFR | afatinib | INHIBITOR | EMA, FDA | 256 |
  | **PAAD** | KRAS | sotorasib | INHIBITOR | EMA, FDA, PMDA | 182 |
* **Come dirlo all'orale**: *"Questa query risponde a una delle domande più rilevanti in oncologia clinica: il riposizionamento di farmaci (*drug repurposing*). Per tumori aggressivi come glioblastoma e adenocarcinoma pancreatico, estraiamo i farmaci con approvazione FDA/EMA già rilasciata che colpiscono i rispettivi geni driver."*

---

#### Query 9: Potenza Farmacologica Sub-Nanomolare e Conversione Logaritmica (CTE + Funzioni Matematiche)
* **Obiettivo SQL**: Definizione di tabella temporanea mediante **Common Table Expression** (`WITH ... AS`), uso di funzioni matematiche scalari (`POW`, `ROUND`), conversione dinamica tra scale non lineari.
* **Concetto biologico per l'ingegnere**: Nel database le misure di laboratorio ($IC_{50}$, $K_i$) sono registrate come p-value logaritmici negativi:
  $$\text{act\_value} = -\log_{10}(\text{Molarità})$$
  Un valore di $9.0$ equivale a una concentrazione nanomolare pura ($10^{-9} \text{ M} = 1 \text{ nM}$). Valori superiori a $8.5$ indicano potenze sub-nanomolari estreme: il farmaco necessita di concentrazioni minime per bloccare l'oncoproteina, massimizzando l'efficacia e minimizzando la tossicità.
* **SQL**:
  ```sql
  WITH HighAffinityInteractions AS (
      SELECT 
          ig.symbol AS driver_gene,
          d.drug_name,
          a.act_type,
          a.act_value
      FROM activity a
      JOIN drug d ON d.struct_id = a.struct_id
      JOIN intogen_driver ig ON ig.accession = a.accession
      WHERE a.act_value >= 8.5
        AND a.act_type IN ('IC50', 'Ki', 'Kd')
  )
  SELECT 
      driver_gene,
      drug_name,
      act_type,
      MAX(act_value) AS max_log_potency,
      ROUND(POW(10, -(MAX(act_value) - 9)), 3) AS approx_concentration_nM
  FROM HighAffinityInteractions
  GROUP BY driver_gene, drug_name, act_type
  ORDER BY max_log_potency DESC
  LIMIT 10;
  ```
* **Output d'esempio**:
  | driver_gene | drug_name | act_type | max_log_potency | approx_concentration_nM |
  |:---|:---|:---:|:---:|:---:|
  | **CSF1R** | axatilimab-csfr | Kd | 11.240 | **0.006 nM** |
  | **CXCR4** | motixafortide | Kd | 11.100 | **0.008 nM** |
  | **BCL2** | venetoclax | Ki | 11.000 | **0.010 nM** |
  | **KDR** | sorafenib | Ki | 10.680 | **0.021 nM** |
  | **ABL1** | bosutinib | Kd | 10.540 | **0.029 nM** |
  | **PIK3CA** | inavolisib | IC50 | 10.420 | **0.038 nM** |
* **Come dirlo all'orale**: *"In questa query avanzata impieghiamo una CTE per isolare le interazioni biofisiche ad altissima affinità. Dimostriamo la capacità del motore SQL di compiere calcoli scalari in tempo reale, riconvertendo il parametro logaritmico pVal nella corrispondente concentrazione lineare in nanomolari ($10^{-(pVal-9)}$)."*

---

## Istruzioni di Esecuzione e Presentazione d'Esame

### 1. Rigenerazione della pipeline ETL
Per ricreare da zero gli 8 file CSV puliti partendo dai dati raw:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/02_clean.py
```

### 2. Inizializzazione e popolamento del database MySQL
Per creare le 8 tabelle e caricare l'intero corpus dati con commit a blocchi di 5.000 record:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/03_load.py --user root --init-schema
```

### 3. Dimostrazione in MySQL Workbench
1. **Verifica Schema EER**:
   * Menu **Database ➔ Reverse Engineer...** ➔ selezionare il database `intogen_drugcentral`.
   * Verrà generato il grafo relazionale completo che illustra la centralità della tabella `protein` e la normalizzazione di `cohort`.
2. **Esecuzione delle Query**:
   * Aprire `sql/queries.sql` in Workbench ed eseguire le interrogazioni suddivise per livello.
