# AshR2RML v26.8.25 — Architecture Requirements Document

**Perspective:** Local DfCM Research & Manufacturing Engine — Architecture Requirements Pass
**Target Repository:** `ash_r2rml`
**Standing:** `PARTIAL_ALIVE`

See also: [`jira_v26_8_25.md`](jira_v26_8_25.md) for the feature roadmap, benchmark numbers, and test suite verification these decisions support.

---

## Part 1: Architecture Decisions & Invariants for v26.8.25

Five real, shipped-but-uncommitted architecture decisions from this session's working tree, each naming the exact module/function it lives in, the invariant it establishes, and the real test that verifies it.

### 1. `AshR2RML.DataLayer.backend/1` as the Single Source of Truth for Backend Detection

- **Decision:** `backend/1` (`lib/ash_r2rml/data_layer.ex:16-33`) is the sole classifier of a resource's Ash data layer (`:postgres | :ets | :unknown`), derived from `Ash.Resource.Info.data_layer/1`. Both consumers read this one function rather than re-deriving the classification: `AshR2RML.Compiler.render_storage_ddl/2` never calls it directly (the caller passes `storage_backend` explicitly), but `AshR2RML.Security.sanitize_mapping/2` (`lib/ash_r2rml/security.ex:41`) gates its structural exclusion on `AshR2RML.DataLayer.backend(ash_resource) == :postgres`, and `table_name/1`/`schema_name/1` (same file) dispatch on it for R2RML rendering, which is otherwise unaffected by backend choice.
- **Invariant Established:** `backend/1` returns `:ets` for real `Ash.DataLayer.Ets`-backed resources and `:unknown` for a non-Ash module, never guessing or raising. Verified by `test/data_layer/ets_backend_test.exs`, `describe "backend/1"` — `"identifies Ash.DataLayer.Ets-backed resources as :ets"` and `"returns :unknown for a plain module that is not an Ash resource"`.

### 2. `AshR2RML.Compiler`'s `storage_backend: :postgres | :ets` Option and the Legality of Skipping SQL DDL

- **Decision:** `AshR2RML.Compiler.compile/2` (`lib/ash_r2rml/compiler.ex:135-136`) reads `Keyword.get(opts, :storage_backend, :postgres)` — backward compatible by default — and routes rendering through `render_storage_ddl/2` (`lib/ash_r2rml/compiler.ex:338-344`). The `:ets` clause returns `{:ok, nil}` rather than a refusal or a BLOCKED status. This is legal, not merely convenient: `AshR2RML.Semantic.SQL.render/1` (`lib/ash_r2rml/semantic_renderers.ex:246-252`) is a pure DDL-string renderer over an already-admitted `SemanticIR` — it performs no admission, validation, or refusal-generation of its own (all validation already happened in `Admission.admit/1` upstream). Skipping the call therefore loses a DDL artifact `Ash.DataLayer.Ets` has no use for, and nothing else.
- **Invariant Established:** Compiling with `storage_backend: :ets` yields `compilation.postgres_ddl == nil`, records `:postgres_ddl_skipped_ets_backend` in `receipt.executed` (not `blocked`), and every backend-independent artifact (`ash_source`, `ecto_migration`, `r2rml`, `shacl`, `mapping_bundle`) still renders in full. Verified by `test/compiler_ets_backend_test.exs`, `"storage_backend: :ets skips SQL DDL rendering without blocking the compilation"` (and the `:postgres` default is pinned by the adjacent `"storage_backend: :postgres (default) renders SQL DDL as before"`).

### 3. `AshR2RML.OBDA.InMemory` Delegates to the Existing `AshR2RML.SPARQL.Local`/SPARQL.ex Engine Instead of Hand-Rolling a Query Language

- **Decision:** `materialize_many/2` (`lib/ash_r2rml/obda_in_memory.ex:63-76`) builds a real `RDF.Graph` from real `Ash.read!/2` rows via the canonical `AshR2RML.Mapping.Resource` IR — the same IR the R2RML renderer consumes. `query_many/3` (`lib/ash_r2rml/obda_in_memory.ex:97-102`) then delegates query execution to `AshR2RML.SPARQL.Local.query/2`, i.e. full `SPARQL.ex` algebra, rather than writing a bespoke BGP matcher. Because the query surface is the real engine, `CONSTRUCT`/`ASK`/`DESCRIBE` are not separately implemented — they work because `SPARQL.ex` already implements them.
- **Invariant Established:** `SELECT`, `CONSTRUCT`, and cross-resource-join queries all execute correctly against the materialized graph with zero query-form-specific code in `AshR2RML.OBDA.InMemory` itself. Verified by `test/obda_in_memory_test.exs`: `"queries the materialized graph with real SPARQL via AshR2RML.SPARQL.Local"`, `"CONSTRUCT queries return real projected triples, not bindings"` (asserts `observation.query_form == :construct` and `observation.result_kind == :rdf`), and `"queries across multiple resources in one SPARQL query via a real Ash relationship join"`.

