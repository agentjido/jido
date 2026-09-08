> Delivery seam gap analysis. This document is pending approval.

# 99 — Delivery gap analysis

## Scope and owner

This report covers only delivery order, acceptance gates, compatibility
periods, retained design history, and direct dependencies between design seams.
It does not review the complete repository. It does not make a subsystem
contract.

The delivery seam owns the cross-system plan and the retained planning record.
Each numbered subsystem owns its detailed contract and implementation. This
boundary agrees with `docs/design/99_delivery/README.md:5-13` and
`docs/design/README.md:31-41`. The design set does not name a release owner or
an approval owner. Thus, this report uses "delivery owner" for the person or
group that maintains the release plan.

## Evidence rule

The following sections state current facts. Code in `lib`, public module
documentation, and executable tests are the source of truth. A pending design
document is not an implemented contract. This rule is in
`docs/design/README.md:1-8` and `docs/design/AGENTS.md:3-20`.

## Implemented baseline

The implemented baseline is a local V3 runtime. It has these delivery-relevant
properties:

- Agent definitions and instances are immutable values. A neutral definition
  and a complete instance are both valid. `Jido.Agent` documents this contract
  in `lib/jido/agent.ex:2-10`. The Server test also starts a neutral definition
  in `test/jido/agent_server/public_api_test.exs:97-114`.
- The DSL, Builder, and Codec are supported authoring forms. The public Agent
  documentation states this in `lib/jido/agent.ex:81-84`. Builder behavior has
  direct tests in `test/jido/agent/authoring_contract_test.exs:34-57`.
- `Jido.AgentServer` is a public PID-based API. Public operations include
  `call/3`, `cast/2`, `send_request/3`, `agent/2`, `status/2`, cancellation, and
  debug history in `lib/jido/agent_server.ex:160-291`.
- One `Jido.Plugin` behavior owns pure preparation, admission, state reduction,
  Directive validation and dispatch, and runtime readiness. See
  `lib/jido/plugin.ex:2-24` and `lib/jido/plugin.ex:67-102`.
- The current command pipeline prepares Plugins before it selects a route.
  `prepare_plugins/3` runs before `prepare_run_turn/2` in
  `lib/jido/agent/command/runner.ex:64-80`. Route resolution requires exactly
  one target in `lib/jido/agent/command/runner.ex:108-117` and
  `lib/jido/agent/command/runner.ex:178-193`.
- Persistence saves use an atomic compare-and-swap operation. Normal delete is
  still a blind adapter delete. The storage key includes the local Jido instance
  and Agent module. See `lib/jido/persistence.ex:77-98`,
  `lib/jido/persistence.ex:137-158`, and `lib/jido/persistence/adapter.ex:20-44`.
- The Agent Server increments `state_version`, writes persistence before it
  changes live state, and starts Directives after commit. See
  `lib/jido/agent_server.ex:1493-1545`. Only an uncertain persistence error
  always stops the Server; other persistence failures use the configured error
  policy. See `lib/jido/agent_server.ex:1548-1568`.
- One Jido instance uses one Agent DynamicSupervisor for Agent Servers and
  Plugin wrapper children. The root strategy is `:one_for_one`. See
  `lib/jido.ex:342-370` and
  `lib/jido/agent_server/plugin_lifecycle.ex:110-155`.
- The branch is an unpublished `3.0.0-beta.1` candidate. Release checks are not
  complete. See `README.md:12-15` and `README.md:148-159`.

The public core scope guide gives the same retained baseline in
`guides/core-scope.md:7-18`. The planning baseline also records it in
`docs/design/99_delivery/planning-baseline.md:25-42`.

## Aligned contracts

These parts of the delivery seam agree with current evidence:

1. The folder states that it is planning history, not a subsystem contract.
   See `docs/design/99_delivery/README.md:3-13`.
2. The old delivery plan states that it is deferred and is not the active plan
   for `v3-spike`. See
   `docs/design/99_delivery/delivery-plan.md:1-16`.
3. The planning baseline retains Builder, Codec, owned children, and the public
   PID API during migration. It also requires a decision and migration evidence
   before removal. See
   `docs/design/99_delivery/planning-baseline.md:91-106` and
   `docs/design/99_delivery/planning-baseline.md:132-161`.
