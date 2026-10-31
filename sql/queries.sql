-- ============================================================
-- queries.sql
-- Progetto Basi di Dati: IntOGen + DrugCentral su MySQL
--
-- INDICE DEI CONTENUTI:
--   PARTE 1: VISTA INTEGRATA (v_driver_drug_candidates) & QC
--   PARTE 2: 5 QUERY LINEARI BASE (MAX 1-3 JOIN, SEMPLICI E DIRETTE)
--   PARTE 3: QUERY ANALITICHE STRUTTURATE (I 3 LIVELLI D'ESAME)
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


-- ============================================================
-- PARTE 2: 5 QUERY LINEARI BASE (MAX 1-3 JOIN, NESSUNA COMPLESSITÀ)
-- Ideali da presentare all'inizio dell'orale per spiegare le tabelle
-- ============================================================

-- ------------------------------------------------------------
-- BASE 1 (1 JOIN): I geni driver più mutati nel tumore al seno (BRCA)
-- Tabelle: intogen_driver, cohort
-- Concetto SQL: INNER JOIN tra tabella fatti e coorti, filtro su stringa, ordinamento numerico.
-- Spiegazione: Mostra quali geni presentano il maggior numero di pazienti mutati
--              negli studi clinici sul carcinoma mammario (es. PIK3CA, TP53).
-- ------------------------------------------------------------
SELECT 
    ig.symbol AS gene,
    ig.role AS biological_role,
    ig.samples AS mutated_patients,
    c.cohort
FROM intogen_driver ig
JOIN cohort c ON c.cohort = ig.cohort
WHERE c.cancer_type = 'BRCA'
ORDER BY ig.samples DESC
LIMIT 10;


-- ------------------------------------------------------------
-- BASE 2 (1 JOIN): Farmaci inibitori con meccanismo d'azione primario
-- Tabelle: drug, drug_target
-- Concetto SQL: INNER JOIN tra farmaco e bersaglio, doppio filtro WHERE su flag e tipo azione.
-- Spiegazione: Isola le molecole che hanno come target primario validato (moa = 1)
--              un'azione inibitoria ('INHIBITOR'), scartando legami aspecifici.
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
-- BASE 3 (2 JOIN): Farmaci approvati FDA attivi sulla famiglia delle chinasi
-- Tabelle: drug, drug_approval, drug_target
-- Concetto SQL: Due INNER JOIN a stella con centro sull'anagrafica del farmaco (drug).
-- Spiegazione: Mostra i farmaci certificati dall'ente regolatore americano (FDA)
--              che colpiscono specificamente la classe proteica delle Chinasi.
-- ------------------------------------------------------------
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
LIMIT 10;


-- ------------------------------------------------------------
-- BASE 4 (2 JOIN): Geni driver e anagrafica proteica nel glioblastoma (GBM)
-- Tabelle: intogen_driver, protein, cohort
-- Concetto SQL: Due INNER JOIN che collegano il tumore alla proteina anagrafica via accession.
-- Spiegazione: Per un tumore cerebrale ad alta mortalità (GBM), elenca i geni driver
--              con il nome completo della proteina UniProt e la classe funzionale.
-- ------------------------------------------------------------
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
LIMIT 10;


-- ------------------------------------------------------------
-- BASE 5 (3 JOIN): Il ponte relazionale completo per un oncogene chiave (EGFR)
-- Tabelle: intogen_driver, protein, drug_target, drug
-- Concetto SQL: Tre INNER JOIN lineari: Gene -> Proteina -> Target -> Farmaco.
-- Spiegazione: Rappresenta il percorso fondante del progetto: dato il gene EGFR
--              identificato in IntOGen, naviga attraverso UniProt ed elenca
--              tutti i farmaci censiti in DrugCentral con la loro azione.
-- ------------------------------------------------------------
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
LIMIT 10;


-- ============================================================
-- PARTE 3: LE 9 QUERY ANALITICHE STRUTTURATE (I 3 LIVELLI D'ESAME)
-- ============================================================

-- ============================================================
-- LIVELLO 1: AGGREGAZIONI DI BASE E VALIDAZIONE
-- ============================================================

-- QUERY 1: Terapie a Bersaglio Molecolare nel Tumore al Polmone (LUAD)
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
LIMIT 15;


-- QUERY 2: Match Meccanicistico Oncogene ↔ Farmaco Inibitore
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
LIMIT 15;


-- QUERY 3: Validazione Epidemiologica delle Coorti (Dimostrazione 3NF)
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


-- ============================================================
-- LIVELLO 2: AGGREGAZIONI CON HAVING E ANALISI DI RETE
-- ============================================================

-- QUERY 4: Druggability Ranking dei Geni Driver Oncologici
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


-- QUERY 5: Polifarmacologia — Farmaci Multi-Target nello Stesso Tumore
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
LIMIT 12;


-- QUERY 6: Panorama delle Classi Funzionali dei Bersagli (Target Landscape)
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
LIMIT 10;


-- ============================================================
-- LIVELLO 3: QUERY DECISIONALI, ANTI-JOIN E FORMULE MATEMATICHE
-- ============================================================

-- QUERY 7: Target Discovery — Geni Driver "Orfani" ad Alta Ricorrenza (Anti-Join)
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


-- QUERY 8: Drug Repurposing su Tumori a Prognosi Infausta (Pancreas PAAD e Glioblastoma GBM)
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
LIMIT 12;


-- QUERY 9: Potenza Farmacologica Sub-Nanomolare e Conversione Logaritmica (CTE + Math)
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