### 4. `AshR2RML.Security.sanitize_mapping/2` as a Structural-Exclusion Architecture, Not a Refusal Gate

- **Decision:** `sanitize_mapping/2` (`lib/ash_r2rml/security.ex:39-46`) is a pure mapping *transform* — it removes `predicate_object_maps` entries and records the removal in `mapping.metadata[:field_policy_excluded_attributes]` — wired directly into `AshR2RML.Compiler.compile_resources/1`'s `do_closure/3` (`lib/ash_r2rml/compiler.ex:462`), which runs on every resource in the compiled closure unconditionally. It never refuses compilation and never requires an operator to remember a gate. The explicit, named tradeoff (`lib/ash_r2rml/security.ex:23-28`): `unenforceable_attributes/2` cannot distinguish an unconditionally-granting `field_policy` (`authorize_if always()`) from a genuinely conditional one, because that would require inspecting Ash's internal check AST — fragile across Ash versions. Any explicit `field_policy` on an R2RML-mapped attribute is excluded, full stop; this is stated as deliberately conservative, not an oversight.
- **Invariant Established:** `unenforceable_attributes/2` flags every attribute carrying an explicit `field_policy` — including an `always()`-policy attribute — identically to a conditionally-policied one, and never flags an attribute with no `field_policy` at all. `sanitize_mapping/2` is a true no-op on non-`:postgres`-backed resources. Verified by `test/obda_in_memory_test.exs`: `"detects field-policy-protected R2RML-mapped attributes against a real resource"` (against `AshR2RML.Fortune5.PaymentGateway`'s real `field_policies` — flags `:secret_key` and the `always()`-policied `:name`, does not flag unpoliced `:id`; also confirms `sanitize_mapping/2` no-ops on the `:ets`-backed fixture) and `"removes field-policy-protected attributes from the real mapping, recording the exclusion"` (exercises `remove_attributes/2` directly).

### 5. IRI-Injection Hardening: Percent-Encode `:template` Substitutions, Validate-and-Skip `:column` Strategies

- **Decision:** `substitute_template/2` (`lib/ash_r2rml/obda_in_memory.ex:180-184`) percent-encodes *only* the substituted field value (`percent_encode_iri_value/1`, `URI.char_unreserved?/1`) before splicing it into an author-written `rr:template` string, matching Ontop's own confirmed live `rr:template` substitution behavior against a real Postgres+Ontop stack. `valid_iri_or_nil/1` (`lib/ash_r2rml/obda_in_memory.ex:194-196`) takes the opposite, deliberately different path for `:column` strategies: it validates the already-stored value as a complete IRI via `RDF.IRI.valid?/1` and drops the row on failure rather than encoding it. This asymmetry is the correct one, not an inconsistency: `rr:column` semantics mean the column's stored value *is* the entire IRI already, so there is nothing to substitute or encode without rewriting already-stored data — a malformed stored IRI is a data-integrity problem in the source row, not an injection surface to neutralize.
- **Invariant Established:** A `:template`-substituted value crafted to break IRIREF syntax is preserved as a triple with the dangerous characters percent-encoded (row not dropped); a `:column`-strategy value crafted the same way is excluded from the graph entirely (row dropped, no malformed IRI embedded). Verified by `test/obda_in_memory_test.exs`: `"adversarial: a :template-substituted value crafted to break IRIREF syntax is percent-encoded, not embedded or dropped"` and `"adversarial: a subject value crafted to break IRIREF syntax is excluded, not embedded"`.

---

## Part 2: Jira Ticket Backlog (`docs/jira/v26.8.25/`)

Below are 4 prioritized Jira tickets for the next release's follow-on work, plus an honest status update on `R2RML-101` carried forward from `jira_v26_8_21_audit.md`.

---


**Verdict: PARTIALLY CLOSED**, re-verified this session against the real repository state, not assumed from the prior audit:



---

### Ticket 1: `R2RML-105` — End-to-End `AshPostgres`-Backed Compiled-Resource Coverage for `AshR2RML.Security`

**Status: CLOSED — re-verified 2026-08-25.** Real evidence, re-confirmed independently of the
implementing agent's self-report:
- `mix.exs:116` carries `{:ash_postgres, "~> 2.0", only: [:test]}`; `mix.lock` resolves it to
  `ash_postgres 2.12.0` with `ash_sql`, `ecto_sql`, `postgrex` as new lock entries.
- `test/support/ash_postgres_fixture/resources.ex` defines a real
  `AshPostgresFixture.MerchantAccount` on `data_layer: AshPostgres.DataLayer` with an `r2rml`
  block and a `field_policies` block restricting `:secret_key`.
- `test/security_ash_postgres_test.exs` exercises `AshR2RML.Compiler.compile_resources/1`
  end-to-end (not `Security.sanitize_mapping/2` directly) and asserts the `:postgres`-backed
  resource is sanitized while an `:ets`-backed resource in the same compile bundle is not.
- `mix test test/security_ash_postgres_test.exs` → `2 tests, 0 failures` (real re-run output).
- Full suite `mix test --exclude external` → `343 tests, 0 failures`, no regressions.
- `mix compile --warnings-as-errors` and `mix format --check-formatted` both exit 0 on this
  ticket's touched files (`mix.exs`, `mix.lock`, `test/support/ash_postgres_fixture/resources.ex`,
  `test/security_ash_postgres_test.exs`).

