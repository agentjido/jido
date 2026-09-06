# Jido core performance plan

Target: `agentjido/jido`, branch `v3-spike`.
Status: 36 of 50 idea rounds are complete. Nine fixes were accepted (05, 07,
08, 09, 14, 16, 18, 31, 39). Six ideas were rejected after measurement (01, 02, 06,
10, 11, 17). Twenty-one were rejected by source inspection. The other 14 rounds
remain. See [source decisions](../performance/cycle-inspection.md) and individual
round reports. The [complete checks](../performance/phase-36-checks.md) passed
with 83.5% core coverage; the same 11 known example failures remain.

## Aim

Reduce execution time and memory use. Preserve public return values, complete
Agent state, Plugin order and state ownership, serial Turns, commit rules,
structured errors, telemetry contracts, and resource cleanup. Do not remove
validation at a public boundary to obtain a lower time.

The benchmark tool follows the local jido_action v3 suite. It separates untraced
time samples from traced resource samples and copied-term probes. See
[the benchmark guide](../../guides/benchmarks.md) for commands and limits.

## Baseline

1. Use the current committed `v3-spike` after the Action and Signal upgrade is
   complete. Keep unrelated working changes out of the experiment checkout.
2. Run all core, integration, flaky, and example tests. Record existing failures.
3. Freeze benchmark scripts. Record their hash, both commits, both source hashes,
   lockfile hash, Elixir, OTP, ERTS, CPU, host, scheduler count, and Mix environment.
4. Use separate worktrees and build directories. Compile before timing. Use an
   idle host with `ERL_FLAGS='+S 2:2'`. Run benchmark VMs one at a time. Stop other
   test, build, and benchmark jobs during measurements.
5. Run short and scale profiles. Inspect raw samples. Select representative hot
   cases from both absolute time and memory cost. Use `:eprof`, `:fprof`, or
   `mix profile.tprof` in a separate diagnostic run when the cause is unclear.
   Profiling results are not timing evidence.
6. Run an unchanged baseline pair first. This establishes host and measurement
   variation. Repeat this control after a runtime, host, or dependency change.

## One optimization round

1. Select one numbered idea. State the cause, expected gain, affected cases,
   acceptance metric, and contracts at risk before changing code.
2. Confirm the cost with the current implementation. Add a focused fixture if
   the suite does not reach the path. Freeze the updated scripts for both sides.
3. Make one small implementation change in the candidate worktree. Add a
   meaningful regression test when control flow, state, or cleanup can change.
4. Run the focused tests and smoke suite. A failed result or cleanup check rejects
   the candidate. Fix the experiment before time measurements continue.
5. Run at least five fresh-VM pairs. Alternate baseline/candidate order. Use the
   same script path from both worktrees. Keep all raw reports and command logs.
6. Accept only if the target has a repeatable gain. Initial gate: median paired
   time ratio at most 0.95, or copied retained bytes at most 0.90. The gain must
   exceed control variation and have the same direction in at least four pairs.
   For microsecond operations, increase repeated work or sample count first.
7. Check other affected cases. A time or memory regression above 5% requires
   investigation. Do not trade a major memory increase for a small time gain.
   Exact copy size or allocation evidence is stronger than a small heap bucket
   change. Observed peak memory is sampled; it is not an allocation total.
8. Run required tests and quality checks for an accepted change. Record the
   candidate commit, evidence paths, ratios, and result in the round record.
   Use Conventional Commits. Push accepted fixes to `v3-spike` without force.
   Rebase onto new upstream commits and repeat affected checks before pushing.
9. Reject a change when it fails a contract or gives no repeatable gain. Revert
   only that experiment. Record the reason. A rejected round counts as a round;
   a benchmark repetition does not count as a new optimization idea.

Use `bench/repeat.py` for paired measurements of one candidate. It does not
edit code, select ideas, accept changes, or push commits. The agent performs
those steps after it reviews evidence. `--rounds 50` is a final repeated
measurement run, separate from the 50 idea rounds below.

## Fifty ideas

The order is an initial order. Measured costs can change it. Each row starts as
`pending`. Code inspection can reject an idea only with a recorded reason.
An unmeasured idea must not be reported as a measured improvement.

