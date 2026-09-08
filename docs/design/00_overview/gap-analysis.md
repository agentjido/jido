# Overview seam gap analysis

Status: Evidence report. This report does not approve a design contract.

## Scope and owner

This report reviews only `docs/design/00_overview`. The seam owns the core
model, shared terms, architecture boundaries, and cross-system invariants. The
detailed subsystem documents own their local APIs and implementation plans.

The implemented `lib` code is the source of truth for current behavior. Public
module documentation and tests give supporting evidence. Deferred design text
is a proposal, not an implemented contract. This rule is stated in
`docs/design/00_overview/README.md:5-10` and `guides/core-scope.md:3-5`.

This review covers direct dependencies only where they define the seam:
`jido_signal` owns Signal routing, and `jido_action` owns Action, Flow, and Exec
behavior. It does not review those repositories as complete systems.

## Implemented baseline

The following facts describe current code.

- `Jido.Agent` is the immutable Agent data value. A definition has schema,
  routes, Plugins, and metadata. An instance adds identity and complete state.
  Direct `cmd/3` returns a candidate Agent and Directives. It does not start a
  process or commit live state (`lib/jido/agent.ex:2-21`,
  `lib/jido/agent.ex:458-462`).
- The private `Jido.Agent.Command.Runner` is the shared evaluation mechanism.
  Direct execution uses `run/3`. The Server uses `prepare/4` and
  `finish_for_server/2` around asynchronous Exec work
  (`lib/jido/agent/command/runner.ex:29-61`,
  `lib/jido/agent_server.ex:1419-1429`,
  `lib/jido/agent_server.ex:1469-1481`).
- Current command preparation runs the Plugin `prepare/2` chain before
  `handle_signal/2` performs route selection. A Plugin can change the Signal or
  caller context, but it cannot replace the Agent
  (`lib/jido/agent/command/runner.ex:64-90`,
  `lib/jido/agent/command.ex:2-17`).
- The Signal Router returns all matching targets in precedence order. The Agent
  then requires exactly one target. It returns a routing error when two or more
  routes match (`../jido_signal/lib/jido_signal/router.ex:297-318`,
  `../jido_signal/lib/jido_signal/router/index.ex:95-103`,
  `lib/jido/agent/command/runner.ex:178-193`).
- The Server serializes Signal admission, evaluation, commit, and Directive
  handling. A successful commit writes a runtime checkpoint or durable record,
  installs the complete Agent, increments `state_version` once, replies to the
  caller, and then processes Directives in list order
  (`lib/jido/agent_server.ex:2-15`,
  `lib/jido/agent_server.ex:1493-1545`).
- Directives are validated before commit. Directive work starts after commit.
  A Directive failure does not undo the Agent or its state version
  (`lib/jido/agent_server.ex:1485-1507`,
  `lib/jido/agent_server.ex:1639-1644`,
  `lib/jido/agent_server.ex:1725-1756`).
- An Action or Flow can do synchronous I/O before commit. A command error does
  not undo that I/O (`lib/jido/agent.ex:12-17`,
  `lib/jido/agent_server.ex:12-15`).
- A Plugin can own one state key and its Directive types. Plugin preparation,
  admission, and state reduction are serial and use declaration order. An
  executable cannot change a Plugin-owned state key. A state reducer receives
  only the Directives that its Plugin owns (`lib/jido/plugin.ex:2-24`,
  `lib/jido/plugin.ex:199-205`, `lib/jido/plugin.ex:238-255`,
  `lib/jido/plugin.ex:826-875`).
- Plugin runtime processes are Server children. Their handles are in private
  Server state, not in Agent state. Runtime initialization currently uses
  `%Jido.Plugin.Init{}` with a Server PID, Agent ID, module, instance,
  partition, and options (`lib/jido/plugin/init.ex:1-19`,
  `lib/jido/agent_server/state.ex:28-36`).
- Durable persistence stores a portable checkpoint in a private map record.
  The adapter stores only binary keys and values. Server writes use
  compare-and-swap with the current `state_version` as the expected revision
  (`lib/jido/persistence.ex:1-16`, `lib/jido/persistence.ex:59-98`,
  `lib/jido/agent_server.ex:2920-2929`).
- A nonpersistent Server in a named Jido instance writes the last committed
  Agent and version to `RuntimeStore`. An abnormal Server restart restores this
  runtime checkpoint (`lib/jido/agent_server/runtime_checkpoint.ex:8-34`).
