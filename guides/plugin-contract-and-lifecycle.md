# Plugin Contract and Lifecycle

A Plugin adds one declared capability to an Agent. It can prepare command
input, control live admission, own one state key, own Directive types, transform
outbound Signals, and start one supervised runtime root.

Declare only the callbacks that the capability needs.

## Callback Order

| Callback | Boundary |
| --- | --- |
| `state_spec/1` | Define one owned state key and static schema |
| `child_spec/1` | Start the optional runtime root |
| `await_ready/2` | Confirm that runtime setup is complete |
| `admit/3` | Accept or reject a live command |
| `prepare/2` | Prepare the Signal or caller context |
| `update_state/3` | Update owned state before final validation |
| `directives/1` | Declare owned Directive modules |
| `validate_directive/2` | Validate one owned Directive before commit |
| `dispatch/4` | Run owned Directive work after commit |
| `prepare_dispatch/4` | Transform an outbound Signal |

`use Jido.Plugin` takes no options. Put options in the Agent declaration:

```elixir
agent do
  plugin MyApp.RateLimit, config: [limit: 100]
end
```

A Plugin module can appear only once in one Agent definition.

## Keep State Ownership Narrow

A stateful Plugin owns one state key. Its update callback changes only that
value. An Agent executable must preserve the key. Jido rejects a candidate that
changes or removes Plugin-owned state before the Plugin update stage.

This is a write-ownership rule. It is not a read-security boundary.

## Keep Preparation Pure

`prepare/2` can change the Signal or caller context before route selection. It
must not start runtime work. A later Plugin can observe and change the prepared
command, so declaration order is not an authorization boundary.

Use `admit/3` when a decision needs the live Plugin runtime.

## Validate Before Commit

Jido validates every Plugin-owned Directive and computes Plugin-owned state
before it validates and commits the complete candidate. Dispatch starts only
after commit. A dispatch failure does not roll back state.

## Own Runtime Resources

Use `child_spec/1` for connections, timers, subscriptions, and other process
state. The runtime gets `Jido.Plugin.Init`, not a private Agent Server state
value. Use `Jido.Plugin.state/1` when a restarted runtime must reconstruct from
current committed Plugin state.

See [Plugin Runtimes](plugin-runtimes.livemd) and
[Plugin-Owned State](plugin-state.md).
