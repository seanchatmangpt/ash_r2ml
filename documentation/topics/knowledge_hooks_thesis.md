<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# Knowledge Hooks: accumulated executable knowledge

## Status

This document is the normative architectural thesis for Knowledge Hooks in AshR2RML. The executable law is the Elixir implementation plus `priv/ontology/knowledge-hooks.ttl` and `priv/shapes/knowledge-hooks.shacl.ttl`. Prose never grants authority.

## Thesis

An intelligent system should not repeatedly spend general cognition on a bounded distinction it has already learned how to make reliably.

A Knowledge Hook is the artifact produced when repeated semantic cognition has been reduced to an admitted deterministic observation law:

\[
h : (O^*, E^*, S) \rightharpoonup (C, R_h)
\]

`O*` is admitted observation, `E*` is an admitted trigger witness, `S` is relevant semantic state, `C` is a constructed consequence description, and `R_h` is the hook evaluation receipt.

A Knowledge Hook does **not** perform consequential DO. External consequence remains a separate transition:

\[
C \xrightarrow{authority\ admission} DO \xrightarrow{independent\ observation} R_{do}
\]

Therefore:

\[
R_h \not\Rightarrow R_{do}
\]

and:

\[
semantic\ certainty \not\Rightarrow authority
\]

## Historical lineage

The implementation is a convergence, not a new disconnected hook system.

1. **UNRDF** established reactive semantic graph operations and low-level hook/validation/transform foundations.
2. **GitVan** made the primitive explicit as `h=(e, phi, a)`: an event plus a semantic predicate selects a consequence.
3. **KNHK** developed the bounded-reflex interpretation, with orchestration patterns and receipt-bearing execution.
4. **ggen / Graphlaw** moved the source of truth toward RDF law compiled through admission, condition IR, dependency scheduling, effects, and receipts.
5. **AutoFDE Lab** made repeated cognition promotable only after positive evidence, falsifiers, replay, postcondition verification, and envelope closure.
6. **AutoFDE** made the authority boundary durable: semantic deltas may manufacture `CONSTRUCT` intents while `do_authority=0` remains mechanically preserved.
7. **AshR2RML** closes the loop around one operational subject exposed lawfully through Ash, SQL, and SPARQL.

The historical `a` in `h=(e, phi, a)` must therefore be interpreted in the mature system as a **construction**, not ambient actuation.

## Canonical model

Every admitted hook converges on the following semantic object:

\[
H = \langle
id,
provenance,
trigger,
observation,
predicate,
construct,
dependencies,
receipt,
authority\_ceiling
\rangle
\]

In AshR2RML this is represented by `AshR2RML.KnowledgeHook.Spec`.

The authority ceiling is invariant:

\[
\alpha(H) \leq CONSTRUCT
\]

Internal normalization, compilation, scheduling, observation, predicate evaluation, and construction may never increase that authority:

\[
\alpha(f(x)) \leq \alpha(x)
\]

unless `f` is an explicitly separate external authority-admission boundary.

No number of agreeing hooks, no ontology assertion, no SHACL conformance result, no SPARQL match, no model confidence, and no generated Reactor module name creates DO authority.

## Why AshR2RML

AshR2RML keeps PostgreSQL or another Ash data layer as operational state while R2RML exposes a semantic projection of that same admitted subject.

The topology is:

```text
Ash / relational operational state
              |
              v
       admitted R2RML
              |
              v
        virtual RDF
              |
              v
      Knowledge Hook
              |
              v
 deterministic receipt
              |
              v
    unauthorized intent
              |
              v
 external authority admission
              |
              v
       Ash / Reactor
              |
              v
 independently verified consequence
```

This avoids a second graph database becoming a competing operational truth merely to enable semantic behavior.

R2RML and Knowledge Hooks remain separate. R2RML answers how relational state is interpreted as RDF. A Knowledge Hook answers what inert construction follows from an admitted semantic observation.

## Trigger law

A trigger specification is not evidence that a trigger occurred.

\[
claimed(e) \neq observed(e)
\]

Event, interval, and RDF-change hooks therefore require an observed trigger receipt before evaluation. A timer definition does not create scheduler authority. An event IRI does not prove the event occurred.

## Observation projection

Hooks should observe the minimum semantic state required for their distinction:

\[
Obs_h(S) \subseteq S
\]

R2RML/SPARQL gives this boundary a standards-based representation. Reducing ambient observation reduces both authority ambiguity and the domain over which equivalence must be proven.

## Downstream targets are data

A Knowledge Hook may construct an inert target describing possible downstream work:

- Reactor orchestration,
- Ash action,
- AshStateMachine transition,
- Oban/AshOban-compatible job description,
- workflow,
- pipeline,
- opaque target.

These values are **not calls**. `AshR2RML.KnowledgeHook.Target` contains no runner. The presence of a module name, action name, transition, worker, schedule, or pipeline identifier does not invoke anything.

