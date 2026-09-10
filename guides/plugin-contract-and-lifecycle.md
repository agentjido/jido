# Plugin Contract and Lifecycle

A Plugin package adds one declared capability to an Agent. The package module
is callback-free. It selects no more than one facet for each Jido owner:

| Facet | Purpose |
| --- | --- |
| `Jido.Agent.Plugin` | Pure input preparation, Plugin-owned state, and state reduction |
| `Jido.AgentServer.Plugin` | Live admission, runtime, readiness, outbound preparation, and post-commit dispatch |
| `Jido.Persistence.Plugin` | Pure dump and load of one paired owned-state value |
| `Jido.Topology.Plugin` | Pure static Topology contribution |

## Declare a Package

```elixir
defmodule MyApp.RateLimit do
  use Jido.Plugin,
    agent: MyApp.RateLimit.Agent,
    agent_server: MyApp.RateLimit.Server,
    vsn: 1,
    option_keys: [agent: [:limit], agent_server: [:endpoint]]
end
```

Put common options in the Agent declaration:

```elixir
agent do
  plugin MyApp.RateLimit, config: [limit: 100, endpoint: "local"]
end
```

If `option_keys` is absent, each selected facet gets all common options. If it
is present, it must assign every declared option to a selected facet. A package
module can appear only once in one Agent definition.

## Agent Facet

The Agent facet can implement these callbacks:

| Callback | Boundary |
| --- | --- |
| `prepare/2` | Reject input or return one portable package-owned execution input |
| `state_spec/1` | Define one owned state key and static schema |
| `directives/1` | Declare owned Directive modules |
| `reduce/2` | Compute the next owned state value after executable success |

`prepare/2` runs in package declaration order before route selection. It
receives `%Jido.Agent.Plugin.Preparation{}` with the unchanged source Signal,
Agent identity, Agent module, the complete current Agent state, and the
Plugin's owned state. It also receives the facet's static options. It can
return `{:ok, input}` or `{:error, reason}`. The input must be portable. Jido
stores it at `context.plugin_inputs[PackageModule].prepared`. The callback
cannot replace the Signal, caller context, route, or Agent state.

An Action or Flow returns the complete candidate state and its Directives. It
must preserve all Plugin-owned fields. Each custom Directive validates itself
through `Jido.Agent.Directive.validate/1`. Jido validates each Directive once,
then calls `reduce/2` in package declaration order. The callback receives a
read-only `%Jido.Agent.Plugin.Reduction{}` with the prior complete state, the
current complete candidate state, its owned value, its pure prepared input,
and all validated Directives. It returns only the next value for its owned
field. Jido validates that value with the owned schema and portable-value rule.

## Agent Server Facet

The Agent Server facet can implement `admit/3`, `prepare_dispatch/4`,
`dispatch/4`, and `await_ready/2`. It can also implement the standard OTP
`child_spec/1` callback for one runtime root. The returned specification must
use `restart: :permanent`.

Admission runs in declaration order after pure preparation and before Turn
evaluation. `admit/3` receives a read-only
`%Jido.AgentServer.Plugin.Admission{}`. It can inspect the Signal, caller
context, complete Agent identity, its owned state, its pure prepared input,
and the current state version. It returns `{:ok, runtime_input}` or rejects
the command. Jido stores a successful value at
`context.plugin_inputs[PackageModule].runtime`. There is no callback return
path that can replace the Agent, incoming Signal, caller context, prepared
input, or another package's input. A runtime input can contain a PID,
reference, or function because it is not stored in Agent state or a checkpoint.

Direct `Jido.Agent.cmd/3` runs pure preparation but does not run live
admission. Outbound Signal preparation runs in reverse declaration order.
Directive dispatch starts only after commit. A dispatch failure does not roll
back committed state.

The Agent Server owns tasks, timeouts, runtime handles, start order, restart,
readiness, and settlement. Runtime handles never enter Agent state or a
checkpoint.

Each runtime receives `%Jido.Plugin.Init{plugin_state: state,
state_version: version}`. The state is only the value owned by that Plugin.
The pair is one immutable committed view for that runtime generation. A
replacement receives a newly built pair. `Jido.Plugin.state/2` remains
available when a running resource must reconcile after a later commit. The
`plugin_state` field is selected from the complete Agent state map. It is not a
second stored map.

Jido puts a temporary owner wrapper beside the Agent Server. The wrapper hosts
each root generation as temporary under its private Supervisor. If the root
stops, the wrapper asks the Agent Server for a new root specification. This
keeps the declared permanent intent while it prevents an automatic restart
with an old state-version pair.

## Persistence and Topology Facets

The Persistence facet implements `dump/3` and `load/3` for one paired Plugin
state value. It cannot receive the adapter, record key, expected revision,
complete Agent, or commit result. Dump output must be portable. Load output
must also match the Agent facet's state schema.

The Topology facet implements `contribute/2`. It can return current canonical
Bus resources, ownership relationships, and Bus subscriptions. Bus is the
first core resource type. The facet cannot start
a process, persist data, or control live activation. Jido calls the facet while
it builds an instance Plan. It processes Agent declarations, then group
declarations, in source order and keeps Plugin declaration order. Included
Topologies receive the same expansion in their own scope. Common Topology
validation checks the complete graph before Controller activation. The source
definition stays unchanged.

Live placement policy uses a different boundary. A control Agent can receive
Topology lifecycle Signals, select an exact node, and return a Plugin-owned
Directive. The Agent Server facet can apply that Directive through
`Jido.Topology.Controller.place_agent/4` after commit. Static contribution does
not gain live authority.

See [Plugin Runtimes](plugin-runtimes.livemd) and
[Plugin-Owned State](plugin-state.md).
