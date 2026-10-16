# AgentServer2 Covenant baseline — activation supervision

Only `jido` changes. All AgentServer2 runtime modules stay in
`lib/jido/agent_server2.ex`. Existing AgentServer source, public Agent/Topology
DSL syntax, dependencies, and the other thread's design documents are unchanged.

## B3: local admission, owners, idle control, and save-and-stop — 2026-10-16

B3 completes H1 and items 41–42 at the single-activation scope. All runtime
changes stay in `lib/jido/agent_server2.ex`. The existing AgentServer and public
Agent/Topology authoring DSL are unchanged. No commits were made.

`quiesce/2` closes admission and immediately rejects queued callers. OTP drains
those postponed events before resume is allowed. Reads stay available. Finish is
the default; cancel applies only before commit. Required writes, failure policy,
commit hooks, directives, and orphan delivery must settle. The control budget is
finite. Caller wait has a further 1,000 ms allowance, capped at the OTP timer
limit. An unresponsive server causes an OTP timeout exit. Caller timeout does not
undo a queued or accepted control. A control deadline leaves admission closed;
explicit resume needs a settled Agent. Owned callbacks cannot synchronously
control their owner. Concurrent controls return an explicit error.

Owners are idempotent monitored runtime records. Match each owner DOWN by its
reference, so an owner that is also the Runner cannot consume the Runner's
lifecycle event. Owner identities and closed admission survive worker recovery
in activation-owned metadata. They do not enter Agent checkpoints. Idle timeout
is disabled by default and accepts instance defaults or startup overrides.
Owner DOWN, last detach, touch, and completed work start a new idle budget only
when ready, idle, open, and without owners. Reads do not reset it.

`hibernate/2` quiesces, saves the current revision through existing Persistence,
and confirms activation DOWN. The storage budget cannot exceed either the
remaining control budget or persistence_timeout. A known no-write save failure
returns a reason and resumable? flag and restores prior admission. An uncertain
write, conflict, deadline, or task loss keeps the live Agent blocked. The blocked
recovery marker is written before starting storage, so worker death cannot reopen
an interrupted writer. Required turn-write failure retains B2's fail-stop rule.
Idle stop performs no extra save. Explicit idle hibernate requires persistence;
a failed automatic save closes admission without a retry loop.

These controls do not quiesce child Agents or serialize a physical process tree.
Plugin resource consistency, family hibernation, and thaw refinements stay in
current-plan tasks 1–6 (former HT1–HT6). Upgrades, saved relationships, export,
and distributed ownership remain open. The plan history maps B4–B6 to current IDs.

### B3 checks

- Normal package suite, seed 0: **1,846 passed**, **1,163 existing exclusions**.
  No new skips or category exclusions.
- AgentServer2 plus incumbent Ref regressions: **245 passed**. AgentServer2 has
  **231 tests**, including **29 new control tests** in `control_test.exs`.
- Covenant gate: **363 passed**, **136/136 obligations**. AgentServer2 has
  **94/94**, with new I84–I94. Agent remains 25/25 and Topology remains 17/17.
- Focused line coverage in the package run: Server **1,244/1,301 = 95.62%**;
  Activation **97/103 = 94.17%**; combined **1,341/1,404 = 95.51%**.
  Unchanged shared RefFacade is **83/106 = 78.30%** in this run.
- Format, compilation with warnings as errors, strict lint on the control suite,
  demo, four benchmark cases, and the two-cycle 100-Agent system check pass.
  Every benchmark reports zero remaining owned processes.
- Runtime diff against the B2 snapshot: **+498 / -22**, net **+476 lib lines**,
  including runtime documentation. Only `agent_server2.ex` changes under lib.
- Elixir 1.20.4, OTP 29, two schedulers. Broad lint, Dialyzer, docs publication,
  external storage services, and the minimum-version platform were not rerun.

The shutdown test holds a Plugin inside terminate and proves that hibernation
has not returned. It then releases the Plugin and checks root death. Other
barriers cover queue rejection, accepted save cancellation protection, effects,
control timeout, worker recovery during quiesce/save, lost storage tasks, safe
and uncertain failures, callback reentrancy, monitor release, owner/Runner PID
overlap, stale timer tokens, idle activity, and an unresponsive server.

Reproduce checks with `tmp/agent-server2-b3/checks.py`; raw logs, coverage,
source snapshots, protected hashes, load JSON, and selected mutations are there.
Runtime SHA256:
`a56ab8b6a79b27841d9deb8e8a123f87d92698ddaaffcc9d55168f22edff052a`.
Control suite SHA256:
`e85ad240c3f0fb34be6e879b7ab4dccd7299e085f5a358d732ff903a4b01cea2`.
The control suite's final change guarantees release of the shutdown barrier on
assertion failure; its 29 checks were rerun after that test-only change.

### B3 load and resource checks

```sh
MIX_ENV=test ERL_FLAGS="+S 2:2" mix run --no-start agent_server2_load.exs 10 1000
MIX_ENV=test ERL_FLAGS="+S 2:2" mix run --no-start agent_server2_load.exs --persistent 10 1000
```

Both modes pass two cycles at each size. Every Agent runs attach, touch,
quiesce, resume, and detach before the memory sample. Each cycle checks release
of 128 KiB transient caller data and five worker recoveries. Persistent cycles
also hibernate and restore five activations at the saved count and revision.
Half the Agents have process-free, worker, or Supervisor Plugins. No 10,000-Agent
run was added.

| Mode | Agents | Activation processes | Idle process MB | Activation ETS MB | Saved bytes | Storage ETS MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Memory | 10 | 33 | 0.23716 | 0.04456 | 0 | 0 |
| Memory | 1,000 | 3,300 | 23.716–23.721 | 4.456 | 0 | 0 |
| Persistent | 10 | 33 | 0.18412 | 0.04512 | 15,086 | 0.004648 |
| Persistent | 1,000 | 3,300 | 18.430–18.433 | 4.512 | 1,512,186–1,514,186 | 0.205296 |

MB is decimal. These local samples are not a capacity limit or speed comparison.
Persistent records survive activation stop by design; the script checks their
count and bytes, then removes them before the resource comparison. Live process
and ETS identities return to baseline: **228 / 90** in memory mode, **228 / 91**
in persistent mode. The persistent table is removed on script exit. VM heap and
binary byte totals can differ after garbage collection.

### B3 focused mutation checks

The selected run checks **22 of 2,054 catalog sites**. It does not run the full
component catalog or the previous 1,302 Agent mutants. Targets include closed
admission recovery, callback checks, owner monitor release and DOWN dispatch,
settlement, accepted save/effect cancellation protection, deadlines, unknown-save
recovery, storage task cleanup, failure admission, idle guards, and root DOWN.

```sh
MIX_ENV=test ERL_FLAGS="+S 2:2" mix covenant.mutate jido.agent_server2 \
  --only m0525,m0570,m0970,m0976,m0986,m0988,m1002,m1006,m1043,m1941,m1946,m1954,m1976,m1978,m1988,m1998,m2004,m2005,m2015,m2019,m2034,m2035 \
  --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 \
  --out tmp/agent-server2-b3/mutations.json
```

All **22/22 selected mutants were killed with exact credit**. There are zero
survivors, invalid mutations, timeout-only verdicts, partial results, annotations,
or problems. Both worker baselines passed all 231 tests. The broad owner-DOWN
guard removal also caused four per-test timeouts; its 16 non-timeout failures
supply the kill. Timeouts receive no kill credit. Raw worker results are under
`tmp/covenant/mutate/jido.agent_server2/run-lYIi8oZK`. The selection is bound to
the source hash above. This is a focused result, not a full component score.

## B2: required durable saves and restore — 2026-10-16

B2 completes item 40 and P3–P5. Runtime changes are only in
`lib/jido/agent_server2.ex`. Persistence stays disabled by default. An explicit
adapter or `:inherit` requires an activation and stable Jido instance namespace.
Create and restore are separate policies. Create writes revision zero before
readiness; restore requires saved compatible state and has no missing-record
fallback. Each storage stage uses a separate finite `persistence_timeout:`.