- `AgentServer.status/2` and `snapshot/2` return maps. `Turn.Outcome` is the
  implemented public terminal Turn struct (`lib/jido/agent_server.ex:257-263`,
  `lib/jido/agent_server.ex:381-389`,
  `lib/jido/agent/turn/outcome.ex:1-15`).
- Semantic telemetry has separate Turn, commit, and Directive boundaries. A
  settled event contains bounded identifiers and status data. It excludes
  Agent state, payloads, raw error details, process handles, and caller context
  (`lib/jido/telemetry.ex:8-30`).
- The Scheduler `delivery_interval` option and Topology manual repair with
  `Controller.reconcile/2` are implemented. They have focused tests
  (`lib/jido/plugin/scheduler.ex:41`,
  `lib/jido/plugin/scheduler/runtime.ex:426`,
  `lib/jido/topology/controller.ex:19-21`,
  `lib/jido/topology/controller.ex:89-90`,
  `test/jido/plugin/scheduler/occurrence_recovery_test.exs:186`,
  `test/jido/topology/controller_test.exs:196`).

## Aligned contracts

The following overview contracts agree with current code and have useful
evidence.

1. Agent data and live ownership are separate. Direct commands return a
   candidate. The Server owns the live commit. Tests show equal direct and live
   state for a single route
   (`test/examples/99_research/99_09_route_selection/route_selection_test.exs:6-14`).
2. One live Turn selects one Action or Flow. Direct and live execution share the
   Runner evaluation logic. `Jido.Exec` supplies the Action and Flow execution
   boundary (`../jido_action/lib/jido_exec.ex:1-18`).
3. A successful Turn increments the commit revision once. A pre-commit error
   preserves state and revision. A post-commit Directive error preserves the
   commit (`lib/jido/agent_server.ex:34-38`,
   `test/jido/agent_server/directive_execution_test.exs:127-169`).
4. Plugin write ownership is enforced. Tests prove declaration order, owned
   Directive filtering, complete state validation, and rejection of executable
   writes to Plugin state (`test/jido/plugin/contract_test.exs:490-503`,
   `test/jido/plugin/contract_test.exs:584-634`).
5. Persistent writes use atomic compare-and-swap. Uncertain writes stop stale
   evaluation and do not dispatch Directives
   (`lib/jido/persistence/adapter.ex:23-41`,
   `test/jido/persistence/indeterminate_write_test.exs:46-93`).
6. Saved values must be portable. Persistence rejects nonportable checkpoint
   data (`lib/jido/persistence.ex:300-315`,
   `test/jido/persistence/checkpoint_portability_test.exs:15-45`).
7. Plugin runtime handles do not enter Agent state. A runtime restart can use
   the public state pull API and preserve committed Agent state
   (`test/jido/agent_server/runtime_lifecycle_test.exs:152-171`,
   `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:14-32`).
8. Direct `Agent.cmd/3` emits no Agent runtime telemetry. Live observation does
   not change the command result. Telemetry data is bounded
   (`test/jido/observe/agent_lifecycle_test.exs:10-45`,
   `test/jido/observe/agent_lifecycle_test.exs:230-270`).
9. The error boundary uses defined Splode error structs. Routing errors from
   `jido_signal` are normalized for direct and live calls
   (`lib/jido/error.ex:1-17`, `lib/jido/agent.ex:40-46`,
   `test/jido/agent_test.exs:650-715`).

## Gaps

### Missing implementation

These items are proposals in the overview and are not current APIs.

1. Core has no `%Jido.Agent.Ref{}`. Registry lookup uses an Agent ID and an
   optional partition. Persistence keys also include the local Jido instance
   module. The same logical namespace cannot move to a replacement instance
   name (`lib/jido/agent_server.ex:295-309`,
   `lib/jido/persistence.ex:153-159`,
   `docs/examples/feature-acceptance-results.md:88-96`).
2. Core has no `%Jido.Agent.Checkpoint{}`, `%Jido.Agent.Commit{}`, or
   `%Jido.Persistence.Record{}`. Checkpoints and persistence records are maps.
   There is no public Commit value (`lib/jido/agent.ex:403-412`,
   `lib/jido/persistence.ex:300-307`).
