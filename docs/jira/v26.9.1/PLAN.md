# v26.9.1 Jira Plan — ash_r2rml

## Charter / Define

Real branch activity in the 24h window since 2026-08-31 shows exactly one branch with a
new commit: `origin/dev`, at `a92ab46` ("release(v26.8.26): close sensitive-attribute
plaintext leak in OBDA.InMemory (R2RML-109)"). `main` last moved on 2026-08-28
(`585972d`, v26.8.29). The `dev` branch is therefore the active integration line for
security/release work right now, running ahead of `main` in its own release-numbering
track (dev is mid v26.8.26 while main is already at v26.8.29 — the two lines have
diverged release-number sequencing, not just content).

The v26.9.1 workstream charter, grounded in what these commits and branch names
actually say:

1. Close out the R2RML-109 sensitive-attribute leak fix on `dev` and reconcile it
   forward into `main`, since `main` has already moved past `dev` on version numbering
   (v26.8.29 vs v26.8.26) without absorbing this security fix.
2. Resolve the backlog of `ws5`/`project2`/`ws2`/`ws4`/`tps` short-lived guard and sync
   branches (test guards, ggen-sync receipts, runtime hardening) that were active
   2026-08-27/28 and never merged — several look like duplicate/competing attempts at
   the same goal (three `ws2/compose-50*` branches, two `ws5-project2-paas-fanout-r9*`
   branches with identical commit messages).
3. Decide fate of the `feat/*` exploratory branches from 2026-08-21/22 (DfCM semantic
   execution/evidence/closure work) — these predate the active window and are stale
   relative to both `main` and `dev`.

Scope: branch triage and a merge/consolidation plan only. This document does not
perform merges; it defines the plan for a follow-up Implement pass.

## Measure — current state (real `git log`/`git branch -a`)

Verified via `git clone` of `https://github.com/seanchatmangpt/ash_r2rml.git`,
`git branch -a`, and `git log --format='%h %ai %s'` per branch on 2026-09-01.

Merge-base of `dev` and `main`: `c7763b2e0a5977dba87dc370ac25cea921ab0ddd`.

### Active in the last 24h (since 2026-08-31)

| Branch | Latest SHA | Latest commit date | Latest commit message |
|---|---|---|---|
| `origin/dev` | `a92ab461f989af5eb95191ea65f942903d3e3d1a` | 2026-08-31 21:56:50 -0700 | release(v26.8.26): close sensitive-attribute plaintext leak in OBDA.InMemory (R2RML-109) |

No other remote branch has a commit dated on or after 2026-08-31. This directly
contradicts a blanket "dev branch active" hint taken at face value in the sense that
only `dev` — no other branch — qualifies; it is confirmed correct as the single
active branch, not merely assumed.

### All remote branches, most recent commit first

| Branch | SHA | Date | Message |
|---|---|---|---|
| `origin/dev` | `a92ab46` | 2026-08-31 21:56:50 -0700 | release(v26.8.26): close sensitive-attribute plaintext leak in OBDA.InMemory (R2RML-109) |
| `origin/main` | `585972d` | 2026-08-28 17:20:38 -0700 | release(v26.8.29): xsd:duration datatype mapping (Ash.Type.Duration) |
| `origin/tps/ws1-ggen-sync-orthogonal-20260828-01` | `8829cc2` | 2026-08-28 01:47:40 -0700 | feat(ggen-sync): realize provenance migration receipt plan |
| `origin/tps/ws1-ggen-sync-c779aec-20260828-01` | `5148ddb` | 2026-08-28 01:20:35 -0700 | chore(ggen-sync): realize option-capital frontier |
| `origin/tps/ws1-forcedtop25-sync-20260828-00` | `da43311` | 2026-08-27 22:22:10 -0700 | fix(test): apply the same linked-Agent flake fix to reactor_saga_test.exs |
| `origin/errc/ash-extension-core-pack-installer-and-pack-name-fix` | `604cc1e` | 2026-08-27 22:03:34 -0700 | release(v26.8.27): Gno-inspired OBDA adapter/changeset abstractions, installer --target fix |
| `origin/project2/ws5-learning-20260827-21c` | `837c797` | 2026-08-27 21:46:18 -0700 | fix: make test-support guard delimiter-safe |
| `origin/ws2/compose-50-20260827-2008` | `60b3d61` | 2026-08-27 20:13:36 -0700 | test(paas): guard default branch identity |
| `origin/ws2/compose-50c-20260827-2008` | `376b043` | 2026-08-27 20:13:27 -0700 | test(paas): guard exact head identity |
| `origin/ws2/compose-50b-20260827-2008` | `060543c` | 2026-08-27 20:13:20 -0700 | test(paas): guard branch identity |
| `origin/project2/ws5-learning-20260828-00` | `5ff5a57` | 2026-08-27 20:05:20 -0700 | test: guard Elixir compatibility floor |
| `origin/project2/ws5-learning-20260827b` | `06d8c7b` | 2026-08-27 18:54:41 -0700 | test: guard priv semantic artifact packaging |
| `origin/ws5-runtime-hardening-r10` | `1f8f630` | 2026-08-27 15:17:38 -0700 | test(paas): refuse vacuous Ash/Reactor guard graphs |
| `origin/ws5-project2-paas-fanout-r9-rebased` | `f4c403a` | 2026-08-27 14:01:19 -0700 | feat(ggen): add AshR2RML PaaS consumer manifest |
| `origin/ws5-project2-paas-fanout-r9` | `4779740` | 2026-08-27 13:59:34 -0700 | feat(ggen): add AshR2RML PaaS consumer manifest |
| `origin/ws4/close-runtime-integration-20260828` | `01cbdd2` | 2026-08-27 13:48:27 -0700 | fix(ci): license runtime contract crown |
| `origin/workstation3/runtime-consumer-20260827` | `5fc9a70` | 2026-08-27 12:57:26 -0700 | test(runtime): qualify full marketplace runtime admission |
| `origin/ws5-project2-lineage-hardening` | `d332f74` | 2026-08-27 12:07:03 -0700 | fix(reuse): classify ggen source artifacts |
| `origin/fanout/r88-ggen-consumer-contract` | `c4eb80d` | 2026-08-26 11:01:39 -0700 | fix(ci): bind R88 court to exact consumer head |
| `origin/automation/fanout-r84-ash-r2rml-20260826` | `e8de8bb` | 2026-08-26 10:45:08 -0700 | fix(r84): declare receipt REUSE provenance |
| `origin/release/v26.8.26` | `62c3138` | 2026-08-25 22:27:47 -0700 | chore(deps): lock ash_cloak regression dependency |
| `origin/fix/fortune5-warnings-as-errors-20260825` | `a14b08d` | 2026-08-25 11:02:38 -0700 | test(type): falsify non-overridable lexical decoder regressions |
| `origin/docs/refresh-agents-20260823` | `d7f8269` | 2026-08-23 10:42:30 -0700 | docs: rebuild agent operating contract |
| `origin/feat/dfcm-semantic-types-v26-8-22` | `effb5ba` | 2026-08-22 16:52:07 -0700 | ci(reuse): cancel superseded compliance runs |
| `origin/feat/chatgpt-cloud-execution-contract` | `e812c36` | 2026-08-21 18:32:09 -0700 | ci(observe): relay exact-head qualification as OCEL |
| `origin/measure/receipt-integrity` | `28abd7a` | 2026-08-21 18:14:52 -0700 | test(measure): falsify contradictory and stale receipts |
| `origin/feat/explore-storage-candidate-probes` | `0dcfab8` | 2026-08-21 17:22:15 -0700 | feat(dfcm): add storage candidate experiment probes |
| `origin/feat/explore-dfcm-candidate-set-admission` | `7de83fd` | 2026-08-21 16:21:25 -0700 | test(dfcm): falsify candidate-set narrowing and replay |
| `origin/feat/replayable-semantic-evidence` | `1235025` | 2026-08-21 15:47:02 -0700 | fix(provenance): project validated semantics explicitly |
| `origin/feat/fortune5-dfcm-production-closure` | `c3d2d38` | 2026-08-21 15:33:47 -0700 | fix(production): repair clean compile and enforce ggen projection boundary |
| `origin/feat/adversarial-semantic-closure-v26-8-21` | `df4750b` | 2026-08-21 15:29:43 -0700 | merge(main): admit concurrent adversarial closure before residual fixes |
| `origin/feat/replayable-semantic-evidence-check` | `2b291c9` | 2026-08-21 15:43:25 -0700 | feat(evidence): make semantic executions causally replayable |
| `origin/feat/ontop-5-5-compliance-crown` | `2e7068b` | 2026-08-21 14:35:09 -0700 | fix: remove unreachable refusal clause |
| `origin/feat/dfcm-semantic-execution-integrity` | `db6d76e` | 2026-08-21 14:18:11 -0700 | fix(ci): bind cache to Erlang and Elixir toolchain |
| `origin/feat/ash-emitted-ggen-ttl` | `741768f` | 2026-08-21 13:28:54 -0700 | chore(ggen): declare Ash-emitted TTL pack contract |

`dev`'s last 15 commits show a recent internal-integration pattern (multiple
`integrate: <workstream-branch>` merge commits on 2026-08-28, plus `test(ws5): guard *`
commits on 2026-08-27) preceding the 2026-08-31 security fix — `dev` has been actively
absorbing the `ws5`/`ws2` guard branches already, which the "Explore" section below
treats as evidence, not assumption.

