# Plugin Contract and Lifecycle

A Plugin package adds one declared capability to an Agent. The package module
is callback-free. It selects no more than one facet for each Jido owner:

| Facet | Purpose |
| --- | --- |
| `Jido.Agent.Plugin` | Pure Turn preparation, owned state, and owned Directives |
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
| `state_spec/1` | Define one owned state key and static schema |
| `observes/1` | Select top-level domain fields for the callback projection |
| `prepare/2` | Change the effective Signal, bounded caller context, or this package's prepared input |
| `contribute/2` | Keep or replace owned state and append owned Directives |
| `directives/1` | Declare owned Directive modules |
| `validate_directive/2` | Validate one owned Directive before candidate return |

`Jido.Agent.Plugin.Preparation` does not contain the complete Agent or another
package's input. Route selection uses the unchanged source Signal before
preparation. The selected Action or Flow reads prepared values from
`context.plugin_inputs[PackageModule]`.

`Jido.Agent.Plugin.Contribution` can replace only one complete owned-state
value. Its Directives must belong to the same Agent facet. Jido appends them
after executable Directives in package declaration order.

## Agent Server Facet

The Agent Server facet can implement `admit/3`, `prepare_dispatch/4`,
`dispatch/4`, and `await_ready/2`. It can also implement the standard OTP
`child_spec/1` callback for one permanent runtime root.

Admission runs in declaration order before Turn evaluation. Outbound Signal
preparation runs in reverse declaration order. Directive dispatch starts only
after commit. A dispatch failure does not roll back committed state.

The Agent Server owns tasks, timeouts, runtime handles, start order, restart,
readiness, and settlement. Runtime handles never enter Agent state or a
checkpoint.

## Persistence and Topology Facets

The Persistence facet implements `dump/3` and `load/3` for one paired Plugin
state value. It cannot receive the adapter, record key, expected revision,
complete Agent, or commit result. Dump output must be portable. Load output
must also match the Agent facet's state schema.

The Topology facet implements `contribute/2`. It can return current canonical
Bus resources, ownership relationships, and Bus subscriptions. It cannot start
a process, persist data, or control live activation.

## Compatibility Form

`use Jido.Plugin` with no options is the supported mixed-callback compatibility
form. Current built-in Plugins use it while they move to owner facets. This
form can receive a complete `Jido.Agent.Command` in `prepare/2`; it is not an
isolation boundary.

See [Plugin Runtimes](plugin-runtimes.livemd) and
[Plugin-Owned State](plugin-state.md).
