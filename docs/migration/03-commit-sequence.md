# Proposed commit sequence

Status: core sequence approved; implementation has not started. Donor preparation is complete.
These are logical final core commits. Refine their
boundaries after the source dependency check, but keep each final commit
buildable. Add a breaking-change footer where a public contract changes.

Start from the M00 plan commit on `v3-spike`, a descendant of `a31b7430`.
The branch contains the SchedEx baseline and planning snapshot. Keep existing published
history. Transfer prepared source `bf6c9fb` as content. Do not merge or cherry-pick
the donor's experiment, fix, or naming history. Its repairs are already in the
source. M03/M04/M07/M11 retain focused acceptance work, not duplicate repairs.

## Order

| ID | Proposed commit title | Depends on | Result |
| --- | --- | --- | --- |
| M00 | `docs: define the V3 Agent migration sequence` | Current branch | This reviewed plan and the source evidence |
| M01 | `test: define V3 migration inputs and acceptance coverage` | M00 decisions | Fixed source manifest, name map, old-test dispositions and reproducible checks |
| M02 | `refactor(agent)!: replace the V2 runtime with the V3 command contract` | M01 | Complete Agent/server/plugin implementation and Basic examples |
| M03 | `test(persistence): prove restored state and uncertain writer boundaries` | M02 | Prepared identity, portability, uncertain-write and format regressions |
| M04 | `test(agent-server): prove remote admission and lifecycle boundaries` | M02, M03 | Prepared remote deadline/liveness and hibernate/restart regressions |
| M05 | `test(examples): port workflow acceptance cases to Agent` | M02 | Nine Workflow fixtures |
| M06 | `test(examples): port LLM acceptance cases to Agent` | M03–M05 | Ten LLM fixtures and shared adapters |
| M07 | `test(examples): prove runtime delivery and recovery with Agent` | M03–M06 | Thirteen Runtime fixtures and external core acceptance files |
| M08 | `test(examples): prove local and remote Agent ownership` | M04, M07 | Six Multi-agent fixtures |
| M09 | `test(examples): port the Factory systems to Agent` | M05–M08 | Four Factory fixtures, local HTTP/SSE tests and runnable demos |
| M10 | `feat(topology): compose and supervise Agent systems` | M08, M09 | Topology implementation, core tests and five catalog fixtures |
| M11 | `test(integration): transfer recovered application scenarios` | M07–M10 | Ten prepared integration scenarios with fixed group recovery |
| M12 | `refactor: complete V3 compatibility and maintenance cleanup` | M02–M11 | Remaining old-feature/test decisions, current-main protections and accurate docs |
| M13 | `test: gate V3 migration on complete example acceptance` | M01–M12 | Full manifest check, repeated example passes, soak evidence and CI gate |
| M14 | `chore: prepare the Jido V3 beta candidate` | M13 acceptance passed | Final QA, migration guide, package/version/release-candidate checks |

M03 and M04 can be developed independently where their edits do not overlap.
Keep the final order explicit. Each commit includes the supporting source and
fixtures required to compile its tests. Some example source may arrive before
the commit that owns its complete acceptance run; record that in the manifest.

## M00–M01: fixed inputs and contracts

- Apply the implemented-design choices in [contracts](01-contracts.md).
  The user deferred redesigns. Record public names, signatures, state/results,
  persistence compatibility, legacy removals, and the approved DIST-03 skip.
- Freeze prepared source `bf6c9fb` and evidence commit `741058d`. Preserve
  original Actor baseline `ba00fcf` as history. Verify the committed lockfile
  and all source hashes before export.
- Use the prepared source-to-target map for all 52 fixtures, tests, shared
  support, JSON examples, profiles, and executable research probes. Names are
  already Agent names. Preserve original provenance fields.
- Adapt the donor check and manifest scripts to core paths. Validate exact
  source bytes, reject destination collisions and missing tests, and retain
  per-test results. Do not apply another identifier replacement.

- Record every old core test as keep, rewrite, replace or retire. List the new
  test owner for each preserved behavior. Do not delete source first and decide
  what was lost afterward.
- Mark source repairs as completed preparation and core checks as pending.
  Keep the user-approved DIST-03 skip explicit in the manifest. Do not exclude all
  research tests to obtain a green baseline.

Exit: the proposed target file set and example count are reproducible. Every
source hash resolves at the pinned commit. The commit adds no partial runtime.

## M02: complete core replacement plus Basic proof

Transfer the mutually dependent runtime together:

- Replace `Jido.Agent`, command/state/validation, and generated authoring with
  prepared Agent code. Add Spark, Builder, Codec, route interfaces and inline Actions.
- Replace the GenServer implementation with the donor `:gen_statem` owner under
  `Jido.AgentServer`; include options/state, active turns, command tasks, directive
  execution, Plugin lifecycle, child lifecycle and checkpoint integration.
- Replace `Jido.Plugin` and its public helper structs. Include built-in runtime
  Plugins referenced by the instance and server. Preserve the prepared reserved keys.
