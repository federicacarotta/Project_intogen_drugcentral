# Progetto IntOGen – DrugCentral

Questo progetto costruisce un **database relazionale** che mette in collegamento due mondi:

1. **I geni che causano il cancro** (dati IntOGen)
2. **I farmaci che agiscono sulle proteine** prodotte da quei geni (dati DrugCentral)

Il collegamento tra i due avviene grazie a **UniProt**, l'archivio pubblico di riferimento per le sequenze proteiche, che assegna a ciascuna proteina un codice univoco chiamato *accession* (es. `P04637` per la proteina p53, `P01116` per KRAS).

L'idea di fondo è semplice ed essenziale per la medicina di precisione: se sappiamo che un gene è responsabile di un tumore e sappiamo che esiste un farmaco che colpisce la proteina codificata da quel gene, abbiamo un possibile percorso terapeutico o un'opportunità di riposizionamento farmacologico (*drug repurposing*).

```
Gene driver ──► Proteina (UniProt accession) ◄── Farmaco
   IntOGen              ponte                    DrugCentral
```

---

## Struttura del progetto

```
Project_intogen_drugcentral/
│
├── data/
│   ├── raw/                 ← dati originali, così come scaricati dalle banche dati
│   │   ├── intogen/         ← file di IntOGen (Compendium_Cancer_Genes.tsv)
│   │   ├── drugcentral/     ← file di DrugCentral (drug.target.interaction.tsv e liste approvati)
│   │   └── uniprot/         ← file di UniProt (anagrafica proteine umane reviewed)
│   │
│   └── clean/               ← dati puliti e normalizzati, pronti per MySQL (8 CSV)
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
│   ├── 01_inspect.py        ← esplora i dati grezzi e ne verifica qualità e tipi
│   ├── 02_clean.py          ← pulisce i dati e produce gli 8 CSV in data/clean/
│   └── 03_load.py           ← crea lo schema ed effettua il caricamento massivo in MySQL
│
├── sql/
│   ├── schema.sql           ← schema DDL MySQL (8 tabelle, vincoli FK e indici)
│   └── queries.sql          ← vista integrata e 8 query analitiche per la presentazione
│
├── docs/
│   └── README.md            ← documentazione completa del progetto
│
└── README.md                ← symlink a docs/README.md per GitHub
```

---

## Le tre sorgenti dati

### 1. IntOGen — I geni driver del cancro

**Cos'è IntOGen**: una piattaforma bioinformatica che analizza dati di sequenziamento somatico (WES/WGS) di migliaia di pazienti oncologici per identificare i geni le cui mutazioni conferiscono un vantaggio selettivo clonale e guidano lo sviluppo del tumore (*driver genes*).

**File**: `Compendium_Cancer_Genes.tsv` — 4 478 righe, 18 colonne.

Ogni riga descrive la scoperta di un gene driver all'interno di una specifica coorte di pazienti affetti da un determinato tumore.

**Colonne principali**:

| Colonna | Cosa significa |
|---------|----------------|
| `SYMBOL` | Simbolo ufficiale del gene (es. TP53, KRAS, BRAF, EGFR) |
| `COHORT` | Nome univoco del dataset/studio clinico di pazienti analizzato |
| `CANCER_TYPE` | Sigla del tipo di tumore (es. BRCA = seno, LUAD = polmone, GBM = glioblastoma) |
| `ROLE` | Ruolo biologico predetto: **Act** (attivante / oncogene) o **LoF** (perdita di funzione / oncosoppressore) |
| `MUTATIONS` | Numero totale di mutazioni somatiche osservate nel gene |
| `SAMPLES` | Numero di pazienti/campioni della coorte che presentano mutazioni nel gene |
| `TOTAL_SAMPLES` | Dimensione campionaria complessiva della coorte analizzata |
| `QVALUE_COMBINATION` | Significatività statistica combinata corretta per FDR (più è vicino a 0, maggiore è la confidenza) |
| `METHODS` | Algoritmi bioinformatici concordi (es. OncodriveFML, dNdScv, HotSPS, MutSigCV) |

