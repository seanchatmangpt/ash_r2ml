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

Supported predicate forms are deliberately bounded:

- `:ask` — one SPARQL ASK observation.
- `:result_delta` — compare the deterministic result identities of an explicit previous and current read-only SPARQL observation.
- `:external_trigger` — admit an already-observed event/time/RDF-change witness carrying `observed?: true` and a stable `receipt_sha256`.

Other predicate semantics are refused instead of approximated.

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