- Transfer the matching `Jido` instance facade, application startup, error and
  observation dependencies, persistence adapter boundary and utility changes.
  Include the prepared persistence, remote admission/liveness, hibernation,
  scheduling, and stale Registry fixes from the start. Defer independent
  `Jido.Topology` code until M10.
- Remove the old Strategy/StateOp, directive executor and Plugin machinery in
  the same commit. Resolve its remaining callers and docs module lists so no
  incompatible V2 path remains active. Record retired tests from M01.
- Adopt the donor Action beta.6 API and matching lockfile entries. Keep the
  patched SchedEx baseline. Resolve build/test support dependencies explicitly.
- Bring over all five Basic fixtures and the shared authoring-format tests.
  Preserve their control barriers, invalid inputs, return assertions, state
  snapshots, ordered dispatch and runtime-free Plugin variant.
- Update core and test `AGENTS.md` to describe the selected V3 command/effect
  contract. A copied claim that all executable work is pure would be wrong.

Exit: compile with warnings as errors; all retained/reworked core tests included
at this point, the two naming-contract checks, the controlled stale Registry
check, and all Basic tests pass. Check no public `Jido.Actor` code exists.
This commit must not temporarily introduce both public Agent and Actor runtimes.

M03 and M04 add the full prepared regression sets. They do not reimplement
the repairs already included in M02. Transfer each test with all supporting
modules. M11 adds the complete prepared group fixtures and their tests.

## M03: persistence boundaries

- Transfer all three persistence probe files: checkpoint identity,
  portability, and indeterminate writes. The prepared set has ten tests,
  including a callback that stores a write and then raises.
- Retain the exact nested identity and recursive portability assertions.
  Compare envelope and restored module/ID; retain partition checks and valid
  nested round trips. Reject PIDs, ports, references, and functions from storage.
- Verify that an unknown write result stops the writer before another Action
  evaluates. Keep shutdown from saving stale state. Preserve the distinction
  between uncertain results and confirmed rejected writes.
- Preserve the adapter contract: indeterminate replies, exceptions, and malformed
  callback results are uncertain. Redis transport failures use the indeterminate
  tag. A new activation restores authoritative state before more work.
- Transfer the Agent naming/format tests with M02 and include them here. Agent
  storage uses `jido:agent:v1:`. Reject old envelopes explicitly. Do not introduce
  automatic Actor or V2 data conversion.
- Port the ETS/File/Redis adapter tests, initial-write failures, conflicts,
  recovery, and direct/live persistence tests. Mocked Redis tests do not prove
  real Redis restart or failover.

Exit: all ten boundary checks, adapter tests, and direct/live recovery pass in
core. No uncertain writer performs a second external Action.

## M04: remote and lifecycle boundaries

- Transfer `test/jido/agent/remote_api_test.exs` and its peer fixtures. It starts
  VMs 6.1 seconds apart and checks both call directions, default/expired calls
  and requests, infinite waits, and live/dead remote PIDs.
- Preserve caller-clock admission checks and their one-second query bound.
  Unavailable clock evidence rejects admission. Do not compare timestamps from
  separate monotonic clock domains. Caller timeout cannot undo active work.
- Preserve bounded remote liveness. A false result during a partition does not
  establish remote death. Retain the richer ownership/disconnect assertions.
- Transfer the immediate hibernate/thaw regression without an arbitrary wait.
  Successful hibernation must finish process termination before return.
- Verify Plugin replacement reads current committed state. Keep persistent and
  nonpersistent restart policies, late-result rejection, cancellation, remote
  disconnection, parent binding, and owned-process cleanup checks.

Exit: the full focused set and repeated hibernate/thaw checks pass in core.
Record actual peer-node execution, not only mocks.

## M05–M06: Workflow and LLM examples

Transfer all source, tests and profiles in groups `02_workflow` and `03_llm`.
Include shared observation/Adapter modules and matching SDKCase helpers. Keep
dependency graphs, Action implementations, loop bounds, failure controls and
fixtures as prepared; record any core-specific change.

Workflow must prove schemas, actual value/control dependencies, parallel overlap,
stable Map order, fail-fast behavior, Reduce, Iterate bounds, Subflow scoping,
continuation and approval as separate Turns. Do not replace Flow execution with
test helpers or manually serialized calls.

LLM must prove the actual requests, tool validation and call-ID ordering,
history across Turns, bounded repair and compaction, real child delegation,
recursive corpus limits and cancellation. Tests use deterministic external
adapters. They are not a benchmark of model quality. Transfer the stress runner
and independent expected-result calculation.

Exit after each commit: its entire group plus all previously imported acceptance
checks pass. Differences from the prepared source have a reason and a regression test.

## M07–M08: Runtime and Multi-agent examples

Transfer both groups and the supporting core tests in the manifest. Seven
fixtures have test-location README files instead of local test files; include
the real `test/jido/observe`, `test/jido/agent` and `test/jido/plugin` tests under
their mapped Agent paths.

Preserve Bus scope, commit-before-ack rules, duplicate ID ledgers, task barriers,
stable work/attempt IDs, recovery on either side of delivery, durable occurrence
generation and acknowledgement. Ordinary directives do not acquire automatic
durability through this transfer.