| Round | Target and hypothesis | Evidence and contract check | State |
| ---: | --- | --- | --- |
| 01 | Thread normalization: use one list pass | `thread/normalize`; exact sequence, defaults, IDs | rejected |
| 02 | Thread append: compute new entry count once | `thread/append_batch`; revision and stats | rejected |
| 03 | Thread append: use cached base count if its invariant holds | Long existing Thread; manually built and restored values | rejected |
| 04 | Thread slice: stop after the upper bound if order is guaranteed | `thread/slice`; gaps and custom sequence values | rejected |
| 05 | Thread kind filter: avoid a list for one kind | Add mixed-kind fixture; nil and invalid kind behavior | accepted |
| 06 | Entry normalization: avoid repeated option lookup per batch | `thread/normalize`; custom ID generator calls | rejected |
| 07 | Audit record: generate default ID only when needed | `audit/record`; explicit/default IDs and UUID validation | accepted |
| 08 | Audit record: get default time only when needed | Explicit/default timestamps; zero timestamps | accepted |
| 09 | Audit update: skip list copy for empty new records | `audit/update`; enforce limit on existing excess | accepted |
| 10 | Audit update: drop old prefix before concatenation | Full buffer and batches; exact record order | rejected |
| 11 | Audit update: new batch fills the buffer | Batch at and above limit; retain exact last records | rejected |
| 12 | Deep merge: empty right map fast path | `state/merge`; struct replacement contract | rejected |
| 13 | Deep merge: empty left map fast path | Add empty-left fixture; struct and keyword behavior | rejected |
| 14 | Deep merge: avoid repeated keyword scans | Add keyword fixtures; duplicate keys and list replacement | accepted |
| 15 | State defaults: fuse default extraction work | `agent/new`; dynamic defaults stay unsupported | rejected |
| 16 | StateBudget: read module limit once per check | `state/budget`; stricter module/instance limit | accepted |
| 17 | StateBudget: reduce intermediate maps in transition | Add replacement fixture; module and limit ownership | rejected |
| 18 | Command: reject reserved keys without scanning all context keys | Add large context; exact structured errors | accepted |
| 19 | Command: avoid intermediate context maps | `agent/prepare`; reserved context and Plugin precedence | rejected |
| 20 | Command: empty Plugin chain fast path | `agent/cmd`; error normalization and validation | pending |
| 21 | Plugin: reuse normalized specs within one command | `plugin/prepare`; callback count and order | pending |
| 22 | Plugin: compose complete schema once within validation | `agent/validate`; reject changed Agent definitions | pending |
| 23 | Plugin: avoid empty directive grouping | No directives and mixed directives; ownership checks | rejected |
| 24 | Plugin: index directive modules within one operation | Add many Plugin directive types; duplicate rejection | pending |
| 25 | Plugin: avoid copying unchanged owned state | Add large Plugin state; protect from Action mutation | rejected |
| 26 | Routing: reuse router within one validation operation | Route counts 1/16/64; defaults and priorities | rejected |
| 27 | Routing: reuse prepared server routing data safely | Mutable neutral definitions and custom handle_signal | pending |
| 28 | Routing: direct path for one exact route | Wildcards, predicates, zero/multiple matches | pending |
| 29 | Agent validation: avoid repeated executable validation within a call | Action and Flow routes; invalid target error contract | pending |
| 30 | Agent transition: avoid duplicate full-state traversals | Large list/map and Plugin state; validation always runs | rejected |
| 31 | Codec encode: avoid repeated Agent validation in generated-registry path | Encode 1/16/64 routes; invalid authoring definitions | accepted |
| 32 | Codec Registry: build reverse lookup for one encode operation | Large Registry; canonical IDs and aliases | rejected |
| 33 | Codec object: avoid sorting fixed field lists repeatedly | Exact allowed/missing key rejection | pending |
| 34 | Codec data: reduce intermediate lists during map traversal | Large metadata; JSON safety and depth/node limits | pending |
| 35 | Checkpoint: avoid repeated definition construction | `agent/checkpoint`; restored identity and module | rejected |
| 36 | Persistence ETS: reduce table-name work per operation | Add put/get/CAS fixture; conflict and table lifecycle | pending |
| 37 | Persistence: reduce repeated encode/copy before CAS | Add durable server fixture; uncertain commit fail-closed | rejected |
| 38 | Server call: reduce default option parsing cost | Default/keyword timeout; reserved context errors | rejected |
| 39 | Server task: reduce closure capture to required values | Large Agent state; actual task transfer size | accepted |
| 40 | Server completion: release large result/context references sooner | Result and failure barriers; state and error policy | rejected |
| 41 | Server queued signals: reduce retained context copies | Add gated backlog fixture; FIFO and capacity rejection | rejected |
| 42 | Server debug buffer: reduce append/trim cost | Add debug-on fixture; bounded history and order | pending |
| 43 | Server snapshot: assess full state copy cost and existing lightweight APIs | `server/snapshot`; do not silently change public data | rejected |
| 44 | Server directives: reduce continuation list copies | Add many directives; order, timeout, post-commit failure | rejected |
| 45 | Observe: avoid duplicate metadata enrichment | `observe/span`; exact telemetry and tracer behavior | pending |
| 46 | Observe: reuse resolved configuration within a span | Noop/custom/strict tracer; runtime config changes | rejected |
| 47 | Scheduler queue: reduce due-item scan or sorting | Add due/not-due fixture; deadline and stable ordering | pending |
| 48 | Scheduler delivery: reduce stored transient data | Add durable enqueue/ack fixture; recovery and duplicates | rejected |
| 49 | Topology activation: reduce repeated reference resolution | Add local multi-Agent topology; readiness and rollback | rejected |
| 50 | Combined fixes: repeat scale and lifecycle checks | Compare original and accepted head; 50 fresh-VM pairs | pending |

