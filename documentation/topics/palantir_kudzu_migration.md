# Palantir → AshR2RML: Kudzu Semantic Sovereignty Case Study

## Working-backwards customer

A Fortune 5 enterprise has encoded a material part of its operating model in a
Palantir-class ontology runtime: object types, links, actions, functions,
permissions, applications, provenance, pipelines, and generated SDK clients.
The enterprise wants to preserve the admitted meaning and behavior while making
its constitutional semantic layer independent of any proprietary runtime.

The target is not a data export and not a re-hosted vendor schema.

```text
Palantir-class ontology/runtime
        |
        | lawful metadata / API / schema observation
        v
candidate semantics
        |
        | public-ontology alignment + SHACL closure
        v
AshR2RML.SemanticIR (O*)
   /        |          \
 Ash      R2RML      read protocols
   |                    |
 actions            GraphQL/SPARQL/JSON-LD
   |                    |
   +---- BRCE/DO -------+
             |
          receipts
```

`SemanticIR` is the crown. Palantir, Ash, SQL, R2RML, GraphQL, SPARQL, and any
future transport are projections or adapters around that admitted object.

## Correspondence

| Palantir-class concept | AshR2RML target |
| --- | --- |
| object type | public ontology class + SHACL application profile + SemanticIR resource |
| property | RDF datatype/object property + SemanticIR attribute/relationship |
| link | RDF object property + admitted relationship cardinality/storage candidates |
| interface | public ontology/RDFS/OWL contract when equivalence is admitted |
| generated SDK | deterministic projection from O*, never canonical source |
| object query | read-only semantic protocol projection |
| action | named Ash action routed through BRCE before consequence-bearing DO |
| function proposing edits | SELECT/CONSTRUCT candidate, not authority |
| action permission/submission criteria | authority/admission policy at the DO boundary |
| action log | provenance + consequence receipt + replay identity |
| pipeline / source connector | transport adapter; semantic identity remains external to the vendor |
| proprietary ontology runtime | removed from canonical semantic authority |

## DfCM closure

The migration does not replace one proprietary runtime with one newly hard-coded
runtime. Before any irreversible cutover, preserve the lawful reversible product
space and collapse dimensions only when admitted constraints force a choice.

For the API-adjacent compiler surface today:

```text
GraphQL projection ∈ {off, canonical read-only}
JSON:API compatibility ∈ {off, existing AshJsonApi projection}

Projection space = GraphQL × JSON:API
                 = 2 × 2
                 = 4 lawful combinations
```

All four combinations remain available. Enabling canonical GraphQL does not
silently disable JSON:API; enabling JSON:API does not pull `AshGraphql.Resource`
back into the canonical GraphQL path. That independence is an executable
invariant, not a migration preference.

Composed ontologies also preserve their identities instead of requiring local
name uniqueness. If two admitted classes collapse to the same GraphQL root
field name — including a single-object query colliding with another class's
list query — the compiler deterministically allocates a content-addressed
suffix. It does not reject a lawful ontology merely because two vocabularies
chose adjacent local names, and it does not silently let one field overwrite
another.

Runtime query serving is deliberately not selected by this compiler. The
manifest records `runtime_execution: external` and `backend_selection:
unselected`. That is a DfCM boundary, not unfinished hidden work: AshR2RML owns
the semantic read contract; the consuming runtime owns transport/query serving
under its own observation/authorization boundary. `runtime_query_execution` is
therefore classified `UNSUPPORTED` by this compile-time projection rather than
as a blocked compiler edge.

## Read-plane law

The externally generated semantic plane is read-only by construction.

```text
GraphQL: Query only; no Mutation or Subscription root
SPARQL:  SELECT / ASK / CONSTRUCT / DESCRIBE only
JSON-LD: representation only
R2RML:   mapping/projection only
```

A GraphQL projection is a boolean compiler switch:

```elixir
AshR2RML.Ggen.compile_bundle(profile, graphql: true)
```

There is no GraphQL DSL in AshR2RML. There are no field renames, resolver
hooks, per-resource switches, mutation settings, or authorization knobs. The
same admitted O* deterministically produces the same GraphQL SDL and semantic
manifest. A product that needs a customized GraphQL API uses `ash_graphql`
instead of extending this semantic plane.

The generated GraphQL artifacts are:

```text
generated/graphql/schema.graphql
generated/graphql/semantic-manifest.json
receipts/graphql-projection.json
```

The receipt explicitly records `authority: none`, `mutation_root: false`, and
`subscription_root: false`. It records runtime query execution as unsupported
by this compiler surface rather than inventing a server or persistence owner.

## Write-plane law

Semantic accessibility does not imply mutation authority.

```text
intent
  -> planner / function
  -> SELECT
  -> CONSTRUCT candidate
  -> BRCE authority/admission
  -> named Ash action / transport
  -> DO
  -> consequence receipt
```

A foreign API may advertise `create`, `update`, `delete`, `send`, `approve`, or
other verbs. Capturing those verbs is an observation of capability. It does not
grant the semantic compiler or a GraphQL caller authority to execute them.

## Kudzu migration phases

1. **Observe** — inventory the incumbent ontology/API/SDK/actions/functions and
   preserve provenance to the exact vendor subject.
2. **Align** — map vendor semantics onto existing public ontology first;
   vendor-specific residue remains a typed extension rather than becoming
   canonical by incumbency.
3. **Admit** — close operational cardinality, datatype, identity, and structural
   constraints with the application profile + SHACL.
4. **Manufacture side-by-side** — generate Ash, PostgreSQL, R2RML, SHACL, and
   optional read-only GraphQL from the same SemanticIR while preserving lawful
   sibling projection combinations.
5. **Verify equivalence** — execute representative read/process/action corpora
   against both worlds. Successful manufacture alone is PARTIAL_ALIVE.
6. **Move consequence paths** — migrate named actions behind BRCE one bounded
   capability at a time, preserving receipts and replay.
7. **Delete the adapter** — only after the vendor contributes no irreducible
   semantic or behavioral dependency.

## Crown

The final acceptance test is deliberately destructive in wording but not in
execution authority:

> If the Palantir-class runtime were removed after an explicitly authorized
> cutover, what admitted meaning, behavior, authority, history, or application
> consequence would be lost?

The migration is incomplete while the answer is non-empty.

```text
Remove(incumbent)
and Preserve(meaning, behavior, authority, history, receipts)
```

The target property is **semantic sovereignty**: the enterprise can retain or
replace any runtime because no commercial runtime owns the canonical meaning of
the enterprise.

## Standing and falsifiers

This document is a migration case study and acceptance model, not evidence that
a Palantir production estate has already been migrated.

The case study is falsified if any of the following remain true after the
claimed crown:

- vendor-specific identity is required to interpret canonical objects;
- a generated projection must be reverse-engineered to reconstruct meaning;
- external semantic protocols can independently mutate state;
- lawful sibling read projections cannot coexist without one implicitly
  selecting, disabling, or re-authoring another;
- composed ontologies lose a class because generated protocol names collide;
- equivalent reads/processes/actions cannot be replayed after removing the
  incumbent transport;
- new vendor captures repeatedly require bespoke semantic reasoning instead of
  reusing admitted mappings, ontology, generators, and verifiers.