**Numeri chiave**:
- 633 geni driver unici
- 260 coorti cliniche distinte
- 86 tipi di tumore analizzati
- I geni driver più ricorrenti: TP53 (presente in 212 coorti), PIK3CA (109), KRAS (84)

---

### 2. DrugCentral — Farmaci, bersagli, interazioni e approvazioni

**Cos'è DrugCentral**: compendio farmacologico online sviluppato dall'Università del New Mexico che integra strutture molecolari, target farmacologici, dosaggi terapeutici e meccanismi d'azione convalidati.

**File principali**:
- `drug.target.interaction.tsv` — 22 364 righe, 20 colonne (interazioni farmaco-bersaglio).
- `FDA_Approved.csv`, `EMA_Approved.csv`, `PMDA_Approved.csv` — elenchi ufficiali dei farmaci autorizzati all'immissione in commercio rispettivamente da FDA (USA), EMA (Europa) e PMDA (Giappone).

**Colonne principali dell'interazione**:

| Colonna | Cosa significa |
|---------|----------------|
| `DRUG_NAME` | Denominazione comune internazionale del farmaco (es. erlotinib, pembrolizumab) |
| `STRUCT_ID` | Identificativo numerico univoco del principio attivo in DrugCentral |
| `TARGET_NAME` | Nome descrittivo del bersaglio molecolare |
| `ACCESSION` | Codice univoco UniProt del bersaglio proteico umano |
| `GENE` | Simbolo del gene codificante |
| `ACTION_TYPE` | Tipo di azione farmacologica (es. INHIBITOR, AGONIST, ANTAGONIST, BLOCKER) |
| `TARGET_CLASS` | Famiglia biologica del bersaglio (es. Kinase, GPCR, Enzyme, Ion channel) |
| `ACT_VALUE` | Affinità/potenza quantitativa misurata (valore -log10, es. pIC50, pKi, pKd) |
| `ACT_TYPE` | Parametro sperimentale impiegato (IC50, Ki, Kd, EC50) |
| `MOA` | Flag binario (1 = bersaglio terapeutico primario/MoA, 0 = interazione secondaria/screening) |
| `MOA_SOURCE` | Fonte o letteratura regolatoria che convalida il meccanismo (es. FDA, ChEMBL) |
| `TDL` | Target Development Level: grado di maturità farmacologica (Tclin, Tchem, Tbio, Tdark) |
| `ORGANISM` | Specie biologica del bersaglio (filtrato su `Homo sapiens`) |

**Numeri chiave**:
- 22 364 righe grezze totali ➔ 16 926 righe con bersaglio umano (`Homo sapiens`)
- 2 632 farmaci unici attivi su bersagli umani
- 18 228 interazioni uniche farmaco-bersaglio in `drug_target.csv`
- 2 401 registrazioni di approvazione regolatoria (1 705 FDA, 356 EMA, 340 PMDA)

---

### 3. UniProt — L'anagrafica delle proteine e dizionario ponte

**Cos'è UniProt**: la banca dati mondiale di sequenze e annotazioni funzionali di proteine. Utilizziamo la porzione **Swiss-Prot** (proteine umane manualmente revisionate e curate con la massima accuratezza biologica).

**File**: `uniprotkb_...2026_10_26.tsv` — 20 431 righe (proteine umane *reviewed*).

UniProt risolve il problema cardine dell'integrazione:
- IntOGen indicizza le scoperte tramite i **simboli dei geni** (`SYMBOL`, es. *ERBB2*).
- DrugCentral indicizza i bersagli tramite **accession UniProt** (`ACCESSION`, es. *P04626*).
- La tabella ponte `gene_symbol` (45 565 record) traduce ogni simbolo e sinonimo storico genico nella corrispondente proteina, identificando il simbolo ufficiale primario (`is_primary = 1`).