- **Type:** Test Coverage / Architecture Gap
- **Priority:** High
- **Component:** `AshR2RML.Security` / `AshR2RML.Compiler.compile_resources/1`
- **Description:**
  `sanitize_mapping/2`'s actual gate (`AshR2RML.DataLayer.backend(ash_resource) == :postgres`, `lib/ash_r2rml/security.ex:41`) has never been exercised end-to-end, because `ash_postgres` is not a dependency of this project (`Code.ensure_loaded?(AshPostgres.DataLayer)` returns `false` in this environment). Today's coverage (`test/obda_in_memory_test.exs`, `"detects field-policy-protected..."` and `"removes field-policy-protected..."`) tests `unenforceable_attributes/2` and `remove_attributes/2` in isolation against a real `Ash.DataLayer.Ets`-backed fixture (`AshR2RML.Fortune5.PaymentGateway`), and separately confirms `sanitize_mapping/2` no-ops on that same `:ets` fixture. The `:postgres` branch of `sanitize_mapping/2` itself — the actual structural fix this module exists to ship — has zero compiled-resource-level test coverage in this repository.
- **Acceptance Criteria:**
  1. Add `ash_postgres` as a `:test`-only dependency (or an equivalent lightweight stand-in that genuinely implements `AshPostgres.DataLayer`'s `Code.ensure_loaded?`/`function_exported?` contract, per this codebase's Chicago-style testing discipline — no mocked data layer).
  2. Add a real `AshPostgres.DataLayer`-backed test resource carrying an explicit `field_policy` on an R2RML-mapped attribute.
  3. Assert `AshR2RML.Compiler.compile_resources/1`'s output mapping bundle has the policied attribute's `predicate_object_map` removed and `mapping.metadata[:field_policy_excluded_attributes]` populated, end-to-end through the real compiler entrypoint rather than by calling `Security.sanitize_mapping/2` directly.

---

### Ticket 2: `R2RML-106` — Distinguish `always()` From Conditional Field Policies in `field_policy_protected?/2`

**Status: WON'T FIX — investigated 2026-08-25, re-verified 2026-08-25.** `lib/ash_r2rml/security.ex`
is confirmed untouched by this ticket (`git log` shows no ticket-attributed edit); `mix compile
--warnings-as-errors` and `mix test --exclude external` (`343 tests, 0 failures`) both re-confirmed
clean against the current tree with `field_policy_protected?/2` left exactly as documented below.

Findings, citing real Ash source read under
`deps/ash/lib/`:

- `Ash.Policy.Info.field_policies_for_field/2` returns `Extension.get_persisted(resource,
  :fields_to_field_policies, %{})[field]` (`deps/ash/lib/ash/policy/info.ex:30-32`) — a list of
  `%Ash.Policy.FieldPolicy{}` structs (`deps/ash/lib/ash/policy/authorizer/transformers/
  cache_field_policies.ex:12-25`), each carrying `:policies` (a list of `%Ash.Policy.Check{}`
  structs: `check_module`, `check_opts`, `type`) and `:condition`
  (`deps/ash/lib/ash/policy/field_policy.ex:5-16`).