## Explore — options implied by branch names and history

1. **`dev`-as-integration-branch model (supported by evidence).** `dev`'s own log
   already shows `integrate: project2/ws5-learning-20260828-c04-ash-r2rml`,
   `integrate: release/v26.8.22-integration`, and `integrate: ws2-contract-guards-
   20260827-2017` merge commits. This confirms `dev` is being used as a rolling
   integration branch for the `ws2`/`ws5`/`project2` short-lived guard branches, not a
   parallel release line competing with `main`. Option: continue this pattern —
   `dev` keeps absorbing workstream branches, then periodically fast-forwards or
   merges into `main` at a stable point.

2. **Triplicate `ws2/compose-50*` branches (`compose-50`, `compose-50b`, `compose-50c`)
   — three near-identical branch-identity guard tests within the same 16-second
   window (20:13:20 to 20:13:36).** These are almost certainly the same fanout attempt
   run three times (retry/backoff pattern common in this repo's `automation`/`fanout`
   naming). Option A: keep only the most complete one (`compose-50` has the latest
   timestamp and the most generic guard name) and delete the other two once verified
   identical in content. Option B: diff all three before discarding, in case they
   guard different branch-identity edge cases despite similar messages.

3. **Duplicate `ws5-project2-paas-fanout-r9` and `-rebased` branches with the identical
   commit message "feat(ggen): add AshR2RML PaaS consumer manifest."** The `-rebased`
   variant is 2 minutes newer (14:01:19 vs 13:59:34) — standard rebase-and-resubmit
   pattern. Option: keep `-rebased` as canonical, close/delete the original once
   confirmed as a strict rebase (same tree, different base).

