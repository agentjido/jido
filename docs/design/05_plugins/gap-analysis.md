> Gap analysis. This document is pending approval.

# Plugin seam gap analysis

Date: **2026-09-08**.

## Scope and owner

This report covers only the Plugin seam in `docs/design/05_plugins`. It focuses
on Plugin composition, owner-specific facets, state and input isolation,
runtime Init, Directives, and scheduled behavior. `lib` is the source of truth
for implemented behavior. Tests and public module documentation are supporting
evidence.

The present implementation has two direct owners:

- `Jido.Agent` owns pure command preparation, Plugin state schema composition,
  Directive validation, and Plugin state reduction.
- `Jido.AgentServer` owns live admission, outbound Signal preparation, runtime
  lifecycle, readiness, and post-commit Directive dispatch.

Persistence and Topology are adjacent seams. This report includes them only
where the Plugin design creates a direct contract with them.

The design set has two proposals. `plugins.md` proposes a new unified Plugin
value and pure callback data model. `plugin-facets.md` proposes a neutral
manifest and four owner-specific facets. Both documents are pending approval.
Neither proposal is the implemented baseline.

## Implemented baseline

These items are current facts.

1. `Jido.Plugin` is one mixed behavior. It has pure Agent callbacks and live
   Agent Server callbacks. The behavior includes `prepare/2`, `admit/3`,
   `prepare_dispatch/4`, `state_spec/1`, `update_state/3`, `directives/1`,
   `validate_directive/2`, `dispatch/4`, and `await_ready/2`
   (`lib/jido/plugin.ex:67-102`). `use Jido.Plugin` accepts no options and adds
   only the behavior and marker (`lib/jido/plugin.ex:52-65`).
2. Agent definitions store ordered module declarations or `{module, keyword}`
   declarations. Core normalizes them to an internal `%Jido.Plugin.Spec{}` with
   state, Directive, dispatch, and runtime fields
   (`lib/jido/plugin.ex:367-415`; `lib/jido/plugin/spec.ex:4-20`). There is no
   public `%Jido.Plugin{}` configuration value or neutral facet manifest.
3. Normalization rejects duplicate Plugin modules, state keys, and Directive
   owners (`lib/jido/plugin.ex:104-113`, `lib/jido/plugin.ex:656-670`). A Plugin
   state key is an atom. Core composes its schema into the top level of the
   complete Agent state map (`lib/jido/plugin.ex:126-143`). The Agent struct has
   no separate `plugin_state` field (`lib/jido/agent.ex:96-120`).
4. `Jido.Agent.Command` contains the complete Agent value, one Signal, and one
   shared context map (`lib/jido/agent/command.ex:1-22`). Each `prepare/2`
   callback receives the result from the prior callback
   (`lib/jido/plugin.ex:696-723`). After Plugin preparation, Agent routing runs
   through `handle_signal/2` (`lib/jido/agent/command/runner.ex:64-90`,
   `lib/jido/agent/command/runner.ex:221-227`).
5. Before commit, core protects Plugin-owned top-level state keys from
   executable changes, validates each Directive through its owner, and gives
   each state reducer only its owned Directives
   (`lib/jido/agent/command/runner.ex:120-133`,
   `lib/jido/plugin.ex:826-875`). Reducers run in declaration order and a failure
   returns no candidate.
6. Agent Server admission runs before the pure Agent preparation path
   (`lib/jido/agent_server.ex:1285-1306`,
   `lib/jido/agent_server.ex:1365-1383`). A successful Turn persists first,
   installs the new Agent and state version, and then starts Directive handling
   (`lib/jido/agent_server.ex:1493-1545`). Plugin Directive work runs in a
   bounded task with committed Plugin state and state version
   (`lib/jido/agent_server.ex:1767-1825`).
7. `%Jido.Plugin.Init{}` contains the Agent Server PID, Agent ID, Plugin module,
   Jido instance, partition, and options. It does not contain the owned state or
   state version (`lib/jido/plugin/init.ex:1-23`). A runtime can call
   `Jido.Plugin.state/2` to get its current owned state, but this API does not
   return a version (`lib/jido/plugin.ex:268-274`).