- `authorize_if always()` compiles to `check_module: Ash.Policy.Check.Static, check_opts: [result:
  true, ...]` (`deps/ash/lib/ash/policy/check/built_in_checks.ex:23-26`:
  `def always, do: {Ash.Policy.Check.Static, result: true}`). In principle, an unconditional
  field policy could be detected by reading `FieldPolicy.policies` for a single
  `%Check{type: :authorize_if, check_module: Ash.Policy.Check.Static, check_opts: [result: true]}`
  entry and confirming `FieldPolicy.condition` is similarly trivial (`nil` or the same
  `Check.Static true`, per `Ash.Policy.FieldPolicy.transform/1`,
  `deps/ash/lib/ash/policy/field_policy.ex:20-39`).
- No stable, documented public API performs this check for the caller. `Ash.Policy.Info`
  (`deps/ash/lib/ash/policy/info.ex`) exposes no sibling function for it — its full public
  surface was read line-by-line and contains only `field_policies_for_field/2`,
  `field_policies/1`, `policies/2`, `private_fields_policy/1`, `default_access_type/1`,
  `describe_resource/2`, and `strict_check/3`, none of which classify a policy as
  unconditional-vs-conditional. `Ash.Policy.Check` (`deps/ash/lib/ash/policy/check.ex`) is the
  only other candidate module, and every function on it that would perform exactly this kind of
  introspection is explicitly marked `@doc false` by Ash's own maintainers — not merely
  undocumented, but affirmatively marked private/no-compatibility-guarantee: `type/1` (line 275),
  and critically `simplify/3` (line 288, the function that reduces `{Check.Static, opts}` down to
  a plain boolean and is Ash's own mechanism for recognizing a check as a constant — see
  `deps/ash/lib/ash/policy/check/static.ex:17-18`, `@impl true def simplify({__MODULE__,
  options}, _context), do: options[:result]`) are both `@doc false`
  (`deps/ash/lib/ash/policy/check.ex:273-274, 286-287`). Ash's authorizer solver itself
  (`Ash.Policy.Policy.fetch_or_strict_check_fact/2`, `deps/ash/lib/ash/policy/policy.ex:275-276`)
  hardcodes a `{Check.Static, opts}` pattern match as an internal fast path, confirming this
  module name is load-bearing for Ash's own internals — but that is Ash depending on its own
  private representation, not a contract published for consumers to rely on.
- Reading `FieldPolicy.policies` / `Check.check_module` / `Check.check_opts` / `Check.type`
  directly to detect `Ash.Policy.Check.Static` with `result: true` is therefore exactly the
  "internal check AST" inspection the module's existing moduledoc
  (`lib/ash_r2rml/security.ex:23-28`) already identified and declined to do — it is reading the
  same persisted DSL-entity struct shape backing the functions Ash itself marks `@doc false`,
  just via direct field access instead of calling those functions. Ash's semver commitment
  (project constraint `{:ash, "~> 3.0 and >= 3.28.0"}`, `mix.exs:116`) does not cover `@doc
  false` internals, so this shape could change within a 3.x minor/patch release without
  constituting a breaking change from Ash's own point of view.
- Acceptance criterion #1's bar ("a stable, version-independent Ash API... not internal
  check-AST inspection") is not met. Per acceptance criterion #3, closing as `WON'T FIX`;
  `AshR2RML.Security.field_policy_protected?/2` (`lib/ash_r2rml/security.ex:84-89`) is left
  unchanged as the permanent, deliberate design, and its existing moduledoc's rationale
  (`lib/ash_r2rml/security.ex:23-28`) stands confirmed rather than superseded.

