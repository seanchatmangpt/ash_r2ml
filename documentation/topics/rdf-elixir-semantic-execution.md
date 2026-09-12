<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# RDF-Elixir semantic execution topology

## Architectural invariant

AshR2RML does not define a new RDF syntax, SPARQL language, SPARQL protocol, JSON-LD processor, or triplestore.

It composes standards implementations around one admitted semantic subject:

```text
                           ontology + application profile + SHACL
                                         |
                                      admission
                                         |
                                  SemanticIR / Mapping
                                   /             \
                                  /               \
                         PostgreSQL              RDF view
                             |                      |
                         R2RML mapping              |
                             |                      |
              +--------------+----------+-----------+
              |                         |           |
          Ontop CLI                Ontop HTTP   local RDF.ex
              |                         |           |
           SPARQL                  SPARQL.Client SPARQL.ex
              |                         |           |
              +------------- normalized results ---+
                                         |
                                      parity
```

No execution surface becomes a second source of semantic truth.

## DfCM dimensions

AshR2RML preserves independent choices until an admitted use case closes them.

### RDF serialization

| Candidate | Role | Standing |
| --- | --- | --- |
| Turtle via RDF.ex | RDF/SHACL authoring and interchange | lawful |
| JSON-LD 1.1 via JSON-LD.ex | RDF/SHACL authoring and interchange | lawful |

Both formats are decoded to RDF and enter the same `AshR2RML.Ingestion.from_graph/2` boundary. A serialization must not create a different `AshR2RML.Mapping.Bundle` for the same admitted RDF graph.

Remote JSON-LD contexts are not ambient authority. HTTP(S) context resolution is refused by default because remote mutable content would make compilation dependent on an unreceipted external observation. Callers may explicitly opt in when that external dependency is itself admitted.

### SPARQL execution

| Candidate | Implementation | Appropriate use |
| --- | --- | --- |
| `:local_rdf` | SPARQL.ex over RDF.ex data | local semantic fixtures, supported in-memory algebra |
| `:protocol` | SPARQL.Client over W3C SPARQL Protocol | arbitrary compatible remote query endpoints |
| `:ontop_cli` | Ontop CLI over generated R2RML + PostgreSQL | direct OBDA execution and CI evidence |

Candidate membership is not equivalence. The SPARQL.ex local execution engine intentionally supports a bounded subset of SPARQL execution semantics; SPARQL.Client can send query forms to a remote SPARQL service that the local engine cannot itself execute. Therefore AshR2RML preserves both instead of pretending one replaces the other.

`AshR2RML.SPARQL.explore/2` carries all supplied lawful candidates. If more than one candidate remains, execution refuses until a caller explicitly selects a strategy. A uniquely available candidate may be selected mechanically.

## Query admission

`AshR2RML.SPARQL.Query.admit/1` parses queries through SPARQL.ex before execution and records the SHA-256 identity of the exact lexical query.

The lexical hash is an evidence identity, not a claim that two lexically different SPARQL queries are semantically inequivalent. AshR2RML does not currently manufacture a canonical normal form for arbitrary SPARQL algebra.

## Result normalization

Every supported execution path is lowered to parity-ready rows:

- `SELECT` solution mappings become maps with string variable names and native RDF term values;
- `ASK` becomes a boolean row;
- RDF graph/dataset results become deterministic subject/predicate/object[/graph] rows.

Normalization uses RDF.ex term semantics and then the existing AshR2RML multiset canonicalization. Result ordering is therefore not confused with semantic result multiplicity.

## SPARQL Update fence

SPARQL.Client is capable of SPARQL Update. AshR2RML deliberately does not expose remote update actuation through its semantic verification API.

```text
client capability != AshR2RML authority
```

AshR2RML owns semantic compilation and evidence production. A consumer that needs SPARQL Update must establish a separate DO authority path and its own receipts. Query verification never manufactures mutation authority.

## JSON-LD closure

JSON-LD.ex is used as the JSON-LD 1.1 processor. AshR2RML adds only application-level admission around it:

1. decode JSON text;
2. reject unadmitted remote context dependencies;
3. convert JSON-LD to RDF through JSON-LD.ex;
4. feed RDF into the same SHACL/application-profile admission used by Turtle;
5. compile the resulting normalized profile into the canonical mapping bundle.

The inverse projection is available for RDF-to-JSON-LD interchange, including optional explicitly admitted compaction contexts.

## ggen law

The ggen boundary operates after semantic admission.

```text
Turtle ----\
            -> RDF -> SHACL admission -> normalized profile -> ggen bundle
JSON-LD ---/
```

The generated Ash, SQL, R2RML, SHACL, semantic catalog, and compilation receipt therefore cannot depend on which lawful RDF serialization was used to supply an equivalent admitted graph.

AshR2RML does not currently claim byte-for-byte canonical JSON-LD serialization. Blank-node labeling and JSON document presentation are not promoted to semantic identity. The crown is canonical mapping/R2RML equivalence, not JSON text equality.

## Multi-engine crown

The bounded integration crown requires one fixture to survive all of the following observations:

1. Turtle/SHACL compilation;
2. JSON-LD/SHACL compilation;
3. generated PostgreSQL DDL and fixture loading;
4. generated R2RML executed by Ontop CLI;
5. the same admitted SPARQL query executed through SPARQL.Client against a live Ontop endpoint;
6. an equivalent supported query executed by SPARQL.ex over a local RDF.ex control graph;
7. reference SQL over PostgreSQL;
9. normalized multiset comparison and stable receipts.

A mismatch falsifies the corresponding equivalence claim. Passing all technical comparisons still does not authorize cutover.

## Definition of Done for this layer

This semantic-web layer is `ALIVE` only when exact-head verification demonstrates:

- SPARQL.ex query admission and local supported execution;
- SPARQL.Client execution against a real SPARQL Protocol endpoint;
- JSON-LD → RDF → SHACL/profile → canonical mapping compilation;
- Turtle and JSON-LD input paths render the same canonical R2RML for the admitted fixture;
- result identities and parity receipts are deterministic under irrelevant row ordering;
- remote JSON-LD context dependencies fail closed unless explicitly admitted;
- no SPARQL Update path is exposed as implicit semantic-verification authority;
- cutover remains separately unauthorized until an explicit authority receipt exists.

Until those executions are observed at the exact head, source manufacture is `PARTIAL_ALIVE`, not `ALIVE`.
