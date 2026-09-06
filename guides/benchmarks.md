# Core benchmarks

Run from the Jido repository root. Use Elixir 1.18 or later and the dependencies in
`mix.lock`. The suite uses the jido_action v3 measurement approach.

```sh
ERL_FLAGS='+S 2:2' mix run bench/run.exs --profile smoke --output bench/results/smoke
ERL_FLAGS='+S 2:2' mix run bench/run.exs --profile short --output bench/results/before
ERL_FLAGS='+S 2:2' mix run bench/run.exs --profile scale --output bench/results/scale
```

| Profile | Cases | Route counts | Thread sizes | Warm-up | Time samples | Resource samples |
| --- | ---: | --- | --- | ---: | ---: | ---: |
| smoke | 84 | 1, 8 | 1, 32 | 1 | 2 | 1 |
| short | 161 | 1, 16 | 1, 100, 1000 | 5 | 30 | 3 |
| scale | 202 | 1, 16, 64 | 1, 100, 1000, 10000 | 10 | 60 | 5 |

Use `--filter SUBSTRING` for selected case IDs. An empty selection is an error.
Each run writes `report.json` and `report.md`. Raw reports under `bench/results/`
are ignored by Git. Keep the same scripts for both sides of a comparison.

## Cases

Agent cases cover construction, validation, command preparation, routing, direct
Action and two-step Flow commands, state transition, and checkpoint/restore.
Live server cases cover calls, Plugin admission, Flow calls, 20 casts with a completion call,
snapshots, failure, and start/stop. Data cases cover Thread append, normalization,
last entry and slice, Audit buffers and 100-record ID batches, state budgets, deep merge, Codec, and spans.
A no-op Plugin case measures the command preparation callback path.
Additional cases cover mixed Thread kinds, large caller contexts, reserved-key
errors, and Codec encoding with a generated Registry. Budget batch cases perform
100 checks or replacements with unlimited, module-limited, and stricter instance
limits. Their time is for the full batch, and every returned Agent is checked.

For admission task arguments, run `mix run bench/capture_admission.exs --output
bench/results/admission-capture.json`. This separate diagnostic captures the
actual function passed to `Task.Supervisor.async/2`, checks the completed call,
and copies that function into a receiver. It reports whether the function holds
the complete Server state. It supplies no timing evidence, and its copied heap
size is one argument transfer rather than total task traffic.

Short and scale use small state, a 1000-entry nested map, a 5000-item list, and
a 1 MiB binary. Smoke uses small state for the main matrix; fixed boundary cases
still use their stated payloads. Actions do no network or provider work.
Each call must produce its expected result. Server cleanup runs even when a
result check fails. The benchmark contract tests are in
`test/jido/bench/core_bench_test.exs`; CI's existing `test/jido` selection runs them.

## Measurements

Time samples use the monotonic clock without tracing. A full caller garbage
collection follows setup before each timed sample. This removes garbage from
untimed setup. It does not force server or worker heaps to collect. Setup, this
garbage collection, checks, and cleanup are outside each timed interval. `agent/new` includes definition construction
and instantiation. Server setup is outside time samples. Burst time covers all
21 messages; it does not measure concurrent per-caller tail latency.

Resource calls are separate. Spawn tracing follows the caller and a dedicated
Task.Supervisor. Callback and result barriers collect process memory, heap,
mailbox size, binary references, and reductions. Garbage collection events are
counted. Teardown and process monitors confirm that observed helpers stop.
Resource measurements include setup. The persistent benchmark Jido instance and
its fixed infrastructure are not attributed to an individual case.

| Metric | Meaning |
| --- | --- |
| Median and p95 ns | Operation time from untraced samples |
| Caller reductions | Caller work only; helper work is excluded |
| Observed process memory | Largest sampled sum of caller and observed descendants |
| Observed binary bytes | Deduplicated off-heap references; ownership can be shared |
| Observed helper reductions | Lower bound from barriers; short tasks can be missed |
| GC count | Observed garbage collections in caller and helpers |
| Local and flat heap bytes | Retained term heap with and without local sharing |
| Copied heap and receiver memory | Actual transfer to a new process |
| External bytes | External term encoding size; not process copy cost |
| VM memory | Includes measurement tools and unrelated work |

Exact lifetime memory peaks and total helper reductions are unavailable and
recorded as `null`. ETS tables, persistent terms, and code memory are not
attributed to individual cases; whole-VM totals include them. Retained term probes include a separate checked operation.
Flat transfers above 64 MiB are rejected. A full Agent result includes its schema
and routes; a server result does not include all server internal data.

## Compare and repeat

Use two isolated worktrees with separate builds. Compile both before measurement.
Run one VM at a time on the same idle host and runtime. Keep dependencies and
scheduler count fixed. Do not compile or run tests during paired measurements.

```sh
ERL_FLAGS='+S 2:2' mix run bench/compare.exs \
  bench/results/before/report.json bench/results/after/report.json \
  bench/results/comparison.md

python3 bench/repeat.py --baseline /path/to/baseline --candidate /path/to/candidate \
  --profile short --rounds 5 --output bench/results/pairs
```

The repeat runner uses one absolute script path from both worktrees, starts fresh
VMs, alternates order, checks report compatibility, and saves all logs and reports.
Use `--rounds 50` for the final repeated measurement run. It never changes or
pushes source code. It does not execute 50 different optimization ideas.

Reports record source revision and hash, source dirtiness, tool hash, lock hash,
runtime, host, and settings. Comparison rejects different environments, settings,
methods, tool hashes, and case sets. Ratios are candidate divided by baseline.
A ratio below one is lower; one run alone does not establish a speed gain.

See the [50-round plan](https://github.com/agentjido/jido/blob/v3-spike/docs/plans/2026-09-05-core-performance.md) for the idea
list, acceptance gates, required tests, and commit process. Distributed load,
complete durable recovery, scheduling, and topology need additional fixtures
before those optimization rounds can run.

Schema version 2 adds the caller collection before timing. Do not compare its
time samples with version 1. Rerun both revisions with the same current scripts.