- **Type:** Architecture Enhancement / Precision
- **Priority:** Medium
- **Component:** `AshR2RML.Security.field_policy_protected?/2`
- **Description:**
  `field_policy_protected?/2` (`lib/ash_r2rml/security.ex:84-89`) currently flags any attribute with a non-empty `Ash.Policy.Info.field_policies_for_field/2` result, deliberately not distinguishing an unconditionally-granting `authorize_if always()` policy from a genuinely conditional one (documented tradeoff, `lib/ash_r2rml/security.ex:23-28`, confirmed by `test/obda_in_memory_test.exs`'s `"detects field-policy-protected..."` test, which shows the `always()`-policied `:name` attribute on `AshR2RML.Fortune5.PaymentGateway` flagged identically to the conditionally-policied `:secret_key`). This is safe (over-broad, never under-broad) but costs resource authors an avoidable metadata review on every `always()`-policied attribute that happens to also be R2RML-mapped.
- **Acceptance Criteria:**
  1. Investigate whether a stable, version-independent Ash API (not internal check-AST inspection) exists to identify an unconditional `always()` check, across the Ash versions this project supports.
  2. If such an API exists, narrow `field_policy_protected?/2` to exclude only genuinely conditional policies, with a new test proving an `always()`-policied attribute is no longer flagged while a conditional one still is.
  3. If no such stable API exists, close this ticket as `WON'T FIX` with the investigation findings recorded, and leave the current conservative behavior as the permanent, deliberate design.

---

### Ticket 3: `R2RML-107` — Resolve Multi-Column `rr:joinCondition` Relationships in `AshR2RML.OBDA.InMemory`

**Status: CLOSED — re-verified 2026-08-25.** Real evidence, re-confirmed independently:
- `lib/ash_r2rml/obda_in_memory.ex` now resolves any number of `JoinCondition` entries via
  `resolve_reference_object/3` + `resolve_composite_object_iri/3`.
- `test/support/grand_example/resources.ex` defines real `Ash.DataLayer.Ets`-backed
  `AshR2RML.GrandExample.Warehouse` (composite `{region, code}` key) and `Shipment` fixtures.
- `test/obda_in_memory_test.exs` includes `"resolves a composite-key (2-column)
  rr:joinCondition relationship into a real object IRI"` and `":join_table many-to-many
  reference object maps are refused with a typed refusal, not silently skipped"`.
- `mix test test/obda_in_memory_test.exs` → `12 tests, 0 failures` (real re-run output).
- Full suite `mix test --exclude external` → `343 tests, 0 failures`, no regressions.
- `mix compile --warnings-as-errors` and `mix format --check-formatted` both exit 0 on this
  ticket's touched files.

- **Type:** Feature Gap / OBDA Parity
- **Priority:** Medium
- **Component:** `AshR2RML.OBDA.InMemory.add_reference_triples/4`
- **Description:**
  `add_reference_triples/4` (`lib/ash_r2rml/obda_in_memory.ex:262-279`) pattern-matches `%ReferenceObjectMap{joins: [%JoinCondition{child: child, parent: parent}], ...}` — a list of exactly one `JoinCondition`. A `ReferenceObjectMap` whose `joins` list has zero or more-than-one entries (a genuine multi-column composite-key join, or the `:join_table` many-to-many shape which carries `joins: []` per `AshR2RML.SemanticAdapter.convert_references/2`, `lib/ash_r2rml/compiler.ex:604-611`) falls through to the catch-all `_reference, acc -> acc` clause and is silently skipped — the relationship traversal simply does not appear in the materialized graph, with no refusal or log signal that it was dropped. This matches the module's own documented admitted-scope statement (moduledoc, `lib/ash_r2rml/obda_in_memory.ex:26-31`: "single-column joins only... a silently-skipped triple, never a fabricated one") but is not yet resolved for real.
- **Acceptance Criteria:**
  1. Extend `add_reference_triples/4` to resolve `ReferenceObjectMap`s with 2+ `JoinCondition` entries by matching on all column pairs simultaneously (composite-key join), producing the object IRI only when every column pair resolves.
  2. Add a real test with a composite-key `belongs_to` relationship (`Ash.DataLayer.Ets`-backed, real `Ash.create!`/`Ash.read!`) asserting the relationship triple is now present.
  3. For the `:join_table` many-to-many shape specifically, either implement real resolution through the join table's own rows or leave it explicitly refused (typed `Refusal`, not a silent skip) rather than the current unlabeled omission — record the decision in the moduledoc either way.

---


**Status: CLOSED — re-verified 2026-08-25.** Real evidence, re-confirmed independently:
- `mix compile --force --warnings-as-errors` → exit 0, zero warnings (the previously-noted
  `ocel_v2.ex:610` warning is also gone from the current tree, confirmed by a fresh forced
  recompile, not carried over from a stale build cache).
- Full suite `mix test --exclude external` → `343 tests, 0 failures`.

- **Type:** Technical Debt / Dependency Hygiene
- **Priority:** Low
- **Component:** `mix.lock` / `deps/`
- **Description:**
- **Acceptance Criteria:**
  3. Re-run `mix deps.get && mix compile --warnings-as-errors` and confirm a clean compile with no new warnings introduced by the lockfile change.
