# Knowledge hooks

AshR2RML treats a knowledge hook as a **semantic observation that may manufacture an intent**. It is not an actuator.

The boundary is:

```text
hook definition
  -> predicate admission
  -> observed trigger / SPARQL observation
  -> deterministic evaluation receipt
  -> optional intent
  -X-> no execution authority
```

A matched hook returns `%AshR2RML.KnowledgeHook.Intent{}` with `authority: :UNAUTHORIZED`, `standing: :constructed_not_actuated`, and `requires_actuation_receipt?: true`. A downstream BRCE/Reactor boundary must separately admit authority and produce its own actuation receipt.

## Normalized hooks

```elixir
hooks = [
  %{
    id: "customer-ready",
    name: "Customer ready",
    trigger_type: :sparql_result,
    predicate: %{
      type: :ask,
      query: """
      ASK WHERE {
        <https://example.com/customer/42>
        <https://example.com/state>
        <https://example.com/ready>
      }
      """
    },
    intent: %{
      kind: :reactor,
      target: "MyApp.CustomerReadyReactor",
      payload: %{customer_id: 42}
    }
  }
]

{:ok, plan} = AshR2RML.KnowledgeHooks.admit(hooks)

{:ok, evaluations} =
  AshR2RML.KnowledgeHooks.evaluate(plan,
    current: [data: graph, strategy: :local_rdf]
  )
```

Supported predicate forms are deliberately bounded — 8 types total, each with `admit/2`
compile-time validation and `evaluate/2` runtime execution:

| Type | What it observes | Typed refusal on malformed input |
|---|---|---|
| `:ask` | SPARQL `ASK` query truth value | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:result_delta` | Change between the normalized result-set SHA-256 identity of an explicit previous and current read-only `SELECT` observation | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:external_trigger` | An externally-supplied, already-observed event/time/RDF-change witness carrying `observed?: true` and a stable `receipt_sha256` | `REFUSED_UNPROVEN_EQUIVALENCE` |
| `:shacl` | SHACL shape conformance for one or more focus nodes | `REFUSED_INVALID_SHACL_SHAPES_GRAPH` |
| `:threshold` | A bound SPARQL `SELECT` variable compared against a numeric bound (`:gt`/`:gte`/`:lt`/`:lte`/`:eq`) | `REFUSED_INVALID_BOUND_PREDICATE` |
| `:count` | Row count of a `SELECT` query compared against a numeric bound | `REFUSED_UNSUPPORTED_SPARQL_FEATURE` (non-`SELECT` form) |
| `:temporal_window` | Every extracted `time_field` value across a `SELECT` result set, compared against `evaluated_at` over a `{unit, comparator, bound}` window | admission: malformed window spec or non-`SELECT` form is Blocked; evaluation: `REFUSED_MISSING_EVALUATION_TIME` when no real `evaluated_at` is supplied |
| `:datalog` | A single, non-recursive Datalog rule (`head(Vars) :- (S,P,O), ...`) joined by nested-loop substitution over `RDF.Data.statements/1` | `REFUSED_INVALID_DATALOG_RULE` (malformed, recursive, or unsafe rule) |

`:threshold` and `:count` both admission-refuse an unsupported `comparator` atom with
`REFUSED_INVALID_BOUND_PREDICATE`; `:shacl` refuses a shapes graph that fails to parse or an
empty focus set with `REFUSED_INVALID_SHACL_SHAPES_GRAPH`.

Other predicate semantics not in this table are refused instead of approximated.

### `:threshold` / `:count`

```elixir
%{
  type: :threshold,
  query: "SELECT ?count WHERE { ... }",
  variable: "count",
  comparator: :gte,
  bound: 10
}
```

### `:shacl`

```elixir
%{
  type: :shacl,
  shapes_graph: shacl_turtle,
  focus_nodes: ["https://example.com/customer/42"]
}
```

### `:temporal_window`

```elixir
%{
  type: :temporal_window,
  query: "SELECT ?observed_at WHERE { ... }",
  time_field: "observed_at",
  window: {:hour, :lte, 1}
}

AshR2RML.KnowledgeHooks.evaluate(plan,
  current: [data: graph, strategy: :local_rdf],
  evaluated_at: DateTime.utcnow()
)
```

