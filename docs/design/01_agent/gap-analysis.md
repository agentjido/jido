# Agent seam gap analysis

> Analysis date: 2026-09-08. This report describes the current `v3-spike`
> branch. The design files are deferred proposals. They are not the implemented
> API.

## Scope and owner

`Jido.Agent` owns the immutable Agent data value, its validation, direct state
changes, direct command evaluation, and Agent checkpoint callbacks. The main
implementation is `lib/jido/agent.ex`. Its private support code is under
`lib/jido/agent`.

This report covers these parts of the `01_agent` seam:

- the Agent data model;
- definition and instance values;
- domain state and Plugin-owned state;
- pure state transitions;
- the Agent parts of direct command evaluation and checkpoint data.

This report checks direct dependencies only where they set an Agent contract.
It does not review the full Agent Server, Plugin, Signal, persistence, or
authoring subsystems.

## Status terms

- **Current fact** means that code under `lib` implements the behavior.
- **Verified fact** means that a focused test also checks the behavior.
- **Proposal** means that `docs/design/01_agent/agent.md` requests the behavior.
  It does not mean that the behavior exists.

## Implemented baseline

The current implementation has the following baseline.

| Area | Current fact | Evidence |
| --- | --- | --- |
| Data type | One `%Jido.Agent{}` struct represents both a neutral definition and an instance. A definition has `id: nil` and `state: nil`. An instance has a nonempty string ID and a plain state map. | `lib/jido/agent.ex:96-135`, `lib/jido/agent.ex:322-337`; verified in `test/jido/agent_test.exs:157-211` |
| Definition construction | `Agent.new/1` builds a neutral definition. `Agent.new/2` builds an instance from an Agent module. `Agent.instantiate/2` builds an instance from a neutral definition. | `lib/jido/agent.ex:259-308`; verified in `test/jido/agent_test.exs:198-226` and `test/jido/agent_test.exs:434-473` |
| Static fields | The struct has `module`, `name`, `description`, `schema`, `plugins`, `routes`, and `metadata`. It has no `definition_revision` field. | `lib/jido/agent.ex:96-123`; verified field list in `test/jido/agent_test.exs:181-195` |
| State shape | `agent.state` is one complete map. `Jido.Plugin.compose_schema/2` adds Plugin-owned top-level keys to the domain schema. There is no `agent.plugin_state` field. | `lib/jido/agent.ex:339-343`, `lib/jido/plugin.ex:126-143`; verified in `test/jido/agent/schema_test.exs:69-100` and `test/jido/plugin/contract_test.exs:604-624` |
| State ownership | An executable returns a complete map. Jido rejects a change to a Plugin-owned key. Each stateful Plugin can then update only its own key. | `lib/jido/agent/command/runner.ex:120-133`, `lib/jido/plugin.ex:238-255`, `lib/jido/plugin.ex:826-855`; verified in `test/jido/plugin/contract_test.exs:584-650` |
| Direct data change | The internal `transition/2` replaces the complete combined state after validation. The public `set/2` deep-merges domain fields only. It rejects Plugin-owned fields. | `lib/jido/agent.ex:439-503`; verified in `test/jido/agent_test.exs:319-339` and `test/jido/agent_test.exs:546-576` |
| Direct command | `cmd/3` validates an instance, runs Plugin preparation, calls the Agent module `handle_signal/2`, executes one Action or Flow, applies Plugin state reducers, and validates the complete next state. It returns a new Agent and Directives. | `lib/jido/agent/command/runner.ex:29-93`, `lib/jido/agent/command/runner.ex:120-133`; verified in `test/jido/agent_test.exs:341-369` and `test/jido/agent_test.exs:790-858` |
| Routing | The default callback routes the Signal after Plugin preparation. It requires exactly one target. More than one match is an error. | `lib/jido/agent/command/runner.ex:64-93`, `lib/jido/agent/command/runner.ex:107-118`, `lib/jido/agent/command/runner.ex:178-193`; verified in `test/jido/agent_test.exs:306-317` and `test/jido/agent_test.exs:580-690` |
| Module callbacks | `handle_signal/2` is required. `checkpoint/2` and `restore/2` are optional and overridable. | `lib/jido/agent.ex:125-132`, `lib/jido/agent.ex:236-246` |
| Checkpoint | The default checkpoint is a plain map. It contains the format version, kind, module, ID, neutral definition, and the complete combined state. Restore normally uses the current module definition when it is available. It has no definition revision check. | `lib/jido/agent.ex:370-423`, `lib/jido/agent.ex:521-598`; verified in `test/jido/agent_test.exs:888-1010` |
| Portable data | The persistence boundary checks the complete record with `Jido.PortableTerm.valid?/1`. Agent construction and `transition/2` do not call this check. | `lib/jido/persistence.ex:284-316`, `lib/jido/portable_term.ex:1-24`; verified at save and load in `test/jido/persistence/checkpoint_portability_test.exs:15-49` |
| Authoring forms | Builder and JSON-compatible Codec APIs are public and supported. `Agent.to_map/1` is also public. | `lib/jido/agent.ex:81-84`, `lib/jido/agent.ex:354-368`, `lib/jido/agent/builder.ex:1-17`, `lib/jido/agent/codec.ex:1-22`; the supported scope confirms this in `guides/core-scope.md:9-15` |
| Live state owner | `Jido.AgentServer` owns the current immutable Agent and a separate commit revision. It persists before it replaces live state. | `lib/jido/agent_server/state.ex:4-79`, `lib/jido/agent_server.ex:1493-1545`; its public snapshot exposes both values at `lib/jido/agent_server.ex:614-620` |