8. Agent Server starts one optional permanent runtime root for each Plugin and
   waits for readiness before it reports the Server as ready
   (`lib/jido/agent_server/plugin_lifecycle.ex:8-39`,
   `lib/jido/plugin.ex:897-929`, `lib/jido/agent_server.ex:506-533`). On an
   internal runtime restart, readiness runs in a separate task so the new
   runtime can read Agent state without a wait cycle
   (`lib/jido/agent_server/plugin_child.ex:89-156`).
9. Persistence stores the complete Agent checkpoint and record revision. It has
   no Plugin-owned slice conversion or facet revision contract
   (`lib/jido/agent.ex:370-423`, `lib/jido/persistence.ex:284-316`). Restore
   completes before Plugin runtime startup
   (`lib/jido/agent_server.ex:450-509`,
   `lib/jido/agent_server.ex:2887-2904`).
10. Scheduler uses the mixed behavior. It owns `:scheduler` state, reduces its
    Directives, dispatches post-commit runtime work, and starts one runtime
    (`lib/jido/plugin/scheduler.ex:135-155`,
    `lib/jido/plugin/scheduler.ex:175-278`). Tracked occurrence identity and the
    durable one-pending-item policy are implemented
    (`lib/jido/plugin/scheduler/occurrence.ex:41-72`,
    `lib/jido/plugin/scheduler/delivery.ex:19-85`).

## Aligned contracts

These design statements agree with current code and tests.

- Declaration order is stable. Pure preparation, admission, and state
  reduction stop at the first error. Outbound transformation uses reverse
  declaration order (`test/jido/plugin/contract_test.exs:490-503`,
  `test/jido/plugin/ordering_test.exs:198-313`).
- State keys and Directive types have one owner. An executable cannot change a
  Plugin-owned state key. A reducer receives only owned Directives
  (`test/jido/plugin/ordering_test.exs:181-196`,
  `test/jido/plugin/contract_test.exs:584-635`).
- A Plugin can dispatch a typed Directive without a runtime process
  (`test/jido/plugin/contract_test.exs:438-455`). A configured runtime root must
  be permanent (`test/jido/plugin/runtime_test.exs:250-255`).
- Runtime Directive dispatch is after commit and receives committed state and
  version. A dispatch failure cannot undo the commit. The code order is explicit
  at `lib/jido/agent_server.ex:1493-1545` and the bounded context is built at
  `lib/jido/agent_server.ex:1793-1817`.
- A replacement runtime reads current committed owned state. The restart tests
  prove that state value `7` is read before readiness
  (`test/jido/agent_server/runtime_lifecycle_test.exs:225-290`).
- Scheduled occurrence coordinates, generation changes, fresh Signal IDs, and
  restore behavior have direct tests
  (`test/jido/plugin/scheduler/occurrence_test.exs:12-106`,
  `test/jido/plugin/scheduler/occurrence_runtime_test.exs:38-117`).
- Durable Scheduler intent, bounded pending work, acknowledgement, cancellation,
  failed writes, runtime loss, and restore have direct tests
  (`test/jido/plugin/scheduler/durable_test.exs:15-144`,
  `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-217`). The
  implemented Scheduler boundary in `scheduled-occurrences.md` is substantially
  aligned with code.

## Gaps

### Missing implementation

#### MI-1: Owner-specific facets and the neutral manifest do not exist

Current fact: there are no `Jido.Agent.Plugin`, `Jido.AgentServer.Plugin`,
`Jido.Persistence.Plugin`, or `Jido.Topology.Plugin` behaviors or Specs in
`lib`. `Jido.Plugin` still executes callbacks and its Spec still joins Agent and
Agent Server fields.

Proposal: `plugin-facets.md:14-48` and `plugin-facets.md:522-549` define a
neutral manifest and four owner Specs. This is a full architectural migration,
not a documentation update.

#### MI-2: The bounded pure Plugin callback model does not exist

Current fact: there are no public `Jido.Plugin.Command`, `Context`,
`Transition`, or `Contribution` modules. Current `prepare/2` receives
`Jido.Agent.Command`, including the complete Agent and shared context. Current
state work uses `update_state/3` after executable evaluation.