Reactor owns process orchestration. Ash owns domain behavior and authorization. StateMachine owns admitted transitions. Oban/AshOban owns scheduling. BRCE or an equivalent explicit downstream authority boundary decides whether an inert intent may cross into consequential DO.

## Dependency law

Hook composition is represented as visible semantic dependency data, not hidden callback flow.

For hooks `h1` and `h2`:

\[
h_1 : O^* \rightarrow C_1
\]

and, when `C1` is an admitted dependency of `h2`:

\[
h_2 : (O^* \cup C_1) \rightarrow C_2
\]

`AshR2RML.KnowledgeHook.Scheduler` provides deterministic topological ordering with stable lexical tie-breaking. Missing dependencies and cycles are typed refusals. Scheduling orders evaluation; it does not execute constructed intents.

## Promotion: cognition to reflex

General cognition is appropriate while a semantic region remains unresolved. Stable repeated distinctions should eventually be compiled out of cognition.

```text
UNKNOWN
  -> EXPLORE
  -> observed episodes
  -> positive evidence + falsifiers
  -> replay/postcondition closure
  -> promotion candidate
  -> deterministic reflex candidate
```

Promotion requires an exact subject/scope/policy/verifier envelope. Positive evidence alone is insufficient; explicit falsifier evidence is required. Every admitted evidence item must be observed, have `ALIVE` standing, and carry verified replay and postcondition identity.

For a candidate hook `h`:

\[
Promote(h) \iff P(h) \land F(h) \land B(h) \land V(h)
\]

where `P` is positive evidence, `F` is falsifier evidence, `B` is bounded-envelope identity, and `V` is verifier/replay closure.

Promotion still preserves:

\[
authority = UNAUTHORIZED
\]

A promoted candidate may manufacture a powerless BRCE request. It may not execute that request.

Reflex-class promotion additionally requires an explicit compensation description. If a bounded reflex cannot name its compensation/fallback path, it remains outside the fast path.

## Cognition elimination

One useful maturity metric is the cognition-elimination rate:

\[
CER = 1 - \frac{C_{current}}{C_{initial}}
\]

where `C` is the number of episodes in a bounded class that still require general cognition.

`CER=0` means no structural learning occurred. `CER` approaching `1` means repeated decisions have been compiled into deterministic mechanisms. This metric does not imply that all reality should become reflexive; it measures closure only inside a declared bounded class.

## Receipts

A Knowledge Hook evaluation receipt should bind the exact plan/hook identity, predicate identity, observation identities, trigger receipt when applicable, match result, and constructed consequence identity.

An actuation receipt is a different artifact. It must bind authority, actuator, requested consequence, observed external effect, and verification/replay identity.

An evaluation receipt cannot be upgraded into a consequence receipt by naming it differently.

## Machine-readable law

The canonical vocabulary lives at:

```text
priv/ontology/knowledge-hooks.ttl
```

Its operational SHACL closure lives at:

```text
priv/shapes/knowledge-hooks.shacl.ttl
```

The SHACL law requires a hook to carry exactly one trigger, observation, predicate, construct, and receipt policy, fixes the authority ceiling to `CONSTRUCT`, and requires evaluation, actuation, and consequence receipts. The shapes are intentionally closed around the admitted vocabulary.

## Falsifiers

The architecture is falsified if any of the following becomes possible inside the Knowledge Hook evaluator:

1. A hook directly invokes arbitrary application code.
2. RDF/ontology membership creates authority.
3. An external trigger fires without observed trigger evidence.
4. A Reactor target executes merely because a predicate matched.
5. A StateMachine transition occurs by direct field mutation from a hook.
6. A scheduler definition creates timer/job authority.
7. A generated plan is reported as executed work.
8. A semantic evaluation receipt is reported as an external consequence receipt.
9. Unsupported historical hook semantics are approximated instead of refused.
10. A promotion candidate acquires authority from evidence volume.
11. Dependency cycles are hidden in callback control flow instead of refused or given explicit fixpoint semantics.
12. A stable bounded distinction continues to invoke general cognition only because the architecture failed to compile the learned rule.

## AGI instruction

For an AGI using this library:

1. Explore broadly while the semantic distinction is genuinely unknown.
2. Identify repeated stable structure.
3. Bound the minimum required observations.
4. State the deterministic predicate.
5. State only the construction that follows without authority.
6. Define falsifiers before promotion.
7. Gather observed replayable evidence.
8. Compile the distinction into canonical Knowledge Hook IR.
9. Preserve the `CONSTRUCT` authority ceiling.
10. Stop spending general cognition on that bounded distinction.

The desired evolution is:

\[
UNKNOWN \rightarrow KNOWN \rightarrow STRUCTURED \rightarrow FORMAL \rightarrow COMPILED \rightarrow VERIFIED \rightarrow REFLEX
\]

The purpose of Knowledge Hooks is therefore not to make every system event-driven. It is to turn repeated correct semantic reasoning into accumulated deterministic knowledge while keeping the distinction between **knowing what should follow** and **being authorized to make it happen** mechanically explicit.