Required commit writes run after Runic cleanup and before local checkpoint
publication, success, hooks, or directives. Reads stay available and later turns
wait. Caller timeout does not cancel save. Cancellation during save reports
`:commit_in_progress`. Failed or unknown writes stop the activation through the
existing cleanup path. Deadline expiry is indeterminate even if the write reply
is ahead of the timer in the mailbox. Core cannot undo a remote write by stopping
its local task. Every persistent replacement worker reloads storage, including
a stored commit not published locally before worker death.

Existing Persistence record, CAS, Agent checkpoint, and Plugin conversion APIs
are reused. Restore validates the complete Agent, identity, revision, and exact
startup definition/version before Plugin Init. Resources and readiness use the
restored domain state. Custom checkpoints and Plugin conversion remain explicit.
Memory-only state rules stay unchanged. No new authoring syntax or Plugin callback
is added. Relationship restore, code migration, quiescence, export, and writer
leases remain outside B2. ETS demonstrates activation recovery; it does not
provide persistence across a BEAM restart.

### B2 checks

- Normal package suite, seed 0: **1,817 passed**, **1,163 existing exclusions**.
  No skips or category filters were added.
- AgentServer2 plus incumbent Ref regressions: **216 passed**. The component has
  **202 tests**, including **27 new persistence tests** in its own suite folder.
- Covenant gate: **334 passed**, **125/125 obligations**. AgentServer2 has
  **83/83**, including seven new obligations I77–I83. Agent and Topology stay at
  **25/25** and **17/17**.
- Focused executable line coverage during the package suite: AgentServer2
  **1,052/1,102 = 95.46%**; Activation **97/103 = 94.17%**; combined
  **1,149/1,205 = 95.35%**. Shared RefFacade: **83/106 = 78.30%** in this run;
  it was not changed in B2. This is not package-wide coverage.
- Format, compilation with warnings as errors, strict lint on the persistence
  suite, the updated demo, four benchmark workloads, and the two-cycle 100-Agent
  system check pass. Each benchmark has zero remaining owned processes.
- B2 runtime diff relative to B1: **+195 / -42**, net **+153** lines under `lib/`.
  All are in the single AgentServer2 runtime file, including documentation.
- Checks use Elixir 1.20.4, OTP 29, and two schedulers. Broad package lint,
  Dialyzer, docs publication, external storage services, and the 1.18/27 floor
  were not rerun. This adds no claim about those checks.

The new suite covers serial saves, responsive reads, separate caller waits,
expected-revision rejection, failed and unknown writes, strict deadlines, lost
storage tasks, provisional resource cleanup, missing/corrupt/incompatible loads,
Plugin state conversion and reconstruction, both durable commit crash windows,
local publication failure after a confirmed write, and no hook/directive replay.

Reproduce checks with the Mix arguments in `tmp/agent-server2-b2/checks.py`.
Coverage uses `tmp/agent-server2-b2/verify.exs`. Raw checks, source snapshots,
protected-file hashes, benchmark output, catalog, and selected sites are in that
ignored evidence folder. The runtime SHA256 is
`51b97df0515f4085fa6f930c5d0480f648a549e8f148eeeddf1095ce9b2e2578`.
The persistence suite SHA256 is
`42bdfb61a8e9f71c407e1b8546749d1e41b5512ecb7c1ec102c939f20c7bc2e1`.

### B2 load and cleanup measurements

Run from `jido`:

```sh
MIX_ENV=test ERL_FLAGS="+S 2:2" mix run --no-start agent_server2_load.exs 10 1000
MIX_ENV=test ERL_FLAGS="+S 2:2" mix run --no-start agent_server2_load.exs --persistent 10 1000
```

Both modes pass two cycles at each size. Half the Agents use process-free,
worker, or Supervisor Plugins. Each cycle checks release of 128 KiB transient
caller input, five worker recoveries, shutdown, empty Registry/claims/Runner,
and no extra live processes or ETS tables. Persistent cycles also check five
new activation restores with count 1 and revision 1. No 10,000-Agent rerun.

| Mode | Agents | Activation processes | Idle process MB | Activation ETS MB | Saved record bytes | Storage ETS MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Memory | 10 | 33 | 0.218 | 0.04344 | 0 | 0 |
| Memory | 1,000 | 3,300 | 21.761 | 4.344 | 0 | 0 |
| Persistent | 10 | 33 | 0.193 | 0.044 | 15,086 | 0.004648 |
| Persistent | 1,000 | 3,300 | 19.395–19.398 | 4.400 | 1,512,186–1,514,186 | 0.205296 |

MB is decimal. Saved record bytes count encoded values; Storage ETS is the table
allocation, reported separately because large binaries are stored outside it.
These are local measurements, not a capacity limit or comparative speedup.
Memory depends on BEAM heap collection and term sharing. Process and table
identities return to the warmed baseline: **228 processes / 90 tables** in
memory mode; **228 / 91** in persistent mode, including its storage table.
Saved records intentionally remain after activation stop. The script verifies
record count, measures values, then explicitly removes records before checking
resource identities. It removes the storage table on exit. Shared VM memory
bytes are recorded; they are not required to equal a byte-for-byte baseline.

Frozen JSON and raw logs are under `tmp/agent-server2-b2/`. The load script also
writes the latest JSON to `tmp/agent-server2-activation/load.json` and
`load-persistent.json`. The persistent-load log was refreshed after splitting
encoded value bytes from storage table allocation.

### B2 focused mutation checks

Only **18 selected sites** ran from the two-module **1,781-site catalog**.
All **18/18 were killed with exact credit**. There are zero survivors, invalid
mutations, timeouts, partial results, annotations, or problems. Both worker
baselines passed the original 202 tests. No Agent mutants or full catalog ran.

```sh
MIX_ENV=test ERL_FLAGS="+S 2:2" mix covenant.mutate jido.agent_server2 \
  --only m0102,m0135,m0699,m0701,m0702,m0704,m0966,m0973,m0976,m1148,m1256,m1261,m1262,m1263,m1488,m1489,m1491,m1499 \
  --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 \
  --out tmp/agent-server2-b2/mutations.json
```

Catalog generation: `mix run --no-start tmp/agent-server2-b2/catalog.exs`.
Site IDs apply to the frozen source hash and default two-module profile above.
Raw worker results: `tmp/covenant/mutate/jido.agent_server2/run-guO3Iyoh/`.
The complete matrix is `tmp/agent-server2-b2/mutations.json`.

| ID | Line | Function | Operator | Result |
| --- | ---: | --- | --- | --- |
| m0102 | 272 | `start_worker/2` | `condition_negate` | killed / exact |
| m0135 | 314 | `persistence_mode/2` | `condition_negate` | killed / exact |
| m0699 | 1246 | `durable_start/2` | `comparison_swap` | killed / exact |
| m0701 | 1255 | `durable_load/4` | `return_nil` | killed / exact |
| m0702 | 1255 | `durable_load/4` | `integer_shift` | killed / exact |
| m0704 | 1259 | `durable_load/4` | `return_nil` | killed / exact |
| m0966 | 1801 | `handle_event/4` | `return_nil` | killed / exact |
| m0973 | 1807 | `handle_event/4` | `element_removal` | killed / exact |
| m0976 | 1811 | `handle_event/4` | `return_nil` | killed / exact |
| m1148 | 2074 | `finish_bootstrap/2` | `statement_removal` | killed / exact |
| m1256 | 2288 | `operation_result/3` | `clause_removal` | killed / exact |
| m1261 | 2288 | `operation_result/3` | `comparison_swap` | killed / exact |
| m1262 | 2289 | `operation_result/3` | `comparison_swap` | killed / exact |
| m1263 | 2290 | `operation_result/3` | `integer_shift` | killed / exact |
| m1488 | 2648 | `finish/2` | `element_removal` | killed / exact |
| m1489 | 2648 | `finish/2` | `element_removal` | killed / exact |
| m1491 | 2648 | `finish/2` | `integer_shift` | killed / exact |
| m1499 | 2666 | `publish_commit/2` | `clause_removal` | killed / exact |