4. **Stale `feat/*` DfCM branches from 2026-08-21/22** (semantic execution integrity,
   replayable evidence, adversarial closure, ontop-5-5 compliance, fortune5 production
   closure, storage candidate probes, candidate-set admission) predate the active
   window by 9-10 days and predate even `main`'s last move. Option A: these were
   superseded by the `release/v26.8.26`-`v26.8.29` train and can be archived/deleted.
   Option B: cherry-pick any DfCM invariants not yet present on `main`/`dev` before
   deleting, since `dfcm-methodology` per `~/.claude/rules/dmedi-methodology.md` treats
   unmerged Explore-phase work as a real, inspectable artifact, not disposable scratch.

5. **`docs/refresh-agents-20260823`** is a documentation-only branch, isolated from the
   code workstreams — low-risk, can merge independently of any other decision above.

## Develop — concrete next engineering steps per branch/workstream

### R2RML-109 security fix (`dev` HEAD, `a92ab46`)
- Verify the fix's test coverage: locate and run the OBDA.InMemory sensitive-attribute
  test(s) added or touched by this commit.
- Confirm no other adapter (besides InMemory) has the same plaintext-leak pattern;
  grep the OBDA adapter modules for equivalent sensitive-attribute handling.
- Prepare a `dev` -> `main` reconciliation: since `main` is numerically ahead
  (v26.8.29) but missing this fix, the merge must be a genuine three-way merge from
  the `c7763b2e` merge-base, not a fast-forward, and must not silently overwrite
  `main`'s v26.8.27-v26.8.29 work.