3. Core has no `%Jido.Agent.Status{}` or `%Jido.Agent.Turn.Status{}`.
   `status/2`, `snapshot/2`, and the active Turn view return maps
   (`lib/jido/agent_server.ex:614-620`,
   `lib/jido/agent_server.ex:1878-1923`).
4. Core has no `%Jido.Plugin.Command{}`, `%Jido.Plugin.Context{}`,
   `%Jido.Plugin.Transition{}`, or `%Jido.Plugin.Contribution{}`. The current
   public input is `%Jido.Agent.Command{}`. Current Plugin state reduction uses
   callback arguments, not the proposed values (`lib/jido/agent/command.ex:1-22`,
   `lib/jido/plugin.ex:67-90`).
5. Core has no `%Jido.Plugin.Runtime.Init{}`, Context, or Status types. It has
   `%Jido.Plugin.Init{}`, `%Jido.Plugin.DirectiveContext{}`, and
   `%Jido.Plugin.SignalContext{}`. Replacement Init does not contain committed
   Plugin state or its matching state version
   (`lib/jido/plugin/init.ex:1-19`,
   `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:35-43`).
6. Core has no `%Jido.Instance.Config{}`. Instance modules return keyword
   configuration (`lib/jido.ex:129-142`).
7. Agent routing does not select only the first target in Router precedence
   order. It rejects multiple targets. Route selection is not fixed before
   Plugin preparation (`lib/jido/agent/command/runner.ex:64-74`,
   `lib/jido/agent/command/runner.ex:178-188`,
   `test/examples/99_research/99_09_route_selection/route_selection_test.exs:23-37`).
8. Plugin read and prepared-input isolation are missing. `prepare/2` receives a
   Command with the complete Agent. A later Plugin can replace changes from an
   earlier Plugin (`lib/jido/agent/command.ex:2-17`,
   `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:22-34`).
9. Checkpoints do not save or enforce a module-owned definition revision.
   Restore can use the current module definition instead of the saved
   definition (`lib/jido/agent.ex:403-420`, `lib/jido/agent.ex:563-574`,
   `docs/examples/feature-acceptance-results.md:98-106`).
10. Durable delete removes the record and its revision history. It does not
    write a tombstone. A delayed initial writer can recreate the record
    (`lib/jido/persistence.ex:137-150`,
    `docs/examples/feature-acceptance-results.md:108-116`).
11. A confirmed persistence conflict does not always stop the Server. The
    configured error policy can continue. Only an uncertain write forces a
    stop in core (`lib/jido/agent_server.ex:1548-1594`,
    `test/jido/persistence_test.exs:305-347`). This does not implement the
    proposed rule that every persistence write error removes write authority.
12. Persistent creation starts Plugin runtimes and waits for readiness, but it
    does not write an initial active durable record after readiness. Durable
    writes occur on commit, hibernate, or clean stop
    (`lib/jido/agent_server.ex:506-533`,
    `lib/jido/agent_server.ex:2907-2949`).

### Design/code conflict

1. `architecture.md:37-50` and `invariants.md:11-17` require route selection
   from the source Signal before Plugin preparation. Current public module
   documentation and code say that Plugin preparation occurs before routing
   and can change the Signal (`lib/jido/agent.ex:19-21`,
   `lib/jido/agent/command/runner.ex:64-74`).
2. `invariants.md:22-23` says that each Plugin receives only declared state
   fields, owned Turn Directives, and owned prepared input. Current `prepare/2`
   receives `%Jido.Agent.Command{agent: complete_agent}`. Current Plugins have no
   observed-field declaration and share one sequential preparation value
   (`lib/jido/agent/command.ex:2-17`,
   `lib/jido/plugin.ex:67-68`).
3. `architecture.md:66-70` and `invariants.md:53-55` say that an abnormal restart
   of a nonpersistent Agent resets it to its initial Agent at version zero.
   Current runtime checkpoints restore the last committed Agent and revision.
   A runtime lifecycle test requires version one after restart
   (`lib/jido/agent_server/runtime_checkpoint.ex:11-31`,
   `test/jido/agent_server/runtime_lifecycle_test.exs:293-326`).
4. `invariants.md:31` says that runtime effects start after commit. This text is
   too broad for current behavior. Actions and Flows can do synchronous I/O
   before commit. Only Directive runtime work is post-commit
   (`lib/jido/agent_server.ex:12-15`,
   `lib/jido/agent_server.ex:1529-1545`).