4. The planning baseline gives useful partial dependency chains for Turn,
   Plugin, identity, persistence, definition revision, and Topology work. See
   `docs/design/99_delivery/planning-baseline.md:185-206`.
5. The test policy keeps missing research assertions in the repository and
   excludes them from the core quality result. See `guides/testing.md:17-44`.
   A focused run on 2026-09-08 gave 34 passed tests and 11 skipped tests.
6. The plan requires synchronization barriers instead of `Process.sleep/1`.
   This agrees with `guides/testing.md:3-8` and
   `docs/design/99_delivery/delivery-plan.md:158-159`.

## Gaps

### Missing implementation

These are current implementation gaps that the delivery seam must schedule.
They are proposals, not regressions against the supported API.

| Dependency group | Missing contract | Current acceptance evidence |
| --- | --- | --- |
| Turn boundary | Exact route precedence and fixed executable selection before Plugin preparation | Two skipped FA-01 tests in `test/examples/99_research/99_09_route_selection/route_selection_test.exs:23-37` |
| Plugin isolation | Observed-field projection and one prepared input for each Plugin | Two skipped FA-02 tests in `test/examples/99_research/99_10_plugin_isolation/plugin_isolation_test.exs:22-34` |
| Plugin runtime | Replacement Init with current committed Plugin state and matching state version | One skipped FA-06 test in `test/examples/99_research/99_03_input_resource_lifecycle/runtime_reconstruction_test.exs:35-43` |
| Identity | Stable namespace, partition, and Agent ID across runtime and storage | One skipped FA-03 test in `test/examples/99_research/99_11_stable_reference/stable_reference_test.exs:60-79` |
| Definition | Exact definition revision check on restore | One skipped FA-04 test in `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:22-27` |
| Persistence | Durable tombstone that fences an old writer | One skipped FA-05 test in `test/examples/99_research/99_13_durable_delete/durable_delete_test.exs:26-30` |
| Upgrade | One executable revision for a complete active Turn | One skipped UP-01 test in `test/examples/99_research/99_14_turn_upgrade/turn_upgrade_test.exs:32-49` |
| Upgrade | Atomic definition and state migration | One skipped UP-02 test in `test/examples/99_research/99_15_state_migration/state_migration_test.exs:52-60` |
| Upgrade | Live Topology target update that retains unchanged PIDs and state | One skipped UP-07 test in `test/examples/99_research/99_16_topology_upgrade/topology_upgrade_test.exs:80-97` |

The delivery plan also names larger unimplemented targets. These targets include
public Ref, Checkpoint, Commit, Record, and Status values; separate runtime
pools; full persistence failure rules; and the complete semantic event set.
The planning baseline lists these targets in
`docs/design/99_delivery/planning-baseline.md:67-89`. They do not yet have one
approved release scope.

### Design and code conflict

1. The old sequence tells the implementation to remove Builder and Codec and to
   use only a versioned Agent module. Current code and public documentation
   support Builder, Codec, neutral definitions, and multiple authoring forms.
   Compare `docs/design/99_delivery/delivery-plan.md:20-32` with
   `lib/jido/agent.ex:2-10` and `lib/jido/agent.ex:81-84`.
2. The old sequence makes the Ref-first instance facade the only public live
   API and makes Agent Server operations internal. The current public API is
   PID-based. Compare `docs/design/99_delivery/delivery-plan.md:30-34` with
   `lib/jido/agent_server.ex:160-291`.
3. The old sequence puts full persistent creation and readiness in step 8, but
   it does not add the proposed separate Plugin runtime hosts until step 9. The
   detailed lifecycle requires Plugin runtime readiness before the initial
   Record and before publication. Compare
   `docs/design/99_delivery/delivery-plan.md:33-40` with
   `docs/design/90_package-boundaries/runtime-extension-boundaries.md:242-272`.
4. The old sequence removes the debug timeline. Current public Jido and Agent
   Server documentation still supports it. Compare
   `docs/design/99_delivery/delivery-plan.md:39-41` with
   `lib/jido.ex:203-229` and `lib/jido/agent_server.ex:283-291`.
5. The historical V3 comparison still presents removal directions beside
   current concerns. Its preamble says that these are not active removals, but
   the tables can still look normative. See
   `docs/design/99_delivery/v3-design-changes.md:8-15` and
   `docs/design/99_delivery/v3-design-changes.md:17-28`.