### `ws2/compose-50*` triplicate branches
- `git diff origin/ws2/compose-50-20260827-2008 origin/ws2/compose-50b-20260827-2008`
  and against `compose-50c` to confirm they are true duplicates before discarding any.
- If duplicates confirmed, keep `compose-50` (newest), close the other two.

### `ws5-project2-paas-fanout-r9` / `-rebased`
- `git diff` the two trees; if identical modulo base, retain `-rebased` and close the
  original.

### Stale `feat/*` DfCM branches (2026-08-21/22)
- For each, `git log --format=%s <branch> ^main` to list commits not already on
  `main`/`dev`.
- Flag any commit touching `lib/ash_r2rml/dfcm/` or `priv/ggen/` for a targeted
  cherry-pick review rather than a blanket merge or blanket discard.

### `docs/refresh-agents-20260823`
- Diff against current `main` docs; if still accurate, merge directly (docs-only,
  lowest risk in the backlog).

## Implement — merge order, verification gates, rollout/monitoring

### Merge order (most urgent / lowest-risk first)

1. `docs/refresh-agents-20260823` -> `main` (docs-only, no code risk).
2. `dev` (`a92ab46`, R2RML-109 fix) -> `main`, as a real three-way merge from
   `c7763b2e`. This is the highest-priority code merge since it closes a security
   leak that `main` does not yet have.
3. Resolved `ws2/compose-50*` (single retained branch) -> `dev` (continuing the
   existing `dev`-as-integration-branch pattern observed in its own log).
4. Resolved `ws5-project2-paas-fanout-r9-rebased` -> `dev`.
5. Cherry-picked DfCM fragments from stale `feat/*` branches (only what Develop-phase
   review flags as not-yet-present) -> `dev`, then `dev` -> `main` at the next
   integration point.
6. Delete/archive branches confirmed as pure duplicates only after their diff-review
   step above is recorded (never delete on assumption).

### Verification gates (per merge)

- Full test suite green on the merge commit before it is pushed to `main`
  (mix test, or the project's declared CI equivalent) — no merge to `main` without a
  clean local run first, matching the Chicago-style state-based verification standard.
- For the R2RML-109 merge specifically: a targeted regression test proving the
  sensitive attribute is no longer emitted in plaintext by `OBDA.InMemory`, run and
  its real output captured before the merge is called done.
- For triplicate/duplicate branch resolution: the `git diff` output showing byte-level
  equivalence (or the specific divergence) must be captured before any branch delete.
- No merge to `main` bypasses code review; no destructive `git reset --hard` or
  history rewrite on any branch per the fix-forward-only git workflow.

### Rollout / monitoring plan

- After the `dev` -> `main` security-fix merge, tag a release consistent with `main`'s
  existing version sequence (next after v26.8.29) rather than reusing the `dev`-side
  v26.8.26 label, to avoid two different commits claiming the same version number.
- Re-run `git branch -a` and this Measure-phase table after each merge wave to
  re-verify branch count reduction — a standing "Measure again after Implement" check
  per the DMEDI Implement-phase discipline, not a one-time close-out.
- Track the deleted/archived branch list in a follow-up ledger so history remains
  auditable (branch SHAs recorded above are already sufficient for that purpose even
  after deletion, since git tags/refs on origin are not created by this plan).

## See Also

- `docs/jira/v26.9.1/PLAN.md` (this file) is the only artifact this plan pass
  produces; no merges, branch deletions, or PRs were performed as part of writing it.

---

Last Updated: 2026-09-01
