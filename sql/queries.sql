-- ============================================================
-- queries.sql
-- Progetto Basi di Dati: IntOGen + DrugCentral su MySQL
--
-- Include:
--   1. VISTA INTEGRATA (v_driver_drug_candidates)
--   2. CONTROLLI DI QUALITÀ E VERIFICA MAPPING
--   3. 8 QUERY ANALITICHE PER LA PRESENTAZIONE (JOIN, GROUP BY,
--      HAVING, CTE/SUBQUERIES, FILTRI BIOLOGICI, ANALISI COORTI)
-- ============================================================

USE intogen_drugcentral;

-- ============================================================
-- SEZIONE 1: VISTA INTEGRATA
-- Unisce geni driver, coorti, proteine UniProt, bersagli e farmaci
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


-- ============================================================
-- SEZIONE 2: CONTROLLI DI QUALITÀ DEL MAPPING (Quality Control)
-- ============================================================

-- QC 1. Percentuale di copertura dei geni driver IntOGen in DrugCentral
SELECT 
    COUNT(DISTINCT ig.symbol) AS total_driver_genes,
    COUNT(DISTINCT dt.accession) AS druggable_driver_proteins,
    COUNT(DISTINCT CASE WHEN dt.struct_id IS NOT NULL THEN ig.symbol END) AS matched_driver_genes,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN dt.struct_id IS NOT NULL THEN ig.symbol END) 
          / COUNT(DISTINCT ig.symbol), 1) AS coverage_pct
FROM intogen_driver ig
LEFT JOIN drug_target dt ON dt.accession = ig.accession;

-- QC 2. Distribuzione delle classi proteiche dei target (es. Chinasi, GPCR, Enzimi)
SELECT 
    COALESCE(p.target_class, 'Non classificata') AS target_class,
    COUNT(DISTINCT p.accession) AS total_proteins,
    COUNT(DISTINCT dt.struct_id) AS total_drugs
FROM protein p
LEFT JOIN drug_target dt ON dt.accession = p.accession
GROUP BY p.target_class
ORDER BY total_proteins DESC;


-- ============================================================
-- SEZIONE 3: QUERY ANALITICHE PER LA PRESENTAZIONE AL DOCENTE
-- ============================================================

-- ------------------------------------------------------------
-- QUERY 1: Farmaci associati ai geni driver di uno specifico tumore
-- Domanda biologica: Quali molecole colpiscono i driver del tumore al seno (BRCA)?
-- Mostra: JOIN, filtri specifici, ordinamento.
-- ------------------------------------------------------------
SELECT DISTINCT 
    driver_gene,
    driver_role,
    drug_name,
    action_type,
    moa,
    COALESCE(approved_by, 'In sperimentazione') AS approval_status
FROM v_driver_drug_candidates
WHERE cancer_type = 'BRCA'
ORDER BY driver_gene, drug_name;


-- ------------------------------------------------------------
-- QUERY 2: Geni driver più "druggable" (con maggior numero di farmaci associati)
-- Domanda biologica: Quali oncoproteine presentano il maggior arsenale terapeutico?
-- Mostra: GROUP BY, funzione di aggregazione COUNT(DISTINCT), clausola HAVING.
-- ------------------------------------------------------------
SELECT 
    driver_gene,
    target_uniprot,
    target_class,
    tdl,
    COUNT(DISTINCT drugcentral_id) AS n_distinct_drugs,
    COUNT(DISTINCT CASE WHEN approved_by IS NOT NULL THEN drugcentral_id END) AS n_approved_drugs
FROM v_driver_drug_candidates
GROUP BY driver_gene, target_uniprot, target_class, tdl
HAVING COUNT(DISTINCT drugcentral_id) >= 10
ORDER BY n_distinct_drugs DESC;


-- ------------------------------------------------------------
-- QUERY 3: Farmaci ad ampio spettro (multi-target) nello stesso tumore
-- Domanda biologica: Esistono farmaci che colpiscono contemporaneamente più geni driver
--                    dello stesso tumore (possibile sinergia o politerapia single-agent)?
-- Mostra: GROUP BY composto, HAVING, conteggio condizionale.
-- ------------------------------------------------------------
SELECT 
    cancer_type,
    drug_name,
    approved_by,
    COUNT(DISTINCT driver_gene) AS n_driver_targets_hit,
    GROUP_CONCAT(DISTINCT driver_gene ORDER BY driver_gene SEPARATOR ', ') AS targeted_genes
FROM v_driver_drug_candidates
GROUP BY cancer_type, drugcentral_id, drug_name, approved_by
HAVING COUNT(DISTINCT driver_gene) >= 3
ORDER BY n_driver_targets_hit DESC, cancer_type;


-- ------------------------------------------------------------
-- QUERY 4: Query "Biologicamente Prudente": Ruolo del driver + Meccanismo Farmacologico
-- Domanda biologica: Se il gene è un oncogene (Act), il farmaco agisce come inibitore?
--                    (Filtro meccanicistico per isolare i candidati coerenti)
-- Mostra: Pattern matching LIKE, filtri semantici combinati, CASE WHEN.
-- ------------------------------------------------------------
SELECT DISTINCT 
    cancer_type,
    driver_gene,
    driver_role,
    drug_name,
    action_type,
    approved_by