---

## Riepilogo delle 8 tabelle create in MySQL

| Tabella | Righe | Descrizione e Contenuto |
|---------|-------|--------------------------|
| `protein` | 20 433 | Anagrafica proteica UniProt (`accession`, `entry_name`, `protein_name`, `target_class`, `tdl`) |
| `gene_symbol` | 45 565 | Mapping proteina → simboli genici e sinonimi con flag ufficiale (`is_primary`) |
| `drug` | 2 632 | Anagrafica molecole DrugCentral (`struct_id`, `drug_name`) |
| `drug_approval` | 2 401 | Approvazioni regolatorie per farmaco ed ente (`struct_id`, `agency`) |
| `drug_target` | 18 228 | Relazione N:M farmaco–bersaglio (`struct_id`, `accession`, `target_class`, `moa`, `action_type`, `moa_source`) |
| `activity` | 16 716 | Misure quantitative sperimentali di affinità/potenza (IC50, Ki, Kd) |
| `cohort` | 260 | Coorti di pazienti oncologici con tipo tumorale e dimensione campionaria (`total_samples`) |
| `intogen_driver` | 4 478 | Geni driver per coorte con statistiche mutazionali e chiave esterna su proteina |

---

## Approfondimenti di Progettazione e Risposte sui Dati

### 1. Perché `target_class` è presente sia in `protein` sia in `drug_target.csv`?

- **Prospettiva di Modellazione Relazionale (Forma Normale 3NF)**:
  `target_class` (es. *Kinase*, *GPCR*, *Ion channel*, *Enzyme*) è una proprietà biologica intrinseca della proteina bersaglio (`accession`), e non del singolo farmaco o della singola somministrazione. Nella tabella anagrafica `protein`, `target_class` descrive la famiglia proteica di appartenenza.
- **Prospettiva Analitica e Pratica in `drug_target.csv`**:
  Nel file raw di DrugCentral (`drug.target.interaction.tsv`), la colonna `TARGET_CLASS` è presente ed è **popolata al 100% per tutte le interazioni umane** (0% nulli). Al contrario, nel file UniProt le proteine umane sono oltre 20.000 ma solo ~2.300 sono bersagli farmacologici censiti in DrugCentral.
  Salvare `target_class` anche in `drug_target.csv` (e nella tabella `drug_target`) garantisce:
  1. La disponibilità immediata della classe funzionale del bersaglio direttamente nelle analisi e nei filtri CSV senza dover obbligatoriamente effettuare una JOIN con `protein`.
  2. Coerenza e completezza immediata per chi esporta o consulta la tabella delle interazioni farmaco-bersaglio.

---

### 2. Perché manteniamo `action_type` in `drug_target.csv` anche se è spesso nullo?

Nel dataset pulito `drug_target.csv`, la colonna `action_type` presenta valori nulli nel **73.4%** dei casi. Nonostante questa sparsità globale, mantenerla è **biologicamente fondamentale** per le seguenti ragioni:

1. **La correlazione con il Meccanismo d'Azione Primario (`moa = 1`)**:
   - Per le interazioni secondarie di screening generico (`moa = 0`), `action_type` è presente solo nell'8.4% dei casi, perché i laboratori testano solo se la molecola si lega (binding/displacement) senza determinarne l'effetto funzionale.
   - Per le interazioni che costituiscono il **vero meccanismo d'azione terapeutico (`moa = 1`)**, `action_type` è popolato nel **99.6% dei casi** (praticamente nel 100% dei farmaci clinici!).
2. **Distribuzione dei valori non-nulli**:
   I valori presenti sono estremamente precisi e informativi:
   - `INHIBITOR`: 1 589 (di cui 1 197 con MoA=1)
   - `AGONIST`: 908 (di cui 588 con MoA=1)
   - `ANTAGONIST`: 816 (di cui 531 con MoA=1)
   - `BLOCKER`: 539 (di cui 440 con MoA=1)
   - `POSITIVE ALLOSTERIC MODULATOR`: 307
   - `ANTIBODY BINDING`: 140
   - `ACTIVATOR`: 96
