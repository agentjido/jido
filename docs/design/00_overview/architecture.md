> Deferred design proposal. This document is pending approval. It does not
> define the current core API. See [the current core scope](../../../guides/core-scope.md).

# Core model and data boundaries

## Current baseline

Core retains Spark DSL, Builder, Codec, owned children, local Topology, and the
public PID-based Agent Server API. Persistence uses the binary adapter with
compare-and-swap. The proposed Ref facade, isolated Plugin pipeline, versioned
module-only authoring, and replacement Record API are deferred.

The refinement pass adds Scheduler `delivery_interval` and Topology
`repair: :manual` with `Controller.reconcile/2`. It creates no new packages and
removes no authoring or relationship APIs. The
[acceptance results](../../examples/feature-acceptance-results.md) and
[upgrade results](../../examples/live-upgrade-results.md) track the remaining
proposed contracts.

## Proposed core model

```text
Signal -> Action or Flow -> Commit -> Result
```

This model describes live execution through a Jido instance. `Result` is the
tagged live reply after commit or a pre-commit error. Direct
`Jido.Agent.cmd/3` does not commit. It returns a candidate Agent and Directives.

An Agent is immutable domain data. An Agent Server owns its live state and
commits one complete validated candidate. Actions and Flows can perform
synchronous I/O before commit. Failure preserves committed Agent state but
does not undo completed external work. Directives request runtime operations
or work after commit. See the
[state and effect contract](../06_commit-and-effects/commit-and-effects.md#state-and-effect-contract).

The proposed live command path is:

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

Value calculation belongs to the Turn Evaluator. Time, processes, resources,
transport, failure detection, and restart belong to OTP. Persistent Agents
restore from committed state. Explicit recovery Plugins resume pending work
stored in that state. An abnormal restart of a nonpersistent Agent resets it
to its preserved initial Agent value.

## Responsibility map

| Component | Responsibility |
| --- | --- |
| `Jido.Agent` | Immutable construction, validation, state access, direct commands, checkpoints, and restoration. |
| Turn evaluator | Execution policy shared by direct and live commands. |
| `Jido.Plugin` | Capability configuration, owned state, command callbacks, and optional runtime work. |
| `Jido.AgentServer` | Serialized admission, live execution, commit coordination, and settlement. |
| Plugin runtime | Supervised resources, Signal production, and post-commit Directive handling. |
| Jido instance | Named OTP runtime, application facade, local lookup, and persistence configuration. |
| Runtime topology | Agent and Plugin pools, owned children, and bounded tasks. |
| `Jido.Telemetry` | Stable runtime events and bounded observation data. |
| `Jido.Error` | Defined Splode errors and public error normalization. |

## Public data boundaries

Each Jido-owned shaped value that crosses a public API or callback has one
owner and one purpose. Proposed structured contracts are Zoi-backed structs.

### Agent construction and configuration

| Public struct | One purpose |
| --- | --- |
| `%Jido.Plugin{}` | Complete validated configuration for one capability. |
| `%Jido.Agent{}` | Complete immutable Agent value. |

These values contain no live runtime state.

### Shared Agent identity

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Ref{}` | Stable identity for lookup, storage, delivery, and future transport. |

See [Stable Agent identity](../03_agent-identity/README.md).

### Turn composition

| Public struct | One purpose |
| --- | --- |
| `%Jido.Plugin.Command{}` | Effective Signal and one Plugin-owned prepared input. |
| `%Jido.Plugin.Context{}` | Bounded view of one Plugin configuration, state, and input. |
| `%Jido.Plugin.Transition{}` | One Plugin's declared view of executable output. |
| `%Jido.Plugin.Contribution{}` | One Plugin state replacement and new Directives. |
| Directive structs | Typed work that can start after commit. |

### Durability

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Checkpoint{}` | Portable data needed to reconstruct one Agent. |
| `%Jido.Agent.Commit{}` | One checkpoint, state version, and Turn identity. |
| `%Jido.Persistence.Record{}` | Compare-and-swap and lifecycle envelope for one Commit. |

The values nest in one direction:

```text
Checkpoint, including explicit work intent
  -> Commit
  -> Persistence Record
```

The Record alone owns the complete Agent Ref and storage version.

### Live runtime and observation

| Public struct | One purpose |
| --- | --- |
| `%Jido.Agent.Status{}` | Current runtime summary for one live Agent. |
| `%Jido.Agent.Turn.Status{}` | Current control stage of one active Turn. |
| `%Jido.Agent.Turn.Outcome{}` | Terminal live Turn summary. |
| `%Jido.Plugin.Runtime.Init{}` | State and identity input for one runtime start. |
| `%Jido.Plugin.Runtime.Context{}` | Committed context for Directive handling. |
| `%Jido.Plugin.Runtime.Status{}` | Current local Plugin runtime observation. |

These values can contain runtime status or PIDs. They never enter an Agent,
Checkpoint, Commit, or Persistence Record.

### Instance configuration

| Public struct | One purpose |
| --- | --- |
| `%Jido.Instance.Config{}` | Complete validated configuration for one Jido instance. |

### Upstream and error boundaries

`Jido.Signal` and `Jido.Signal.Trace` come from `jido_signal`. Errors are
defined Splode exception structs. See
[Errors and public contracts](../12_errors-and-contracts/errors.md).

Tagged tuples express success, failure, and control flow. Lists contain
defined values. OTP child specifications keep their standard forms. Public
keyword options remain idiomatic lists and are validated at entry. Telemetry
measurements and metadata remain maps.
