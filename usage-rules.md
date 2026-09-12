<!--
SPDX-FileCopyrightText: 2025 Matthew Graham Beanland and contributors
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# Rules for working with AshR2RML

AshR2RML is a generic semantic mapping extension for Ash. It compiles Ash resource semantics into a normalized mapping IR and standards-valid W3C R2RML while leaving persistence to the resource's existing Ash data layer.

AshR2RML is **not** an `Ash.DataLayer`, graph database, triplestore, migration engine, or SPARQL engine.

## Core invariant

```text
Ash.Resource + semantic metadata
             │
             ▼
      AshR2RML.Mapping
         ╱         ╲
        ▼           ▼
 relational DB     R2RML
        │           │
        └─────┬─────┘
              ▼
       ONE SUBJECT
       Ash / SQL / SPARQL
```

The RDF graph is normally virtual. A compatible OBDA engine rewrites SPARQL into SQL against the same relational database used by the Ash application.

## Rules by concern

| Concern | Rule |
|---|---|
| Installation and runtime boundary | [setup.md](usage-rules/setup.md) |
| Public Spark/RDF DSL | [dsl.md](usage-rules/dsl.md) |
| Normalized compiler representation | [semantic-ir.md](usage-rules/semantic-ir.md) |
| RDF subject identity | [identities.md](usage-rules/identities.md) |
| Ash relationships → RDF object properties | [relationships.md](usage-rules/relationships.md) |
| Ash/RDF datatype correspondence | [datatypes.md](usage-rules/datatypes.md) |
| Custom Ash datatype contracts | [custom-types.md](usage-rules/custom-types.md) |
| Relational logical tables/views | [logical-tables.md](usage-rules/logical-tables.md) |
| R2RML rendering/conformance | [r2rml.md](usage-rules/r2rml.md) |
| Ash/SQL/SPARQL query boundaries | [query-surfaces.md](usage-rules/query-surfaces.md) |
| Virtual RDF / OBDA boundary | [obda.md](usage-rules/obda.md) |
| Ontology-first compilation | [ontology-first.md](usage-rules/ontology-first.md) |
| ggen manufacturing | [ggen.md](usage-rules/ggen.md) |
| Ash actions/mutation boundary | [actions.md](usage-rules/actions.md) |
| Verification and semantic round trips | [testing.md](usage-rules/testing.md) |

Legacy donor-era filenames remain only as compatibility tombstones and must not be treated as active AshR2RML features.

## Resource configuration

A normal relational resource keeps its data layer and adds AshR2RML as an extension:

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]

  postgres do
    table "people"
    repo MyApp.Repo
  end

  r2rml do
    class "https://schema.org/Person"

    subject do
      template "https://example.org/people/{id}"
      term_type :iri
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false

      rdf do
        predicate "http://xmlns.com/foaf/0.1/name"
      end
    end
  end
end
```

AshR2RML should infer relational facts already known by Ash/data-layer metadata and require explicit semantic facts only where inference would be unsafe.

## Mapping compiler

All entry paths converge on `AshR2RML.Mapping` structures before rendering. The renderer must not rediscover Ash metadata independently.

Canonical mapping concepts include:

```text
Resource
SubjectMap
PredicateObjectMap
ReferenceObjectMap
JoinCondition
Datatype
GraphMap
```

A mapping is deterministic and inspectable.

## Semantic identity

Database primary keys are not automatically public RDF identity. Every RDF subject requires an explicit deterministic subject strategy.

A subject template may use Ash attributes only when those fields exist and form the intended stable semantic identity.

Blank nodes are explicit, never a fallback for missing identity.

## Relationships

An Ash relationship with an RDF predicate must survive compilation as a semantic relationship. For relational resources, AshR2RML derives reference object maps and join conditions from proven Ash/data-layer metadata.

Never silently omit a relationship because the join is difficult to derive. Refuse instead.

## Datatypes

Use an explicit registry. Unsupported types do not become strings silently.

Exact numeric, date/time, enum, structured, and custom types must preserve their admitted semantic representation.

## R2RML

Render standards-valid Turtle. Parse generated output with an independent RDF parser. Relationship mappings use `rr:RefObjectMap`; scalar properties use predicate-object maps; subject identity uses subject maps.

Do not confuse syntactically valid Turtle with a proven end-to-end virtual RDF graph.

## Ontology-first generation

Ontology-first applications use:

```text
RDF/OWL
   ↓
application profile
   ↓
SHACL operational shapes
   ↓
ggen
   ↓
generated Ash.Resource
   ↓
AshR2RML.Mapping
```

SHACL supplies operational closure. Arbitrary OWL is not deterministically compiled directly into SQL.

If constraints do not select one lawful Ash/relational projection, generation fails closed.

## ggen

ggen is the manufacturer, not the request-time runtime.

Generated Ash/R2RML surfaces are projections owned by ontology/profile/shapes, SPARQL gates/queries, and templates. Fix source authority and regenerate rather than hand-editing outputs.

## OBDA

AshR2RML does not implement SPARQL-to-SQL rewriting. A compatible external OBDA/R2RML engine owns that boundary.

The crown integration proves that a subject written/read through Ash is exposed with the same semantic identity, values, and relationships through SPARQL over generated R2RML.

## Typed failures

AshR2RML fails closed at semantic boundaries. Representative classifications include:

```text
REFUSED_INVALID_CLASS_IRI
REFUSED_MISSING_SUBJECT_MAP
REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY
REFUSED_UNMAPPED_DATATYPE
REFUSED_AMBIGUOUS_RELATIONSHIP
REFUSED_INVALID_JOIN_CONDITION
REFUSED_RELATIONSHIP_WITHOUT_PREDICATE
REFUSED_R2RML_JOIN_WITHOUT_IDENTITY
REFUSED_UNPROVEN_EQUIVALENCE
UNSUPPORTED_TERM_TYPE
UNSUPPORTED_ASH_TYPE
```

Expected unsupported conditions are typed results, not guessed mappings.

## Verification

Use the ladder:

```text
pure mapping tests
→ DSL/introspection tests
→ R2RML render tests
→ independent Turtle parse
→ deterministic regeneration
→ real relational integration
→ real OBDA/SPARQL integration
→ ontology-first ggen round trip
```

A lower checkpoint can be `PARTIAL_ALIVE`. `ALIVE` requires the exact claimed external boundary to execute.

## Non-goals

AshR2RML does not:

- replace AshPostgres or another Ash data layer;
- write triples as its persistence model;
- manage graph indexes;
- implement graph traversal expressions;
- implement vector/spatial query engines;
- implement SPARQL planning;
- infer arbitrary OWL;
- grant execution authority from RDF/SHACL facts.
