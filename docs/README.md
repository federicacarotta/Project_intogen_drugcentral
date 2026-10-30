# Progetto IntOGen – DrugCentral

Questo progetto costruisce un **database relazionale** che mette in collegamento due mondi:

1. **I geni che causano il cancro** (dati IntOGen)
2. **I farmaci che agiscono sulle proteine** prodotte da quei geni (dati DrugCentral)

Il collegamento tra i due avviene grazie a **UniProt**, un archivio pubblico di proteine
che assegna a ciascuna proteina un codice univoco chiamato *accession*
(es. `P04637` per la proteina p53).

L'idea di fondo è semplice: se sappiamo che un gene è responsabile di un tumore
e sappiamo che esiste un farmaco che colpisce la proteina di quel gene,
allora abbiamo un possibile percorso terapeutico.

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
│   ├── raw/                 ← dati originali, così come scaricati
│   │   ├── intogen/         ← file di IntOGen (geni driver)
│   │   ├── drugcentral/     ← file di DrugCentral (interazioni e farmaci approvati)
│   │   └── uniprot/         ← file di UniProt (anagrafica proteine)
│   │
│   └── clean/               ← dati puliti, pronti per il database (8 CSV)
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
│   ├── 01_inspect.py        ← esplora i dati grezzi (non modifica nulla)
│   ├── 02_clean.py          ← pulisce i dati e produce gli 8 CSV in data/clean/
│   └── 03_load.py           ← crea il DB ed effettua il caricamento massivo in MySQL
│
├── sql/
│   ├── schema.sql           ← schema DDL MySQL (8 tabelle, vincoli e indici)
│   └── queries.sql          ← vista integrata e 7 query analitiche per la presentazione
│
└── docs/
    └── README.md            ← documentazione del progetto