Proposal: `plugins.md:196-295` and `plugins.md:301-365` define per-Plugin input,
bounded state observation, `contribute/2`, and private preparation data. None of
these values or callbacks is implemented.

#### MI-3: Plugin state is not a separate state class

Current fact: Plugin schemas are added to the complete top-level Agent state.
Protection uses a list of reserved top-level keys. Checkpoints store one state
map.

Proposal: `plugins.md:179-194` defines separate `Agent.state` and
`Agent.plugin_state` contracts with atomic commit. That storage shape and public
contract are not implemented.

#### MI-4: Runtime Init has no committed state snapshot or version

Current fact: Init has identity and connection data only. Runtime code must make
a later Agent Server call for owned state. The call does not return
`state_version`. `DirectiveContext` does contain the committed version, but only
after a Directive (`lib/jido/plugin/directive_context.ex:10-27`).

Proposal: `plugins.md:373-378` requires every activation and replacement to use
the latest complete owned state and state version. Current code proves fresh
state, but it does not provide one atomic `{state, version}` bootstrap value.

#### MI-5: Persistence and Topology facets do not exist

Current fact: persistence calls whole-Agent `checkpoint/2` and `restore/2`.
Topology has no Plugin contribution behavior. There is no package or facet
revision in the durable Plugin state envelope.

Proposal: `plugin-facets.md:330-433` and `plugin-facets.md:434-504` define these
two facets. Their implementation phases are still listed as future work at
`plugin-facets.md:723-748`.

### Design and code conflict

These conflicts compare pending proposals with canonical code. They are not
claims that the current code violates an approved contract.

#### DC-1: The public Plugin type and authoring API are incompatible

`plugins.md:31-33`, `plugins.md:113-129`, and `plugins.md:131-177` specify a
public `%Jido.Plugin{}` value, macro configuration, and `new/new!` constructors.
Current code defines `Jido.Plugin` as a behavior module, has no such struct or
constructors, and explicitly rejects macro options (`lib/jido/plugin.ex:52-65`).

#### DC-2: Input isolation conflicts with shared mutable command context

`plugins.md:230-235` says that each Plugin owns one private input and cannot
read or replace another Plugin input. Current callbacks pass the complete
resulting Command to the next Plugin. Admission tests intentionally use the
shared context as an ordered accumulator
(`test/jido/plugin/ordering_test.exs:78-108`,
`test/jido/plugin/ordering_test.exs:198-220`). Current behavior therefore
provides composition, but not input isolation.

#### DC-3: Route timing conflicts with the proposed source-Signal rule

`plugins.md:339-345` says core selects the executable from `source_signal`
before Plugin preparation and never routes again. Current Runner calls Plugin
preparation first and then calls the Agent `handle_signal/2` with the prepared
Signal (`lib/jido/agent/command/runner.ex:64-90`,
`lib/jido/agent/command/runner.ex:221-227`). A current Plugin can therefore
change route selection by changing `command.signal.type`.

#### DC-4: The unified behavior conflicts with facet ownership

`plugin-facets.md:25-45` says the manifest must have no execution callbacks and
each owner must have a separate behavior. Current public module documentation
states that one Plugin can own both pure and live work
(`lib/jido/plugin.ex:2-24`). Built-ins confirm the mixed model. Scheduler and
Sensor Manager each implement state reduction, runtime dispatch, readiness, and
child startup in one module (`lib/jido/plugin/scheduler.ex:175-278`,
`lib/jido/plugin/sensor_manager.ex:37-96`).

#### DC-5: The proposed removal of live callbacks conflicts with current public
behavior

`plugins.md:367-371` removes `admit/3` and `prepare_dispatch/4`. The facet plan
keeps equivalent live callbacks under the Agent Server owner
(`plugin-facets.md:268-295`). Current `Jido.Plugin` implements and publicly
documents both callbacks (`lib/jido/plugin.ex:5-18`,
`lib/jido/plugin.ex:71-78`). The design set must select one target.