Multi-agent must prove real child startup/restart/stop, bounded workers, result
ordering, hierarchy cleanup and remote placement. Retain disconnect-versus-death
assertions and explicit replacement after reconnect. Run the VM recovery tests
with actual nodes and preserve the cleanup checks.

Transfer the prepared scheduling correction and controlled early-timer test.
The default clock callback now waits for its scheduled instant before delivery
and return. Keep stable identity for repeated delivery of one slot, and distinct
identity for different instants. Preserve custom-clock behavior. Do not replace
the regression with a fresh ID for each delivered Signal.

Exit: all 19 fixtures and their external acceptance tests pass. No record of
cluster-singleton support is inferred from remote child placement.

## M09: Factory examples

Transfer the four Factory systems, tools/protocol/inspection/async helpers,
interactive launchers, profiles, local HTTP adapter and SSE test server.
Preserve the prepared Factory and Agent identifiers.

Prove history, duplicate handling, FIFO job order, fixed capacity, retries,
pause/resume/cancel, department dependencies, late-result rejection, streaming
completion and cleanup. Flow Factory must use its real nine-worker graph,
parallel joins, ordered Map, Choice, two repair cycles and accepted handoff.
Keep the distinction between proposal artifacts and repository modification.

Exit: all seven Factory test files pass without a provider key. No secrets are
copied into core. A live-provider demo is optional and needs a separate budget.

## M10: Topology

Transfer `lib/jido/topology.ex` and all supporting modules, all core Topology
tests, five examples, JSON fixtures and profiles. Preserve prepared Agent keys in stored
authoring JSON and the declared Codec contract.

Prove DSL/Builder/JSON equality, validation before process startup, independent
state, owned hierarchy, deterministic keyed identity, import/export/binding
scope, partial-start cleanup, repair and final shutdown. The swarm test must
reach all 1,000 workers and check cleanup; preserve the explicit capacity setting.

Exit: all five examples and core Topology tests pass. Document the local scope;
do not promise live replacement or cluster placement that these tests do not prove.

## M11: complete application scenarios

Transfer both prepared files from each of the 10 `test/integration` directories.
The group corrections are complete in the donor. Fixed Group uses instance
Bus scope and restores the exact saved state and handled-task history. Elastic
Group retries saved assignments with a newer attempt and rejects stale attempts
and completion. Transfer its added regression unchanged. Do not redo the original
failed reset-history expectation or remove the saved work.

The original failures and selected replacement contract remain recorded in
[preparation](07-prepared-donor.md) and the original baseline evidence.

Retain audit, coordinator, inbox, identity, purpose loop, ReAct, encrypted/signed
signals and subscription-reconciliation behavior. Use the saved diagnostics as
reproduction aids; a script that prints a defect and exits zero is not a test.

Carry the user's explicit DIST-03 skip with its reason and exact test identity.
The other distributed-authority check remains active. The acceptance gate must
reject any additional unexpected skip or failure. Cluster-exclusive ownership
remains unimplemented; adding it later requires authority and partition tests.

Exit: all application scenarios pass. Every test/assertion change has a contract
reason, and known research failures have an explicit disposition.

## M12: compatibility and maintenance

Finish the removal/test register from M01. Check old API consumers and document
intentional losses. Port current-main state-size budgets and validation-path
transport protection into the new boundaries; add their behavior tests. Keep
the retired tracker absent. Reconcile CI and dependency maintenance.

Compare prepared donor source with the final core examples. Restore accidental
edits. Separate a readability refactor from a behavior change and rerun the
owning tests. Update all current docs and code examples to the selected Agent
contract, with separate labels for unimplemented future designs.

Exit: no unexplained file deletion, lost public behavior, obsolete dependency,
broken API/doc reference or unclassified old test remains.

## M13–M14: acceptance first, beta QA second

M13 adds a single reliable acceptance command and CI job. Verify manifest
completeness, no missing/empty tests, exact source coverage, all 52 fixtures,
supporting core tests and all application scenarios. Run recorded seeds and a
bounded recovery/cleanup workload as specified in [validation](05-validation.md).

Only after this gate passes, M14 performs the full test/coverage/quality/docs
checks, supported-runtime matrix, clean package consumer test and migration-guide
review. Choose the beta version and release notes from the final commits.
Preparing a candidate does not authorize publishing a package or merging a PR.

## History rules

Use Conventional Commits and a `Source: jido_v3@bf6c9fbec569cb6438b6a1629a2768058d439d1f` trailer for transferred
work. Record intentional deviations in the manifest. Internal experiment/fixup
commits may be folded locally before publication. Do not rewrite already shared
commits without a separate synchronization decision.

If a proposed commit cannot compile independently, combine it with its smallest
required dependency. Do not add temporary public Actor aliases or no-op stubs
solely to keep artificial commit boundaries. Recheck the final edited series,
not only the combined working tree. Every published checkpoint must have a clear
scope, useful tests and no hidden required failure.