6. The two saved acceptance reports say that the 11 assertions are enabled
   failures and that no test is skipped. The current tests use `@tag skip`.
   Compare `docs/examples/feature-acceptance-results.md:3-17` and
   `docs/examples/live-upgrade-results.md:3-18` with the test evidence in the
   missing implementation table. The planning baseline identifies this drift
   in `docs/design/99_delivery/planning-baseline.md:208-213`, but the source
   reports still contain the old claim.
7. The Turn design puts route selection before Plugin preparation. The Plugin
   facet design puts Agent facet preparation before route selection. Current
   code follows the second order. Compare
   `docs/design/04_turn-evaluation/turn-evaluation.md:74-105`,
   `docs/design/05_plugins/plugin-facets.md:564-577`, and
   `lib/jido/agent/command/runner.ex:64-80`. The two designs must select one
   order before the Turn or Plugin gate can become active.

### Missing decision

1. All design documents in the review index are pending approval. There is no
   approved target contract from which to make a release plan. See
   `docs/design/README.md:43-92`.
2. The delivery seam has two different proposed orders. The old delivery plan
   has ten implementation steps. The planning baseline has eight planning
   steps. Neither document selects one active plan. See
   `docs/design/99_delivery/delivery-plan.md:18-41` and
   `docs/design/99_delivery/planning-baseline.md:132-183`.
3. The eight release-scope questions in the planning baseline are still open.
   They include retained APIs, Plugin facets, checkpoint ownership, stable Ref,
   definition revision, persistence guarantees, upgrades, and observability.
   See `docs/design/99_delivery/planning-baseline.md:226-240`.
4. The Plugin facet proposal cannot implement its Persistence facet until the
   design selects the rule for complete custom Agent checkpoints. See
   `docs/design/05_plugins/plugin-facets.md:416-432` and
   `docs/design/05_plugins/plugin-facets.md:848-864`.
5. There is no one compatibility policy for V3. The Plugin proposal says "the
   rest of the beta or one full minor release." The OpenTelemetry proposal says
   one migration release. The removal proposals for Builder, Codec, neutral
   definitions, PID operations, owned children, and debug have no selected
   support period. See `docs/design/05_plugins/plugin-facets.md:630-648`,
   `docs/design/13_observability/opentelemetry-bridge.md:232-244`, and
   `docs/design/99_delivery/planning-baseline.md:91-106`.
6. No document names the release owner, approval owner, compatibility owner, or
   the person who can accept an exception to a gate.
7. The retained-history policy is not complete. The folder does not define when
   a document becomes an immutable historical record, how a superseded contract
   is marked, or which commit and date the record describes. The planning
   baseline proposes contract-level status, but the design index tracks only
   whole documents. See `docs/design/99_delivery/planning-baseline.md:208-224`.

### Missing verification

1. `mix quality` checks format, compile, Credo, Dialyzer, and core tests. It does
   not run examples, documentation, package build, or coverage. See
   `mix.exs:378-398`. These checks need separate release gates.
2. Research examples do not block `mix quality`. This separation is useful, but
   the delivery seam does not say which skipped test must become a blocking test
   for each delivery phase. See `guides/testing.md:17-44`.
3. The delivery plan has acceptance lists, but it does not map each item to a
   test file, test name, owning seam, phase, or current result. See
   `docs/design/99_delivery/delivery-plan.md:43-157`.
4. The planning foundation has point-in-time command results, a dependency
   commit, and branch names. It does not give the Jido commit that those results
   tested. It also does not define an expiry rule for those results. See
   `docs/design/99_delivery/planning-baseline.md:242-255`.
5. Seven upgrade ideas have no executable probes. The retained upgrade report
   states this in `docs/examples/live-upgrade-results.md:3-9`. The delivery seam
   does not decide whether these ideas are release requirements or deferred
   research.
6. There is no compatibility test matrix for supported old and new forms at the
   cross-system level. The Plugin and persistence documents contain local test
   plans, but the delivery seam does not combine them. See
   `docs/design/05_plugins/plugin-facets.md:762-814` and
   `docs/design/07_persistence/persistence-adapters.md:744-792`.
7. There is no release gate that proves the public migration guides and module
   documentation agree with the selected retained API.

## Narrow dependency notes