`evaluated_at` is required as a real `%DateTime{}` supplied by the caller in `opts` — evaluation
never falls back to an internal `DateTime.utcnow()`/`System.os_time()` call, and omitting it is
refused with `:REFUSED_MISSING_EVALUATION_TIME` rather than silently defaulting to "now." The
verdict fires only when every extracted `time_field` value across all result rows satisfies
`compare(DateTime.diff(evaluated_at, value, unit), comparator, bound)`.

### `:datalog`

```elixir
%{
  type: :datalog,
  datalog_rule: "grandparent(X, Z) :- (X, parentOf, Y), (Y, parentOf, Z)."
}
```

`AshR2RML.KnowledgeHook.Datalog` is explicitly scoped: single rule only, no recursion, no
negation, no aggregation, no stratification. A recursive or unsafe rule (a head variable not
bound in the body) is refused at admission with `:REFUSED_INVALID_DATALOG_RULE`, not
approximated or partially evaluated. This is a deliberate hand-written subset, not a general
Datalog engine — `deps/rdf` (rdf ~> 3.0) ships no Datalog evaluator, and adding a full external
Datalog dependency was a scope decision left for a future release if a real need for recursion
or negation appears.

Real test coverage for all 8 predicate types (conforming/violating/malformed cases per type,
real `RDF.Graph`/`RDF.Turtle` fixtures, real local-RDF SPARQL execution, zero mocks) lives in
`test/knowledge_hooks_shacl_threshold_count_test.exs`,
`test/knowledge_hooks_temporal_window_test.exs`, and `test/knowledge_hooks_datalog_test.exs`.

## GitVan Graph Hook interoperability

`AshR2RML.KnowledgeHooks.from_turtle/2` recognizes the GitVan v4 graph-hook vocabulary at `https://gitvan.dev/graph-hook#` for:

- `gh:Hook`
- `gh:hasPredicate`
- `gh:ASKPredicate`
- `gh:ResultDelta`
- `gh:queryText`
- `gh:orderedPipelines`

The pipeline node is retained only as an opaque intent target. AshR2RML never executes the pipeline.

```elixir
{:ok, plan} = AshR2RML.KnowledgeHooks.from_turtle(hook_turtle)
```

## KNHK interoperability

The same Turtle adapter recognizes `http://knhk.io/ontology#Hook` definitions with `name`, `triggerType`, `triggerPattern`, `checkCondition`, `action`, and `emitReceipt`.

`RdfChange`, `Event`, and `Interval` hooks without a SPARQL check become `:external_trigger` predicates. They cannot fire from a caller assertion alone. Evaluation requires an observed trigger receipt:

```elixir
AshR2RML.KnowledgeHooks.evaluate(plan,
  trigger_receipts: %{
    "https://example.com/hook" => %{
      observed?: true,
      receipt_sha256: "...stable identity..."
    }
  }
)
```

A KNHK hook that explicitly disables receipts is refused at admission.

## Result-delta hooks

Result-delta evaluation requires two explicit observation contexts. AshR2RML does not silently invent history:

```elixir
{:ok, evaluations} =
  AshR2RML.KnowledgeHooks.evaluate(plan,
    previous: [data: old_graph, strategy: :local_rdf],
    current: [data: new_graph, strategy: :local_rdf]
  )
```

The hook matches only when the normalized SPARQL result SHA-256 identities differ.

## ggen projection

`AshR2RML.Ggen.KnowledgeHooks` manufactures a deterministic path/content graph for ggen without writing files or running hooks:

```elixir
{:ok, bundle} = AshR2RML.Ggen.KnowledgeHooks.compile(plan)
```

The bundle contains:

```text
generated/knowledge-hooks/plan.json
receipts/knowledge-hooks-compilation.json
```

Both artifacts preserve `authority: UNAUTHORIZED`. Filesystem writes, hook registration, scheduling, workflow execution, and consequential actions remain downstream responsibilities.

## Refusal boundary

Admission fails closed when a hook has duplicate or unstable identity, malformed or unsupported predicate semantics, a missing opaque intent target, executable callbacks/runtime handles embedded in its definition, a disabled receipt requirement, or unsupported vocabulary semantics. An external trigger without an observed receipt and a result-delta hook without a previous observation context are also refused.
