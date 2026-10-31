-- ============================================================
-- schema.sql
-- Database IntOGen-DrugCentral
-- Crea le 7 tabelle e i vincoli di integrità referenziale.
--
-- Uso:
--   mysql -u <user> -p < sql/schema.sql
-- ============================================================

DROP DATABASE IF EXISTS intogen_drugcentral;
CREATE DATABASE intogen_drugcentral
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
USE intogen_drugcentral;

-- ============================================================
-- 1. PROTEIN
-- Anagrafica proteica. Fonte: UniProt (reviewed, Homo sapiens)
-- + stub per le poche accession DrugCentral assenti in UniProt.
-- ============================================================
CREATE TABLE protein (
    accession     VARCHAR(15)   NOT NULL,
    entry_name    VARCHAR(30),
    protein_name  TEXT,
    target_class  VARCHAR(50),
    tdl           VARCHAR(10)   COMMENT 'Target Development Level: Tclin, Tchem, Tbio, Tdark',
    PRIMARY KEY (accession)
) ENGINE=InnoDB;

-- ============================================================
-- 2. GENE_SYMBOL
-- Mapping proteina → simboli genici (1:N).
-- is_primary = 1 indica il nome ufficiale HGNC.
-- ============================================================
CREATE TABLE gene_symbol (
    id            INT           NOT NULL AUTO_INCREMENT,
    accession     VARCHAR(15)   NOT NULL,
    symbol        VARCHAR(50)   NOT NULL,
    is_primary    TINYINT(1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE KEY uq_acc_sym (accession, symbol),
    KEY idx_symbol (symbol),
    CONSTRAINT fk_gs_protein
        FOREIGN KEY (accession) REFERENCES protein(accession)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- 3. DRUG
-- Anagrafica farmaci. struct_id è l'ID DrugCentral.
-- ============================================================
CREATE TABLE drug (
    struct_id     INT           NOT NULL,
    drug_name     VARCHAR(255)  NOT NULL,
    PRIMARY KEY (struct_id)
) ENGINE=InnoDB;

-- ============================================================
-- 4. DRUG_APPROVAL
-- Stato di approvazione per agenzia regolatoria.
-- agency: 'FDA', 'EMA', 'PMDA'.
-- ============================================================
CREATE TABLE drug_approval (
    struct_id     INT           NOT NULL,
    agency        VARCHAR(10)   NOT NULL COMMENT 'FDA | EMA | PMDA',
    PRIMARY KEY (struct_id, agency),
    CONSTRAINT fk_da_drug
        FOREIGN KEY (struct_id) REFERENCES drug(struct_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- 5. DRUG_TARGET
-- Relazione N:M farmaco ↔ proteina bersaglio.
-- target_class specifica la famiglia biologica del bersaglio.
-- moa = 1 se è il meccanismo d'azione principale.
-- ============================================================
CREATE TABLE drug_target (
    id            INT           NOT NULL AUTO_INCREMENT,
    struct_id     INT           NOT NULL,
    accession     VARCHAR(15)   NOT NULL,
    target_class  VARCHAR(50)   COMMENT 'Famiglia biologica del bersaglio (es. Kinase, GPCR)',
    moa           TINYINT(1)    NOT NULL DEFAULT 0,
    action_type   VARCHAR(50),
    moa_source    VARCHAR(50),
    PRIMARY KEY (id),
    UNIQUE KEY uq_drug_target (struct_id, accession),
    KEY idx_dt_accession (accession),
    KEY idx_dt_class (target_class),
    CONSTRAINT fk_dt_drug
        FOREIGN KEY (struct_id) REFERENCES drug(struct_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_dt_protein
        FOREIGN KEY (accession) REFERENCES protein(accession)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- ============================================================
-- 6. COHORT
-- Coorti tumorali analizzate da IntOGen.
-- ============================================================
CREATE TABLE cohort (
    cohort        VARCHAR(80)   NOT NULL,
    cancer_type   VARCHAR(30),
    total_samples INT,
    PRIMARY KEY (cohort)
) ENGINE=InnoDB;

-- ============================================================
-- 7. INTOGEN_DRIVER
-- Geni driver identificati per coorte. Il campo accession
-- collega il gene alla proteina (ponte UniProt).
-- ============================================================
CREATE TABLE intogen_driver (
    id                  INT           NOT NULL AUTO_INCREMENT,
    symbol              VARCHAR(50)   NOT NULL,
    cohort              VARCHAR(80)   NOT NULL,
    accession           VARCHAR(15),
    transcript          VARCHAR(20),
    methods             VARCHAR(255),
    mutations           INT,
    samples             INT,
    pct_samples_cohort  DECIMAL(12,10),
    qvalue_combination  DOUBLE,
    role                VARCHAR(10)   COMMENT 'Act | LoF | ambiguous',
    domains             TEXT,
    clusters_2d         TEXT,
    clusters_3d         TEXT,
    excess_mis          DECIMAL(10,6),
    excess_non          DECIMAL(10,6),
    excess_spl          DECIMAL(10,6),
    is_driver           TINYINT(1)    NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    UNIQUE KEY uq_sym_cohort (symbol, cohort),
    KEY idx_ig_accession (accession),
    KEY idx_ig_cohort    (cohort),
    CONSTRAINT fk_ig_cohort
        FOREIGN KEY (cohort) REFERENCES cohort(cohort)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_ig_protein
        FOREIGN KEY (accession) REFERENCES protein(accession)
        ON UPDATE CASCADE ON DELETE SET NULL
) ENGINE=InnoDB;
