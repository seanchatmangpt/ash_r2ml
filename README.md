<!--
SPDX-FileCopyrightText: 2025 ash_neo4j contributors <https://github.com/diffo-dev/ash_neo4j/graphs.contributors>
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# AshR2RML

**Ontology-first semantic mappings for Ash. Keep PostgreSQL relational; expose the same admitted subject as RDF.**

AshR2RML is an Ash extension that compiles Ash resources and relationships into standards-valid W3C R2RML mappings. It lets an Ash application persist through its normal data layer—typically AshPostgres—while exposing the same relational state as a virtual RDF graph through any compatible OBDA/R2RML engine.

AshR2RML is **not** a graph database, **not** an `Ash.DataLayer`, and **not** a SPARQL engine.

Its job is narrower and more useful:

```text
Ash.Resource + semantic mapping
             │
             ▼
      AshR2RML.Mapping
         ╱         ╲
        ▼           ▼
  AshPostgres     R2RML
        │           │
        ▼           ▼
   PostgreSQL   virtual RDF graph
        │           │
        └─────┬─────┘
              ▼
       ONE SUBJECT
       SQL / Ash / SPARQL
```

The same facts are not synchronized between two databases. PostgreSQL remains the operational store; R2RML defines a semantic projection over it.

## Why AshR2RML

A conventional semantic integration often starts too late:

```text
application schema → database tables → retrofit RDF mapping
```

AshR2RML supports both that pragmatic direction and an ontology-first direction:

```text
RDF/OWL + SHACL
       │
       ▼
      ggen
       │
       ▼
generated Ash resources
       │
       ▼
 AshR2RML.Mapping
    ╱        ╲
   ▼          ▼
AshPostgres  R2RML
```

Both routes converge on the same semantic mapping intermediate representation.

That gives an application three lawful query surfaces over one admitted subject:

- Ash queries and actions for application behavior.
- SQL for relational analytics and operations.
- SPARQL over the virtual RDF graph for semantic interoperability.

## Installation

Add AshR2RML beside the Ash data layer you already use:

```elixir
def deps do
  [
    {:ash, "~> 3.0"},
    {:ash_postgres, "~> 2.0"},
    {:ash_r2rml, "~> 1.0"}
  ]
end
```

AshR2RML does not replace AshPostgres. A resource continues to use its normal data layer:

```elixir
defmodule MyApp.Person do
  use Ash.Resource,
    domain: MyApp.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshR2RML.Resource]
end
```

## Ash-first quick start

Define the relational resource normally, then add only the semantic information Ash cannot infer.

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
    class "http://xmlns.com/foaf/0.1/Person"

    subject do
      template "https://example.org/people/{id}"
      term_type :iri
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true

      rdf do
        predicate "http://xmlns.com/foaf/0.1/name"
      end
    end
  end
end
```

AshR2RML introspects the Ash resource, its data layer metadata, attributes, identities, and relationships and compiles them into a normalized mapping.

```elixir
mapping = AshR2RML.Resource.Info.mapping(MyApp.Person)
```

Generate R2RML:

```elixir
{:ok, turtle} = AshR2RML.R2RML.render([MyApp.Person])
File.write!("priv/r2rml/application.ttl", turtle)
```

The resulting triples map is equivalent in shape to:

```turtle
<#Person>
    a rr:TriplesMap ;
    rr:logicalTable [ rr:tableName "people" ] ;
    rr:subjectMap [
        rr:template "https://example.org/people/{id}" ;
        rr:class foaf:Person ;
        rr:termType rr:IRI
    ] ;
    rr:predicateObjectMap [
        rr:predicate foaf:name ;
        rr:objectMap [
            rr:column "name" ;
            rr:datatype xsd:string
        ]
    ] .
```

## Relationships are semantic edges

Ash relationships are first-class inputs to the mapping compiler.

```elixir
relationships do
  belongs_to :organization, MyApp.Organization do
    allow_nil? false

    rdf do
      predicate "https://schema.org/memberOf"
    end
  end