FROM v_driver_drug_candidates
WHERE driver_role = 'Act'
  AND (
      UPPER(action_type) LIKE '%INHIBITOR%' 
      OR UPPER(action_type) LIKE '%ANTAGONIST%' 
      OR UPPER(action_type) LIKE '%BLOCKER%'
  )
ORDER BY cancer_type, driver_gene, drug_name;


-- ------------------------------------------------------------
-- QUERY 5: Opportunità di Drug Discovery (Geni driver "orfani" ad alta frequenza)
-- Domanda biologica: Quali sono i geni driver trovati in più coorti/pazienti
--                    per cui DrugCentral non ha ALCUN farmaco registrato?
-- Mostra: LEFT JOIN tra tabelle base, condizione IS NULL, aggregazione su coorti.
-- ------------------------------------------------------------
SELECT 
    ig.symbol AS undrugged_driver_gene,
    p.accession AS uniprot_acc,
    p.target_class,
    COALESCE(p.tdl, 'Tdark') AS tdl,
    COUNT(DISTINCT ig.cohort) AS n_cohorts_detected,
    SUM(ig.samples) AS total_mutated_samples
FROM intogen_driver ig
JOIN protein p ON p.accession = ig.accession
LEFT JOIN drug_target dt ON dt.accession = p.accession
WHERE dt.struct_id IS NULL
GROUP BY ig.symbol, p.accession, p.target_class, p.tdl
ORDER BY n_cohorts_detected DESC, total_mutated_samples DESC
LIMIT 15;


-- ------------------------------------------------------------
-- QUERY 6: Farmaci ad altissima affinità sperimentale (Misure quantitative di Activity)
-- Domanda biologica: Quali interazioni farmaco-oncoproteina presentano una potenza sub-nanomolare
--                    (act_value >= 8.0, corrispondente a IC50/Ki <= 10 nM)?
-- Mostra: JOIN su tabella numerica `activity`, CTE (Common Table Expression), filtri numerici.
-- ------------------------------------------------------------
WITH HighAffinityInteractions AS (
    SELECT 
        d.drug_name,
        p.entry_name,
        ig.symbol AS driver_gene,
        a.act_type,
        a.act_value,
        a.act_source
    FROM activity a
    JOIN drug d ON d.struct_id = a.struct_id
    JOIN protein p ON p.accession = a.accession
    JOIN intogen_driver ig ON ig.accession = p.accession
    WHERE a.act_value >= 8.0
      AND a.act_type IN ('IC50', 'Ki', 'Kd')
)
SELECT 
    driver_gene,
    drug_name,
    act_type,
    MAX(act_value) AS max_potency_pVal,
    ROUND(POW(10, -(MAX(act_value) - 9)), 2) AS approx_concentration_nM
FROM HighAffinityInteractions
GROUP BY driver_gene, drug_name, act_type
ORDER BY max_potency_pVal DESC
LIMIT 20;


-- ------------------------------------------------------------
-- QUERY 7: Riposizionamento Farmacologico (Drug Repurposing)
-- Domanda biologica: Quali farmaci già approvati (FDA / EMA) per altre indicazioni
--                    colpiscono oncoproteine di tumori rari o ad alta mortalità (es. PAAD, GBM)?
-- Mostra: Sottoquery correlata, vincoli di approvazione, GROUP_CONCAT.
-- ------------------------------------------------------------
SELECT 
    v.drug_name,
    v.approved_by,
    v.driver_gene,
    v.action_type,
    v.cancer_type,
    v.samples AS cohort_mutated_samples
FROM v_driver_drug_candidates v
WHERE v.cancer_type IN ('PAAD', 'GBM', 'LAML') -- Pancreas, Glioblastoma, Leucemia mieloide
  AND v.approved_by IS NOT NULL
  AND v.moa = 1
ORDER BY v.cancer_type, v.drug_name;


-- ------------------------------------------------------------
-- QUERY 8: Analisi epidemiologica delle coorti (Giustificazione suddivisione COHORT / INTOGEN_DRIVER)
-- Domanda biologica: Quante coorti e quanti pazienti totali sono stati sequenziati per ciascun tipo tumorale,
--                    e quanti geni driver unici sono stati identificati?
-- Perché giustifica la suddivisione:
--   Se COHORT e INTOGEN_DRIVER fossero un'unica tabella non normalizzata, SUM(total_samples) moltiplicherebbe
--   il numero di pazienti per ogni gene driver scoperto in quella coorte (sovrastima da 20x a 100x!).
--   Separando le tabelle, la dimensione campionaria è un attributo puro della coorte (2NF/3NF),
--   garantendo statistiche corrette, zero ridondanza e facilità di JOIN con i driver.
-- Mostra: LEFT JOIN tra tabella di dimensione (cohort) e tabella dei fatti (intogen_driver), aggregazioni accurate.
-- ------------------------------------------------------------
SELECT 
    c.cancer_type,
    COUNT(DISTINCT c.cohort) AS n_cohorts,
    SUM(c.total_samples) AS total_patients_sequenced,
    COUNT(DISTINCT ig.symbol) AS total_unique_driver_genes,
    ROUND(SUM(c.total_samples) / COUNT(DISTINCT c.cohort), 0) AS avg_patients_per_cohort
FROM cohort c
LEFT JOIN intogen_driver ig ON ig.cohort = c.cohort
GROUP BY c.cancer_type
ORDER BY total_patients_sequenced DESC
LIMIT 20;
