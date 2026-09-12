# AshR2RML Documentation Hub (Diátaxis Framework)

AshR2RML maps ordinary Ash resources to a normalized semantic mapping IR (`AshR2RML.Mapping`) and standards-valid W3C R2RML Turtle while leaving relational persistence to the active Ash data layer (such as `AshPostgres`).

The documentation is organized using the **[Diátaxis documentation framework](https://diataxis.fr/)** into four distinct quadrants:

```text
               LEARNING-ORIENTED          MOSTLY PRACTICAL
                       │                         │
  TUTORIALS ───────────┼─────────── HOW-TO GUIDES
                       │
 ──────────────────────┼─────────────────────────
                       │
  REFERENCE ───────────┼─────────── EXPLANATION (TOPICS)
                       │
                MOSTLY THEORETICAL       UNDERSTANDING-ORIENTED
```

---

## 🎓 1. Tutorials (Learning-Oriented)

Hands-on, step-by-step lessons for newcomers to learn AshR2RML from scratch.

- [Getting Started with AshR2RML](tutorials/getting_started.md) — Build your first mapped resource, compile to IR, render Turtle, and validate RDF output.
- [Canonical Runnable Livebook](../ash_r2rml.livemd) — Interactive end-to-end mental model and execution sandbox.

---

## 🛠️ 2. How-To Guides (Task-Oriented)

Recipes and practical guides for solving specific real-world tasks.

- [Ash-First Mapping Guide](how_to/ash_first.livemd) — Annotate an existing Ash/AshPostgres application with RDF metadata.
- [Ontology-First Generation](how_to/ontology_first.livemd) — Generate Ash resources from RDF/OWL profiles and SHACL shapes via `ggen`.
- [Managing Relational Schema & R2RML](how_to/managing_schema.livemd) — Keep PostgreSQL DDL migrations and semantic projections synchronized.
- [Integrating with OBDA Query Engines](how_to/obda_integration.md) — Execute virtual SPARQL queries against AshPostgres via Ontop/GraphDB.

---

## 📋 3. Reference (Information-Oriented)

Strict, technical specifications, API contracts, DSL references, and refusal catalogs.

- [AshR2RML DSL Reference](reference/dsl_reference.md) — Complete specification for `r2rml`, `subject`, `rdf`, and `sparql` Spark DSL extensions.
- [Normalized Mapping IR Reference](reference/mapping_ir.md) — Structural reference for `AshR2RML.Mapping.*` IR structs.
- [Typed Refusals Catalog](reference/typed_refusals.md) — Exhaustive list of compile-time and runtime refusal exceptions (`REFUSED_*`).
- [Feature Support Matrix](reference/support_matrix.md) — Compatibility matrix for W3C R2RML features and Ash data layers.
- [Usage Rules Index](../usage-rules.md) — Specifications for [semantic IR](../usage-rules/semantic-ir.md), [R2RML](../usage-rules/r2rml.md), [identities](../usage-rules/identities.md), [relationships](../usage-rules/relationships.md), [datatypes](../usage-rules/datatypes.md), and [ggen](../usage-rules/ggen.md).

---

## 💡 4. Explanation / Topics (Understanding-Oriented)

Conceptual essays, system architecture, theoretical rationale, and product invariants.

- [One-Subject Architecture & Compiler Layers](topics/architecture.md) — Compiler architecture and database boundaries.
- [Core Semantic Correspondence](topics/semantic_correspondence.md) — Principles of mapping Ash resources to R2RML constructs and SHACL closure.
- [Ash vs W3C R2RML Side-by-Side](topics/r2rml-side-by-side.md) — Comparative overview of Ash DSL and R2RML Turtle structures.
- [Closed-World Elixir vs Open-World RDF](topics/rdf-elixir-semantic-execution.md) — Semantic execution models in application code vs graph query engines.
- [Why AshR2RML](topics/why-ashr2rml.md) — Semantic/graph query capability as a mapping decision, not a database decision, grounded in real `bench/RESULTS.md` numbers.

---

## Product Boundary Invariant

AshR2RML is **not** an `Ash.DataLayer`, graph database, triplestore, or SPARQL engine. Its job is deterministic semantic compilation:

```text
Ash.Resource + RDF metadata
          ↓
   AshR2RML.Mapping
      ╱       ╲
relational    R2RML
   state        │
 (AshPostgres) OBDA Engine
      ╲       ╱
     one subject
```