end
```

For a relational data layer, AshR2RML derives the join from the relationship metadata and emits an R2RML reference object map:

```turtle
rr:predicateObjectMap [
    rr:predicate schema:memberOf ;
    rr:objectMap [
        rr:parentTriplesMap <#Organization> ;
        rr:joinCondition [
            rr:child "organization_id" ;
            rr:parent "id"
        ]
    ]
] .
```

One admitted relationship therefore has three corresponding projections:

```text
Ash relationship
      │
      ├── PostgreSQL FK / join structure
      └── R2RML RefObjectMap / RDF object property
```

AshR2RML refuses mappings that cannot be derived without inventing semantics.

## Semantic identity

Database identity and RDF identity are separate concerns.

AshR2RML supports subject maps based on:

- IRI templates,
- a column,
- a constant IRI,
- blank nodes where explicitly configured.

Example:

```elixir
r2rml do
  class "https://schema.org/Organization"

  subject do
    template "https://example.org/org/{tenant_id}/{id}"
    term_type :iri
  end
end
```

Every template field must resolve to an admitted Ash attribute. Subject construction is validated at compile time; invalid or ambiguous identity mappings are refused rather than guessed.

## Datatypes

AshR2RML maps Ash types to RDF datatypes through an explicit datatype registry.

Typical built-ins include:

| Ash type | RDF datatype |
|---|---|
| `:string` | `xsd:string` |
| `:integer` | `xsd:integer` |
| `:boolean` | `xsd:boolean` |
| `:decimal` | `xsd:decimal` |
| `:date` | `xsd:date` |
| UTC datetime types | `xsd:dateTime` |
| `:uuid` | `xsd:string` unless overridden |
| `:duration` (`Ash.Type.Duration`, Ash >= 3.23) | `xsd:duration` |

A type with no lawful mapping is `UNSUPPORTED`; it is never silently coerced to a string.

Custom Ash types can implement the AshR2RML datatype contract to define their RDF lexical form and datatype IRI.

## The mapping intermediate representation

Every public entry path compiles to the same IR:

```text
AshR2RML.Mapping.Resource
AshR2RML.Mapping.SubjectMap
AshR2RML.Mapping.PredicateObjectMap
AshR2RML.Mapping.ReferenceObjectMap
AshR2RML.Mapping.JoinCondition
AshR2RML.Mapping.Datatype
AshR2RML.Mapping.GraphMap
```

This representation is deliberately close to R2RML terminology. It is inspectable, deterministic, and independent of any one application ontology.

```elixir
%AshR2RML.Mapping.Resource{
  resource: MyApp.Person,
  class_iris: ["http://xmlns.com/foaf/0.1/Person"],
  logical_table: "people",
  subject_map: %AshR2RML.Mapping.SubjectMap{...},
  properties: [...],
  relationships: [...]
}
```

## Ontology-first Ash with ggen

AshR2RML ships a ggen pack for generating ordinary Ash resources from an admitted RDF/SHACL application profile.

The source of truth is the ontology/profile, not the generated Elixir:

```text
public ontology / application ontology
               │
               ▼
          SHACL shapes
               │
               ▼
             ggen
               │
               ▼
       generated Ash.Resource
               │
               ▼
         AshR2RML.Mapping
               │
               ▼
             R2RML
```

Example shape:

```turtle
ex:PersonShape
    a sh:NodeShape ;
    sh:targetClass foaf:Person ;
    r2ml:ashModule "MyApp.Person" ;
    r2ml:table "people" ;
    r2ml:subjectTemplate "https://example.org/people/{id}" ;
    sh:property [
        sh:path foaf:name ;
        sh:datatype xsd:string ;
        sh:minCount 1 ;
        sh:maxCount 1
    ] .