Focused verification on 2026-09-08 had these results:

- 95 tests passed in `agent_test.exs`, `agent/schema_test.exs`, and
  `plugin/contract_test.exs`.
- 4 research tests passed in `persistence/checkpoint_portability_test.exs` with
  `--include research`.

## Aligned contracts

The proposal and current code agree on these points.

1. `%Jido.Agent{}` is immutable application data. `cmd/3`, `transition/2`, and
   `set/2` return a new value. They do not change the source value. See
   `docs/design/01_agent/agent.md:21-23` and
   `test/jido/agent_test.exs:319-350`.
2. An Agent value contains no PID, timer, task, monitor, or runtime handle. The
   Agent struct schema has only data and configuration fields. See
   `docs/design/01_agent/agent.md:201` and `lib/jido/agent.ex:96-123`.
3. Construction and transitions use Zoi schemas and apply schema defaults. See
   `docs/design/01_agent/agent.md:82-87`,
   `lib/jido/agent/validation.ex:186-205`, and
   `test/jido/agent_test.exs:510-515`.
4. Domain state and Plugin-owned state are validated as one candidate before a
   direct command succeeds. See `docs/design/01_agent/agent.md:130-143` and
   `lib/jido/agent/command/runner.ex:120-133`.
5. An Action or Flow cannot change Plugin-owned state. A Plugin state reducer
   receives only Directives that it owns. See
   `docs/design/01_agent/agent.md:275-278`,
   `lib/jido/plugin.ex:238-255`, and
   `test/jido/plugin/contract_test.exs:584-650`.
6. Direct `cmd/3` returns a candidate Agent and Directives. It does not commit
   live state or dispatch Directives. See `docs/design/01_agent/agent.md:234-244`,
   `lib/jido/agent.ex:458-462`, and `lib/jido/agent_server.ex:1469-1545`.
7. Static Agent configuration is copied into each instance. Instance overrides
   can set only ID and state. See `docs/design/01_agent/agent.md:14-16`,
   `lib/jido/agent/validation.ex:186-193`, and
   `lib/jido/agent/validation.ex:303-307`.

## Gaps

### Missing implementation

These proposal contracts have no current implementation.

#### M1. Definition revision

The proposal requires a positive `definition_revision` in every Agent and
checkpoint. It also requires an exact revision check during restore
(`docs/design/01_agent/agent.md:89-93`, `docs/design/01_agent/agent.md:189-199`).
The current Agent schema and checkpoint have no such field
(`lib/jido/agent.ex:96-123`, `lib/jido/agent.ex:403-412`).

#### M2. Fixed checkpoint value

