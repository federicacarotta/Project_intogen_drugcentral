-- ============================================================
-- queries.sql
-- Progetto Basi di Dati: IntOGen + DrugCentral su MySQL
--
-- INDICE DEI CONTENUTI:
--   PARTE 1: VISTA INTEGRATA (v_driver_drug_candidates) & QC
--   PARTE 2: LE 8 QUERY D'ESAME OMOGENEIZZATE E ORDINATE
--      1. Il Ponte Relazionale Fondamentale (Caso Studio EGFR) [3 JOIN]
--      2. Geni Driver più Mutati nel Tumore al Seno (BRCA) [1 JOIN]
--      3. Farmaci Inibitori con Meccanismo d'Azione Primario [1 JOIN]
--      4. Farmaci Approvati da FDA Attivi sulle Chinasi [2 JOIN]
--      5. Geni Driver e Anagrafica Proteica nel Glioblastoma (GBM) [2 JOIN]
--      6. Terapie a Bersaglio Molecolare nel Tumore al Polmone (LUAD)
--      7. Polifarmacologia — Farmaci Multi-Target nello Stesso Tumore
--      8. Drug Repurposing su Tumori a Prognosi Infausta (PAAD e GBM)
-- ============================================================

USE intogen_drugcentral;

-- ============================================================
-- PARTE 1: VISTA INTEGRATA E CONTROLLI DI QUALITÀ
-- ============================================================

CREATE OR REPLACE VIEW v_driver_drug_candidates AS
SELECT 
    c.cancer_type,
    c.cohort,
    ig.symbol AS driver_gene,
    ig.role AS driver_role,
    p.accession AS target_uniprot,
    p.entry_name,
    p.protein_name,
    p.target_class,
    p.tdl,
    d.struct_id AS drugcentral_id,
    d.drug_name,
    dt.action_type,
    dt.moa,
    GROUP_CONCAT(DISTINCT da.agency ORDER BY da.agency SEPARATOR ', ') AS approved_by,
    ig.qvalue_combination,
    ig.mutations,
    ig.samples
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
JOIN protein p ON p.accession = ig.accession
JOIN drug_target dt ON dt.accession = p.accession
JOIN drug d ON d.struct_id = dt.struct_id
LEFT JOIN drug_approval da ON da.struct_id = d.struct_id
GROUP BY 
    c.cancer_type, c.cohort, ig.symbol, ig.role, p.accession, 
    p.entry_name, p.protein_name, p.target_class, p.tdl, 
    d.struct_id, d.drug_name, dt.action_type, dt.moa, 
    ig.qvalue_combination, ig.mutations, ig.samples;

-- QC 1. Percentuale di copertura dei geni driver IntOGen in DrugCentral
SELECT 
    COUNT(DISTINCT ig.symbol) AS total_driver_genes,
    COUNT(DISTINCT dt.accession) AS druggable_driver_proteins,
    COUNT(DISTINCT CASE WHEN dt.struct_id IS NOT NULL THEN ig.symbol END) AS matched_driver_genes,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN dt.struct_id IS NOT NULL THEN ig.symbol END) 
          / COUNT(DISTINCT ig.symbol), 1) AS coverage_pct
FROM intogen_driver ig
LEFT JOIN drug_target dt ON dt.accession = ig.accession;

-- QC 2. Distribuzione delle classi proteiche dei bersagli
SELECT 
    COALESCE(p.target_class, 'Non classificata') AS target_class,
    COUNT(DISTINCT p.accession) AS total_proteins,
    COUNT(DISTINCT dt.struct_id) AS total_drugs
FROM protein p
LEFT JOIN drug_target dt ON dt.accession = p.accession
GROUP BY p.target_class
ORDER BY total_proteins DESC;


-- ============================================================
-- PARTE 2: LE 8 QUERY D'ESAME
-- ============================================================