3. **Valore critico in Oncologia di Precisione**:
   In oncologia non basta sapere che un farmaco "tocca" una proteina; è indispensabile conoscere la **direzione dell'effetto**:
   - Se un gene driver è classificato da IntOGen come oncogene attivante (`role = 'Act'`), il paziente ha bisogno di un **INIBITORE**, **ANTAGONISTA** o **BLOCCANTE**. Somministrare un agonista o un attivatore alimenterebbe la proliferazione tumorale!
   - Se il driver è un oncosoppressore inattivato (`role = 'LoF'`), un inibitore non avrebbe utilità clinica.
   Mantenere `action_type` rende possibile l'esecuzione di query biologiche mirate (come la **Query 4** in `sql/queries.sql`), che scarta falsi positivi e individua solo le terapie meccanicisticamente corrette.

---

### 3. Perché abbiamo diviso `cohort` da `intogen_driver`?

Nel file grezzo `Compendium_Cancer_Genes.tsv`, ogni riga conteneva contemporaneamente i dati del gene driver (`SYMBOL`, `MUTATIONS`, `QVALUE_COMBINATION`, ecc.) e i dati dello studio clinico (`COHORT`, `CANCER_TYPE`, `TOTAL_SAMPLES`).

La suddivisione in due tabelle distinte (`cohort` e `intogen_driver`) è motivata da precise regole di ingegneria dei dati e dalla biologia analitica:

#### A. Rispetto della Seconda e Terza Forma Normale (2NF / 3NF)
In un'unica tabella non normalizzata, la chiave primaria logica di un'osservazione è la coppia composta `(symbol, cohort)`.
Tuttavia, `cancer_type` e `total_samples` dipendono **esclusivamente dalla coorte** (`cohort -> cancer_type, total_samples`), e non dal gene driver:
- Si tratta di una **dipendenza funzionale parziale**.
- Mantenerli nella stessa tabella viola la Seconda Forma Normale (2NF) e introduce ridondanza sistematica: la dimensione di una coorte (es. 1 098 campioni per TCGA-BRCA) verrebbe replicata identica su centinaia di righe.

#### B. Eliminazione delle anomalie relazionali
1. **Anomalia di aggiornamento (Update Anomaly)**: se la dimensione campionaria di una coorte viene ricalcolata o rettificata a seguito di ri-sequenziamento, in una tabella unificata bisognerebbe aggiornare decine di righe con il rischio di generare stati disallineati. Con la tabella `cohort`, si aggiorna un solo record.
2. **Anomalia di inserimento/cancellazione**: è possibile censire una nuova coorte clinica sequenziata prima ancora che vengano identificati i relativi geni driver, o conservare i metadati di una coorte anche se nessun gene supera le soglie statistiche di driver.

#### C. Prevenzione dell'errore di moltiplicazione nei calcoli aggregati (Aggregation Bias)
Se volessimo calcolare quanti pazienti oncologici complessivi sono stati sequenziati per il tumore al polmone (`LUAD`), eseguendo `SUM(total_samples)` su una tabella non normalizzata si moltiplicherebbe la dimensione della coorte per il numero di geni driver identificati in quello studio! Se una coorte ha 40 driver, il numero di pazienti verrebbe sovrastimato di 40 volte.
Con la tabella `cohort`, il conteggio è esatto e immediato.

#### Esempio di Query Tipica che Giustifica la Suddivisione

