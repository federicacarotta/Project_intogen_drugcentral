# Progetto IntOGen – DrugCentral

## In poche parole

Questo progetto costruisce un **database** che mette in collegamento due mondi:

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

## Cosa c'è in ogni cartella

```
Project_intogen_drugcentral/
│
├── data/
│   ├── raw/                 ← dati originali, così come scaricati
│   │   ├── intogen/         ← file di IntOGen (geni driver)
│   │   ├── drugcentral/     ← file di DrugCentral (farmaci e bersagli)
│   │   └── uniprot/         ← file di UniProt (anagrafica proteine)
│   │
│   └── clean/               ← dati puliti, pronti per il database
│       ├── protein.csv
│       ├── gene_symbol.csv
│       ├── drug.csv
│       ├── drug_target.csv
│       ├── activity.csv
│       ├── cohort.csv
│       └── intogen_driver.csv
│
├── scripts/
│   ├── 01_inspect.py        ← esplora i dati grezzi (non modifica nulla)
│   └── 02_clean.py          ← pulisce i dati e produce i CSV in data/clean/
│
├── sql/                     ← (da creare) schema e query del database
│
└── docs/
    └── README.md            ← questo file
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
| `ROLE` | Il ruolo del gene: **Act** (acceleratore) o **LoF** (freno rotto) |
| `MUTATIONS` | Quante mutazioni sono state trovate |
| `SAMPLES` | In quanti pazienti sono state trovate |
| `QVALUE_COMBINATION` | Un numero statistico: più è vicino a zero, più siamo sicuri che il gene è davvero driver |
| `METHODS` | Quali algoritmi bioinformatici hanno identificato il gene come driver |

<!-- [APPROFONDIMENTO] Ruolo biologico dei geni driver: differenza tra oncogeni (Act)
     e tumor suppressor (LoF), con esempi concreti (TP53, KRAS, BRAF).
     Spiegare perché questa distinzione conta per la scelta dei farmaci:
     un oncogene iperattivo si può "spegnere" con un inibitore,
     un tumor suppressor rotto è molto più difficile da riparare. -->

**Numeri chiave**:
- 633 geni driver unici
- 260 coorti (dataset di pazienti)
- 86 tipi di tumore diversi
- I geni più frequentemente driver: TP53 (212 coorti), PIK3CA (109), KRAS (84)

---

### 2. DrugCentral — I farmaci e i loro bersagli

**Cos'è DrugCentral**: un database pubblico che raccoglie informazioni su farmaci
(approvati e in sperimentazione) e sulle proteine su cui agiscono.

**File**: `drug.target.interaction.tsv` — 22 364 righe, 20 colonne.

Ogni riga dice: *"Il farmaco X si lega alla proteina Y con una certa forza
e produce un certo effetto"*.

**Colonne principali**:

| Colonna | Cosa significa |
|---------|----------------|
| `DRUG_NAME` | Nome del farmaco (es. imatinib, nivolumab) |
| `STRUCT_ID` | Codice numerico univoco del farmaco |
| `TARGET_NAME` | Nome della proteina bersaglio |
| `ACCESSION` | Codice UniProt della proteina bersaglio |
| `GENE` | Gene che codifica la proteina bersaglio |
| `ACTION_TYPE` | Come il farmaco agisce: inibitore, agonista, antagonista, ecc. |
| `ACT_VALUE` | Quanto è potente il farmaco (un numero più alto = farmaco più forte) |
| `ACT_TYPE` | Che tipo di misura è (IC50, Ki, Kd, ecc.) |
| `MOA` | Se questa interazione è il *meccanismo d'azione* principale del farmaco (1 = sì) |
| `TDL` | Quanto è studiata la proteina bersaglio (Tclin → Tdark, dal più al meno conosciuto) |
| `TARGET_CLASS` | Famiglia della proteina (GPCR, Chinasi, Canale ionico, Enzima, ecc.) |
| `ORGANISM` | Organismo della proteina bersaglio (Homo sapiens, Mus musculus, ecc.) |

<!-- [APPROFONDIMENTO] Spiegare il significato di ACTION_TYPE con esempi concreti:
     - INHIBITOR: blocca la proteina (es. imatinib blocca BCR-ABL)
     - AGONIST: attiva il recettore (es. morfina attiva il recettore mu-oppioide)
     - ANTAGONIST: si lega senza attivare e impedisce al segnale naturale di agire
     - BLOCKER: chiude fisicamente un canale ionico
     Spiegare anche i livelli TDL (Tclin/Tchem/Tbio/Tdark) e perché
     un gene driver Tdark è un'opportunità di ricerca. -->

<!-- [APPROFONDIMENTO] Spiegare le misure di potenza dei farmaci (IC50, Ki, Kd):
     cosa significano concretamente, perché usiamo la scala logaritmica,
     e come si interpreta un valore di 9 vs un valore di 5. -->

**Numeri chiave**:
- 22 364 interazioni totali (tutti gli organismi)
- 16 926 interazioni umane (dopo il filtro a Homo sapiens)
- 2 632 farmaci unici
- Le classi di bersagli più rappresentate: GPCR (6 543), Enzimi (5 653), Chinasi (4 802)

Nella cartella `data/raw/drugcentral/` ci sono anche dei file aggiuntivi
con le liste di farmaci approvati dalle agenzie regolatorie (FDA, EMA, PMDA).
Per ora non sono usati, ma potranno essere integrati in futuro.

---

### 3. UniProt — L'anagrafica delle proteine (il ponte)

**Cos'è UniProt**: il più grande archivio pubblico di informazioni sulle proteine.
Ogni proteina ha un codice univoco chiamato *accession* (es. `P04637`).

**File**: `uniprotkb_...2026_10_26.tsv` — 20 431 righe (solo proteine umane *reviewed*).

UniProt **non contiene nuove informazioni biologiche per il nostro database**:
il suo ruolo è fare da **ponte** tra IntOGen e DrugCentral.

- IntOGen usa i **nomi dei geni** (es. `TP53`)
- DrugCentral usa i **codici accession** delle proteine (es. `P04637`)
- UniProt ha **entrambi**: sa che il gene `TP53` codifica la proteina `P04637`

Senza UniProt non potremmo collegare i due dataset.

**Dettaglio importante**: un singolo gene può avere **più nomi** (sinonimi).
Per esempio il gene `ERBB2` è conosciuto anche come `HER2` e `NEU`.
UniProt li elenca tutti, e il primo è quello ufficiale.

---

## Cosa fa lo script di ispezione (01_inspect.py)

Questo script **non modifica nessun dato**. Si limita a leggere i tre file
e a stampare informazioni utili per capire com'è fatto ogni dataset.

In pratica risponde a queste domande:

1. **Quante righe e colonne ha ogni file?**
2. **Quali colonne hanno molti valori mancanti?** (ci aiuta a capire cosa è obbligatorio
   e cosa è opzionale nello schema del database)
3. **Quali valori possono assumere le colonne categoriche?** (es. quali organismi,
   quali tipi di azione farmacologica, quali ruoli dei geni)
4. **Ci sono problemi nei dati?** (celle con più valori, formati inattesi)
5. **I tre dataset sono compatibili?** (quanti geni/proteine hanno in comune)

### Cosa si è scoperto

- DrugCentral contiene interazioni per **molti organismi** (ratto, topo, batteri, virus...),
  ma a noi servono solo quelle umane
- Alcune celle di DrugCentral contengono **più valori** separati da `|` o `,`
  (es. `P35367|P35368` nel campo ACCESSION) — vanno separati
- La colonna `ACT_UNIT` è **completamente vuota** (100% null) — inutile
- Il campo `ACTION_TYPE` è nullo nel 79% dei casi — non è sempre disponibile
- Il confronto diretto dei nomi dei geni tra IntOGen e DrugCentral trova solo **144 geni in comune**,
  ma il numero reale è più alto perché il confronto per nome è impreciso
  (sinonimi, maiuscole/minuscole, celle multi-valore)
- UniProt copre il **99.9%** delle accession di DrugCentral (solo 2 mancanti su 1 893)

---

## Cosa fa lo script di pulizia (02_clean.py)

Questo script legge i tre file grezzi e produce **7 file CSV puliti**,
uno per ogni tabella del futuro database.

### Passo 1 — UniProt

**Cosa fa**: prende il file UniProt e crea due tabelle.

**Tabella `protein`** (20 433 righe): un elenco di proteine umane, una per riga.
Ogni proteina ha il suo codice accession (che sarà la chiave principale del database),
il suo nome e il nome mnemonico SwissProt.

**Tabella `gene_symbol`** (45 565 righe): collega ogni proteina ai nomi dei geni
che la codificano. Una proteina può avere più nomi di gene (sinonimi),
quindi servono più righe. Il campo `is_primary` indica quale nome è quello ufficiale.

*Perché due tabelle separate?* Perché una proteina può avere 2, 5, anche 57 nomi
di gene diversi. Metterli tutti in un'unica colonna renderebbe impossibile
cercare per nome in modo efficiente.

### Passo 2 — DrugCentral

**Cosa fa**: il passo più complesso. Diverse operazioni in sequenza.

**a) Filtro a Homo sapiens**
- Si tengono solo le righe dove `ORGANISM = "Homo sapiens"`
- Da 22 364 a **16 926 righe**
- *Perché*: i geni driver di IntOGen sono umani, quindi ci servono
  solo le interazioni con proteine umane

**b) Separazione delle celle multi-valore**
- Alcune righe hanno più codici accession o più geni nella stessa cella,
  separati da `|`, `,` o `;`
- Queste righe vengono "esplose": una riga con due accession diventa due righe
- Da 16 926 a **18 749 righe**
- *Perché*: nel database ogni interazione deve avere esattamente un farmaco
  e un bersaglio. Se un farmaco agisce su due proteine diverse,
  sono due interazioni distinte

<!-- [APPROFONDIMENTO] Perché esistono celle multi-valore: complessi proteici
     (es. un recettore formato da due subunità diverse) e isoforme
     (es. più varianti della stessa proteina prodotte dallo stesso gene
     per splicing alternativo). -->

**c) Conversione dei tipi di dato**
- `STRUCT_ID` (identificativo del farmaco): da testo a numero intero
- `ACT_VALUE` (potenza del farmaco): da testo a numero decimale
- `MOA` (meccanismo d'azione): da numero con virgola a un semplice sì/no (1 o 0)

**d) Creazione della tabella `drug`** (2 632 righe)
- Un elenco di farmaci unici, ciascuno con il suo codice e il suo nome
- Si è verificato che ogni codice ha sempre lo stesso nome (0 conflitti)

**e) Gestione delle proteine mancanti in UniProt**
- 2 accession di DrugCentral non esistono in UniProt
  (probabilmente codici vecchi o proteine non ancora revisionate)
- Per non perdere queste interazioni, si creano dei record "provvisori" (stub)
  nella tabella protein, usando le informazioni disponibili in DrugCentral
- *Perché*: se le scartassimo, perderemmo tutti i farmaci collegati a queste proteine

**f) Creazione della tabella `drug_target`** (18 228 righe)
- Contiene le coppie uniche farmaco–proteina bersaglio
- Quando la stessa coppia appare più volte (da fonti diverse) con classificazioni
  diverse dell'`ACTION_TYPE`, si tiene quella più frequente (6 casi di conflitto)
- *Perché*: nel database la relazione farmaco–bersaglio deve apparire una sola volta.
  Le misurazioni multiple vanno in una tabella separata (activity)

**g) Creazione della tabella `activity`** (16 716 righe)
- Contiene le misurazioni quantitative di potenza dei farmaci
  (solo le righe che hanno effettivamente un valore numerico)
- Ogni riga dice: *"Il farmaco X è stato testato contro la proteina Y
  con il metodo Z e ha dato un risultato W"*

### Passo 3 — IntOGen

**Cosa fa**: pulisce i dati di IntOGen e crea il collegamento con le proteine.

**a) Pulizia dei nomi e dei tipi**
- I nomi delle colonne vengono rinominati in minuscolo (convenzione SQL)
- `IS_DRIVER`: da testo `"True"` a numero `1`
- `MUTATIONS` e `SAMPLES`: da numeri con decimali (es. `10.0`) a numeri interi (es. `10`),
  perché sono conteggi e non ha senso che siano decimali

**b) Creazione della tabella `cohort`** (260 righe)
- Ogni coorte è un dataset di pazienti analizzato.
  Ha un nome, un tipo di tumore e un numero totale di campioni
- Si è verificato che ogni coorte ha sempre lo stesso tipo di tumore
  e lo stesso numero di campioni (0 incoerenze)

**c) Collegamento dei geni alle proteine (il passo chiave)**
- IntOGen usa i nomi dei geni (es. `TP53`)
- Il database ha bisogno dei codici accession (es. `P04637`)
- Si usa la tabella `gene_symbol` (costruita da UniProt) per tradurre:
  *per ogni gene di IntOGen → cerca tra i simboli → trova l'accession*
- Risultato: **tutti i 633 geni** hanno trovato un match (0 senza accession)
- 18 geni erano ambigui (lo stesso nome poteva corrispondere a più proteine):
  in questi casi si è scelta la proteina dove quel nome è il nome **ufficiale**

<!-- [APPROFONDIMENTO] Perché i nomi dei geni possono essere ambigui:
     storia della nomenclatura genetica, gene renaming da parte di HGNC,
     e l'importanza di usare identificatori stabili come le accession UniProt. -->

**d) Creazione della tabella `intogen_driver`** (4 478 righe)
- Contiene tutte le associazioni gene driver–coorte, arricchite con l'accession UniProt
- 0 duplicati trovati (ogni coppia gene–coorte è unica)

### Passo 4 — Controlli finali e scrittura

- Si verifica che nessun campo di testo superi la lunghezza massima prevista
  dallo schema del database → **3 campi sforano** (`entry_name`, `protein_name`, `tdl`)
  e andranno corretti nello schema SQL
- Si scrivono i 7 file CSV nella cartella `data/clean/`

### Il numero più importante

> **149 geni driver su 633 (il 23.5%) hanno almeno un farmaco conosciuto
> che colpisce la loro proteina.**

Questo significa che per quasi un quarto dei geni che guidano i tumori
esiste già un farmaco che potenzialmente potrebbe essere usato.
I restanti ~484 geni sono territori ancora inesplorati dal punto di vista farmacologico.

---

## Riepilogo delle 7 tabelle prodotte

| Tabella | Righe | Cosa contiene |
|---------|-------|---------------|
| `protein` | 20 433 | Anagrafica delle proteine: codice, nome, classe, livello di studio |
| `gene_symbol` | 45 565 | Collegamento proteina → nomi del gene (con sinonimi) |
| `drug` | 2 632 | Elenco dei farmaci: codice e nome |
| `drug_target` | 18 228 | Quali farmaci agiscono su quali proteine (e come) |
| `activity` | 16 716 | Misurazioni di potenza dei farmaci sui bersagli |
| `cohort` | 260 | Dataset di pazienti oncologici analizzati da IntOGen |
| `intogen_driver` | 4 478 | Geni driver trovati in ogni coorte, con statistiche sulle mutazioni |

---

## A quali domande potrà rispondere il database

1. **Per un tipo di tumore, quali geni driver hanno già un farmaco?**
2. **Per un gene driver specifico, quali farmaci lo colpiscono e quanto sono potenti?**
3. **Quanti geni driver sono ancora senza farmaci conosciuti?**
   (opportunità per la ricerca)
4. **Quali geni driver sono poco studiati (Tdark)?**
   (bersagli "oscuri" su cui si sa ancora poco)
5. **Per un farmaco, agisce su qualche gene driver tumorale?**
   (possibilità di riposizionamento del farmaco in oncologia)

---

## Prossimi passi

I dati sono puliti e pronti. Ecco cosa resta da fare, nell'ordine:

### Passo 3 — Schema SQL (`schema.sql`)
Scrivere le istruzioni `CREATE TABLE` per creare le 7 tabelle nel database MySQL,
definendo per ogni campo il tipo di dato, la chiave primaria, le chiavi esterne
(i collegamenti tra le tabelle) e gli indici per velocizzare le ricerche.

### Passo 4 — Caricamento (`03_load.py`)
Scrivere uno script Python che legge i 7 CSV puliti e li carica nelle tabelle MySQL.
Al termine si fanno controlli automatici: i conteggi tornano? Le chiavi esterne
sono tutte valide?

### Passo 5 — Query analitiche
Scrivere delle query SQL che rispondono alle domande del progetto
(vedi sezione precedente). Queste query sono il vero "prodotto" del database:
dimostrano che l'integrazione dei dati funziona e produce risultati utili.

### Passo 6 (opzionale) — Arricchimenti
- Aggiungere una tabella `drug_approval` con i farmaci approvati da FDA, EMA, PMDA
  (i file sono già nella cartella raw, servono solo poche righe di codice)
- Normalizzare i codici dei tipi tumorali in una tabella `cancer_type`
  (es. BRCA = "Breast invasive carcinoma")
