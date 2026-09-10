# Plugin Contract and Lifecycle

A Plugin package adds one declared capability to an Agent. The package module
is callback-free. It selects no more than one facet for each Jido owner:

| Facet | Purpose |
| --- | --- |
| `Jido.Agent.Plugin` | Pure input preparation, Plugin-owned state, and Directive validation |
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
| `validate_directive/2` | Validate one owned Directive before candidate return |
| `update_state/3` | Update the owned state value from owned Directives |

`prepare/2` runs in package declaration order before route selection. It
receives `%Jido.Agent.Plugin.Preparation{}` with the unchanged source Signal,
Agent identity, Agent module, and the Plugin's owned state. It also receives
the facet's static options. It can return `{:ok, input}` or `{:error, reason}`.
The input must be portable. Jido stores it at
`context.plugin_inputs[PackageModule]`. The callback cannot replace the Signal,
caller context, route, or Agent state.

An Action or Flow returns the complete candidate state and its Directives. It
must preserve all Plugin-owned fields. Jido validates each Directive, gives
each Agent facet only its owned Directives, and calls `update_state/3` in
package declaration order. The callback receives only the current owned value.
Jido validates the returned value with the owned schema.

## Agent Server Facet

The Agent Server facet can implement `admit/3`, `prepare_dispatch/4`,
`dispatch/4`, and `await_ready/2`. It can also implement the standard OTP
`child_spec/1` callback for one runtime root. The returned specification must
use `restart: :permanent`.

Admission runs in declaration order after pure preparation and before Turn
evaluation. `admit/3` can reject the command or replace only its own value at
`command.plugin_inputs[PackageModule]`. It cannot change the Agent, incoming
Signal, caller context, or another package's input. A live input can contain a
runtime value, such as a PID or function, because it is not stored in Agent
state or a checkpoint.

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
Bus resources, ownership relationships, and Bus subscriptions. It cannot start
a process, persist data, or control live activation. Jido calls the facet while
it builds an instance Plan. It processes Agent declarations, then group
declarations, in source order and keeps Plugin declaration order. Included
Topologies receive the same expansion in their own scope. Common Topology
validation checks the complete graph before Controller activation. The source
definition stays unchanged.

See [Plugin Runtimes](plugin-runtimes.livemd) and
[Plugin-Owned State](plugin-state.md).