```

The pack deterministically manufactures the corresponding Ash resource and semantic annotations. Generated resources are projections and should not be hand-edited.

See [Ontology-first generation](documentation/how_to/ontology_first.livemd).

## SHACL as the operational closure boundary

AshR2RML does not claim that arbitrary OWL can be deterministically compiled into a relational schema.

OWL describes open-world semantics. Ash resources and relational schemas need operationally closed decisions about cardinality, datatype, identity, and storage.

For ontology-first generation, SHACL supplies that closure:

```text
OWL/RDFS vocabulary
      ↓
application profile
      ↓
SHACL operational shapes
      ↓
ggen compilation
```

If the shape does not provide enough information to choose one lawful Ash/relational projection, generation fails with a typed refusal.

## Typed refusals

AshR2RML fails closed at semantic boundaries. Representative failures include:

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

The exact Elixir error is a typed AshR2RML/Spark error. No mapping path silently drops a resource, attribute, relationship, or identity.

## Virtual RDF, not RDF synchronization

AshR2RML generates mappings; an OBDA engine executes SPARQL against the relational database.

```text
SPARQL
   │
   ▼
OBDA / R2RML engine
   │ rewrites
   ▼
 SQL
   │
   ▼
PostgreSQL
```

There is no RDF replication requirement and no dual-write protocol. The RDF graph is virtual unless the application deliberately materializes it elsewhere.

This eliminates an entire class of synchronization drift:

```text
Postgres row/FK state == source of truth
RDF triples            == semantic projection of that state
```

## Architecture invariant

AshR2RML follows this correspondence:

| Semantic construct | Ash | Relational projection | R2RML |
|---|---|---|---|
| RDF/OWL class | Resource | table/view | `rr:class` |
| datatype property | attribute | column/expression | predicate-object map |
| object property | relationship | FK/join | reference object map |
| semantic identity | subject DSL / Ash identity | unique key(s) | subject map |
| datatype | Ash type | storage type | `rr:datatype` |
| required property | `allow_nil? false` | NOT NULL where applicable | shape constraint |
| one-to-one / many-to-one | relationship | FK | reference object map |
| many-to-many | relationship/join resource | join table | chained reference maps |

R2RML should name and expose relationships the relational model already preserves. It should not repair a semantically impoverished schema.

## Deterministic generation

The ontology-first pack follows the ggen model:

```text
ontology + shapes + queries + templates
             │
             ▼
          ggen sync
             │
             ▼
      deterministic artifacts
```

A semantic change should require one authoritative edit and zero manual synchronization across generated Ash and R2RML projections.

## Verification model

AshR2RML treats compile success as a checkpoint, not the crown.

The integration contract is:

```text
Ash resources
    ↓
PostgreSQL fixture
    ↓
AshR2RML-generated R2RML
    ↓
real R2RML/OBDA engine
    ↓
SPARQL
```

The semantic identity and required relationships returned through SPARQL must match the subject visible through Ash.

Ontology-first generation adds the upstream leg:

```text
RDF/SHACL
   ↓
ggen
   ↓
Ash
   ↓
Postgres
   ↓
R2RML
   ↓
SPARQL
```

## What AshR2RML does not do

AshR2RML deliberately does not:

- replace AshPostgres, AshSql, Ecto, or another Ash data layer;
- store RDF triples itself;
- require Neo4j or another graph database;
- implement a SPARQL optimizer;
- infer arbitrary OWL semantics;
- invent missing relationship or identity information;
- make generated ontology facts executable with ambient authority.

## Documentation

- [Architecture](documentation/topics/architecture.md)
- [Ash-first mapping](documentation/how_to/ash_first.livemd)
- [Ontology-first generation](documentation/how_to/ontology_first.livemd)
- [Managing relational schema and R2RML](documentation/how_to/managing_schema.livemd)
- [Usage rules](usage-rules.md)

## Development

AshR2RML uses ggen to manufacture generated semantic compiler surfaces. Generated artifacts are projections; change their owning ontology/query/template and regenerate rather than hand-editing them.

The repository's `AGENTS.md` is the authoritative contributor contract.

## License

MIT. See `LICENSES/MIT.md`.
