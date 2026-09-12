<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Side-by-side R2RML migration architecture

## Status


## System invariant

PostgreSQL does not need to become a graph database. A relational Ash resource may remain transactionally authoritative in PostgreSQL while exposing a virtual RDF graph through W3C R2RML mappings and a SPARQL-to-SQL OBDA engine.

The semantic and relational views must describe one admitted subject:

```text
Public ontologies / XAAS application profile / SHACL
                         |
                    Ash resource
                   /            \
       storage data layer      AshR2RML
       (control/authority)   (semantic compiler)
              |                   |
                                  |
                         R2RML + SHACL artifacts
                                  |
                         future OBDA/SPARQL engine
```

The first PR does **not** authorize the lower-right path to mutate data and does **not** remove the control path.

## Why this is not search-and-replace


DfCM therefore keeps both topologies:

- **Candidate topology:** `AshR2RML` Spark extension, canonical mapping IR, R2RML renderer, SHACL renderer, and validation receipt.


## R2RML projection

The candidate path compiles Ash metadata into these R2RML concepts:

| Ash concept | R2RML concept |
| --- | --- |
| resource | `rr:TriplesMap` |
| table/view | `rr:logicalTable` + `rr:tableName` |
| SQL projection | `rr:logicalTable` + `rr:sqlQuery` |
| resource class | `rr:subjectMap` + `rr:class` |
| deterministic identity | `rr:template` |
| attribute | `rr:predicateObjectMap` + `rr:column` |
| typed attribute | `rr:objectMap` + `rr:datatype` |
| Ash relationship | referencing object map + `rr:parentTriplesMap` |
| source/destination attributes | `rr:joinCondition` child/parent columns |

Relationship destinations are dependency-closed. Rendering fails rather than silently dropping a relationship whose destination resource has not been semantically mapped.

## Admission rules

The Spark verifier rejects a mapping unless:

1. exactly one of `table_name` and `sql_query` is present;
2. class, graph, predicate, and datatype identifiers are absolute IRIs;
3. mapped attributes exist on the Ash resource;
4. mapped relationships exist and expose source/destination attributes;
5. an attribute is not mapped twice through the typed and untyped surfaces; and
6. the subject template includes every primary-key column placeholder.

These constraints make identity and joins explicit before Turtle generation.

## SHACL projection

SHACL is rendered from the same canonical mapping IR, not maintained independently. Required Ash attributes become `sh:minCount 1`; explicit R2RML datatypes become `sh:datatype`; mapped relationships become IRI-valued properties constrained to the destination RDF class.

The purpose is to preserve correspondence:

```text
Ash resource -> canonical mapping IR -> R2RML
                             |
                             +-------> SHACL
```

No hand-synchronized second schema is introduced.

## Validation receipt

`AshR2RML.validate/1` executes deterministic R2RML and SHACL rendering and records hashes. Successful rendering is intentionally reported as:

- status: `PARTIAL_ALIVE`
- standing: `semantic_projection_only`
- query parity: `UNKNOWN`
- blocked: `sparql_sql_behavioral_parity`, `cutover_authority`

This prevents a generated mapping file from being mistaken for an executed SPARQL system.

## Cutover falsifier

The candidate path is **not** ready to replace the control path if any of the following remains true:

- an Ash resource or relationship required by the admitted application profile has no R2RML mapping;
- R2RML or SHACL generation is nondeterministic;
- an OBDA engine cannot execute the generated mappings against the target PostgreSQL schema;
- paired SQL and SPARQL queries over the same fixture produce different normalized result multisets;
- transaction/identity semantics differ across the compared subject boundary; or
- production cutover authority has not been explicitly granted.

## Next validation phase

The next phase should add an actual PostgreSQL fixture plus an OBDA engine (for example Ontop) and define a corpus of paired queries. Each case should carry:

```text
subject identity
PostgreSQL schema + fixture hash
R2RML mapping hash
SPARQL query
reference SQL query
normalized SQL result hash
normalized SPARQL result hash
parity verdict
```

Only successful execution of that corpus can move `query_parity` from `UNKNOWN` to `VERIFIED`. Only then should a separate cutover PR be considered.
