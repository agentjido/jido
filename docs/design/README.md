> Deferred design proposal. This document is pending approval. It does not define
> the current core API. See [the implemented contract](../migration/01-contracts.md).

# Jido v3 spike design

- Design status: Proposal
- Purpose: Cohesive design base for review

These documents contain proposals. The migration preparation updates the
framework names. It retains implemented Builder, Codec, child ownership, and
Topology behavior. The Ref facade, Plugin pipeline, and replacement persistence
architecture are not implemented by that naming change. See the
[prepared serialization contract](../migration/01-contracts.md).

## Core model

```text
Signal -> Action or Flow -> Commit -> Result
```

This short model describes live execution through a Jido instance. `Result`
is the tagged live reply after commit or a pre-commit error. Direct
`Jido.Agent.cmd/3` does not commit. It returns an evaluation value that contains
the candidate Agent and Directives.

An Agent is immutable domain data. An Agent Server owns its live state and
commits one complete validated candidate. Actions and Flows can perform
synchronous I/O before commit. Failure preserves committed Agent state but does
not undo completed external work. Directives request runtime operations or work
after commit. The [state and effect contract](commit-and-effects.md#state-and-effect-contract)
defines this boundary; a Turn is not an external transaction.

The live command path adds Plugin work without changing the protected Turn:

```text
Signal
  -> Turn Evaluator
     -> resolve one route from the source Signal
     -> prepare Plugins for the fixed executable
     -> execute one Action or Flow
     -> apply Plugin contributions in order
     -> validate the candidate Agent
  -> Commit
  -> Result
  -> dispatch the current Directive batch
  -> admit the next Signal
```

Jido defines Signal meaning, Turn execution, candidate state, commit rules,
and Directives. OTP owns mailboxes, processes, scheduling, supervision, timers,
failure signals, and shutdown.

| Concern | Jido owns | OTP owns |
| --- | --- | --- |
| Input | Signal validation and meaning. | Mailbox delivery and ordering. |
| Execution | Fixed compiled-Elixir stages and deterministic assembly. | Processes, tasks, and scheduling. |
| State | Candidate Agent and commit rules. | Live process state ownership. |
| Effects | Executable effect boundary and typed Directives after commit. | I/O, timers, and resource processes. |
| Failure | Domain and validation errors. | Exits, monitors, and restart. |
| Lifecycle | Logical Agent policy. | Supervision and shutdown. |

Value calculation belongs to the Jido Turn Evaluator. Time, processes,
resources, transport, failure detection, and process restart belong to OTP.
Jido restores persistent Agents from committed state. Explicit recovery
Plugins resume pending work stored in that state. An abnormal restart of a nonpersistent Agent resets it to its
preserved initial Agent value.

## Document map

Read the design in this order:

1. [Agent](agent.md) defines the immutable domain value and its public API.
2. [Turn evaluation](turn-evaluation.md) defines the command sequence and
   protected state transition.
3. [Plugins](plugins.md) defines pure Plugin configuration, state ownership,
   and command callbacks.
4. [Agent Server](agent-server.md) defines the internal live process and its
   state machine.
5. [Jido instance](jido-instance.md) defines `use Jido`, the application
   facade, and the instance OTP boundary.
6. [Commit and effects](commit-and-effects.md) defines persistence,
   Directives, restoration, and hibernation.
7. [Instance persistence](instance-persistence.md) defines the optional
   application callbacks for durable Agent records.
8. [Durability guarantee](durability-guarantee.md) defines the scope and
   limits of durable Agent commits and effect recovery.
9. [Runtime topology](runtime-topology.md) defines OTP supervision, Agent
   identity, Signal delivery, and Plugin runtimes.
10. [Observability](observability.md) defines runtime telemetry, trace
    correlation, safe metadata, metrics, and logs.
11. [Errors](errors.md) defines the Splode error set, normalization rules, and
    safe public error projection.
12. [Runtime extension boundaries](runtime-extension-boundaries.md) locks the
    core contracts needed by future durable, cluster, and fabric packages and
    marks all package designs as proposed.

Supporting documents:

- [Agent authoring](authoring.md) records the versioned-module proposal and
  links to the authoring formats implemented on the current SDK.
- [Agent Spark DSL and route interfaces](agent-dsl-interfaces.md) describes block
  authoring, generated interfaces, Builder, and Codec support on the current SDK.
- [v3 design changes](v3-design-changes.md) maps current contracts to the
  proposed v3 design.
- [Delivery plan](delivery-plan.md) contains implementation steps, tests, and
  open questions.

## Document review status

Design maturity and user approval are separate. A document can contain locked
core decisions and still wait for user approval. Only an explicit user review
can move a document from `Pending approval` to `Approved`.

| Document | Review status |
| --- | --- |
| [Design overview](README.md) | Pending approval |
| [Agent](agent.md) | Pending approval |
| [Turn evaluation](turn-evaluation.md) | Pending approval |
| [Plugins](plugins.md) | Pending approval |
| [Agent Server](agent-server.md) | Pending approval |
| [Jido instance](jido-instance.md) | Pending approval |
| [Commit and effects](commit-and-effects.md) | Pending approval |
| [Instance persistence](instance-persistence.md) | Pending approval |
| [Durability guarantee](durability-guarantee.md) | Pending approval |
| [Runtime topology](runtime-topology.md) | Pending approval |
| [Remote owned children](remote-owned-children.md) | Pending approval |
| [Scheduled occurrence identity and delivery](scheduled-occurrences.md) | Pending approval |
| [Observability](observability.md) | Pending approval |
| [Errors](errors.md) | Pending approval |
| [Runtime extension boundaries](runtime-extension-boundaries.md) | Pending approval |
| [Agent authoring](authoring.md) | Pending approval |
| [Agent Spark DSL and route interfaces](agent-dsl-interfaces.md) | Pending approval |
| [v3 design changes](v3-design-changes.md) | Pending approval |
| [Delivery plan](delivery-plan.md) | Pending approval |

## Responsibility map

| Component | Responsibility |
| --- | --- |
| `Jido.Agent` | Immutable Agent construction, validation, state access, command evaluation, checkpoints, and restoration. |
| `Jido.Agent.Turn.Evaluator` | Private execution policy shared by direct and live commands. |
| `Jido.Plugin` | Plugin configuration, owned state, and pure preparation and contribution callbacks. |
| `Jido.AgentServer` | Internal serialized Signal admission, Turn execution, and commit coordination. |
| `Jido.Plugin.Runtime` | Supervised resources, Signal production, and post-commit Directive handling. |
| `MyApp.Jido` | Named OTP instance, application runtime facade, and optional persistence callbacks. |
| Jido runtime | Registry, Agent and Plugin runtime pools, and bounded tasks. |
| `Jido.Telemetry` | Stable runtime events, safe metadata, trace correlation, and standard metrics. |
| `Jido.Error` | Defined Splode errors and public error normalization. |

## Public data boundaries

Each Jido-owned shaped value that crosses a public API or callback is a
Zoi-backed struct with one purpose. The owning design document defines its
fields and cross-field rules.

### Agent construction and configuration

| Public struct | One purpose |
| --- | --- |
| `%Jido.Plugin{}` | Complete validated configuration for one Agent capability. |
| `%Jido.Agent{}` | Complete immutable Agent value. |

The values in this group produce an Agent. They do not contain live runtime
state.

### Shared Agent identity

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Ref{}` | Stable Agent identity for lookup, storage, delivery, and future transport. |

Agent Ref is the identity shared by the runtime, persistence, Directives, and
future transport. Core defines no logical relationship model.

### Turn composition

| Public struct | One purpose |
| --- | --- |
| `%Jido.Plugin.Command{}` | Effective Signal and one Plugin-owned prepared input. |
| `%Jido.Plugin.Context{}` | Bounded view of one Plugin's configuration, state, and prepared input. |
| `%Jido.Plugin.Transition{}` | One Plugin's declared projection of a successful executable transition. |
| `%Jido.Plugin.Contribution{}` | One Plugin's proposed state replacement and new Directives. |
| Directive structs | Typed descriptions of external work that can start after Commit. |

These values cross Plugin preparation and contribution boundaries. Every Directive is a
Zoi-backed struct owned by its Directive module.

### Durability

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Checkpoint{}` | Portable state needed to reconstruct one Agent. |
| `%Jido.Agent.Commit{}` | One Agent checkpoint, state version, and Turn identity. |
| `%Jido.Persistence.Record{}` | Compare-and-swap storage and lifecycle envelope for one Commit. |

These values nest in one direction:

```text
Checkpoint (including explicit work intent) -> Commit -> Persistence Record
```

The Record alone owns the complete Agent Ref and storage version.

### Live runtime and observation

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Status{}` | Complete current runtime summary for one live Agent. |
| `%Jido.Agent.Turn.Status{}` | Current control stage of one active Turn. |
| `%Jido.Agent.Turn.Outcome{}` | Terminal live Turn summary after Commit and Directives. |
| `%Jido.Plugin.Runtime.Init{}` | Agent-owned Plugin state and identity inputs for one runtime start. |
| `%Jido.Plugin.Runtime.Context{}` | Committed context for one Plugin Directive dispatch. |
| `%Jido.Plugin.Runtime.Status{}` | Current local observation of one Plugin runtime. |

These values can contain runtime status or PIDs. They never enter an Agent,
Checkpoint, Commit, or Persistence Record.

### Instance configuration

| Public struct | One purpose |
| --- | --- |
| `%Jido.Instance.Config{}` | Complete validated runtime configuration for one Jido instance. |

### Upstream and error boundaries

`Jido.Signal` and `Jido.Signal.Trace` are Zoi structs supplied by
`jido_signal`. Errors are defined Splode exception structs, as specified in
[Errors](errors.md).

`Jido.Agent.Turn`, `Jido.Agent.Turn.Result`, `Jido.Plugin.Preparation`, and
`Jido.AgentServer.Snapshot` are not public v3 data types. Private evaluator
values can use tuples or maps.

The Zoi-struct rule does not replace normal Elixir and platform contracts:

- Tagged tuples express success, failure, and control flow.
- Lists contain defined values.
- Agent and Plugin state maps use their declared Zoi schemas.
- OTP child specifications and reply envelopes keep their standard forms.
- Public keyword options remain idiomatic lists and are validated by a Zoi
  schema at entry.
- `:telemetry` measurements and metadata stay maps.

## Required invariants

- The Agent path works with no Plugins.
- Agent route resolution selects the first match in Signal Router precedence
  order.
- Route resolution uses the original source Signal and completes before Plugin
  preparation.
- Plugin preparation cannot replace the selected executable or cause another
  route lookup.
- Direct `Agent.cmd/3` and live Server execution use the same Turn Evaluator.
- Instance casts are best-effort sends. `:ok` does not confirm
  admission, execution, or commit.
- During a command, the Action or Flow is the only writer of domain state.
- Plugin callbacks cannot read or change the complete executable output.
- Each Plugin owns at most one complete `plugin_state` entry.
- Each Plugin contribution can replace only its complete owned state entry.
- Each Plugin receives only its declared state fields, owned Turn Directives,
  and owned prepared input.
- Plugin preparation and composition run serially in declaration order.
- Plugin contribution assembly follows Plugin declaration order.
- Only Jido can assemble the candidate Agent.
- Live Agent state has one commit point.
- A new Agent state Commit increments the state version by one. It stores no
  duplicate prior version; Record storage version is the CAS guard.
- Runtime effects start after commit.
- Explicit durable work stores portable intent and stable IDs in Agent or
  Plugin state, in the same checkpoint as the business change.
- A supervised capability worker resumes pending work after startup.
- Completion enters through a new Signal and normal Agent commit.
- Later Turns preserve pending work. There is no universal durable outbox gate.
- Ordinary Directive dispatch does not promise recovery after a crash.
- Runtime error policy is closed data: `:continue` or `:stop` after a normal
  pre-commit error. It is not an application callback.
- Every Agent uses a positive module-owned definition revision. Restore
  requires the saved module and revision to match the current definition.
- A persistent Agent Server restart loads the latest durable Record.
- A nonpersistent Agent Server restart uses its preserved initial Agent at
  state version zero and does not recover later in-memory commits.
- Persistence I/O crosses only the owning Jido instance callback boundary.
- Persistent creation completes provisional Plugin runtime readiness before it
  writes the initial active Record. Readiness failure writes no Record.
- Every Agent Server is a peer under the Agent Pool.
- The Agent Pool contains only Agent Servers.
- Core defines no logical Agent relationship store, API, or Directive set.
- Registry, persistence, and Directives use the same Agent Ref.
- Public live Agent operations use the Ref-first instance facade. Agent Server
  commands and messages are internal.
- Persistence updates use compare-and-swap storage versions.
- Only a confirmed successful persistence write lets the current Agent Server
  keep write authority.
- Any persistence write error stops the current Server with
  `:lost_write_authority`. A later activation loads the authoritative Record.
- Normal durable deletion writes a tombstone.
- Plugin runtime hosts do not live in the Agent Pool.
- Every first runtime start uses validated initial Plugin state at version
  zero. During persistent creation, this state is provisional before the first
  write. Activation and replacement use the latest committed Plugin state and
  Agent state version.
- A runtime host does not reuse stale initialization data.
- The Turn Evaluator owns no process or runtime resource.
- Only pre-commit evaluation is cancellable. Commit and Directive dispatch are
  not cancellable.
- Turn evaluation has an independent `:turn_timeout`. Caller request timeouts
  do not stop an active Turn.
- A persistence timeout is an indeterminate write error and removes the
  current Server's write authority in the proposed instance persistence API.
  A Directive timeout follows runtime error policy; explicit work keeps its
  pending intent according to the capability contract.
- Plugin runtimes send Signals through the Agent mailbox.
- Runtime handles and `Jido.Exec` workflow state never enter Agent state or
  checkpoints.
- Agent state, Plugin state, and saved work satisfy the recursive portable-term
  contract. Runtime Directive fields follow their declared schemas.
- Every Jido-owned shaped public success value is a Zoi-backed struct.
- Each public struct has one owner and one documented purpose.
- Command, construction, and lifecycle failures use defined Splode errors.
- Raw Map and OTP control values are explicit documented protocol exceptions.
- `Agent.cmd/3` emits no telemetry.
- The live Turn telemetry span stops at the Commit and Result boundary.
- Directive work uses separate post-commit telemetry spans.
- Observability cannot change an Agent result or runtime outcome.
- Agent Server state contains no debug timeline or observation buffer.
- `Jido.Signal.Trace` is the distributed trace carrier.
- Telemetry metadata never contains Agent state, Plugin state, or payloads.
- Shaped public data uses defined structs. Private evaluation plumbing can use
  tuples, lists, and maps.
- Structured contracts are Zoi-first.
- Jido semantic results use tagged tuples and defined Splode errors.

## Terms

| Term | Meaning |
| --- | --- |
| Agent | A complete immutable domain value. |
| Turn | One selected Action or Flow and its input. |
| Executable output | The private complete state and Directive output of the selected Action or Flow. |
| Plugin Transition | One Plugin's declared bounded view of successful executable output. |
| Candidate Agent | The complete validated Agent proposed by one command. |
| Commit | The only operation that makes a candidate Agent live. |
| Result | The tagged live instance reply that reports commit success or pre-commit failure. |
| Evaluation return | The direct `Agent.cmd/3` return with a candidate Agent and Directives; it proves no live or durable commit. |
| Turn Outcome | Runtime observation produced when the complete live Turn stops. |
| Directive | A typed description of external work that starts after commit. |
| Durable work intent | Portable pending work saved in Agent or Plugin state by an explicit capability. |
| Plugin | Static Agent configuration with owned state and pure command callbacks. |
| Plugin runtime | Optional supervised processes and resources for one Plugin instance. |
| Provider | Instance infrastructure behind a fixed core boundary. |
