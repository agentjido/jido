# Agent and Topology refinement checks — 2026-10-16

Items 17, 18, and 21–25 remove repeated authoring code. The library delta is
43 added and 90 removed lines: **47 fewer lines**. The public DSL is unchanged.
AgentServer source and tests are unchanged. The design documents from the
other thread are unchanged by this work.

## Changes and guards

- Build graph edges and root import placeholders in one reduction.
- Set final graph metadata once. Keep parent, policy, subscriptions, and
  dependency defaults in the returned plan.
- Collect each ready layer in a list, then sort it. Keep dependency
  deduplication, stable order, and cycle errors.
- Define the nine DSL structs from one ordered table. Keep their module
  names, fields, defaults, and the absent Group count used with keyed members.
- Return generated Agent code directly from lowering.
- Share the indexed source-location walk between Agent and Topology. Keep
  nested binding property paths and exact source locations.
- Use the existing result unwrap helper in Registry bang construction.

The Agent and Topology Covenant suites have 130 tests and 42 obligations.
Focused mutation checks kill all 13 selected executions at 11 distinct sites.
Two shared source-path sites run through both component suites. All verdicts
have exact attribution. There are no invalid mutants, survivors, timeouts,
partial verdicts, or new survivor exceptions. The full 1,302-mutant profile
was not run. The Agent ledger keeps all 215 historical decisions; only 12
source locations move. The final restored-source Covenant gate passes all
130 tests and all 42 obligations (25 Agent, 17 Topology).

Four separate defect probes confirm that tests reject unsorted layers,
missing graph edges, a retained 128 KiB binary, and a helper process started
only during warm-up. Each probe produces a test assertion failure. Source
bytes are restored and checked by SHA-256 after each probe. These probes
receive no Covenant mutation credit.

## Benchmark refresh

The full smoke profile checks 128 workloads. Short and scale profiles now
have 200 and 242 workloads. New cases check Agent Codec operations and
composed Topology plans, documents, and instances. Topology fixtures include
an input-sized group, ownership, a Bus subscription, a static include, and
a runtime child command gate. Each operation checks its complete result.
One stale Plugin benchmark assertion now uses the current context contract.

Four focused baseline/candidate pairs run in eight fresh VMs, in alternate
order. The baseline library comes from a frozen archive of checkpoint
`77e2a1d9769688e60f8c467dc5b5a406d413905a`. The candidate is the current
uncommitted library. Both sides use the same refreshed benchmark files,
dependencies, settings, and host. Both report the checkpoint commit; the
runtime hashes below identify the actual source difference.

| Profile | Filter | Cases per side | Warm-up | Time samples | Resource samples |
| --- | --- | ---: | ---: | ---: | ---: |
| short | `authoring/` | 16 | 5 | 30 | 3 |
| short | `topology/` | 10 | 5 | 30 | 3 |
| scale | `authoring/` | 20 | 10 | 60 | 5 |
| scale | `topology/` | 15 | 10 | 60 | 5 |

All 61 paired cases pass result and cleanup checks. The copied flat heap,
flat heap, local heap, receiver process memory, and external encoded size
match between the two sides for every case. No operation starts or leaves
an owned helper process across all 506 resource calls. Receiver binary
reference samples match in 53 cases; the other eight differ by small byte
counts in Topology plans and instances. Those samples count shared binary
references, not unique value ownership.

Sampled process memory can differ. For example, the 16-member Topology decode
case samples 67,840 baseline bytes and 284,576 candidate bytes. The resource
call also records different GC counts (124 and 93), while caller reductions
are close (221,159 and 220,749). The equal returned-value sizes and the
post-GC load checks do not show retained growth. This sample also does not
prove equal temporary allocation or equal peak memory. Samples include setup
and checks; they are barrier observations, not exact lifetime peaks. Composed
fixture setup builds a definition, document, Registry, and expected expanded
instance for each operation. The resource runner does not collect setup
garbage before the operation. Its samples include that state. At 256 members,
the same decode process-memory sample falls from 1,115,016 to 426,432 bytes.

Timing varies in both directions. This is one pair per profile and filter on
a shared host. These results establish checked workloads and a new baseline;
they do not establish a speed gain or equal peak memory.

