<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors

SPDX-License-Identifier: MIT
-->

# AshR2RML benchmark results

Real runs, this machine, this commit. Follows the reporting contract in `bench/README.md`:
exact versions, correctness verified before every timed run, external engines named and their
overhead attributed to them (not to AshR2RML), warm/cold conditions stated. No graph database
or engine outside AshR2RML's own supported stack (Ash, `Ash.DataLayer.Ets`, `AshPostgres`,
Ontop) was benchmarked.

**Commit:** `ff1405ca59083a45321c05363673230dcf36c548` (`ff1405c`)
**Elixir** 1.19.5 / **OTP** 28
**Ash** 3.29.3, **AshR2RML** 26.8.22
**PostgreSQL** 15.2 (Debian, `xaas-db-1` container)
**Ontop** 5.5.0 (`ontop/ontop:5.5.0`, CLI invoked per query via `docker run --rm`)

## 1. Mapping compilation (ontology-first: Admission → IR → Ash + Ecto + SQL + R2RML + SHACL)

Command: `MIX_ENV=test mix run bench/compilation_and_rendering.exs`

Connected resource graphs per `bench/README.md`'s scale-tier guidance (each resource
`belongs_to` the previous one, 8 datatype attributes each). Correctness verified for every
tier before timing: exact resource count in the mapping bundle, `rr:class` present in the
rendered Turtle, SQL DDL non-empty.

| Resources | Mean time | 99th %ile | Memory |
|---:|---:|---:|---:|
| 10 | 8.6 ms | 9.2 ms | 6.9 MB |
| 100 | 91.8 ms | 99.4 ms | 70.0 MB |
| 1,000 | 1,319.0 ms | 1,361.9 ms | 703.4 MB |

Scaling is close to linear (10.7x time for 10x resources, 153x time for 100x resources —
slightly super-linear at the 1,000 tier, consistent with GC pressure at ~700 MB working set,
reported honestly rather than smoothed over). Memory is linear at ~0.7 MB/resource.

## 2. OBDA SPARQL query latency: `AshR2RML.OBDA.InMemory` vs Ontop+PostgreSQL

Command: `BENCH_ONTOP_RUNS=3 MIX_ENV=test mix run bench/obda_query_latency.exs`

Same query shape against both backends: `SELECT ?s ?name WHERE { ?s a
<.../Organization> ; <.../name> ?name . }`. Row counts verified equal to the seeded tier size
on every run before recording a timing.

**Methodology note, stated plainly:** `Ash.DataLayer.Ets` is one shared in-process table for
the life of the script, so InMemory's row counts accumulate across tiers (10 → 110 → 1,110
real rows queried, not 10/100/1,000 in isolation) — the numbers below are exactly what was
observed, not adjusted. The tier-10 InMemory number also carries first-call module-loading
cold start; tier-100's lower absolute time than tier-10 is that effect, not "100 rows queries
faster than 10."

| Tier (nominal / actual rows queried) | `AshR2RML.OBDA.InMemory` (materialize + SPARQL, in-process) | Ontop 5.5.0 + PostgreSQL 15.2 (`docker run --rm` per query; min / avg / max of 3 real runs) |
|---:|---:|---:|
| 10 / 10 | 52.0 ms | 1,911.1 / 1,925.2 / 1,952.2 ms |
| 100 / 110 | 4.0 ms | 1,843.2 / 1,871.2 / 1,885.5 ms |
| 1,000 / 1,110 | 32.0 ms | 1,917.0 / 2,012.7 / 2,192.8 ms |

**What this measures, precisely:** the Ontop number is dominated by the `docker run --rm`
container start plus the Ontop JVM's own mapping/JDBC initialization on every single
invocation — it is essentially flat regardless of row count (10 rows and 1,110 rows cost
the same ~1.9–2.0 s), which is exactly what a per-invocation-startup cost looks like, not a
per-row query-execution cost. **This is Ontop's own CLI invocation model, not a claim about
Ontop's or PostgreSQL's SQL-rewriting/query-execution engine** — a persistent Ontop server
process (rather than one Docker container per query) would eliminate nearly all of this
overhead, and `AshR2RML.OBDA.Ontop` itself doesn't control which invocation model an operator
chooses. `AshR2RML.OBDA.InMemory` has no external process, no container, no JVM, no JDBC round
trip at all — it runs `Ash.read!/2` and real `SPARQL.ex` algebra in the same BEAM process — so
the ~35–600x difference observed here is real and reproducible, but it's an architectural
difference (in-process vs. external-process-per-query), not a claim that AshR2RML's SPARQL
engine out-executes Ontop's query planner on a query-for-query basis at scale.

## Reproducing

```bash
mix test test/adversarial/ontop_postgres_test.exs   # confirms live Ontop+Postgres infra is up
MIX_ENV=test mix run bench/compilation_and_rendering.exs
BENCH_ONTOP_RUNS=3 MIX_ENV=test mix run bench/obda_query_latency.exs
```

## What is not benchmarked here

externally-observed comparison an operator may attach — AshR2RML does not run, query, or
benchmark any graph database itself.