5. `architecture.md:93-98` names `%Jido.Plugin{}` as a public configuration
   struct. `Jido.Plugin` is a behavior and has no struct. The implemented
   normalized value is private `%Jido.Plugin.Spec{}`
   (`lib/jido/plugin.ex:1-10`, `lib/jido/plugin/spec.ex:1-21`).

### Missing decision

1. Decide which route and Plugin order is the contract. The decision must cover
   direct preparation, live `admit/3`, route predicates, and the meaning of
   source and effective Signals. It must also state whether admission can change
   the executable selection.
2. Decide if Plugin preparation is a shared transformation chain or a set of
   isolated Plugin-owned inputs. Define observed Agent fields and merge rules
   before new Context, Transition, and Contribution structs are added.
3. Decide if nonpersistent restart restores the runtime checkpoint or resets to
   the initial Agent. Both behaviors cannot be invariant contracts.
4. Define write-authority loss for confirmed conflict, confirmed adapter error,
   and uncertain write. State if a stopped activation can be restarted
   automatically and when it must reload storage.
5. Define the initial durable Record operation. State its revision, active
   lifecycle value, compare-and-swap expectation, readiness failure behavior,
   and cleanup behavior.
6. Define tombstone retention, purge, and reactivation rules. A tombstone
   contract is incomplete without the next allowed writer and revision.
7. Define Agent Ref namespace ownership and migration from current
   `{instance, module, partition, id}` storage identity and PID-based APIs.
8. Define definition revision scope. A label alone cannot pin Action, Flow,
   schema, route, and Plugin code for a complete Turn. The live-upgrade probe
   shows that one Flow can execute two loaded code revisions
   (`docs/examples/live-upgrade-results.md:45-63`).
9. Define compatibility and migration for current public maps and structs before
   the proposed public value set replaces them. This includes `Agent.Command`,
   `Plugin.Init`, Plugin contexts, `status/2`, and persistence maps.
10. Define whether `Result` is only the tagged `AgentServer.call/3` tuple or a
    new owned value. Also define its relation to the later `Turn.Outcome`.

### Missing verification

1. The two FA-01 route contract tests are skipped. The two FA-02 isolation
   tests are skipped. The FA-03, FA-04, FA-05, and FA-06 missing-contract tests
   are also skipped. Therefore, these target contracts have executable
   specifications but no passing verification
   (`test/examples/99_research/99_09_route_selection/route_selection_test.exs:23-37`,
   `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:22-34`).
2. No overview conformance test maps all cross-system invariants to current
   code. Existing tests cover separate behaviors, but they do not prove the
   complete proposed command path as one contract.
3. No numbered subsystem index links back to `00_overview/invariants.md`, even
   though `invariants.md:5-6` requires each owner to link the invariant that it
   implements. This makes ownership and verification hard to trace.
4. The current portability checks run at persistence encoding. There is no one
   cross-boundary test that proves all proposed Agent, Plugin, Commit, Record,
   runtime, and observation values obey their stated storage exclusions.
5. The current error tests prove many normalized failures. There is no one
   matrix that checks all public construction, command, lifecycle, persistence,
   and topology entries against the proposed Splode-only rule.
6. Scheduler interval and manual topology repair have focused tests. The
   overview has no direct evidence link to those tests, and it does not state
   the verified limit of each contract.

## Narrow dependency notes

- `jido_signal` owns ordered route matching. It returns all matches in
  precedence order (`../jido_signal/lib/jido_signal/router.ex:3-16`,
  `../jido_signal/lib/jido_signal/router.ex:297-318`). Jido owns the policy that
  currently requires exactly one match. The proposed first-match rule can be a
  Jido policy without a Router API change, but this ownership must be explicit.
- `jido_action` owns `Jido.Exec`, Action, Flow, execution timeout, cancellation,
  and continuation behavior. Jido wraps this boundary with candidate assembly,
  commit, and Directive handling (`../jido_action/lib/jido_exec.ex:1-18`,
  `lib/jido/agent/command/runner.ex:32-41`). Definition revision pinning cannot
  be complete unless the `jido_action` boundary can retain one executable code
  revision for a Turn.
- The package uses a sibling path for `jido_action`, but it uses Hex
  `jido_signal ~> 3.0.0-beta.4` (`mix.exs:351-356`). Cross-package acceptance
  work must test a compatible V3 pair and must not assume uncommitted
  `jido_signal` behavior is in the consumer build.

## Ordered recommendations

