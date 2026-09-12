<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
SPDX-License-Identifier: MIT
-->

# R84 GGEN fanout receipt

## Exact subjects

- Consumer base: `seanchatmangpt/ash_r2rml@263aa768bbc5a933124409ee68f2b9efb9d09a3a`
- Canonical factory: `seanchatmangpt/ggen-marketplace@6b7fb4af7b4ef3a6330ad61ca833b98902300332`
- Canonical pack: `packs/ash-reactor-domain-error-contract-pack`

## Admitted correspondence

AshR2RML already owns a native Reactor boundary. `CompileResources.run/3` returns the compiler result directly and `compensate/4` treats `%AshR2RML.Refusal{}` as typed, fail-closed, and non-retryable. R84 therefore composes with the existing path; no parallel normalizer is introduced in this consumer.

The consumer court falsifies two failure classes:

1. a compiler refusal is collapsed into a generic Reactor execution envelope;
2. a typed refusal is treated as a transient retryable error during compensation.

## Authority and generated status

- SELECT: canonical R84 pack already exists upstream.
- CONSTRUCT: this branch adds a consumer-owned court and qualification rail.
- DO: false. No external or runtime actuation is introduced.
- Generated outputs edited: none.
- Handwritten irreducible substrate: only the repository-native ExUnit consumer court and GitHub qualification adapter; reusable semantic law remains owned by the canonical GGEN pack.

## Standing

`PARTIAL_ALIVE` until the exact PR head executes the dedicated R84 consumer court. A workflow definition, source inspection, or upstream pack merge is not sufficient to promote the consumer to ALIVE.