## Next experiments

The measured work suggests this order for the remaining ideas. All remain
pending until their own check and decision.

- Round 20: test a direct `Plugin.normalize_all([])` result. Empty declarations
  need no uniqueness scans. Keep public command validation and callbacks.
- Round 22: return the composed schema from common Agent validation and reuse it
  for instance state parsing. Keep a fresh definition check on each call.
  Check Plugin declaration callback behavior before changing normalization.
- Round 36: test a constant table name for the default ETS base. Add get, put,
  successful CAS, and conflicting CAS cases with exact cleanup of fixture keys.
- Round 45: reuse the metadata and tracer already resolved at synchronous span
  start. Keep public async spans and strict failure handling. End-of-span
  correlation enrichment is a separate behavior and must be preserved.
- Round 47: the relevant sort is durable pending-job selection. Compare a single
  pass that chooses the first job after the cursor, or the smallest job on wrap,
  with the current full sort. Check mixed term keys and stable tie behavior.

## Round record

Create `bench/results/cycle/round-NN/decision.md` with these fields. Copy the
accepted summary into a tracked report before raw local files are removed.

- Idea number and hypothesis.
- Baseline and candidate commits; source, tool, and lock hashes.
- Selected cases and reason; control variation.
- Raw report and comparison paths.
- Target time, p95, caller reductions, observed process/binary bytes, copied term
  bytes, helper starts, GC counts, and cleanup results.
- Contract tests and quality checks; exact commands and outcomes.
- Decision: accepted, rejected, or deferred. State the reason.
- Accepted commit and remote branch, or the remaining work for a deferred idea.

## Completion

Complete all 50 records. Do not count a deferred idea as tested. Finish remaining
fixtures before testing those ideas. Run the complete suite with examples,
format, compile with warnings as errors, lint, Dialyzer, docs, and package checks.
Run the 80% coverage gate on core tests and core source only. Exclude example
modules, test fixtures, and benchmark helpers from the coverage calculation. Check Elixir 1.18 / OTP 27 and the available newer runtime.
Push only after checks pass or after a specific existing failure is documented
and shown to be unchanged. Do not lower the 80% coverage requirement.

Publish a final table with accepted fixes, rejected ideas, total paired ratios,
and limits. Keep separate claims for speed, retained memory, sampled peak memory,
and process cleanup. Report missing platform coverage directly.