The following items are proposals. They do not describe current behavior.

1. Resolve the two direct contradictions first: route-before-preparation and
   nonpersistent restart behavior. Update the overview or change code only
   after each decision is explicit.
2. Lock the smallest shared vocabulary around the current values: Agent,
   source Signal, effective Signal, Turn, candidate, commit revision, live
   result tuple, Turn Outcome, and Directive. Mark every other glossary term as
   proposed.
3. Define the route and Plugin isolation contract. Then enable FA-01 and FA-02
   as the acceptance gate. Keep current write protection and declaration order.
4. Define stable Agent Ref and definition revision together. Both affect
   Registry keys, persistence keys, restore, Directives, and upgrade behavior.
5. Define durable lifecycle Records, write-authority loss, and tombstones as one
   persistence contract. Add tests for create, commit, conflict, uncertain
   write, delete, purge, restart, and reactivation.
6. Define runtime replacement Init from one committed Agent snapshot and
   version. Preserve the current public state-pull recovery path during
   migration.
7. Add public structs only after ownership and compatibility are decided. Do
   not present unimplemented struct names as the current public data boundary.
8. Add links from each numbered subsystem index to the exact overview
   invariants that it owns. Add one evidence table that maps each invariant to
   an implementation test or a missing-contract test.
9. Run focused core tests for every aligned contract. Run the research examples
   only as secondary acceptance tests until each proposed contract is
   implemented.

## Validation

The following checks ran in the current worktree on 2026-09-08.

- The focused Agent, Plugin, persistence-authority, and observation tests passed:
  94 tests, zero failures.
- The selected FA-01 through FA-06 research examples passed 10 implemented
  controls and skipped eight missing-contract tests. There were zero failures.

The commands were:

```sh
mix test test/jido/agent_test.exs test/jido/plugin/contract_test.exs \
  test/jido/persistence/indeterminate_write_test.exs \
  test/jido/observe/agent_lifecycle_test.exs --seed 0

mix test test/examples/99_research/99_03_input_resource_lifecycle \
  test/examples/99_research/99_09_route_selection \
  test/examples/99_research/99_10_plugin_isolation \
  test/examples/99_research/99_11_stable_reference \
  test/examples/99_research/99_12_definition_revision \
  test/examples/99_research/99_13_durable_delete --include example --seed 0
```

## Evidence references

Primary current-behavior evidence:

- `lib/jido/agent.ex:2-46`, `lib/jido/agent.ex:370-423`,
  `lib/jido/agent.ex:458-477`
- `lib/jido/agent/command/runner.ex:29-132`,
  `lib/jido/agent/command/runner.ex:178-269`
- `lib/jido/plugin.ex:2-24`, `lib/jido/plugin.ex:190-255`,
  `lib/jido/plugin.ex:797-875`
- `lib/jido/agent_server.ex:2-42`, `lib/jido/agent_server.ex:1285-1545`,
  `lib/jido/agent_server.ex:1548-1756`,
  `lib/jido/agent_server.ex:1878-1923`,
  `lib/jido/agent_server.ex:2890-2949`
- `lib/jido/persistence.ex:1-16`, `lib/jido/persistence.ex:59-159`,
  `lib/jido/persistence.ex:300-379`
- `lib/jido/persistence/adapter.ex:1-46`
- `lib/jido/telemetry.ex:1-30`
- `guides/core-scope.md:1-22`, `guides/core-scope.md:91-109`

Primary test evidence:

- `test/jido/agent_test.exs:580-858`
- `test/jido/plugin/contract_test.exs:490-670`
- `test/jido/agent_server/directive_execution_test.exs:127-184`
- `test/jido/agent_server/runtime_lifecycle_test.exs:152-180`,
  `test/jido/agent_server/runtime_lifecycle_test.exs:293-326`
- `test/jido/persistence/indeterminate_write_test.exs:35-93`
- `test/jido/observe/agent_lifecycle_test.exs:10-119`,
  `test/jido/observe/agent_lifecycle_test.exs:230-302`
- `test/examples/99_research/99_09_route_selection/route_selection_test.exs:6-37`
- `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:6-34`
- `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:14-43`

The historical result reports use baseline commit `a23091b4` from
2026-09-05. Use them as gap evidence, not as proof of the current worktree test
result (`docs/examples/feature-acceptance-results.md:8-17`,
`docs/examples/live-upgrade-results.md:3-18`).
