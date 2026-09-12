<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# AGENTS.md — AshR2RML ontology-first side-by-side compiler

This subtree is governed by the root `AGENTS.md` plus the following migration rules.

## Purpose

`AshR2RML` is a W3C R2RML/SHACL semantic compiler for Ash. It is not a replacement data layer. Existing `AshPostgres.DataLayer`, in-memory ETS layers, and any other storage implementation retain persistence and transaction authority.

The mature source of truth is **not** hand-written Ash and is **not** the `r2rml do ... end` block. The canonical object is an admitted closed operational ontology/application profile represented as `AshR2RML.SemanticIR`.

## Foundational order

Preserve → Fence → Calculus → Exclusions → Falsifier → Extension → Operationalization.

The compiler correspondence is:

```text
public ontology + application profile + SHACL
                    |
                admission
                    |
             SemanticIR (O*)
          /         |          \
       Ash      PostgreSQL     R2RML
                    |
                  SHACL
```

Ash resources, SQL schema, R2RML, and generated SHACL are projections of the same admitted object. Never make one generated projection the source from which another is semantically reconstructed when the IR is available.

## DfCM migration law

Preserve both lawful worlds until behavioral equivalence is observed:

2. Keep the existing `r2rml` Spark DSL as a compatibility/projection surface while ontology-first compilation is proven.
3. Admit ontology/application-profile/SHACL information into one canonical semantic IR.
4. Preserve all lawful relational storage candidates when constraints do not force a unique selection.
5. Refuse executable projection when an irreversible storage choice remains unadmitted.
6. Manufacture Ash, PostgreSQL DDL, R2RML, and SHACL from the same IR.
7. Treat successful projection as `PARTIAL_ALIVE`, not runtime or cutover readiness.
9. Cutover is a separate authorized actuation and requires its own receipt.

## SHACL boundary

Do not compile arbitrary OWL directly into PostgreSQL.

OWL defines the semantic universe. The application profile selects the operational interpretation. SHACL closes the structural facts required for deterministic runtime/schema projection: datatype, class, cardinality, identity, and other bounded constraints.

An open-world object property with insufficient cardinality/storage evidence remains a DfCM candidate set. It does not silently become `belongs_to`.

## Authority boundary

The compiler is SELECT/CONSTRUCT only. It may manufacture source, DDL, mappings, manifests, and receipts. It must not:

- apply migrations;
- write application rows;
- write graph nodes;
- start or configure production OBDA endpoints;
- grant its own cutover authority;
- treat model/planner output as execution authority.

`AshR2RML.Ggen.compile_bundle/1` returns a deterministic path/content graph for ggen. ggen owns rendering/filesystem actuation and its own receipts.

## Typed refusals

Prefer typed fail-closed refusals, including:

- `REFUSED_UNMAPPED_RESOURCE_CLASS`
- `REFUSED_ATTRIBUTE_WITHOUT_PREDICATE`
- `REFUSED_INVALID_SUBJECT_TEMPLATE`
- `REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY`
- `REFUSED_RELATIONSHIP_WITHOUT_TARGET_MAP`
- `REFUSED_CARDINALITY_STORAGE_MISMATCH`
- `REFUSED_DATATYPE_CAST_NOT_LOSSLESS`
- `REFUSED_UNPROVEN_EQUIVALENCE`
- `REFUSED_R2RML_JOIN_KEY_NOT_UNIQUE`

Do not convert unsupported or unproven semantics into a convenient default.

## Standards boundary

Use W3C terms precisely:

- R2RML namespace: `http://www.w3.org/ns/r2rml#`
- SHACL namespace: `http://www.w3.org/ns/shacl#`
- R2RML logical tables are exactly one of `rr:tableName` or `rr:sqlQuery`.
- To-one relational relationships become referencing object maps only after join identity is admitted.
- Many-to-many mappings require an admitted join-table representation or a reified association resource.
- Subject templates must cover the admitted semantic identity.

## Side-by-side falsifier

The virtual Postgres graph is not equivalent to the control graph if any admitted comparison corpus query returns a different normalized semantic result multiset.

Use `AshR2RML.Parity.compare/5` only on results that were actually executed by the relevant systems. A manufactured or mocked result set is not a parity witness.

## Verification ladder

Run, in order:

1. `mix compile --force --warnings-as-errors`
2. `mix test test/ash_r2rml_test.exs test/ontology_first_compiler_test.exs`
3. `mix test`
4. full CI matrix from `.github/workflows/ci.yaml`
5. PostgreSQL + real OBDA paired SQL/SPARQL corpus
7. explicit cutover-authority receipt

Only observed execution can promote the relevant parity field to `VERIFIED`. Only both parity receipts plus explicit authority can make `cutover_ready?/1` true.