The proposed `%Jido.Agent.Checkpoint{}` Zoi struct does not exist. The current
checkpoint is a plain map. Agent modules can replace its shape through callbacks
(`docs/design/01_agent/agent.md:149-187`, `lib/jido/agent.ex:125-132`,
`lib/jido/agent.ex:370-423`).

#### M3. Proposed state access and replacement API

The proposal lists `state/1`, `fetch_state/2`, `plugin_state/2`,
`fetch_plugin_state/3`, `replace_state/2`, and `replace_plugin_state/3`
(`docs/design/01_agent/agent.md:203-237`). None of these functions exists on
`Jido.Agent`. Current callers read `agent.state`, use internal `transition/2`,
or use public `set/2`.

#### M4. Portable-term validation at every Agent boundary

The proposal requires path-aware portable-term checks during construction,
replacement, candidate validation, checkpoint construction, and restore
(`docs/design/01_agent/agent.md:133-147`). Current code checks portability only
when persistence builds or validates a record. The current check returns only a
boolean and does not report a state path (`lib/jido/portable_term.ex:1-24`,
`lib/jido/persistence.ex:284-316`).

#### M5. Static definition ownership check

The proposal requires `checkpoint/1` to compare all static Agent configuration
with the current module definition (`docs/design/01_agent/agent.md:189-192`).
Current `checkpoint/2` validates the instance but does not compare the static
fields with `module.agent()` (`lib/jido/agent.ex:370-381`).

### Design and code conflict

These points are not small omissions. The proposal contradicts a current public
contract.

#### C1. Definition and instance model

The proposal says that every Agent is complete and that no definition form
exists (`docs/design/01_agent/agent.md:18-23`). Current code and tests make the
neutral definition a public, supported value. They provide `new/1`,
`instantiate/2`, `definition/1`, `definition?/1`, and `validate_definition/1`
(`lib/jido/agent.ex:259-337`). The public core guide also marks neutral
definitions, Builder, and Codec as supported (`guides/core-scope.md:9-15`).

#### C2. Plugin state shape

The proposal uses a separate `plugin_state` map (`docs/design/01_agent/agent.md:68-84`).
Current code adds each Plugin state key to the one `agent.state` map
(`lib/jido/plugin.ex:126-143`). This affects schemas, Action output, Plugin
reducers, checkpoints, persistence, Server reads, and user code.

#### C3. Replacement semantics and names

The proposal removes the ambiguous `set` API and defines complete replacement
functions (`docs/design/01_agent/agent.md:267-278`). Current `set/2` is public
and does a deep merge. Current complete replacement is named `transition/2` and
is documented as internal (`lib/jido/agent.ex:439-455`).

#### C4. Routing selection and order

The proposal selects the first match by precedence and resolves it before Plugin
preparation (`docs/design/01_agent/agent.md:95-114`). Current code runs Plugin
preparation first, then routes the prepared Signal, and requires exactly one
target (`lib/jido/agent/command/runner.ex:64-93`,
`lib/jido/agent/command/runner.ex:178-193`). Current tests require a multiple
match error (`test/jido/agent_test.exs:306-317`).

#### C5. Agent module callback contract

The proposal says that Agent modules have no routing or persistence callback
(`docs/design/01_agent/agent.md:364-370`). Current modules must implement
`handle_signal/2`. They can override `checkpoint/2` and `restore/2`
(`lib/jido/agent.ex:125-132`, `lib/jido/agent.ex:236-246`). Current tests verify
custom routing and persistence callbacks (`test/jido/agent_test.exs:718-737`,
`test/jido/agent_test.exs:937-1010`).

#### C6. Authoring serialization

The proposal says that core has no `to_map/1`, `from_map/1`, Builder, or Agent
authoring serialization boundary (`docs/design/01_agent/agent.md:280-290`).
Current core has public `to_map/1`, Builder, Codec, and Registry APIs
(`lib/jido/agent.ex:354-368`, `lib/jido/agent/builder.ex:1-17`,
`lib/jido/agent/codec.ex:1-22`).

#### C7. Restore authority