The numbered folder order is a review order, not an implementation order. The
index says this in `docs/design/README.md:4-29`. Delivery work needs the following
direct dependency edges:

```text
approved shared errors and portable values
  -> Agent, Plugin, persistence, Server, and observability public boundaries

fixed source-Signal route selection
  -> Plugin input isolation
  -> stable direct and live Turn equivalence

stable Agent identity + selected definition revision rule
  -> durable Record identity and restore checks
  -> Ref-first instance API
  -> tombstone deletion and later upgrade recovery

selected custom-checkpoint ownership rule
  -> Plugin Persistence facet
  -> durable Plugin state migration

Plugin Server facet + fresh runtime Init
  -> persistent create and restore readiness
  -> separate Plugin runtime pool, if that topology is approved

commit and persistence order + Plugin Topology facet
  -> durable Topology owner state
  -> live target reconciliation
  -> rolling or resumable Topology upgrade

approved semantic Telemetry contract
  -> optional OpenTelemetry bridge
  -> removal of duplicate Observe and debug paths
```

The Plugin design gives the code dependency direction in
`docs/design/05_plugins/plugin-facets.md:102-128`. It also shows restore and
Topology activation order in `docs/design/05_plugins/plugin-facets.md:592-614`.
The Topology owner design requires committed desired state before live
reconciliation in
`docs/design/11_topology-control-plane/topology-authoring-host.md:198-238`.
The OpenTelemetry plan completes the semantic contract before it adds the
bridge or removes the old path in
`docs/design/13_observability/opentelemetry-bridge.md:192-244`.

These edges permit parallel work only after their input decisions are approved.
For example, Turn routing and identity design can proceed in parallel. Tombstone
implementation must wait for the selected durable identity and Record shape.

## Ordered recommendations

The following items are proposals. They do not describe current behavior.

1. Select and publish one V3 release scope. Resolve the eight questions in
   `planning-baseline.md`. Name a delivery owner and an approval owner. Mark
   non-release work as deferred.
2. Convert the delivery seam to one active release plan and one retained-history
   area. Keep the old delivery plan and V3 comparison as immutable records with
   a date, source commit, status, and link to the plan that replaced them.
3. Add a gate register. Give each gate an ID, owning seam, approved contract,
   prerequisite gates, implementation location, exact test names, compatibility
   tests, documentation work, current result, and release status.
4. Make Gate 0 the retained baseline. Freeze the public API that remains valid
   during the beta. Add characterization tests before a compatible API changes.
5. Make Gate 1 the fixed Turn boundary. Enable both FA-01 tests. Do not start
   the Plugin input migration until this gate passes for direct and live Turns.
6. Make Gate 2 the Plugin Agent and Agent Server split. Resolve checkpoint
   ownership first. Enable FA-02 and FA-06. Keep the old Plugin declaration
   through one selected and dated compatibility period.
7. Make Gate 3 stable identity and definition revision. Keep current authoring
   forms. Require all forms to produce the same selected revision contract.
   Enable FA-03 and FA-04.
8. Make Gate 4 persistence hardening. Add the selected Record shape, revision
   zero creation, strict write-authority rules, and tombstones. Enable FA-05.
   Run the same conformance tests for each supported adapter.
9. Make Gate 5 explicit upgrade operations. Enable UP-01 and UP-02 first. Do
   not claim live upgrade support from ordinary code loading or a predeclared
   broad schema.
10. Make Gate 6 the Topology owner and live target update. Require committed
    desired state and Plugin facet dependencies. Enable UP-07 before work on
    rolling or resumable upgrades.
11. Make observability a parallel workstream after semantic event names are
    approved. Keep the old observation path until the new path has equivalent
    evidence and the selected compatibility period ends.
12. Define the final release gate. At minimum, run `mix quality`, core coverage,
    all examples with no release-required skip, documentation with warnings as
    errors, Hex package build, supported Elixir and OTP versions, migration
    tests, and compatibility tests. Record the Jido commit, dependency commits,
    command, date, and result.

## Evidence summary

This analysis used the current `v3-spike` working tree on 2026-09-08. The tree
contained user documentation work before this report was added. No runtime code
was changed. The focused research command was:

```sh
mix test test/examples/99_research --only example --seed 0
```

It completed with 34 passed tests and 11 skipped tests. This result confirms the
current acceptance-test state. It does not approve or implement the proposed
contracts.