#### DC-6: A state-only Directive has different live-Server meaning

Current normalization accepts a Directive that only reduces Plugin state
(`lib/jido/plugin.ex:622-643`). After commit, Agent Server treats an owned
Directive with `dispatch?: false` as complete
(`lib/jido/agent_server.ex:1767-1773`). `plugin-facets.md:326-328` says a live
Server must report an unsupported Directive when no built-in or Plugin handler
exists. The design does not state whether successful Agent-facet reduction
counts as handling for this rule.

### Missing decision

#### MD-1: Select the normative Plugin architecture

The seam has two pending and incompatible target models. One model makes
`Jido.Plugin` the only public configuration and callback type
(`plugins.md:31-33`). The other makes it a callback-free manifest with four
facets (`plugin-facets.md:28-45`). Implementation work cannot safely start until
one model is normative and the other document is updated or removed.

#### MD-2: Select state and input identity rules

The design must decide all of these items together:

- Separate `Agent.plugin_state` or keep Plugin-owned keys in complete Agent
  state.
- Plugin instance ID with atom or string keys, or one atom state key per module.
- Per-Plugin private prepared input, or the current shared context composition.
- Route from the source Signal before preparation, or route from the prepared
  Signal after preparation.

These choices change checkpoint data, Codec data, Action context, migration,
and Plugin compatibility.

#### MD-3: Define one atomic runtime bootstrap contract

The design asks how a replacement runtime gets committed state and version
(`README.md:27-28`). Current code can read fresh state, but not the matching
version in one operation. Decide whether Init contains an immutable
`{owned_state, state_version}` snapshot or whether Agent Server provides one
versioned read call. Also define how restart readiness handles a commit that
occurs during bootstrap.

#### MD-4: Resolve state-only Directive handling

Decide whether an Agent facet that validates and reduces a Directive fully
handles it for a live Server. If yes, the unsupported rule needs an explicit
exception. If no, current state-only Plugins require a Server handler or a new
non-dispatch Directive class.

#### MD-5: Resolve custom checkpoint interaction

`plugin-facets.md:416-433` correctly records an open choice between canonical
Plugin-aware checkpoints, compatibility bypass, and strict rejection. This
decision is required before a Persistence facet or Plugin state migration can
be implemented.

### Missing verification

#### MV-1: No test proves per-Plugin preparation input isolation

Current tests prove ordered shared mutation, not isolation. If private Plugin
input is selected, add tests that prove a later Plugin cannot read or replace a
prior Plugin input and that `Jido.Exec` receives a read-only keyed map.

#### MV-2: No test proves a state and version bootstrap pair

Runtime restart tests prove fresh state and responsive readiness
(`test/jido/agent_server/runtime_lifecycle_test.exs:225-290`). They do not prove
that a runtime receives the matching commit version, because the bootstrap API
does not expose it.

#### MV-3: The facet architecture checks are not present

The checks proposed at `plugin-facets.md:764-803` do not exist because the facet
modules do not exist. In particular, there is no automated dependency check
that prevents Agent facet code from depending on Agent Server, Persistence, or
Topology, and no test that owner Specs exclude foreign fields.

#### MV-4: No compatibility fixture proves old and new normalization parity

The compatibility plan requires legacy declarations and new manifests to
normalize to equivalent ownership data (`plugin-facets.md:630-651`). There is
no new manifest normalizer, Codec fixture, facet revision fixture, or migration
test.

#### MV-5: Scheduled behavior needs facet-migration parity tests

Current Scheduler behavior has strong direct coverage. The missing verification
is specific to a future split: the Agent facet and Agent Server facet must keep
the present Directive order, commit boundary, occurrence identity, retry,
readiness, and restart behavior. The existing occurrence and recovery tests
must run unchanged, or with mechanical declaration-only changes, after the
split.

## Narrow dependency notes

- **Turn evaluation:** Current Plugin preparation runs inside
  `Jido.Agent.Command.Runner`. A change to input isolation or route timing is a
  direct change to the Turn contract, not only to Plugin code
  (`lib/jido/agent/command/runner.ex:64-90`).