The proposal says that restore rebuilds configuration from the module and
rejects a changed revision (`docs/design/01_agent/agent.md:194-199`). Current
restore uses the current module definition when it exists, but it can also use a
definition stored in the checkpoint. It has no revision test
(`lib/jido/agent.ex:563-598`). This fallback supports direct definitions and
behavior-only modules (`test/jido/agent_test.exs:904-934`).

#### C8. Public documentation is not fully consistent with current state shape

`Jido.Agent.checkpoint/2` says that it builds a "domain-only checkpoint"
(`lib/jido/agent.ex:370`). The checkpoint stores `agent.state`, and that map also
contains Plugin-owned fields. Persistence tests confirm that Plugin state is
restored (`test/jido/persistence_test.exs:186-205`).

### Missing decision

The design needs explicit decisions before implementation starts.

#### D1. Compatibility or replacement

Decide if the proposed Agent model replaces the supported current API or if it
must keep a compatibility path. This decision must cover neutral definitions,
`instantiate/2`, `set/2`, `transition/2`, Builder, Codec, `to_map/1`, custom
`handle_signal/2`, and checkpoint callbacks.

#### D2. One design model across adjacent documents

`01_agent/agent.md` says that neutral definitions do not exist. The adjacent
authoring design says that the current SDK retains them and that all authoring
forms use `Agent.new/1` and `Agent.instantiate/2`
(`docs/design/02_agent-authoring/dsl-and-interfaces.md:198-212`). The other
authoring document proposes the opposite result
(`docs/design/02_agent-authoring/authoring.md:93-123`). Select one target model.

#### D3. Plugin identity and state keys

The proposal gives each Plugin a stable `id` and uses it as a key in
`plugin_state` (`docs/design/01_agent/agent.md:39-84`). Current Plugin
declarations are `{module, keyword}` pairs. The normalized private spec has a
separate `state_key` (`lib/jido/plugin/spec.ex:4-21`). Decide the migration and
collision rules for existing Plugin modules and saved state.

#### D4. Checkpoint customization and migration

Decide if checkpoint callbacks are removed, kept as migration hooks, or moved to
another seam. The persistence design calls the current checkpoint override a
migration point (`docs/design/07_persistence/persistence-adapters.md:260-270`).
The Agent proposal says that modules cannot replace the format
(`docs/design/01_agent/agent.md:185-187`).

#### D5. Definition equality

Define the exact canonical equality rule for Zoi schemas, routes, Plugin
options, metadata, and function captures. The proposal requires static equality
but does not define how code changes that keep the same data revision are found.

#### D6. Route ambiguity

Decide if route precedence permits several matches or if several matches stay an
error. Also decide if Plugin preparation can change the Signal used for routing.
This decision must be the same in the Agent and Turn Evaluator designs. The Turn
Evaluator proposal also requires route resolution before Plugin preparation
(`docs/design/04_turn-evaluation/turn-evaluation.md:74-105`).

#### D7. Error compatibility

Define error types and details for new revision, portable-state, Plugin-state,
and replacement failures. The proposal requires defined `Jido.Error.t()` values
but gives no stable fields for these new cases
(`docs/design/01_agent/agent.md:239-244`).

### Missing verification

The current suite verifies the current model well. It does not verify these
proposal contracts because the related code does not exist:

1. No test requires a positive definition revision at compile time or runtime.
2. No test rejects restore after a definition revision change.
3. No test checks full static-definition equality before checkpoint creation.
4. No test covers `%Jido.Agent.Checkpoint{}` because the type does not exist.
5. No test checks separate domain and Plugin state replacement functions.
6. No test checks path-aware portable-term errors at construction, transition,
   direct command, checkpoint, and restore. Current portability tests check the
   persistence boundary only.
7. No test requires first-match route precedence. Current tests require an error
   when more than one route matches.
8. No test proves that route selection uses the source Signal before Plugin
   preparation. Current code has the reverse order.
9. No migration test covers old combined state, old checkpoint maps, neutral
   definitions, Builder documents, or Codec documents under the proposed model.

## Narrow dependency notes