-- ------------------------------------------------------------
-- QUERY 1 (ex BASE 5): Il Ponte Relazionale Fondamentale (Caso Studio EGFR)
-- Tabelle: intogen_driver, protein, drug_target, drug (3 JOIN)
-- Concetto SQL: Tre INNER JOIN lineari: Gene -> Proteina -> Bersaglio -> Farmaco.
-- Spiegazione: È il cuore del progetto. Dato l'oncogene EGFR identificato in IntOGen,
--              attraversa UniProt e trova tutti i farmaci approvati/sperimentali
--              di DrugCentral con il relativo tipo di azione farmacologica.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 2 (ex BASE 1): Geni Driver più Mutati nel Tumore al Seno (BRCA)
-- Tabelle: intogen_driver, cohort (1 JOIN)
-- Concetto SQL: INNER JOIN tra tabella fatti e tabella dimensionale coorte, ordinamento numerico.
-- Spiegazione: Mostra i geni driver con il maggior numero di pazienti mutati
--              negli studi clinici sul carcinoma mammario (es. PIK3CA, TP53, ESR1).
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 3 (ex BASE 2): Farmaci Inibitori con Meccanismo d'Azione Primario
-- Tabelle: drug, drug_target (1 JOIN)
-- Concetto SQL: INNER JOIN con doppio filtro WHERE su flag di primarietà e tipo azione.
-- Spiegazione: Isola le molecole che agiscono come inibitori accertati ('INHIBITOR')
--              sul loro bersaglio terapeutico primario (moa = 1), escludendo lo screening aspecifico.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 4 (ex BASE 3): Farmaci Approvati da FDA Attivi sulle Chinasi
-- Tabelle: drug, drug_approval, drug_target (2 JOIN)
-- Concetto SQL: Due INNER JOIN centrate sull'anagrafica del farmaco (drug).
-- Spiegazione: Seleziona i farmaci autorizzati dall'agenzia americana FDA
--              che colpiscono specificamente la classe delle Chinasi (cruciale in oncologia).
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 5 (ex BASE 4): Geni Driver e Anagrafica Proteica nel Glioblastoma (GBM)
-- Tabelle: intogen_driver, protein, cohort (2 JOIN)
-- Concetto SQL: Due INNER JOIN che collegano la coorte clinica all'anagrafica UniProt.
-- Spiegazione: Per il glioblastoma cerebrale (GBM), traduce i simboli genici nelle corrispondenti
--              proteine umane UniProt evidenziando la famiglia funzionale e il ruolo biologico.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 6 (ex LIVELLO 1 Q1): Terapie a Bersaglio Molecolare nel Tumore al Polmone (LUAD)
-- Tabelle: intogen_driver, cohort, protein, drug_target, drug, drug_approval (5 JOIN)
-- Concetto SQL: Catena completa di 5 JOIN con aggregazione stringa GROUP_CONCAT per le agenzie.
-- Spiegazione: Nel carcinoma polmonare (LUAD), estrae i farmaci approvati con meccanismo d'azione
--              primario validato (moa = 1) attivi contro i suoi oncogeni (BRAF, EGFR).
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 7 (ex LIVELLO 2 Q5): Polifarmacologia — Farmaci Multi-Target nello Stesso Tumore
-- Tabelle: intogen_driver, cohort, drug_target, drug (3 JOIN)
-- Concetto SQL: Raggruppamento per tumore e farmaco, HAVING su conteggio distinto, GROUP_CONCAT.
-- Spiegazione: Identifica farmaci capaci di inibire contemporaneamente più geni driver
--              dello stesso tumore ("un cocktail in una sola molecola"), riducendo il rischio di resistenze.
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- QUERY 8 (ex LIVELLO 3 Q8): Drug Repurposing su Tumori a Prognosi Infausta (PAAD e GBM)
-- Tabelle: intogen_driver, cohort, drug_target, drug, drug_approval (4 JOIN)
-- Concetto SQL: Filtro categorico su istotipi (IN), unione tra dati clinici e approvazioni, GROUP_CONCAT.
-- Spiegazione: Per patologie aggressive a prognosi infausta (pancreas PAAD e glioblastoma GBM),
--              individua farmaci già approvati per altre indicazioni che possono essere
--              rapidamente riposizionati sui bersagli mutati di questi pazienti.
-- ------------------------------------------------------------
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
