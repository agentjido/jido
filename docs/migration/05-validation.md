# Validation and beta gate

## Prepared source evidence

Tested source: `bf6c9fbec569cb6438b6a1629a2768058d439d1f`.
Report commit: `741058d128928d05bdee109f3c6a0425eb82db89`.
Runtime: Elixir 1.20.3 and OTP 29.0.5 on macOS.

On 2026-09-05, the user requested a skip for the one failing test. Only
DIST-03 is skipped. The current full suite passed 1005 tests with zero failures
and one skip. The exact exception is in the manifest; other unexpected skips
and failures remain errors. [Current command](evidence/prepared/scoped-final-full-seed-0.json),
[log](evidence/prepared/scoped-final-full-seed-0.log), and
[mapped results](evidence/prepared/scoped-final-full-seed-0.results.manifest.json).

ExUnit records the skipped test as excluded because the configuration excludes
the skip tag. It remains separate from passed tests.

The records below are the previous preparation runs. Coverage, serial, quality,
docs, and package checks were not rerun for the skip. Production code is unchanged.

The [preparation record](07-prepared-donor.md) describes completed source work.
The follow-up ran two full concurrent commands and one focused repeat command.
The first full run exposed the Factory timing race; the final run passes.
The plan check verifies the committed source, command record, individual
results, and mapped selections.

| Check | Tested revision | Result | Exact command and log |
| --- | --- | --- | --- |
| Full suite, concurrent | `08117d1` | 1005 passed, DIST-03 failed; exit 2 | [Record](evidence/prepared/final-full-seed-0.json), [log](evidence/prepared/final-full-seed-0.log) |
| Full suite with coverage, concurrent | `7e18634` | 1005 passed, DIST-03 failed; 83.0%; exit 2 | [Record](evidence/prepared/final-coverage.json), [log](evidence/prepared/final-coverage.log) |
| Full suite, serial | `7e18634` | 1005 passed, DIST-03 failed; exit 2 | [Record](evidence/prepared/final-serial.json), [log](evidence/prepared/final-serial.log) |
| Required regression repeat | `7e18634` | 42 passed in each of five runs; exit 0 | [Record](evidence/prepared/final-regression-repeat.json), [log](evidence/prepared/final-regression-repeat.log) |
| Quality | `7e18634` | Format, compile, Dialyzer passed; Credo ran zero checks; exit 0 | [Record](evidence/prepared/final-quality.json), [log](evidence/prepared/final-quality.log) |
| Docs | `7e18634` | No warnings; exit 0 | [Record](evidence/prepared/final-docs.json), [log](evidence/prepared/final-docs.log) |
| Local package build | `7e18634` | Built jido-2.3.3.tar; exit 0 | [Record](evidence/prepared/final-package.json), [log](evidence/prepared/final-package.log) |

Only status documents changed between `08117d1` and `7e18634`. The final report
commit changes only preparation documents and evidence. Those previous full results contain
zero skips or exclusions. The suite grew by seven tests. Added checks cover remote API, early timer,
raised write, stale Registry, Elastic attempts, and old-format rejection.

All 52 catalog fixtures pass 317 direct/shared checks. All 10 application
scenarios pass 13 checks. Four supporting Topology files pass 47 tests.
Persistence research passes ten tests. In these previous records, distributed
authority has one pass and one failure. The current run has one pass and one
approved skip. Four research entries remain narrative-only and add no passing
tests. [Complete mapped serial results](evidence/prepared/final-serial.results.manifest.json).

Coverage exceeds the unchanged 80% threshold. AgentServer is 78.3%; child
placement and spawn Registry are 13.7% and 19.0%. Inspect these boundaries
during core QA. Credo's zero-check success is not a substantive lint pass.

## Original failures and current disposition

The original Actor source `ba00fcf` passed 992 of 999 tests in the recorded
serial run. Preserve its [metadata](evidence/donor-full-seed-0.json),
[log](evidence/donor-full-seed-0.log), [failure summary](evidence/baseline-summary.json),
[source hashes](evidence/actor-sources.json), and
[example manifest](evidence/actor-example-manifest.json) as historical evidence.

| Original failure | Prepared result | Core check owner |
| --- | --- | --- |
| Nested checkpoint identity | Fixed; restored module and ID are checked | M03 |
| Nested nonportable checkpoint data | Fixed; recursive validation runs on load | M03 |
| Indeterminate write permits later evaluation | Fixed; uncertain writer stops and does not save stale shutdown state | M03 |
| Fixed Group replay/restart | Fixed; scoped Bus and exact restored history | M11 |
| Elastic Group recovery | Fixed; scoped Bus, saved input, newer attempts, and stale-result rejection | M11 |
| Scheduled occurrence duplicate slot | Fixed; controlled early-timer regression and default-clock wait | M07 |
| DIST-03 duplicate cluster owner | Skipped by user request; capability remains unimplemented | D06/M11: exact manifest exception |

Saved remote deadline, liveness, and hibernate/thaw defects were reproduced and
fixed. Their prepared real-node and lifecycle tests belong to M04. A stale
Registry race has a controlled reproduction and fixed lookup/list/count logic.
Concurrent first-use model loading now occurs before tests; no paid request is
needed. Keep those source changes when transferring the implementation.

Early Directive timeouts did not recur in 31 focused runs or the final full
runs. Their logs remain diagnostic evidence in the donor report. The 10-seed
campaign and 30-minute workload have not run. Real multi-host partitions, Redis
failover, the declared runtime floor, downstream compatibility, and fresh
package consumption remain unverified. No core acceptance run has occurred.