- **Zoi:** Agent construction depends on a field-based `Zoi.object`. Plugin
  schema composition preserves root refinements. A separate `plugin_state` map
  needs a new complete-candidate validation boundary. See
  `lib/jido/agent/state.ex:23-61`, `lib/jido/plugin.ex:126-143`, and
  `test/jido/agent/schema_test.exs:69-153`.
- **Plugin:** The proposed state split changes `Jido.Plugin.compose_schema/2`,
  `protect_state/3`, `update_state/2`, Plugin state reads, and the Plugin callback
  inputs. This is a direct cross-seam change, not an Agent-only struct change.
- **Signal Router:** The Router returns target lists. `Jido.Agent` currently
  converts list length other than one into a routing error. A first-match rule
  must define whether Agent or Router owns precedence.
- **Action and Flow:** Current executables receive `context.agent_state` with the
  complete combined state and return a complete combined map. The proposed split
  requires domain-only input and output. Existing Actions and Flows can need a
  migration.
- **Agent Server and persistence:** The Server owns `state_version`; it is not a
  definition revision. Persistence validates portability and stores the Agent
  checkpoint. A new checkpoint struct and revision rule must keep this version
  separation.
- **Authoring:** Definition revision becomes part of every module, Builder, and
  Codec declaration. The current supported Builder and Codec omit it.

## Ordered recommendations

These are proposals, not current facts.

1. **Select the target Agent model first.** Decide whether the current neutral
   definition and combined-state model stays supported. Update the conflicting
   `01_agent` and `02_agent-authoring` design text to one model before code work.
2. **Write a compatibility table.** For each current public function and value,
   state `keep`, `deprecate`, `replace`, or `move`. Include saved checkpoints and
   Codec documents.
3. **Lock the state ownership shape.** Decide between combined state and separate
   `plugin_state`. Then define the Action, Flow, Plugin, checkpoint, and restore
   inputs for that shape.
4. **Lock route semantics and pipeline order.** Choose exactly-one or
   first-match routing. Choose source-Signal or prepared-Signal routing. Apply
   the same rule to the Agent and Turn Evaluator designs.
5. **Define revision identity.** Specify the normalized fields, equality rule,
   revision error, and behavior for code changes without a revision change.
6. **Define the checkpoint migration path.** Specify the new value shape, old
   map support, callback policy, and restore behavior for direct or behavior-only
   definitions.
7. **Add failing contract tests.** Add tests for the selected model, revision,
   state ownership, portable paths, route order, checkpoint migration, and error
   shapes before runtime changes.
8. **Change code in seam order.** Change Agent validation and values first. Then
   change Plugin state composition, Turn evaluation, Server commit integration,
   persistence, and authoring adapters. Keep each step compatible or make its
   breaking boundary explicit.
9. **Correct current public documentation now if the current API remains for any
   release.** In particular, do not call the default checkpoint domain-only
   while it stores the combined Agent and Plugin state map.

## Evidence index

Primary design evidence:

- `docs/design/01_agent/README.md:5-18`
- `docs/design/01_agent/agent.md:12-93`
- `docs/design/01_agent/agent.md:95-147`
- `docs/design/01_agent/agent.md:149-199`
- `docs/design/01_agent/agent.md:203-290`
- `docs/design/01_agent/agent.md:292-379`

Primary implementation evidence:

- `lib/jido/agent.ex:1-135`
- `lib/jido/agent.ex:137-352`
- `lib/jido/agent.ex:354-603`
- `lib/jido/agent/validation.ex:24-229`
- `lib/jido/agent/command/runner.ex:29-133`
- `lib/jido/agent/command/runner.ex:178-293`
- `lib/jido/plugin.ex:104-167`
- `lib/jido/plugin.ex:238-255`
- `lib/jido/plugin.ex:826-855`
- `lib/jido/persistence.ex:284-325`
- `lib/jido/agent_server.ex:1469-1545`

Primary verification evidence:

- `test/jido/agent_test.exs:157-390`
- `test/jido/agent_test.exs:490-858`
- `test/jido/agent_test.exs:888-1010`
- `test/jido/agent/schema_test.exs:69-153`
- `test/jido/plugin/contract_test.exs:584-650`
- `test/jido/persistence/checkpoint_portability_test.exs:15-49`
