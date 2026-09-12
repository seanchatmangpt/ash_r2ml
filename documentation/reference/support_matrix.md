# AshR2RML support matrix

This reference defines the finished public capability boundary. A capability is supported only when its compiler, verifier, renderer, and applicable integration tests agree.

## Ash resource constructs

| Construct | Mapping status | R2RML projection |
|---|---|---|
| table-backed resource | supported | `rr:TriplesMap` + `rr:tableName` |
| explicit logical view | supported | logical table mapping |
| scalar attribute | supported when datatype is mapped | predicate-object map |
| `belongs_to` | supported with deterministic join | `rr:RefObjectMap` |
| `has_one` | supported with deterministic reverse join | reference object map |
| `has_many` | supported with deterministic join | repeated/reference mapping |
| `many_to_many` | supported through actual join structure | chained/reference mapping |
| association resource | supported | independent triples map + relationships |
| Ash identity | usable as semantic-identity evidence | subject-map input |
| primary key | usable when explicitly selected | subject-map input |
| runtime-only calculation | not automatically mapped | requires relational/logical-table projection |
| arbitrary action | not an RDF class by implication | no automatic mapping |

## Subject maps

Supported strategies:

- IRI template;
- column/attribute value;
- constant IRI;
- explicit blank node.

Missing/ambiguous subject identity is refused.

## RDF term/datatype constructs

| Construct | Status |
|---|---|
| IRI subject/object | supported |
| plain typed literal | supported |
| explicit language literal | supported when declared |
| custom datatype | supported through datatype registry/contract |
| opaque automatic stringification | unsupported |
| implicit JSON serialization of structured values | unsupported by default |

## R2RML constructs

| R2RML construct | Status |
|---|---|
| `rr:TriplesMap` | supported |
| `rr:logicalTable` | supported |
| `rr:tableName` | supported |
| explicit SQL-query logical table | supported as advanced read-only mapping |
| `rr:subjectMap` | supported |
| `rr:class` | supported |
| `rr:predicateObjectMap` | supported |
| `rr:objectMap` | supported |
| `rr:RefObjectMap` | supported |
| `rr:parentTriplesMap` | supported |
| `rr:joinCondition` | supported |
| named graph maps | supported when explicitly configured |

## Ontology-first constructs

Ontology-first generation consumes an application profile plus SHACL operational shapes. It does not claim arbitrary OWL-to-SQL compilation.

Supported operational cases include:

- `sh:NodeShape` targeting an admitted class;
- scalar property shapes with supported `sh:datatype`;
- required/optional scalar cardinality;
- to-one object-property shape with deterministic target/storage mapping;
- to-many relationships when storage strategy is determined;
- association-resource shapes;
- semantic identity templates supplied by profile/mapping metadata.

Ambiguous open-world constructs are refused rather than guessed.

## Data layers

AshR2RML is data-layer independent at the semantic API boundary, but relational R2RML compilation requires enough data-layer metadata to identify logical tables, columns, and joins.

AshPostgres/PostgreSQL is the canonical conformance implementation.

A different Ash data layer is supported only for the subset for which an adapter can lawfully expose equivalent relational mapping metadata.

## Query execution

| Surface | Owner |
|---|---|
| Ash queries/actions | Ash + active data layer |
| SQL | relational database |
| SPARQL | external compatible OBDA/R2RML engine |
| SPARQL-to-SQL rewriting | external OBDA engine |
| OWL reasoning | external reasoner/OBDA capability, not AshR2RML core |

## Explicit non-goals