- **Agent Server:** Admission, runtime lookup, post-commit dispatch, and
  outbound Signal transformation are live Plugin responsibilities today. The
  facet split must preserve bounded tasks, timeouts, and committed context
  (`lib/jido/agent_server.ex:1365-1383`,
  `lib/jido/agent_server.ex:1664-1709`,
  `lib/jido/agent_server.ex:1767-1825`).
- **Persistence:** The current record stores one complete checkpoint and one
  record revision. A separate Plugin state envelope or facet revision changes
  the durable format and must follow a checkpoint compatibility decision
  (`lib/jido/persistence.ex:284-316`).
- **Topology:** The proposed Topology facet is pure planning. No current Plugin
  code calls the Topology planner. Keep live reconciliation in Agent Server if
  this facet is added, as stated in `plugin-facets.md:470-483`.
- **Scheduler:** Scheduler depends on Agent state reduction, Agent Server
  post-commit dispatch, runtime restart, and persistence. It is the main parity
  fixture for any facet migration. Scheduled occurrence identity itself does
  not require the facet split.

## Ordered recommendations

The following items are proposals, not current facts.

1. Approve one Plugin architecture first. If the four-facet model is selected,
   make `plugin-facets.md` normative and rewrite `plugins.md` as the Agent-facet
   contract. Do not keep two definitions for `Jido.Plugin`.
2. Before code changes, add characterization tests for the current mixed
   behavior: callback order, failure containment, state-only Directives,
   process-free dispatch, runtime-backed dispatch, checkpoint form, and Codec
   form.
3. Implement the neutral manifest and owner Specs before moving callbacks.
   Require the legacy and new declarations to normalize to the same ownership
   data. Add the dependency and field-isolation checks at this stage.
4. Resolve state shape, Plugin identity, private input, and route timing as one
   Agent-facet decision. Provide an explicit checkpoint and Codec migration for
   any data-shape change.
5. Define a versioned runtime bootstrap value. Prefer one immutable owned-state
   and state-version snapshot. Use it for first activation and every replacement,
   and keep the current non-blocking readiness path.
6. Resolve whether state reduction counts as live Directive handling. Encode the
   result in normalization and Agent Server tests before the callback split.
7. Resolve the custom checkpoint rule. Then add the Persistence facet with
   owned-slice access only and explicit package and facet revisions.
8. Split Scheduler and Sensor Manager only after the contracts above exist. Use
   the current Scheduler occurrence, failed-write, cancellation, recovery, and
   restart tests as required parity tests.
9. Add the Topology facet last. Keep it pure and verify that plan construction
   starts no process and performs no I/O.

## Review verification

The focused baseline test run passed: **88 tests, 0 failures**. The run included
the Plugin contract, ordering, runtime, Agent Server runtime lifecycle,
Scheduler occurrence, durable Scheduler, and occurrence recovery test files.
This result verifies the cited current behavior. It does not verify any missing
facet or proposed API.

## Evidence reference index

- Seam index and open questions: `docs/design/05_plugins/README.md:5-28`
- Unified Plugin proposal: `docs/design/05_plugins/plugins.md:12-408`
- Owner-specific facet proposal: `docs/design/05_plugins/plugin-facets.md:14-875`
- Scheduled occurrence design: `docs/design/05_plugins/scheduled-occurrences.md:8-144`
- Current Plugin behavior and normalization: `lib/jido/plugin.ex:1-979`
- Current Agent command pipeline: `lib/jido/agent/command.ex:1-75` and
  `lib/jido/agent/command/runner.ex:29-294`
- Current runtime lifecycle: `lib/jido/agent_server/plugin_lifecycle.ex:8-233`
  and `lib/jido/agent_server/plugin_child.ex:41-206`
- Current Scheduler public contract: `lib/jido/plugin/scheduler.ex:1-397`
- Current Plugin contract tests: `test/jido/plugin/contract_test.exs:424-670`
- Current runtime restart tests:
  `test/jido/agent_server/runtime_lifecycle_test.exs:225-290`
- Current durable scheduling tests:
  `test/jido/plugin/scheduler/occurrence_recovery_test.exs:84-217`