## B1: stable local Refs and checkpoint recovery — 2026-10-16

B1 completes REF1 and item 39 / P1–P2. The existing Ref facade resolves exact
namespace, partition, and Agent ID to the current local worker. It selects the
request protocol during resolution and does not retry accepted work. Starting
AgentServer2 registrations return `:recovering`; missing or dead registrations
return `:not_found`; Registry loss or synchronous worker loss returns
`:unavailable`. Caller timeout remains an OTP exit and does not cancel work.
Unsupported operations return an explicit runtime-operation error. Existing
AgentServer Ref behavior remains guarded. Generated instance wrappers add
`submit`, `await`, and `abandon` with the existing pending-owner rules.

An activation-owned ETS entry stores the canonical Agent and revision. An atomic
expected-revision replacement precedes commit installation, success replies,
hooks, and directives. Recovery validates complete state, identity, definition
including version, and revision before Plugin construction. It retains the old
Runic cleanup barrier and fresh readiness. Missing, corrupt, or incompatible
records stop recovery. Publication conflict stops the activation without success
or effects. Checkpointing does not call portable serialization callbacks, copy
transient input into domain state, or reject schema-permitted local values.

The recovery suite covers both commit crash windows, lost replies, cancellation,
timeout, unchanged success, Plugin reconstruction, and crashes during hooks and
directives without replay. Complete activation replacement loses local commits;
bare workers have no activation checkpoint. Durable records remain B2. Saved
child relationships remain B5. Narrow shared changes are in `Jido` and
`Jido.Instance.RefFacade`; all AgentServer2 lifecycle code stays in one file.

### B1 test and coverage checks

- Normal package suite, seed 0: **1,790 passed**, **1,163 existing category
  exclusions**. No skips or category filters were added. This is the normal
  core suite, not all six execution categories.
- AgentServer2 and existing Ref regression tests, seed 0: **189 passed**.
  AgentServer2 has **175 tests**, including 14 new recovery tests.
- Covenant gate, seed 452717: **307 passed**, **118/118 obligations**.
  AgentServer2 has **76/76**, Agent **25/25**, Topology **17/17**.
- Focused executable line coverage, including generated line 0: AgentServer2
  **999/1,048 (95.32%)**; Activation **91/97 (93.81%)**; combined
  **1,090/1,145 (95.20%)**. The shared Ref facade has **84/106 (79.25%)**
  during the normal package run, including legacy operations and generated default-arity
  wrappers. This is not package-wide coverage or a full shared-facade score.
  Results and scripts are under `tmp/agent-server2-b1/`.
- Format, compilation with warnings as errors, and strict lint on the new
  recovery suite and shared Ref facade pass. Broad package lint, Dialyzer,
  docs publication, and Elixir 1.18/OTP 27 checks were not rerun.

### B1 focused mutations

The final three-module profile has **1,798 sites**. Only **16 selected mutations**
ran: **16 killed**, all with exact credit; **0 survivors**, **0 invalid**,
**0 timeouts**, **0 partial results**, and **0 annotations**. Both worker
baselines passed all 175 scoped tests. The full profile and the earlier 1,302
Agent mutants were not run. No survivor exceptions were added.

Source SHA256 values:

- `lib/jido/agent_server2.ex`: `2b049b83f5f8aa50b43c67f35807b83356dbac074e0e3dc2041bc48d73160df7`.
- `lib/jido/instance/ref_facade.ex`: `3fcc3010c1f393afb074fcde5779043eb6bcce99136d68cfd8389bdae86a1413`.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --module Jido.AgentServer2 --module Jido.AgentServer2.Activation --module Jido.Instance.RefFacade --only m0076,m0100,m0106,m0108,m0112,m0120,m0685,m1391,m1393,m1394,m1693,m1698,m1699,m1758,m1764,m1765 --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 --out tmp/agent-server2-b1/mutations.json
```

IDs apply only to these sources and this module profile. Evidence is in
`tmp/agent-server2-b1/`: `catalog.json`, `selected.json`, and `mutations.json`.
The selected sites test initial revision, revision validation, identity and
definition validation, atomic publication, failed publication, next revision,
child reads, recovering results, both runtime protocols, unsupported operations,
caller timeout, and worker loss. The focused result is not a full component score.

| ID | File / line | Operator | Change |
| --- | --- | --- | --- |
| m0076 | `lib/jido/agent_server2.ex:216` | integer_shift | `0` → `1` |
| m0100 | `lib/jido/agent_server2.ex:256` | logical_swap | `and` → `or` |
| m0106 | `lib/jido/agent_server2.ex:258` | comparison_swap | `==` → `!=` |
| m0108 | `lib/jido/agent_server2.ex:259` | comparison_swap | `===` → `!==` |
| m0112 | `lib/jido/agent_server2.ex:271` | arithmetic_swap | `-` → `+` |
| m0120 | `lib/jido/agent_server2.ex:276` | integer_shift | `0` → `1` |
| m0685 | `lib/jido/agent_server2.ex:1295` | return_nil | `with :ok <- validate_wait(timeout) do context = :gen_statem…` → `nil` |
| m1391 | `lib/jido/agent_server2.ex:2507` | return_nil | `case Activation.publish_checkpoint(data.activation_state, c…` → `nil` |
| m1393 | `lib/jido/agent_server2.ex:2511` | clause_removal | `case {:error, reason} ->` → `(removed)` |
| m1394 | `lib/jido/agent_server2.ex:2507` | arithmetic_swap | `+` → `-` |
| m1693 | `lib/jido/instance/ref_facade.ex:56` | clause_removal | `case {:starting, {AgentServer2, :init, 1}} ->` → `(removed)` |
| m1698 | `lib/jido/instance/ref_facade.ex:53` | element_removal | `AgentServer` → `(removed)` |
| m1699 | `lib/jido/instance/ref_facade.ex:53` | element_removal | `AgentServer2` → `(removed)` |
| m1758 | `lib/jido/instance/ref_facade.ex:203` | condition_negate | `if function_exported?(runtime, operation, length(args) + 1)` → `if !(function_exported?(runtime, operation, length(args) + 1))` |
| m1764 | `lib/jido/instance/ref_facade.ex:213` | logical_swap | `and` → `or` |
| m1765 | `lib/jido/instance/ref_facade.ex:213` | comparison_swap | `==` → `!=` |

### B1 memory and cleanup checks

The updated demo passes. The focused final check passes **30 tests**, seed 0:
14 recovery tests, 14 incumbent Ref tests, the four-workload benchmark smoke
check, and the two-cycle 100-Agent system load check. Seven unrelated benchmark
cases are outside that line selection. They are not new skips.

The load script runs **10 and 1,000 Agents twice**, with half using Plugins.
Each cycle checks transient input release, five worker recoveries with committed
count 1 and revision 1, complete shutdown, empty Registry/claims/Runner work,
and no new live processes or ETS tables after cleanup. All four cycles return
from 261 or 3,528 VM processes to **228 processes and 90 ETS tables**.

| Agents | Activation processes | Idle process memory | Owned ETS memory | Startup | Stop |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10 | 33 | 0.237–0.242 MB | 0.043–0.043 MB | 3.29–4.80 ms | 0.33–0.38 ms |
| 1,000 | 3,300 | 23.755–23.794 MB | 4.344–4.344 MB | 349.18–386.08 ms | 33.93–35.52 ms |

Memory uses decimal MB on Elixir 1.20.4 / OTP 29 with two schedulers. The
checkpoint adds retained canonical Agent data; it adds no processes. These are
local measurements, not capacity limits. The earlier 10,000-Agent results below
precede B1 and were not rerun. Raw current measurements are in
`tmp/agent-server2-b1/load.json`; the refreshed four-workload report is under
`tmp/agent-server2-b1/bench/`.

## Startup return simplification — 2026-10-16

`Activation.start_link` returns `{:ok, root}` without a startup message handshake.
Parent attachment and failed-attachment cleanup use `finish_start`. Instance
start and child spawn share worker lookup. They return `{:ok, worker}` on success
or stop the new root and return `{:error, :worker_unavailable}` if lookup fails.

The scoped AgentServer2 suite passes **161 tests**, seed 0. The focused benchmark
test passes all four AgentServer2 workloads. The demo, compilation with warnings
as errors, focused format checks, and strict lint on `activation_races_test.exs`
pass. The new race check covers a missing worker, a dead root, owned children,
independent children, cleanup, and tag reuse. Timeout tests observe the worker
through Plugin startup events before a bounded child start delays root lookup.

No mutations were rerun for this refactor. The mutation evidence below applies
only to its listed source hashes.

## Activation review fixes — 2026-10-16

F1–F7 are fixed in the same runtime file. Recovery retains the previous Runic
scope until cleanup is confirmed and uses the existing readiness task and
budget before admitting work. Required Plugin roots must belong to this
activation. Adoption rejects pending orphan dispatch, unavailable ancestry,
and bare workers. Lost adopted-child tags are released on root replacement.
Child records no longer retain a stale worker PID. Plugin initialization and
directive-owner selection each use one local helper. The callback-child
contract is unchanged.

Nine regression tests are in `activation_races_test.exs`. The scoped suite now
has **160 tests**. The final normal package suite passes **1,775 tests**, seed 0,
with **1,163 existing category exclusions**. The Covenant passing-test gate
passes **292 tests** and **111/111 obligations**, including AgentServer2
**69/69**. Compilation with warnings as errors, focused format checks, strict
lint on the new regression file, and the unchanged demo pass. Broad package
lint still reports existing style findings; it is not a passing gate.

Source SHA256: `1df593dabfa02d27a5f8c3f696063771569d1c992b2b5bbc3d38e4dbad126b44`.
Evidence is under `tmp/agent-server2-review/`: `final-source.ex`,
`final-tests.log`, `fixes-covenant.log`, `fixes-lint.log`, `fixes-demo.log`,
`fixes-catalog.json`, and `final-selected.json`.

The final catalog contains **1,633 sites**. Only **14 selected mutations** run:
**14 killed**, with exact credit, **0 survivors**, **0 invalid mutations**,
**0 timeouts**, **0 partial results**, and **0 annotations**. Both worker
baselines pass all 160 scoped tests. This is a focused result; the full catalog
and the earlier 1,302 Agent mutations were not run. The first selection exposed
one redundant ignored-start check, which was removed, and one invalid removal
of a required struct field, which was excluded from the final selection.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0114,m0116,m0120,m0129,m0135,m0136,m0611,m0638,m0690,m0697,m0797,m0811,m1043,m1426 --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 --out tmp/agent-server2-review/final-mutations.json
```

These IDs apply only to the source hash above. The final report and log are
`final-mutations.json` and `final-mutations.log` in the same evidence directory.

The sections below retain the earlier activation rollout evidence and source.

## Current contract

A normal activation Supervisor owns the request worker, required Plugin roots,
and a lazy DynamicSupervisor for owned child activations. Plugin roots can be
workers or supervisors. A `:one_for_all` group refreshes readiness, generation,
and worker references after server or required-root failure. A Plugin supervisor
can recover its leaves locally. Explicit stop confirms complete root shutdown.
The former Runtime guardian and process-link traversal are removed.

The instance DynamicSupervisor can also own independent child activations.
Logical parent relationships refer to activation roots. Independent children can
stop, continue, or emit `jido.agent_server2.orphaned` after parent loss. Adoption
is limited to an independent orphan in the same instance and partition. Tag
reservation tokens prevent a late start from taking a reused tag. Failed
reservations release caller monitors. Adoption rejects cycles.

One supervisor-owned ETS table holds runtime relationships, the current worker,
and the local Agent/revision checkpoint. It survives worker recovery. Whole
activation replacement uses original startup arguments; later adoption and
commits are not restored. A restarted owned-child DynamicSupervisor starts empty.
Item 44 stays open for directive integration and saved relationships.

Normal OTP child-start functions must return within a bounded time. Put long
initialization in readiness. The readiness deadline closes admission immediately;
cleanup waits for an already-running bounded supervisor start to settle. An
arbitrary start function that never returns is outside this contract. Both OTP
success forms use the same readiness and cleanup path. The bare-worker
`start_link/1` API rejects runtime Plugins; normal operation uses activation
startup. Existing `Jido.start_agent` and `Jido.stop_agent` are not migrated.

## Checks

- Normal package suite: **1,766 passed**, seed 0, **1,163 category exclusions**.
  This is `mix test`, not all six execution categories. No skips or category
  filters were added. Two new excluded benchmark/system tests run separately.
- AgentServer2 suite: **151 passed**. The combined runtime, benchmark, and system
  check passes **160 tests**, seed 0. All fixtures remain scoped to this work.
- Covenant gate: **283 passed**, seed 175715. AgentServer2 **69/69**, Agent
  **25/25**, and Topology **17/17** obligations pass: **111/111** overall.
- Focused line coverage with 151 tests: AgentServer2 **977/1,026, 95.22%**;
  Activation **64/71, 90.14%**; combined **1,041/1,097, 94.90%**. Each module
  includes generated line 0. Store, Pending, dependencies, and package-wide
  coverage are outside this measurement.
- The final demo passes in test and development environments. It checks local
  Plugin leaf recovery, activation recovery, nested owned cleanup, independent
  Plugin survival, adoption, and the previous turn/effect/deadline checks.
- Format checks, compilation with warnings as errors, and strict Credo on all
  **12 scoped test source files** pass. Broad package Credo is not a passing
  gate: it reports style findings and the existing turn_id Logger warning.
  Dialyzer, publication checks, and the Elixir 1.18/OTP 27 floor were not rerun.

## Focused mutation evidence

The catalog contains **1,598 sites** across AgentServer2 and Activation.
Catalog generation executes no mutants. Only **20 selected sites** run:
**20 killed**, all with exact credit. There are **0 survivors, 0 invalid mutants,
0 timeouts, 0 partial results, and 0 annotations**. Both worker baselines pass
151 tests. Fail-fast is off. This is a focused result, not a full component
score. The earlier 1,302 Agent mutants were not rerun.

The first run found one assertion gap: the missing-instance test accepted any
error. It now requires `{:error, :jido_instance_required}` before resources are
created. The same mutant is caught in the final run. One initial selection
removed an enforced struct key and could not compile. It is retained in the
initial evidence and replaced by a valid mutation of Plugin specification
selection. No surviving mutant is annotated or removed.

| ID | Source line | Protected decision | Operator |
| --- | ---: | --- | --- |
| m0069 | 204 | rollback root | statement_removal |
| m0088 | 236 | restart limit | integer_shift |
| m0093 | 248 | purge owned generation | statement_removal |
| m0097 | 254 | refresh worker | statement_removal |
| m0145 | 333 | startup token | element_removal |
| m0151 | 338 | child watch | statement_removal |
| m0436 | 785 | activation DOWN wait | statement_removal |
| m0663 | 1290 | cycle guard | clause_removal |
| m0693 | 1341 | owned lifetime | clause_removal |
| m0694 | 1344 | independent instance | clause_removal |
| m0736 | 1389 | release monitor | statement_removal |
| m0765 | 1460 | adoption instance | clause_removal |
| m0777 | 1469 | persist adoption | statement_removal |
| m0784 | 1495 | Plugin specification selection | comparison_swap |
| m0813 | 1548 | readiness clock | condition_negate |
| m0816 | 1549 | ready registration | statement_removal |
| m0959 | 1765 | clear orphan parent | statement_removal |
| m0961 | 1772 | continue policy | clause_removal |
| m0962 | 1775 | orphan policy | clause_removal |
| m0979 | 1802 | orphan deadline | comparison_swap |

Source SHA256: `ceecc7338878c3c12ac538c863fad4f1c0092f142f1635194a7ca83537142e48`.
Artifacts: `tmp/covenant/agent-server2/activations/` contains the catalog,
initial and final selections/results, exact runtime source, activation tests,
and per-module line coverage. Old IDs apply only to their recorded sources.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0069,m0088,m0093,m0097,m0145,m0151,m0436,m0663,m0693,m0694,m0736,m0765,m0777,m0784,m0813,m0816,m0959,m0961,m0962,m0979 --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 --out tmp/covenant/agent-server2/activations/final.json
```

## Benchmark and load evidence

The four-case `agent_server2` profile checks plain turns, worker Plugins,
supervisor Plugins, and owned/independent family cleanup. Every resource sample
has zero remaining traced processes. Shared Runner and independent instance
resources are not all descendants of the measured caller; the load check also
measures the complete activation forest and instance cleanup.

The load script passes two cycles each at 10, 1,000, and 10,000 Agents. Half use
Plugins: process-free, one worker, or supervisor trees with 1, 3, or 5 leaves.
Each cycle checks turns, release of 128 KiB transient caller input, five worker
recoveries, full shutdown, empty Registry/registration claims/Runner work, and
no new live processes or ETS tables. Process identity checks permit a
pre-existing VM process to end. All activation resources are gone after stop.

| Agents | Activation processes | Idle process MB | Owned ETS MB | Startup | Stop |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10 | 33 | 0.178–0.181 | 0.026 | 2.9–3.5 ms | 0.36–0.37 ms |
| 1,000 | 3,300 | 18.02 | 2.608 | 287–322 ms | 37–39 ms |
| 10,000 | 33,000 | 167.95–169.42 | 26.080 | 2.38–3.48 s | 0.30–0.36 s |

MB is decimal. Measurements use Elixir 1.20.4, OTP 29, and two online schedulers.
They do not establish a production capacity or comparative speedup. Raw load
results, source hash, environment, benchmark report, and command logs are under
`tmp/agent-server2-activation/`. The suite guide gives the runnable commands.

---

# Historical checkpoint: F1–F4 and cleanup wait guard

Only `jido` changes. Runtime implementation remains in `lib/jido/agent_server2.ex`.
Existing AgentServer, the public authoring DSL, dependencies, and the other
thread's design documents remain unchanged by these fixes.

The fixes cover supervised Plugin shutdown, ownership of provisional roots during
blocked startup, roots that trap exits, and both OTP child-start success forms.
Callbacks must finish linked child work before returning. Plugin runtime trees
own longer-lived resources. Runtime settings share one source for keys and
defaults; validation names invalid timeout fields. Explicit settings still
override instance defaults, and only `turn_timeout` reads application defaults.

I2, I44, I50, and I61 state these limits. I62 protects both valid OTP startup
results and their common readiness and cleanup path. The demo uses a root that
traps exits, a finite child shutdown setting, a three-element success result, and
a commit hook that waits for linked work before it returns.

## Checks

- Final normal package tests: **1745 passed**, 1161 existing exclusions, seed 0.
  No new skips or exclusion tags were added.
- Final focused suite: **130 passed**, including 16 new regression tests.
- Final Covenant gate: **262 passed**, seed 586239. AgentServer2 **62/62**,
  Agent **25/25**, and Topology **17/17** obligations have passing tests:
  **104/104** overall. Obligation coverage does not replace mutation evidence.
- Prior F1–F4 focused line coverage, measured with 129 tests: main module
  **778/807, 96.41%**; nested Runtime
  **50/57, 87.72%**; combined **828/864, 95.83%**. These measurements include
  generated line 0 and cover only the two named modules.
- The updated demo passes. It verifies the OTP info success form, finite root
  shutdown, cleanup of a root that traps exits, linked callback completion, and
  field-specific timeout errors. Its main server ends at count 4, revision 4.
- Compile with warnings as errors, explicit format checks, and strict Credo on
  all 11 scoped test source files pass. Broad Credo still reports package style
  findings and the existing Logger metadata warning; it is not a green lint
  gate. Dialyzer and package publication checks were not repeated; the earlier
  limitations remain recorded below.

## Focused mutation evidence

The catalog contains **1272 sites** across `Jido.AgentServer2` and its nested
`Runtime`. Catalog generation executes no mutants. Only **18 selected sites**
run; the previous full Agent mutation run is not repeated.

Final result after closing the cleanup wait gap: **18/18 killed**, with exact
credit. There are **0 survivors, 0 invalid mutants, 0 timeouts, and 0 partial
results**. Both worker baselines pass all 130 focused tests. Fail-fast is off.
No survivor annotations were added. This focused mutation gate passes; it does
not establish a full component score.

The initial run exposed an established exit-trapping root left alive while a
sibling start was blocked. A new regression checks root-owned ETS cleanup when
the server stops, then confirms root and startup supervisor death. It now kills
`m0093`, which removes cleanup of the established roots.

The earlier run left `m0113` alive. It removes the explicit `DOWN` wait at
`lib/jido/agent_server2.ex:300` from forced cleanup. The new I50 regression now
kills it. With one online scheduler, cleanup and its caller have maximum priority
while an established root has low priority. The root cannot process its pending
kill until cleanup waits. The test calls the public `stop/1` API and checks that
the root-owned ETS table is gone before any process probe can flush the kill
signal. Removing the wait now fails that resource assertion. The test restores
the caller priority and online scheduler count on success or failure.

The runtime source is unchanged. The new guard needs no test hook or public API
change. Both the earlier surviving result and the final passing result remain
available; the mutant was not marked equivalent or removed from the selection.

Source SHA256: `6770db141db232b6d91ffc949fe5d1a12b9373386eb377aafa40c883e0583416`.
Current artifacts: `tmp/covenant/agent-server2/down-wait/` (source, test source,
selected sites, and final mutation report). Earlier F1–F4 artifacts remain in
`tmp/covenant/agent-server2/f1-f4/`, including the unchanged catalog, initial
reports, and per-module line coverage.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test --seed 0
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test.contract
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start agent_server2_demo.exs
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0016,m0070,m0071,m0086,m0090,m0091,m0092,m0093,m0098,m0099,m0102,m0104,m0112,m0113,m0219,m0245,m0256,m0273 --jobs 2 --seed 0 --timeout 4000 --max-runtime 600000 --out tmp/covenant/agent-server2/down-wait/final.json
```

---

# Historical checkpoint: items 36–37

Only `jido` changes. Runtime changes stay in `lib/jido/agent_server2.ex`.
The existing AgentServer and the other thread's design documents are unchanged.

Commit hooks run in declaration order before directives, including commits with
no directives. `commit_timeout` is a separate finite 5000 ms batch budget with
instance defaults and startup overrides. Plugin-owned effects use the declared
live dispatcher and narrow committed context. Existing custom handlers remain
available as a fallback. Post-commit failure stops later work and preserves
state, revision, and the successful turn reply.

## Checks

- Final normal package tests: **1729 passed**, 1161 existing exclusions, seed 0.
  No new skips were added.
- Final focused suite: **114 passed**, including 13 new tests.
- Final Covenant gate: **246 passed**; AgentServer2 **61/61**, Agent **25/25**,
  Topology **17/17** obligations; **103/103** overall.
- Focused line coverage: main module **786/818, 96.09%**; Runtime **16/19,
  84.21%**; combined **802/837, 95.82%**. Measurements include generated line 0.
- Updated demo passes in both test and development environments. It checks live
  commit notification and Plugin directive dispatch before Stop.
- Compile with warnings as errors, explicit format checks, and strict Credo on
  the new test file pass. Broad Credo still reports existing package findings;
  it is not a passing package lint gate. Dialyzer and package publication checks
  were not repeated in this step; the prior limitations remain recorded below.

## Focused mutations

The catalog has **1317 sites**; catalog generation executes no mutants. Only
14 selected sites run. The previous full Agent mutation run is not repeated.
The first run exposed two test gaps: delayed completion of the last hook and
starting the directive budget only after the last hook. Both tests now hold the
last hook, with message barriers and real deadline waits.

Final result: **14/14 selected mutants killed**, with exact credit. There are
**0 survivors, 0 invalid mutants, 0 timeouts, and 0 partial results**. Both
worker baselines pass 114 tests. Fail-fast is off. No survivor annotations were
added. This is a focused result and does not establish a full component score.

Source SHA256: `67052ffc2783723fc7c78872f53719f28418ac8df3f2d2fa239359091b8c431b`.
Artifacts: `tmp/covenant/agent-server2/36-37/` (catalog, selection, original
source, initial report, final report, and per-module line coverage).

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test test/contract/agent_server2 --seed 0
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test.contract
env MIX_ENV=dev ERL_FLAGS='+S 2:2' mix run --no-start agent_server2_demo.exs
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0284,m0648,m0843,m0844,m0853,m1072,m1104,m1114,m1116,m1127,m1151,m1154,m1162,m1165 --jobs 2 --seed 0 --timeout 4000 --max-runtime 300000 --out tmp/covenant/agent-server2/36-37/focused.json
```

The previous checkpoint follows as historical evidence.

---

# AgentServer2 Covenant baseline — items 31–35

## Scope

Only `jido` changes. The runtime stays in `lib/jido/agent_server2.ex`, including
its nested `Runtime` owner monitor and supervisor connection. Existing
AgentServer and its support files, the public authoring DSL, dependencies, and
the other thread's design documents are unchanged by this step.

Items 31–35 add explicit/default/self Signal destinations, instance Bus scope,
Stop, reported errors, supervised application process startup, owned Plugin
trees, readiness, and ordered live admission. Existing Plugin callback adapters
and envelopes supply callback validation and state ownership. Runtime handles
stay outside Agent state. All roots start before ordered readiness checks.
Inspection remains available during startup; turns return `not_ready` until
readiness succeeds. Registry lookup advertises only ready activations.

Readiness has a separate finite 5000 ms default budget. An independent owner
monitor also stops provisional trees when a child start callback is blocked.
Root loss stops this activation; root replacement remains item 38. SpawnProcess
children belong to the instance supervisor and can outlive AgentServer2.
A timed-out supervisor request cannot revoke external work or an in-flight start.
Plugin commit notifications and Plugin directive dispatch remain items 36–37.

## Final checks

- Normal package tests: **1716 passed**, 1161 existing exclusions, seed 0.
  No new skips or exclusion tags were added.
- Focused suite: **101 passed**. Both final mutation worker baselines also
  run these 101 tests. All fixtures remain in the scoped test folder.
- Covenant gate: **233 passed**. AgentServer2 **54/54**, Agent **25/25**, and
  Topology **17/17** obligations have passing tests: **96/96** total.
- Main-module line coverage: **721 covered, 33 uncovered, 95.62%**.
  Nested Runtime: **16 covered, 3 uncovered, 84.21%**. Both raw measurements
  count generated line 0 as uncovered. Runtime's other unexecuted lines are
  independent supervisor-exit handling and the final forced-stop fallback.
  Together these two measured modules have **737/773 lines, 95.34%**.
  This is focused coverage; Store, Pending, dependencies, and the whole package
  are not included in this line-coverage measurement.
- Demo passes readiness gating, live admission, self-emission, supervised
  application process startup, Stop cleanup, and the earlier request/turn/effect
  checks. Its original main server still ends at count 4 and revision 4.
- Compile with warnings as errors, explicit format checks, strict Credo on all
  ten scoped test source files, and ExDoc HTML generation pass.
- Full Dialyzer still reports **12 warnings** in generated/test code and the
  unchanged caller-ancestry helper. It is not green. No filters were added.
- Broad package Credo also reports existing style/design findings and the
  existing turn_id Logger metadata warning. It is not a green package lint run.
  The separate ten-file focused lint run passes.
- Hex package build is blocked by existing local path dependencies
  `jido_action`, `runic`, and `zoi`. Dependency declarations remain unchanged.

The reported-error Signal test first exposed a success summary used by one
failure-policy path. Both policy callbacks and error Signals now use one shared
summary. Reported effect failure does not replace the saved successful turn.
Error Signal Bus targets also inherit the instance. A regression test checks the
summary, safe data, and instance scope before the final mutation check.

## Focused mutations

The final profile contains **1239 sites** across `Jido.AgentServer2` and its nested
`Runtime`. Only **18 sites** are executed in the final check. The initial check
caught 17 selected sites before the shared-summary correction. The final check
reruns those 17 sites and adds the shared-summary branch. The old results and
source are retained separately; they are not substituted for the final check.
No full catalog or previous 1302-mutant Agent run is repeated.

Final result: **18/18 selected mutants killed**, with exact credit. There are
**0 survivors, 0 invalid mutants, 0 timeouts, and 0 partial results**. Both
worker baselines pass all 101 focused tests. Fail-fast is off. This is a focused
result, not a full component score. No survivor annotations were added.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test --seed 0
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test.contract
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start agent_server2_demo.exs
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0040,m0044,m0046,m0280,m0538,m0549,m0571,m0591,m0592,m0596,m0791,m0822,m0823,m1044,m1057,m1099,m1101,m1206 --jobs 2 --seed 0 --timeout 4000 --max-runtime 300000 --out tmp/covenant/agent-server2/31-35/focused.json
```

IDs apply only to the final source and two-module profile below.
Catalog enumeration does not execute mutants.

| ID | Site | Operator | Change |
| --- | --- | --- | --- |
| m0040 | 155:15 | statement_removal | `Process.exit(data.supervisor, :kill)` → `(removed)` |
| m0044 | 166:32 | logical_swap | `or` → `and` |
| m0046 | 168:15 | statement_removal | `Process.exit(data.supervisor, :kill)` → `(removed)` |
| m0280 | 495:26 | comparison_swap | `!=` → `==` |
| m0538 | 888:61 | boolean_flip | `true` → `false` |
| m0549 | 913:9 | element_removal | `plugin_state: plugin_state(data.agent, spec)` → `(removed)` |
| m0571 | 981:5 | condition_negate | `if owned_process?(caller, data.bootstrap.task.pid, MapSet.new(…` → `if !(owned_process?(caller, data.bootstrap.task.pid, MapSet.new(…)` |
| m0591 | 1013:48 | comparison_swap | `<` → `>=` |
| m0592 | 1014:11 | statement_removal | `mark_ready(data)` → `(removed)` |
| m0596 | 1042:11 | return_nil | `{:stop, {:shutdown, :plugin_runtime_lost}, data}` → `nil` |
| m0791 | 1312:5 | return_nil | `with {:ok, inputs} <- Jido.Agent.Plugin.prepare(agent, sign…` → `nil` |
| m0822 | 1405:34 | clause_removal | `cond match?({:stop, _}, result) ->` → `(removed)` |
| m0823 | 1413:44 | clause_removal | `cond match?({:reported_error, _}, result) ->` → `(removed)` |
| m1044 | 1737:51 | comparison_swap | `!=` → `==` |
| m1057 | 1756:5 | condition_negate | `if is_nil(config.jido)` → `if !(is_nil(config.jido))` |
| m1099 | 1833:15 | clause_removal | `case nil ->` → `(removed)` |
| m1101 | 1832:23 | logical_swap | `&#124;&#124;` → `&&` |
| m1206 | 2006:9 | condition_negate | `if active.effect_outcome` → `if !(active.effect_outcome)` |

Ignored local evidence is under `tmp/covenant/agent-server2/31-35/`:
`catalog.json`, `selected.json`, `focused.json`, `source-tested.ex`, per-module
line coverage, and the preserved initial profile/results/source. Test and check
logs are under `/tmp/server2-31-35-*.log`.

Final source SHA256: `77f8fcd9e7d172bd2c50d9a63367c04800bc5f4172aeea9807d46bb67073be25`.
Existing AgentServer SHA256 remains
`6820ad1943e8ec2f053467d87ac7ec6db9613712e41c1fad82aa02c9eee9b29f`.

## Historical checkpoint: items 26–30

# AgentServer2 Covenant baseline — items 26–30

## Current scope

AgentServer2 remains in `lib/jido/agent_server2.ex`. The only other runtime edits
are the instance option and stored-default connection in `lib/jido.ex` and
`lib/jido/instance/options.ex`. Existing AgentServer and its support modules,
Agent/Topology authoring, dependencies, and the other thread's design documents
are unchanged by this step. Public DSL syntax is unchanged.

This step adds stable transient child identity, instance supervision and lookup,
partition ownership, OTP names and liveness, instance runtime defaults, complete
pre-commit directive admission, and ordered owned post-commit effects. Explicit
Emit dispatch and Plugin-owned custom directives with a handler are supported.
Implicit destinations, process/control directives, Plugin runtime trees, and
persistence remain outside this step. Instance restart uses the original Agent;
it does not restore commits.

## Validation

- Normal package run: **1,688 passed**, 1,161 existing exclusions, seed 0. Two
  additional fault tests were then added and pass in the focused and Covenant
  checks below. No new skip or exclusion tags were added.
- Focused suite: **75 passed**. The 73-test intermediate suite also passes with
  seed 41. Both mutation baselines use 75 tests with seed 0. The final guard-loss
  assertion change is verified by the 75-test baseline and single-site rerun.
- Complete Covenant gate: **207 passed**; AgentServer2 **44/44**, Agent 25/25,
  Topology 17/17 active obligations have passing tests (86/86 total).
- Main-module line coverage: **595 covered, 23 uncovered, 96.28%**. Generated
  line 0 is in the uncovered list. Nested Store/Pending and dependencies are not
  part of this measurement.
- Demo passes instance lookup/defaults, commit reply while an adapter is blocked,
  ordered effects, live reads and progress, queue replay, cleanup, and explicit
  stop without restart. The original demo still ends at count 4, revision 4.
- Compilation with warnings as errors, format checks, and strict Credo for all
  nine focused test source files pass.
- Full Dialyzer with the existing PLT reports **12 warnings**: generated Action
  JSON contracts in examples/fixtures, a deliberate improper-list fixture, and
  two opacity warnings in the unchanged AgentServer2 caller-ancestry helper.
  Dialyxir also fails to format one of those warnings. This is not a green
  Dialyzer result. No warning filters or dependency changes were added.
- ExDoc HTML generation passes in dev.
- Hex package build is blocked by the existing local path dependencies
  `jido_action`, `runic`, and `zoi`. They were not changed for this task.

## Focused mutation checks

The catalog contains 1,064 sites. Only **18 distinct sites** were selected.
The first check detected 17 sites and timed out on the removed registration-guard
monitor. The test had waited on a turn reply before checking owner exit. It now
checks the DOWN message first, so the missing monitor produces an assertion
failure within one second. A single-site rerun detects that mutant with exact
credit. No survivor annotation was added.

Final evidence across the two checks: **all 18 selected sites are detected**.
There were no invalid mutants or partial results. The initial timeout is retained
in the first report; it is resolved by the second report, not rewritten as a kill.
Nineteen mutant executions cover 18 distinct sites. Both checks run without
fail-fast. This is not a full component score. The earlier 1,302 Agent mutants
were not rerun.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test test/contract/agent_server2 --seed 41
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test.contract
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start agent_server2_demo.exs
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0032,m0085,m0093,m0431,m0438,m0691,m0696,m0697,m0894,m0906,m0911,m0917,m0923,m0924,m0926,m0932,m0945,m0948 --jobs 2 --seed 0 --timeout 4000 --max-runtime 300000 --out tmp/covenant/agent-server2/26-30/focused.json
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m0431 --jobs 1 --seed 0 --timeout 4000 --max-runtime 120000 --out tmp/covenant/agent-server2/26-30/guard-check.json
```

IDs apply only to the `source-tested.ex` hash below. Catalog enumeration executes no
mutants. Tests were extended for the guard rerun; executable runtime code is identical
across the two checks. After those checks, one docstring reference to the hidden
Store module was changed to plain text so ExDoc has no hidden-module warning.
`source-tested.ex` retains the exact mutation source; no executable code changed.

| ID | Site | Operator | Change |
| --- | --- | --- | --- |
| m0032 | 148:7 | element_removal | `restart: :transient` → `(removed)` |
| m0085 | 243:9 | condition_negate | `if is_nil(opts[:partition])` → `if !(is_nil(opts[:partition]))` |
| m0093 | 252:57 | comparison_swap | `==` → `!=` |
| m0431 | 722:36 | element_removal | `Jido.registration_guard_name(jido)` → `(removed)` |
| m0438 | 737:18 | statement_removal | `Registry.update_value(registry, key, fn _ -> :ready end)` → `(removed)` |
| m0691 | 1089:74 | clause_removal | `cond System.monotonic_time(:millisecond) >= data.active.effect_d… ->` → `(removed)` |
| m0696 | 1092:14 | comparison_swap | `==` → `!=` |
| m0697 | 1093:62 | arithmetic_swap | `+` → `-` |
| m0894 | 1405:50 | comparison_swap | `>` → `>=` |
| m0906 | 1429:43 | logical_swap | `and` → `or` |
| m0911 | 1443:62 | arithmetic_swap | `+` → `-` |
| m0917 | 1453:18 | element_removal | `{:next_event, :internal, :effect_next}` → `(removed)` |
| m0923 | 1460:43 | comparison_swap | `>=` → `<` |
| m0924 | 1463:27 | comparison_swap | `==` → `!=` |
| m0926 | 1471:11 | element_removal | `agent: data.agent` → `(removed)` |
| m0932 | 1477:11 | element_removal | `state_version: data.state_version` → `(removed)` |
| m0945 | 1506:7 | element_removal | `status: status` → `(removed)` |
| m0948 | 1509:7 | element_removal | `committed_version: data.state_version` → `(removed)` |

Local raw evidence (ignored by Git) is in `tmp/covenant/agent-server2/26-30/`:
`catalog.json`, `selected.json`, `focused.json`, `guard-check.json`, and
`line-coverage.json`.

| File | SHA-256 |
| --- | --- |
| `lib/jido/agent_server2.ex` | `b980e16cb41d0b87e909abf5b2b9cebd7f8f35a59e32bd273d6bd058918c6814` |
| `tmp/covenant/agent-server2/26-30/source-tested.ex` | `c4217c94196d7232ebb624e5fd7129ca4a73577e32e907cfe8ef6b529a59077a` |
| `tmp/covenant/agent-server2/26-30/focused.json` | `014eae01b2e38de0614d01dc55fa03d199961a3278b83669a1120663f8a8f95e` |
| `tmp/covenant/agent-server2/26-30/guard-check.json` | `decf7adc81565f152ef11eb15e7cb37c2595d030efa81d28012f5c1d43ea3cd2` |

The following records describe earlier source checkpoints.

# Previous checkpoint: items 21–25

## Current scope and result

The runtime remains in one file: `lib/jido/agent_server2.ex`. Existing AgentServer,
Agent and Topology authoring, dependencies, and the other thread's design documents
are unchanged by this step. The local `../covenant` fork supplies the test runner.

There are **55 focused tests and 34 active obligations**. Items 21–25 add execution
policy, one terminal outcome, bounded failure policy, telemetry and trace context,
and opt-in bounded history. Retry scheduling stays in the owned Runic Worker.
The outer deadline and commit decision stay in AgentServer2.

Validation:

- Focused suite: 55 passed with seeds 0 and 41. After a small fixture-only
  simplification, all 55 pass again with seed 0 under line instrumentation.
- Normal package suite: 1,670 passed, 1,161 existing category exclusions. No new
  skip or exclusion tags. This is `mix test`, not the six-category `mix test.all`.
- Complete Covenant gate: 187 passed; AgentServer2 34/34, Agent 25/25, and
  Topology 17/17 active obligations have passing tests (76/76 total).
- Main-module line coverage: 430 covered, 16 uncovered, **96.41%**. The uncovered
  list includes generated line 0. Nested Store/Pending modules and dependencies
  are outside this measurement.
- Demo smoke checks pass, including timeout/cancellation cleanup. Its original
  main server ends at count 4 and revision 4. The new separate policy example
  checks safe error Signals, terminal summaries, and bounded history.
- Compilation with warnings as errors, format checks, and strict Credo for all
  eight focused test source files pass.

## Current focused mutation check

The source catalog contains 764 sites. Only **15 selected sites** ran: **15 killed,
zero survivors, zero invalid mutants, zero timeouts, and zero partial results**.
All verdicts have exact credit; fail-fast was off. No survivor exemptions were added.
This is a focused safety check, not a full component score. The 1,302 Agent mutants
were not rerun.

The selected decisions cover the callback deadline, eligible retries, attempt
limits, commit revision, cancellation/timeout classification, error counting,
commit indication, summary schema, settled events, history opt-in and retention,
error thresholds, and the error-Signal loop guard.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test test/contract/agent_server2 --seed 41
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test.contract
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix run --no-start agent_server2_demo.exs
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m481,m514,m519,m520,m641,m648,m649,m652,m663,m675,m701,m702,m704,m722,m726 --jobs 2 --seed 0 --timeout 4000 --max-runtime 300000 --out tmp/covenant/agent-server2/21-25/focused.json
```

IDs apply only to the source hash below. Enumerating a catalog executes no mutants.

| ID | Site | Operator | Change |
| --- | --- | --- | --- |
| m481 | 801:5 | condition_negate | `if System.monotonic_time(:millisecond) >= data.active.policy_d…` → `if !(System.monotonic_time(:millisecond) >= data.active.policy_d…)` |
| m514 | 880:7 | element_removal | `max_retries: Keyword.get(opts, :max_attempts, 1) - 1` → `(removed)` |
| m519 | 885:7 | element_removal | `retry_if: {Jido.Action.Error, :retryable?, []}` → `(removed)` |
| m520 | 880:56 | arithmetic_swap | `-` → `+` |
| m641 | 1063:73 | arithmetic_swap | `+` → `-` |
| m648 | 1076:26 | clause_removal | `case :cancelled ->` → `(removed)` |
| m649 | 1077:29 | clause_removal | `case :turn_timeout ->` → `(removed)` |
| m652 | 1081:39 | condition_negate | `if status == :failed` → `if !(status == :failed)` |
| m663 | 1090:47 | comparison_swap | `==` → `!=` |
| m675 | 1105:7 | element_removal | `state_version_after: data.state_version` → `(removed)` |
| m701 | 1142:38 | element_removal | `:settled` → `(removed)` |
| m702 | 1148:7 | condition_negate | `if data.debug` → `if !(data.debug)` |
| m704 | 1150:30 | comparison_swap | `>` → `>=` |
| m722 | 1174:29 | comparison_swap | `>=` → `>` |
| m726 | 1178:45 | element_removal | `active: %{signal_type: @error_signal}` → `(removed)` |

Raw evidence is local and ignored by Git:

- `tmp/covenant/agent-server2/21-25/catalog.json`
- `tmp/covenant/agent-server2/21-25/selected.json`
- `tmp/covenant/agent-server2/21-25/focused.json`
- `tmp/covenant/agent-server2/21-25/line-coverage.json`

| File | SHA-256 |
| --- | --- |
| `lib/jido/agent_server2.ex` | `29f66860f1f429dafab1c42d9ee664568277085576d05c4c2d429e5931d96d5b` |
| `tmp/covenant/agent-server2/21-25/focused.json` | `2892f4648ed36371645ec78e525b1ce254411cfc132b23990bd62d2e76d43229` |

The following record describes the earlier source and is retained for comparison.

# Initial checkpoint: items 1–20

## Scope

Component: `jido.agent_server2`. Implementation target: `Jido.AgentServer2` only.
The suite contains 36 tests for 25 active obligations. The runtime file is unchanged
by this rollout. Existing AgentServer and dependency source are unchanged.

The local `../covenant` fork supplies the mutation runner. No dependency changes
or fork changes are required. The suite runs under Elixir 1.20.4 / OTP 29.1.
The declared Elixir 1.18 / OTP 27 floor was not checked in this rollout.

## Focused mutation result

The catalog contains 444 sites. Only the following 15 sites were selected.
Final result: **15 killed, zero survivors, zero invalid mutants, zero timeouts,
and zero partial results**. Every mutant ran the component tests without
fail-fast. Both workers passed the original suite again before retirement.
No survivor exemptions were added. This is not a full component score.
The earlier 1,302-mutant Agent run was not repeated.

The first run used 32 tests: 14 sites were killed and one survived. The survivor
removed the final cleanup deadline check. A new test now queues the cleanup
result before the timeout message while the server is suspended, waits past
the deadline, and then resumes the server. The original code must reject the
candidate even though it reads the cleanup result first. The final 36-test run
kills this mutant. The other added tests cover unlimited admission, maximum
finite waits, and completion/cancellation races.

```sh
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix test test/contract/agent_server2 --seed 41
env MIX_ENV=test ERL_FLAGS='+S 2:2' mix covenant.mutate jido.agent_server2 --only m125,m138,m159,m306,m311,m312,m317,m345,m367,m372,m385,m394,m421,m423,m425 --jobs 2 --seed 0 --timeout 4000 --max-runtime 300000 --out tmp/covenant/agent-server2/final-focused.json
```

IDs apply only to this source and module profile. Check the site and mutation
before reusing them after edits. Catalog enumeration executes no mutants.

| ID | Site | Operator | Change |
| --- | --- | --- | --- |
| m125 | 299:5 | condition_negate | `if System.monotonic_time(:millisecond) >= deadline` → `if !(System.monotonic_time(:millisecond) >= deadline)` |
| m138 | 318:31 | guard_removal | `when is_integer(timeout) and timeout in 0..@max_timeout` → `(no guard)` |
| m159 | 363:63 | guard_removal | `when owner == self()` → `(no guard)` |
| m306 | 603:24 | element_removal | `_global: context` → `(removed)` |
| m311 | 615:32 | clause_removal | `cond data.active.abort_reason ->` → `(removed)` |
| m312 | 616:29 | clause_removal | `cond expired?(data.active) ->` → `(removed)` |
| m317 | 624:53 | return_nil | `cleanup(data, result)` → `nil` |
| m345 | 686:16 | return_nil | `Logger.put_process_level(self(), :error)` → `nil` |
| m367 | 741:87 | clause_removal | `cond data.max_postponed_signals != :infinity and count >= data.m… ->` → `(removed)` |
| m372 | 741:57 | comparison_swap | `>=` → `>` |
| m385 | 766:22 | element_removal | `data.active.worker` → `(removed)` |
| m394 | 773:74 | boolean_flip | `true` → `false` |
| m421 | 801:39 | clause_removal | `case {:ok, candidate, _directives} ->` → `(removed)` |
| m423 | 802:72 | arithmetic_swap | `+` → `-` |
| m425 | 802:74 | integer_shift | `1` → `0` |


## Local evidence

- Catalog: `tmp/covenant/agent-server2/catalog.json`.
- First result, with the detected gap: `tmp/covenant/agent-server2/focused.json`.
- Final result: `tmp/covenant/agent-server2/final-focused.json`.

| File | SHA-256 |
| --- | --- |
| `lib/jido/agent_server2.ex` | `0c66d0f615ea0dbaa4ecc854f94e41d6ad9af6f1fe5c3655e6a33944dc90eba0` |
| `tmp/covenant/agent-server2/final-focused.json` | `cb295c64d535e3bd401bdeefb23ff364070ccac660ce88631183dba77509af01` |


## Validation

- Standalone suite: 36 passed with seed 41; the mutation baselines also pass with seed 0.
- Complete Covenant gate: 168 passed; all 67 active obligations have passing tests,
  including all 25 AgentServer2 obligations.
- Normal package suite: 1,651 passed, with 1,161 existing category exclusions.
  No new skip or exclusion tags are added.
- AgentServer2-only line coverage: 279 covered lines, 14 uncovered, 95.22%,
  measured with OTP `:cover` and these 36 tests. The uncovered list includes
  generated line 0. This measures the main module, not nested Store/Pending
  modules, dependencies, or package-wide coverage. Evidence:
  `tmp/covenant/agent-server2/line-coverage.json`.
- Format checks and compilation with warnings treated as errors pass.
- Focused strict Credo checks all six test source files and reports no issues.

The normal package run uses `mix test --seed 0`, which retains the existing
category filters. It is not the six-category `mix test.all` run. The existing
AgentServer suite runs as part of this normal package check.