```

---

## Le tre sorgenti dati

### 1. IntOGen — I geni driver del cancro

**Cos'è IntOGen**: un progetto che analizza i dati di sequenziamento genetico
di migliaia di pazienti oncologici per trovare i geni le cui mutazioni
*guidano* lo sviluppo del tumore (da qui il nome "driver").

**File**: `Compendium_Cancer_Genes.tsv` — 4 478 righe, 18 colonne.

Ogni riga dice: *"Il gene X è stato trovato come driver nel dataset Y
(che riguarda il tipo di tumore Z)"*.

**Colonne principali**:

| Colonna | Cosa significa |
|---------|----------------|
| `SYMBOL` | Il nome del gene (es. TP53, KRAS, BRAF) |
| `COHORT` | Il nome del dataset di pazienti analizzato |
| `CANCER_TYPE` | Il tipo di tumore (es. BRCA = seno, LUAD = polmone) |
| `ROLE` | Il ruolo del gene: **Act** (acceleratore/oncogene) o **LoF** (freno rotto/oncosoppressore) |
| `MUTATIONS` | Quante mutazioni sono state trovate |
| `SAMPLES` | In quanti pazienti sono state trovate |
| `QVALUE_COMBINATION` | Valore statistico combinato: più è vicino a zero, maggiore è la confidenza |
| `METHODS` | Quali algoritmi bioinformatici hanno identificato il gene come driver |

**Numeri chiave**:
- 633 geni driver unici
- 260 coorti (dataset di pazienti)
- 86 tipi di tumore diversi
- I geni più frequentemente driver: TP53 (212 coorti), PIK3CA (109), KRAS (84)

---

### 2. DrugCentral — I farmaci, bersagli e approvazioni

**Cos'è DrugCentral**: un database pubblico che raccoglie informazioni su farmaci
(approvati e in sperimentazione) e sulle proteine su cui agiscono.

**File principali**:
- `drug.target.interaction.tsv` — 22 364 righe, 20 colonne (interazioni farmaco-bersaglio).
- `FDA_Approved.csv`, `EMA_Approved.csv`, `PMDA_Approved.csv` — liste ufficiali di farmaci approvati dai principali enti regolatori mondiali (FDA per gli USA, EMA per l'Europa, PMDA per il Giappone).

Ogni riga di interazione dice: *"Il farmaco X si lega alla proteina Y con una certa forza
e produce un certo effetto"*.

**Colonne principali dell'interazione**:

| Colonna | Cosa significa |
|---------|----------------|
| `DRUG_NAME` | Nome del farmaco (es. imatinib, nivolumab) |
| `STRUCT_ID` | Codice numerico univoco del farmaco in DrugCentral |
| `TARGET_NAME` | Nome della proteina bersaglio |
| `ACCESSION` | Codice UniProt della proteina bersaglio |
| `GENE` | Gene che codifica la proteina bersaglio |
| `ACTION_TYPE` | Meccanismo: inibitore, agonista, antagonista, modulatore, ecc. |
| `ACT_VALUE` | Potenza del farmaco (es. pIC50, pKi in scala -log10) |
| `ACT_TYPE` | Tipo di misura (IC50, Ki, Kd, EC50, ecc.) |
| `MOA` | Flag meccanismo d'azione principale del farmaco (1 = sì, 0 = no) |
| `TDL` | Target Development Level (Tclin → Tchem → Tbio → Tdark) |
| `TARGET_CLASS` | Famiglia della proteina (GPCR, Chinasi, Canale ionico, Enzima, ecc.) |
| `ORGANISM` | Organismo della proteina bersaglio (Homo sapiens, Mus musculus, ecc.) |

**Numeri chiave**:
- 22 364 interazioni totali (tutti gli organismi)
- 16 926 interazioni umane filtrate (`Homo sapiens`)
- 2 632 farmaci unici associati a bersagli umani
- Classi di bersagli più frequenti: GPCR (6 543), Enzimi (5 653), Chinasi (4 802)
- Farmaci approvati integrati: 1 705 FDA, 356 EMA, 340 PMDA

---

### 3. UniProt — L'anagrafica delle proteine (il ponte)

**Cos'è UniProt**: il più grande archivio pubblico di informazioni sulle proteine.
Ogni proteina ha un codice univoco chiamato *accession* (es. `P04637`).

**File**: `uniprotkb_...2026_10_26.tsv` — 20 431 righe (solo proteine umane *reviewed* / Swiss-Prot).

UniProt fa da **ponte** tra IntOGen e DrugCentral:
- IntOGen cataloga i dati tramite **nomi dei geni** (es. `TP53`)
- DrugCentral indicizza i bersagli tramite **codici accession** UniProt (es. `P04637`)
- UniProt associa entrambi, gestendo anche la molteplicità di sinonimi genici

---

## Cosa fa lo script di ispezione (01_inspect.py)

Questo script **non modifica nessun dato**. Si limita a leggere i file grezzi
e a stampare a terminale diagnostiche complete:

1. **Dimensioni e scheletro dei dati** (righe, colonne, tipi di dato).
2. **Percentuale di valori nulli** per colonna per identificare vincoli `NOT NULL` vs `NULL`.
3. **Distribuzione delle categorie** (`ORGANISM`, `ACTION_TYPE`, `TARGET_CLASS`, `ROLE`).
4. **Anomalie strutturali** (celle multi-valore con delimitatori, righe duplicate).
5. **Compatibilità di overlap**: quanti geni/proteine risultano in comune tra le sorgenti.

---

## Cosa fa lo script di pulizia (02_clean.py)

Questo script legge i dati grezzi e genera gli **8 file CSV puliti** in `data/clean/`,
garantendo la conformità allo schema relazionale in forma normale.

### Passo 1 — UniProt (Anagrafica proteine e simboli)
- Estrae le proteine umane revisionate generando `protein.csv` (20 433 righe).
- Esplode i sinonimi genici generando `gene_symbol.csv` (45 565 righe), distinguendo il simbolo primario ufficiale (`is_primary = 1`) dai sinonimi secondari (`is_primary = 0`).

### Passo 2 — DrugCentral (Interazioni, farmaci e bersagli)
- **Filtro organismo**: seleziona unicamente le interazioni con bersagli umani (`ORGANISM = 'Homo sapiens'`), passando da 22 364 a 16 926 righe.
- **Normalizzazione celle multi-valore**: le celle contenenti più accession o geni separati da delimitatori (`|`, `,`, `;`) vengono esplose in righe singole (da 16 926 a 18 749 righe), rispettando la 1a Forma Normale.
- **Pulizia stringhe e rimozione valori ripetuti**: per campi come `TDL`, `SWISSPROT` e `TARGET_CLASS` (che presentavano stringhe ripetute come `Tclin|Tclin|Tclin` o multiple come `Tclin|Tchem`), la funzione dedicata `first_val()` estrae il singolo valore pulito.
- **Creazione tabella `drug`**: isola 2 632 farmaci unici (`struct_id`, `drug_name`).
- **Gestione accession orfane (stub)**: crea record "stub" nella tabella `protein` per le 2 accession umane presenti in DrugCentral ma assenti in UniProt, salvaguardando l'integrità referenziale.
- **Creazione tabella `drug_target`**: genera 18 228 relazioni uniche farmaco-bersaglio. In caso di conflitti su `ACTION_TYPE`, adotta la classificazione più frequente (moda statistica).
- **Creazione tabella `activity`**: isola 16 716 misurazioni numeriche di attività/potenza (`act_value`, `act_type`, `relation`, `act_source`).

### Passo 3 — IntOGen (Geni driver e coorti)
- **Standardizzazione**: nomi colonne in snake_case, conversione `is_driver` in booleano (0/1), conversione conteggi a interi (`Int64`).
- **Creazione tabella `cohort`**: 260 coorti tumorali uniche con tipo tumorale associato e campioni totali.
- **Risoluzione ponte genico IntOGen ──► UniProt**:
  - Mappatura di ciascun `symbol` tramite la tabella `gene_symbol`.
  - Risolti con successo **tutti i 633 geni driver** (0 geni senza accession).
  - Per i 18 simboli ambigui (associati a più accession), priorità assegnata al simbolo primario HGNC.
- **Creazione tabella `intogen_driver`**: 4 478 record gene driver–coorte arricchiti con l'accession UniProt.

### Passo 4 — Approvazioni regolatorie (FDA, EMA, PMDA)
- Importazione dei file di approvazione `FDA_Approved.csv`, `EMA_Approved.csv` e `PMDA_Approved.csv`.
- Mappatura e filtraggio su `struct_id` validi presenti nella tabella `drug`.
- Generazione della tabella `drug_approval.csv` (2 401 associazioni farmaco-agenzia).
  - FDA: 1 705 approvazioni
  - EMA: 356 approvazioni
  - PMDA: 340 approvazioni

### Passo 5 — Validazione lunghezze e salvataggio
- Verifica automatica che nessuna colonna ecceda i limiti VARCHAR previsti dallo schema SQL.
- Salvataggio degli 8 file CSV pronti per il caricamento nel database.

---

## Numeri chiave del database

- **633** geni driver oncologici totali analizzati in 260 coorti e 86 tipi tumorali.
- **149 geni driver su 633 (23.5%)** hanno almeno un farmaco registrato in DrugCentral.
- **515** farmaci totali colpiscono proteine di geni driver del cancro.
- **361 farmaci su 515 (70.1%)** sono farmaci **già approvati** da almeno un'agenzia regolatoria (FDA, EMA o PMDA).

---

## Riepilogo delle 8 tabelle create

| Tabella | Righe | Descrizione e Contenuto |
|---------|-------|--------------------------|
| `protein` | 20 433 | Anagrafica proteica UniProt (accession, entry_name, protein_name, target_class, tdl) |
| `gene_symbol` | 45 565 | Mapping proteina → simboli genici con flag per nome primario (`is_primary`) |
| `drug` | 2 632 | Anagrafica farmaci DrugCentral (`struct_id`, `drug_name`) |
| `drug_approval` | 2 401 | Approvazioni regolatorie per farmaco e agenzia (`struct_id`, `agency`) |
| `drug_target` | 18 228 | Relazione N:M farmaco–bersaglio con meccanismo d'azione (`moa`, `action_type`) |
| `activity` | 16 716 | Misure quantitative di affinità/potenza farmacologica (IC50, Ki, Kd, ecc.) |
| `cohort` | 260 | Coorti di pazienti oncologici con tipo di cancro e campioni |
| `intogen_driver` | 4 478 | Geni driver per coorte con statistiche mutazionali e accession proteica collegata |

---

## Problemi riscontrati e soluzioni adottate

Durante l'ispezione, la pulizia dei dati e la progettazione dello schema relazionale sono state affrontate diverse criticità tecniche e biologiche:

### 1. Dati multi-valore e complessi proteici (DrugCentral)
- **Problema**: Le colonne `ACCESSION` e `GENE` di DrugCentral contenevano celle con valori multipli separati da pipe `|`, virgole o spazi (es. complessi eterodimerici o canali composti da più subunità). Inserire valori composti avrebbe violato la 1a Forma Normale.
- **Soluzione**: Implementazione della funzione `split_multi()` ed esplosione delle righe (`explode`), trasformando ogni coppia farmaco-subunità in una riga autonoma (da 16 926 a 18 749 righe).

### 2. Valori duplicati e concatenati nei metadati dei target (`TDL`, `SWISSPROT`, `TARGET_CLASS`)
- **Problema**: In DrugCentral, colonne descrittive come `TDL` (Target Development Level) contenevano spesso stringhe ripetute decine di volte separate da pipe (es. `Tclin|Tclin|Tclin|...` per decine di ripetizioni) o valori eterogenei come `Tclin|Tchem`. Questo sporcava il dato e faceva fallire i vincoli di dimensione (`VARCHAR(10)`).
- **Soluzione**: Creazione della funzione `first_val()`, che estrae unicamente il primo token valido ed elimina la ridondanza prima dell'inserimento.

### 3. Disallineamento tra identificatori IntOGen e DrugCentral
- **Problema**: IntOGen utilizza unicamente i simboli genici (`SYMBOL`, es. *TP53*), mentre DrugCentral identifica i bersagli proteici tramite codici UniProt (`ACCESSION`, es. *P04637*). Un confronto diretto per nome del gene intercettava appena 144 corrispondenze a causa di sinonimi e nomenclature disomogenee.
- **Soluzione**: Utilizzo dell'archivio UniProt come "dizionario ponte", creando la tabella `gene_symbol` (45 565 record) che ha permesso di collegare correttamente tutti i 633 geni driver IntOGen alle rispettive proteine.

### 4. Ambiguità nei simboli dei geni (Sinonimi condivisi)
- **Problema**: A causa di ridenominazioni storiche della nomenclatura genetica (HGNC), 18 simboli genici in IntOGen corrispondevano a più di un'accession proteica in UniProt.
- **Soluzione**: Risoluzione deterministica dell'ambiguità assegnando priorità ai record con `is_primary = 1` (simbolo ufficiale HGNC), garantendo la copertura del 100% dei geni driver senza duplicazioni orfane.

### 5. Accession DrugCentral non censite in UniProt
- **Problema**: 2 codici accession di proteine umane presenti in DrugCentral non risultavano nel compendio Swiss-Prot delle proteine umane revisionate. Scartarli avrebbe comportato la perdita delle interazioni e dei farmaci collegati.
- **Soluzione**: Generazione di record provvisori (*stub*) nella tabella `protein`, popolandoli con i dati accessori forniti da DrugCentral per preservare l'integrità referenziale.

### 6. Conflitti di annotazione in `ACTION_TYPE`
- **Problema**: Alcune coppie farmaco-bersaglio presentavano classificazioni discordanti dell'azione farmacologica (`ACTION_TYPE`) dovute alla confluenza di molteplici banche dati e pubblicazioni in DrugCentral (6 coppie in conflitto).
- **Soluzione**: Selezione del valore più frequente per la coppia tramite la moda statistica (`mode_or_na`) per la tabella relazionale `drug_target`, conservando invece tutte le misure dettagliate nella tabella `activity`.

### 7. Formato eterogeneo dei file di approvazione farmaci
- **Problema**: I file `FDA_Approved.csv`, `EMA_Approved.csv` e `PMDA_Approved.csv` erano file grezzi privi di riga di intestazione e includevano farmaci veterinari o non presenti nell'anagrafica dei farmaci umani analizzati.
- **Soluzione**: Assegnazione programmata delle intestazioni, filtraggio selettivo sui soli `struct_id` validati nella tabella `drug`, deduplicazione e aggiunta della colonna identificativa dell'agenzia (`agency`).

### 8. Dimensionamento dei tipi di dato nello schema SQL
- **Problema**: Dai test di lunghezza eseguiti sui CSV puliti rispetto allo schema SQL iniziale sono emerse stringhe più lunghe del previsto:
  - `protein_name` superava `VARCHAR(500)` a causa di descrizioni proteiche ed enzimatiche estese.
  - `cohort` superava `VARCHAR(60)` per coorti con nomi compositi.
  - `cancer_type` superava `VARCHAR(20)`.
  - `accession` rischiava di saturare `VARCHAR(10)` per formati estesi.
- **Soluzione**: Riadattamento dello schema DDL MySQL (`schema.sql`):
  - `protein_name` impostato a `TEXT`.
  - `cohort` allargato a `VARCHAR(80)`.
  - `cancer_type` allargato a `VARCHAR(30)`.
  - `accession` allargato a `VARCHAR(15)`.

### 9. Qualità e tipi di dato nativi dei file grezzi
- **Problema**: In IntOGen i campi di conteggio (`MUTATIONS`, `SAMPLES`) erano esportati con decimali (`10.0`), e `IS_DRIVER` conteneva stringhe `"True"`. In DrugCentral la colonna `ACT_UNIT` era vuota al 100%.
- **Soluzione**: Cast dei conteggi al tipo intero (`Int64`), trasformazione del flag in intero booleano `TINYINT(1)`, e rimozione della colonna `ACT_UNIT`.

---

## Stato del progetto e prossimi passi

### Passo 1 — Esplorazione dei dati (`01_inspect.py`)
- **[COMPLETATO]** Diagnosi e ispezione qualitativa dei file raw.

### Passo 2 — Pulizia ed esportazione CSV (`02_clean.py`)
- **[COMPLETATO]** Generazione degli 8 file CSV normalizzati in `data/clean/`, inclusa la tabella `drug_approval`.

### Passo 3 — Schema SQL relazionale (`sql/schema.sql`)
- **[COMPLETATO]** Creato lo script DDL per MySQL con:
  - Creazione del database `intogen_drugcentral` (`utf8mb4`).
  - 8 tabelle relazionali conformi alla forma normale.
  - Chiavi primarie, vincoli di unicità e indici di ricerca (`KEY idx_*`).
  - Vincoli di chiave esterna con gestione dell'integrità referenziale (`ON UPDATE CASCADE`, `ON DELETE CASCADE` / `SET NULL`).

### Passo 4 — Caricamento nel database (`03_load.py`)
- **[COMPLETATO]** Creato lo script di caricamento automatico [`scripts/03_load.py`](../scripts/03_load.py) che:
  - Si connette a MySQL (creando lo schema da `sql/schema.sql` se non presente).
  - Inserisce i dati in batch (5.000 righe) rispettando rigorosamente l'albero delle Foreign Key.
  - Verifica l'integrità referenziale e stampa la tabella dei conteggi effettivi.

### Passo 5 — Viste e Query analitiche SQL (`sql/queries.sql`)
- **[COMPLETATO]** Creato il file [`sql/queries.sql`](../sql/queries.sql) contenente:
  - **Vista integrata** `v_driver_drug_candidates`: collega driver oncologici, coorti, proteine UniProt, target, farmaci e approvazioni.
  - **Query di controllo qualità (QC)**: misura percentuale di copertura e classi proteiche dei bersagli.
  - **7 Query analitiche d'esame**:
    1. Farmaci associati a geni driver di specifici tumori (es. BRCA, LUAD).
    2. Geni driver più "druggable" (con aggregazioni `GROUP BY` e filtro `HAVING`).
    3. Farmaci multi-target attivi su più geni driver dello stesso tumore.
    4. Query "biologicamente prudente" (oncogeni `Act` combinati con farmaci inibitori).
    5. Opportunità di Drug Discovery: oncoproteine ad alta frequenza senza alcun farmaco noto.
    6. Misure quantitative di potenza sperimentale (CTE con filtri `act_value >= 8.0`, ovvero concentrazione sub-nanomolare).
    7. Opportunità di riposizionamento farmacologico (*drug repurposing*) su tumori ad alta mortalità (PAAD, GBM, LAML).

---

## Come eseguire il caricamento e presentare su MySQL

### 1. Caricamento rapido (via Script)
Dal terminale, con l'ambiente virtuale attivo:
```bash
cd /Users/federica/Desktop/Project_intogen_drugcentral
.venv/bin/python scripts/03_load.py --user root --init-schema
```
Lo script ti chiederà la password di `root`, creerà il database, le 8 tabelle e caricherà tutti i dati in pochi secondi.

### 2. Presentazione d'esame (in MySQL Workbench)
1. **Mostrare l'EER Diagram (Schema concettuale/logico)**:
   - Apri MySQL Workbench e connettiti alla tua istanza locale (`root@localhost:3306`).
   - Vai nel menu in alto: **Database ➔ Reverse Engineer...**
   - Seleziona il database `intogen_drugcentral` e clicca *Next*.
   - Verrà generato automaticamente il diagramma con tutte le 8 tabelle e le relative relazioni (1:N e N:M). Mostra al docente come UniProt fa da ponte tra IntOGen e DrugCentral.
2. **Creare la vista ed eseguire le query**:
   - Apri il file `sql/queries.sql` dentro una scheda di Workbench (`File ➔ Open SQL Script...`).
   - Esegui la prima istruzione per creare la vista `v_driver_drug_candidates`.
   - Esegui le singole query analitiche (usando il cursore e il pulsante fulmine ⚡️) commentando i risultati biologici ottenuti.



prova prova prova 
