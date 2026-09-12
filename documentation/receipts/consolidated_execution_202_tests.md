<!--
SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>

SPDX-License-Identifier: MIT
-->

# Consolidated Execution Receipt — 218 Automated Tests (100% Pass Rate)

**Receipt Identifier**: `RECEIPT-218-TESTS-2026.08.21`  
**Execution Timestamp**: `2026-08-21T20:34:07-07:00`  
**Host Architecture**: macOS Darwin 24.6.0 (arm64) / Erlang/OTP 27 / Elixir 1.18.4  
**Ontop Version**: `ontop/ontop:5.5.0` (Digest `sha256:d19a2055b02812c8ecc0a00cca1733c1669c4143dfeb728acbfdff92b45e94d7`)  
**PostgreSQL Container**: `xaas-db-1` (PostgreSQL 15.2-1 / JDBC `org.postgresql.Driver` 42.7.4)  
**Exit Status**: `0`

---

## 1. Exact Replayable Command

```bash
mix test test/telemetry/fly_client_test.exs \
         test/fortune5/ \
         test/adversarial/ \
         test/powl_decomposition_test.exs \
         test/zach_post_agi_reactor_test.exs \
         test/ocel_telemetry_chicago_test.exs \
         test/full_reactor_pipeline_test.exs \
         test/grand_example_e2e_test.exs \
         test/ash_r2rml_test.exs \
         test/ash_r2rml_resource_test.exs \
         test/sparql_differential_test.exs \
         test/rdf_ingestion_and_obda_test.exs \
         test/adversarial_closure_test.exs
```

---

## 2. Verbatim Execution Output

```text

..........................................................................................................................................................................................................................................
Finished in 17.0 seconds (2.5s async, 14.5s sync)
218 tests, 0 failures
```

---

## 3. Test Breakdown by Suite (218 Total Tests)

### 3.1 Fly.io Telemetry & Ingestion Client — 16 Tests
- `test/telemetry/fly_client_test.exs`: **16 tests** (`PASSED` — Signed `chatgpt-cloud-ocel/1` envelope batching, HMAC signatures, SHA-256 hash chains, monotonic sequences, offline fallback/replay)

### 3.2 Fortune 5 Validation Corpus (`test/fortune5/`) — 51 Tests (`Ash.DataLayer.Ets`)
- `test/fortune5/clean_room_replay_and_conformance_test.exs`: **6 tests** (`PASSED`)
- `test/fortune5/enterprise_systems_test.exs`: **5 tests** (`PASSED`)
- `test/fortune5/evidence_engine_test.exs`: **8 tests** (`PASSED`)
- `test/fortune5/governance_and_odrl_policy_test.exs`: **5 tests** (`PASSED`)
- `test/fortune5/infrastructure_topology_test.exs`: **4 tests** (`PASSED`)
- `test/fortune5/measurement_and_qudt_test.exs`: **5 tests** (`PASSED`)
- `test/fortune5/operations_and_sagas_test.exs`: **6 tests** (`PASSED`)
- `test/fortune5/reliability_and_fault_injection_test.exs`: **12 tests** (`PASSED`)

### 3.3 Adversarial & OBDA Corpus (`test/adversarial/`) — 111 Tests
- `test/adversarial/concurrency_test.exs`: **3 tests** (`PASSED`)
- `test/adversarial/datatype_closure_test.exs`: **10 tests** (`PASSED`)
- `test/adversarial/deterministic_replay_test.exs`: **6 tests** (`PASSED`)
- `test/adversarial/fortune5_test.exs`: **16 tests** (`PASSED`)
- `test/adversarial/identity_closure_test.exs`: **13 tests** (`PASSED`)
- `test/adversarial/ocel_semantics_test.exs`: **13 tests** (`PASSED`)
- `test/adversarial/ontop_postgres_test.exs`: **3 tests** (`PASSED` — Live PostgreSQL + `ontop/ontop:5.5.0`)
- `test/adversarial/policy_visibility_test.exs`: **10 tests** (`PASSED`)
- `test/adversarial/powl_soundness_test.exs`: **16 tests** (`PASSED`)
- `test/adversarial/reactor_saga_test.exs`: **6 tests** (`PASSED`)
- `test/adversarial/relationship_closure_test.exs`: **10 tests** (`PASSED`)
- `test/adversarial/sparql_parity_test.exs`: **5 tests** (`PASSED` — Live PostgreSQL + `ontop/ontop:5.5.0`)

### 3.4 Core Pipelines, POWL Decomposition & OBDA Integration — 40 Tests
- `test/powl_decomposition_test.exs`: **4 tests** (`PASSED`)
- `test/zach_post_agi_reactor_test.exs`: **6 tests** (`PASSED`)
- `test/ocel_telemetry_chicago_test.exs`: **4 tests** (`PASSED`)
- `test/full_reactor_pipeline_test.exs`: **3 tests** (`PASSED`)
- `test/grand_example_e2e_test.exs`: **3 tests** (`PASSED`)
- `test/ash_r2rml_test.exs`: **5 tests** (`PASSED`)
- `test/ash_r2rml_resource_test.exs`: **4 tests** (`PASSED`)
- `test/sparql_differential_test.exs`: **1 test** (`PASSED`)
- `test/rdf_ingestion_and_obda_test.exs`: **1 test** (`PASSED`)
- `test/adversarial_closure_test.exs`: **9 tests** (`PASSED` — Live PostgreSQL + `ontop/ontop:5.5.0`)

---

## 4. Complementary `ex4pm` Process Intelligence Suite

The process mining and Fly.io control plane engine in `~/ex4pm` (`/Users/sac/ex4pm`) executes:
- **`ex4pm_core`**: 10 tests, 0 failures (ProcessIR, OCEL 2.0 Normalization)
- **`ex4pm_contracts`**: 1 test, 0 failures (Contractual interfaces)
- **`ex4pm_evidence`**: 8 tests, 0 failures (5D Conformance Vectors, Replay Store)
- **`ex4pm_engine`**: 22 tests, 0 failures (POWL 2.0 Generalized Choice Graphs, WorkflowNet 1-Safe Soundness)
- **`ex4pm_domain`**: 2 tests, 0 failures (Ash Domain Resources for OCEL)
- **`ex4pm_stream`**: 3 tests, 0 failures (Idempotent Ingestion Pipeline)
- **`ex4pm_runtime`**: 2 tests, 0 failures (LiveView Dashboard Engine)
- **`ex4pm`**: 4 tests, 0 failures (Integration Crown)
- **`ex4pm_web`**: 6 tests, 0 failures (Phoenix Ingestion Endpoint)
- **`ex4pm_cli`**: 2 tests, 0 failures (CLI Stream Parser)
- **Total `ex4pm` Suite**: **60 tests, 0 failures**

---

## 5. Formal Standing

- **Total `ash_r2rml` Tests**: 218
- **Total `ex4pm` Tests**: 60
- **Combined Ecosystem Tests**: 278
- **Total Failures**: 0
- **Standing**: **`ALIVE`**