##### Esempio 1: Statistiche epidemiologiche corrette per tipo di tumore
```sql
-- Calcola coorti e pazienti totali senza duplicazioni, associando i driver scoperti
SELECT 
    c.cancer_type,
    COUNT(DISTINCT c.cohort) AS n_cohorts,
    SUM(c.total_samples) AS total_patients_sequenced,
    COUNT(DISTINCT ig.symbol) AS unique_driver_genes,
    ROUND(SUM(c.total_samples) / COUNT(DISTINCT c.cohort), 0) AS avg_patients_per_cohort
FROM cohort c
LEFT JOIN intogen_driver ig ON ig.cohort = c.cohort
GROUP BY c.cancer_type
ORDER BY total_patients_sequenced DESC;
```

##### Esempio 2: Filtrare i geni driver in base alla potenza statistica della coorte
Permette di selezionare driver ad altissima confidenza identificati esclusivamente in studi ampi (es. almeno 500 pazienti):
```sql
SELECT 
    c.cancer_type,
    ig.symbol AS driver_gene,
    c.cohort,
    c.total_samples AS cohort_size,
    ig.samples AS mutated_samples,
    ROUND(ig.pct_samples_cohort * 100, 2) AS pct_mutated,
    ig.qvalue_combination
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
WHERE c.total_samples >= 500
  AND ig.qvalue_combination < 0.001
ORDER BY c.total_samples DESC, ig.pct_samples_cohort DESC;
```

---

## Risoluzione del problema di aggiornamento su GitHub

### Perché il repository GitHub non si aggiornava con le modifiche locali?
Analizzando la configurazione Git locale in `Project_intogen_drugcentral`, sono emerse due cause principali:

1. **Assenza della destinazione remota (`origin`)**:
   Il repository locale non aveva alcun URL remoto configurato (`git remote -v` era vuoto). I commit effettuati in locale (`c693325`, `a846865`, `a4d8d16`) rimanevano confinati sul computer e nessun comando `git push` poteva contattare GitHub.
2. **Cronologie disconnesse (Unrelated Histories) da upload web iniziale**:
   La versione presente su GitHub derivava da un caricamento manuale tramite interfaccia web ("Add files via upload", commit `b990d34`), in cui l'intero progetto era stato inserito dentro una sotto-cartella duplicata `Project_intogen_drugcentral/`. Il repository locale aveva invece un commit iniziale indipendente (`ab18736`, "primo caricamento").

### Azioni correttive intraprese
1. Aggiunto il puntatore remoto corretto:
   ```bash
   git remote add origin https://github.com/federicacarotta/Project_intogen_drugcentral.git
   ```
2. Rimosso il tracciamento dei file di sistema non necessari (`.DS_Store`) e creato il file `.gitignore`.
3. Per allineare GitHub e sostituire il vecchio caricamento web con l'albero pulito e aggiornato, è sufficiente eseguire:
   ```bash
   git push -u origin main --force
   ```

---

## Modalità di Esecuzione e Presentazione d'Esame

### 1. Rigenerazione dei dati puliti
Per ri-eseguire da zero la pulizia dei dati grezzi e rigenerare tutti gli 8 CSV:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/02_clean.py
```

### 2. Caricamento automatico nel database MySQL
Per ricreare lo schema da zero e caricare tutte le 8 tabelle in MySQL:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/03_load.py --user root --init-schema
```
*Lo script richiederà la password di MySQL `root`, eseguirà `sql/schema.sql`, caricherà tutti i record in batch da 5.000 righe e stamperà il riepilogo con verifica di integrità referenziale.*

### 3. Presentazione in MySQL Workbench
1. **Diagramma EER**: Menu **Database ➔ Reverse Engineer...** ➔ selezionare il database `intogen_drugcentral`. Verranno visualizzate le 8 tabelle con le relazioni 1:N e N:M centrate sul ponte UniProt.
2. **Esecuzione Query**: Aprire `sql/queries.sql` in Workbench ed eseguire le 8 query analitiche (dal calcolo di druggability al riposizionamento su tumori rari e alle statistiche epidemiologiche delle coorti).


aggiornato