## Gate A: each migration commit

- Compile all introduced production code with warnings as errors.
- Run every retained or migrated test included through that commit. Add no
  skip beyond the exact user-approved DIST-03 exception, no-op stub, or blanket exclusion.
- Run the owning example group and shared tests. Verify that each path exists
  and that its test selection is nonempty.
- Check prepared donor-to-core differences, module/path collisions, generated
  interfaces, JSON fields, telemetry and persistence keys.
- Record source revision, core revision, runtime, exact command, seed, counts
  and log. Logs must correspond to the final commit content.

`mix test` currently excludes examples and integration tests in the donor.
`mix examples` uses `--only example` and misses some integration-only and
supporting core tests. Neither command is the complete acceptance gate.

## Gate B: example transfer complete

Implement one acceptance command in M13, proposed as `mix migration.acceptance`.
This Mix task does not exist yet. The prepared donor has
`scripts/migration-check.py`, `scripts/migration-manifest.py`, and a JSON
formatter. Adapt their paths and use them as inputs; do not rebuild identical
reporting tools without need. The core gate must read a checked manifest and run:

1. All mapped tests for the 52 catalog fixtures.
2. Shared Basic authoring and Factory streaming tests.
3. The mapped observation, recovery, scheduling, remote ownership and core
   Topology tests, including tests stored outside catalog folders.
4. All 10 application integration scenarios.
5. Persistence and other defect regressions required by this migration.

The runner must propagate a nonzero test exit. It must fail on missing fixtures,
missing or empty test selections, duplicate IDs, unexpected exclusions or a
changed input snapshot. Count tests and skips so an omitted suite cannot appear
as a faster success. Keep source counts as a reference; additional regression
tests may increase the core total. Explain reductions individually.

Until that command exists, run the equivalent explicit paths with these tags:

```sh
mix test --include example --include integration --include flaky --seed 0
```

That is a complete-suite check under the current donor exclusions except for
`:skip`; require exactly the recorded DIST-03 exception and inspect all skips.
The skipped test is not counted as passed. The three persistence probes are required
regressions, not a reason to exclude all `:research` tests.

Mark a fixture migrated only when its core test set passes with the selected
Agent names. Passing unchanged donor tests is only a source baseline. If a
contract change alters an assertion, retain the original expected behavior in
the deviation record and explain the selected replacement contract.

## Gate C: burn-in

Run Gate B with seeds 0 through 9, recording each result. Use normal concurrent
test execution for this stage. Use serial runs only to diagnose a failure, not
to replace a failing concurrent requirement. Repeat hibernate/thaw and remote
deadline race checks with bounded runs.

Run a 30-minute workload built from accepted examples. These bounds are proposed
acceptance criteria, not measurements already achieved. The workload must:

- Issue concurrent commands while preserving per-Agent Turn serialization.
- Replace workers and Plugin runtimes before/after commit and result delivery.
- Restore saved work and reject stale attempts and duplicate completion.
- Exercise real remote nodes with staggered startup, both call directions,
  disconnect and reconnect. Record the declared partition/ownership limit.
- Stop the systems and assert registry, child, task, subscription, timer and
  connection cleanup. Resource counts must return to the expected baseline.
- Record accepted/rejected work, terminal results, retries, queue growth and
  latency. Do not count time alone as success or promise an unmeasured throughput.

Run the 1,000-worker Topology case and recursive-analysis stress runner as
separate measured checks. Preserve the independent result oracle and resource
bounds. A local scale test is not evidence of durable multi-host capacity.

Required LLM/Factory tests use deterministic adapters and local HTTP/SSE. A paid
provider session is optional and must have a separate model/budget/run record.

## Gate D: final beta QA

Begin only after Gates B and C pass. Core must then pass:

```sh
mix test --include example --include integration --include flaky --seed 0
mix test --include example --include integration --include flaky --cover --seed 0
mix quality
mix docs --no-open
mix hex.build
```

Confirm the actual aliases/options in the migrated project. Require Credo to
run a meaningful enabled check set and retain its count. The donor command ran
zero checks; an exit code alone cannot close this requirement. The current coverage
threshold is 80%; inspect uncovered changed boundaries instead of lowering the
threshold. Do not silently exclude new production modules from coverage.

Also require:

- The declared minimum runtime and selected supported runtime matrix. Verify
  Elixir 1.18/OTP 27 support or deliberately revise the public requirement.
- A fresh consumer built from the package, using `Jido.Agent` and instance
  startup, without local path dependencies or optional model clients.
- Explicit CI jobs for core, full examples/integration, real-node regressions,
  quality, docs and packaging. Use a scheduled job for longer burn-in if chosen.
- A final check against current main for security, correctness, dependency and
  CI changes. Do not restore retired tracker code.
- A migration guide covering old public removals, changed returns/callbacks,
  state/storage migration and downstream package compatibility.
- No current public Actor names, stale V2 guide claims, unresolved required
  failures, hidden skips or unexplained test deletions.
- A build/test check of the final edited commit series, not only its tip.

DIST-03 is deferred by an explicit user-approved skip. Its assertion and original
failure remain visible. The acceptance gate allows only this exact exception.
Keep cluster-exclusive ownership outside support claims until it is implemented
and the assertion passes. Package publication and PR merge remain separate
actions after candidate review.
