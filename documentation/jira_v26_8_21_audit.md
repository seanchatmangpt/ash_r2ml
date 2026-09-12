# AshR2RML v26.8.21 — Adversarial Audit & Jira Ticket Backlog
**Perspective:** Post-AGI Systems Architect / Zach Daniel Ash Framework Law  
**Target Repository:** `ash_r2rml`  
**Standing:** `PARTIAL_ALIVE`  

---

## Part 1: Adversarial Codebase Audit

Reviewing `ash_r2rml` through the strict lens of Ash architectural purity, Spark DSL laws, and fail-closed semantic mapping standards reveals several lingering technical compromises that must be ticketed and resolved before full cutover.

### 1. The Spark DSL Introspection Flaw (Late Evaluation)
- **Critique:** `AshR2RML.Introspection.identities/2` currently inspects Spark DSL entities dynamically during transformer execution to recover primary keys. If called before `Ash.Resource.Info.primary_key/1` finishes, fallback logic estimates keys from attributes (`primary_key?: true`).
- **Ash Invariant Risk:** In Ash, primary keys can be composite or derived via custom data layers. Guessing identity keys from un-compiled Spark DSL entities breaks the principle that `Ash` owns resource semantics.


### 3. Legacy Adapter Dual-Path Fallbacks
- **Critique:** `AshR2RML.Resource.LegacyAdapter.convert/1` maintains compatibility logic for legacy DSL options (`attribute_mappings`, `relationship_mappings`).
- **Risk:** Maintaining dual compilation paths (`PersistMapping` vs `LegacyAdapter`) risks semantic drift where legacy options might produce different `AshR2RML.Mapping.Resource` IR structs than the core Spark transformer.

---

## Part 2: Jira Ticket Backlog (`docs/jira/v26.8.21/`)

Below are the 4 prioritized Jira tickets for sprint execution:

---


- **Type:** Technical Debt / Architecture  
- **Priority:** High  
- **Component:** Core / Mix Dependencies  
- **Description:**  
- **Acceptance Criteria:**  

---

### Ticket 2: `R2RML-102` — Single Canonical DSL Transformer (Deprecate Dual Legacy Adapter Path)

- **Type:** Refactoring / Compiler Safety  
- **Priority:** High  
- **Component:** `AshR2RML.Resource.Info` / `AshR2RML.Resource.LegacyAdapter`  
- **Description:**  
  Consolidate `AshR2RML.Resource.Persist` and `LegacyAdapter` into a single, deterministic Spark DSL transformer (`AshR2RML.Transformers.BuildMapping`). Ensure `Spark.Dsl.Extension.get_persisted(resource, :ash_r2rml_public_mapping)` is the single source of truth for resource mappings.
- **Acceptance Criteria:**  
  1. `AshR2RML.Resource.Info.mapping_result/1` fetches strictly from persisted Spark DSL state.
  2. Unpersisted or malformed resources immediately return typed refusals (`:REFUSED_MISSING_SUBJECT_MAP`).
  3. Eliminate fallback calls to `LegacyAdapter.convert/1`.

---

### Ticket 3: `R2RML-103` — Rigorous Composite & Custom Primary Key Introspection

- **Type:** Bug / Semantic Identity Law  
- **Priority:** Medium  
- **Component:** `AshR2RML.Introspection`  
- **Description:**  
  Ensure resource subject template resolution handles composite primary keys (e.g. `[:tenant_id, :user_id]`) and custom data layer field aliases (`attribute.source`) deterministically without relying on premature Spark DSL entity iteration.
- **Acceptance Criteria:**  
  1. Subject template field extraction maps `attribute.source || attribute.name` for composite primary keys.
  2. Add unit tests for multi-column composite key resource subject templates.

---

### Ticket 4: `R2RML-104` — Full Automated Ontop OBDA Integration Pipeline

- **Type:** Feature / Integration Crown  
- **Priority:** Medium  
- **Component:** `AshR2RML.ObdaCrown`  
- **Description:**  
  Automate Ontop CLI container execution in `test/integration/obda_crown.exs` with a bundled PostgreSQL JDBC driver, verifying real-time SPARQL-to-SQL query rewriting without requiring manual environment variables (`ASH_R2RML_ONTOP_JDBC_DIR`).
- **Acceptance Criteria:**  
  1. `mix test test/integration/obda_crown.exs` runs end-to-end against PostgreSQL and Ontop.
  2. SPARQL client queries match Ash relational queries for 100% of admitted fixture subjects.