## Repeated load and memory

The new authoring load test uses four monitored workers and explicit start,
completion, and trace-delivery barriers. Each cycle creates definitions,
validates owned Plugin state, checks JSON Codec round trips, builds composed
plans, rejects invalid state and an unresolved child member, then discards
the results. Each cycle includes a 128 KiB transient binary. No AgentServer
is started.

Three fresh BEAM runs with 50 rounds per worker complete **600 measured
cycles**, plus warm-up. At all 24 warm/final checkpoints, each worker has:

| Resource after major GC | Observed |
| --- | ---: |
| Process memory | 2,712 bytes |
| Retained binary references | 0 bytes |
| Owned ETS tables | 0 |
| Mailbox messages | 0 |
| Helper processes started, including warm-up | 0 |

The test allows 1 MiB of process growth above its warm baseline and at most
64 KiB of retained binary references at both checkpoints. Worker monitors
confirm termination. Spawn tracing starts before warm-up. A separate defect
probe confirms that a warm-up-only helper is detected and cleaned up.
These are retained worker-memory limits. They do not measure whole-VM leaks,
exact peak memory, live Topology activation, or distributed runtime load.

Run commands and limits are in [the benchmark guide](../../guides/benchmarks.md)
and [the system test guide](../../test/system/README.md#authoring-load).

## Verification

The restored-source coverage run passes all 2,105 selected tests, with 51
excluded tests. Fresh package line coverage is **92.4%** (8,968 of 9,701
relevant lines), above the 90% gate.

| Changed module | Covered / relevant lines |
| --- | ---: |
| Agent authoring compiler | 138 / 139 |
| Shared source map | 17 / 17 |
| Codec Registry | 57 / 58 |
| Topology composition | 127 / 129 |
| Topology DSL compiler | 53 / 53 |
| Topology DSL extension | 3 / 3 |
| Topology validation | 183 / 185 |

A clean compile passes with warnings treated as errors. Credo warning checks
and the final format check pass. A byte audit confirms that all 105 protected
AgentServer and design-document files match their starting values. Dialyzer
still reports the same ten findings recorded before this
pass: two in the Action dependency, seven generated example/fixture contracts,
and one intentional improper-list test fixture. No finding was suppressed.

The first full coverage attempt passes 2,610 of 2,611 tests. One peer shutdown
test receives `:ok` where it expects an unavailable-node error. Its source,
peer helper, and liveness path match the checkpoint. The isolated test passes
on the candidate and checkpoint; 12 more fresh checkpoint runs also pass.
This supports a shutdown timing hypothesis but does not prove an existing
defect or a fix. AgentServer and its tests remain unchanged. The final normal
suite rerun passes: **2,611 passed, 2 existing skips, 161 excluded**, with seed
0 and four test cases in parallel. No skips were added. Services remain
opt-in. The peer check passes in this full rerun.

## Source and evidence

Runtime: Elixir 1.20.4, OTP 29.1, Apple M1 Max, two schedulers, Mix test.
The declared Elixir 1.18 / OTP 27 floor was not tested in this run.

| Input | SHA-256 |
| --- | --- |
| Baseline library | `f6de1f3d2f2d0aedd763d97ad2526be199dc98d61b17d9795f1ba5778121d59e` |
| Candidate library | `d9628c02bc22d7ea9876bfa8b222b84b01b30f8881d1a3a56e042e8fd266e136` |
| Shared benchmark tool | `c7143d977fe704991c7876ea820d6a1bb1bf40092d78664c1cb8042da64df0de` |
| Dependency lock | `974e93f5876dc74d718f8b33ee1a084025c348f9c6147918b7d7e4db816494c3` |

Local raw evidence is ignored under `tmp/covenant/next-reductions/`:
`benchmark-commands.json`, `bench-*-{baseline,candidate}/report.json`,
`bench-*-comparison.md`, `authoring-memory-summary.json`, `*-mutants.json`,
`mutation-commands.json`, `semantic-probes.json`, and `ledger-rebase.json`.
The [Topology Covenant record](../../test/contracts/jido/topology.baseline.md#final-local-reductions--2026-10-16)
lists exact mutation sites and operators.
