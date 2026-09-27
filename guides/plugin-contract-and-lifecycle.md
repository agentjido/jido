# Plugin Contract and Lifecycle

A Plugin adds callbacks to an Agent through one module and one behaviour:
`Jido.Plugin`. Implement only the callbacks that the capability needs. Core
controls callback execution and state ownership.

| Owner | Purpose |
| --- | --- |
| Agent | Pure input preparation, owned state, and state reduction |
| Agent Server | Live admission, runtime, readiness, outbound preparation, commit hooks, and Directive dispatch |
| Persistence | Pure dump and load of one owned state value |
| Topology | Pure static Topology contribution |

## Define a Plugin

Start with [extension selection](extension-boundaries.md#select-an-extension-type)
and [Write a Plugin](your-first-plugin.md).

```elixir
defmodule MyApp.Counter do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:turns, Zoi.integer() |> Zoi.default(0)}

  @impl true
  def reduce(reduction, _opts), do: {:ok, reduction.plugin_state + 1}
end
```

Add `plugin MyApp.Counter` in the Agent's `agent` block. Use
`plugin MyApp.Counter, config: [option: value]` for common options. A Plugin
module can appear only once in an Agent definition.

The fixed documented callbacks select the internal owner Specs at compile time.
`roles:` and separate facet selectors are not accepted. Use ordinary functions
or `defdelegate` to split a large implementation. Only the Plugin module is
registered with Jido.

All callbacks receive the common options by default. Optional `option_keys`
metadata can restrict options by owner, for example
`option_keys: [agent: [:limit], agent_server: [:endpoint]]`. When present, it
must assign each declared option to an owner with callbacks. `vsn` defaults to
1. Package identity, stored definitions, versions, contexts, and callback order
keep their existing meaning.

## Agent callbacks

Agent owns these callbacks:

| Callback | Boundary |
| --- | --- |
| `prepare/2` | Reject input or return one portable package-owned execution input |
| `state_spec/1` | Define one owned state key and static schema |
| `directives/1` | Declare owned Directive modules |
| `reduce/2` | Compute the next owned state value after executable success |

`prepare/2` runs in package declaration order before route selection. It
receives `%Jido.Agent.Plugin.Preparation{}` with the unchanged source Signal,
Agent identity, Agent module, the complete current Agent state, and the
Plugin's owned state. It also receives the Plugin's static options. It can
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
field. Jido validates that value with the owned schema. Local values are allowed
when the schema accepts them. Persistence checks the stored representation for
portability after conversion.

## Agent Server callbacks

The Agent Server owns `validate_options/1`, `admit/3`, `prepare_dispatch/4`,
`after_commit/3`, `dispatch/4`, and `await_ready/2`. It can also implement the
standard OTP `child_spec/1` callback for one runtime root. The returned specification must
use `restart: :permanent`.

`validate_options/1` runs when Jido normalizes a declaration. It returns
`:ok` or `{:error, reason}`. It checks static options before Jido starts a
runtime. The option callback does not give a Server callbacks a runtime capability
by itself. Use it with a live callback or `child_spec/1`.

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

### Required hook before dispatch

Use `after_commit(runtime, commit, opts)` when a Plugin must keep a live
projection of its owned state. The Action does not need to return a custom
Directive. The hook receives `%Jido.AgentServer.Plugin.Commit{}` with only its
owned value, the matching revision, Turn and Agent identity, and instance and
partition context. A stateless Plugin receives `plugin_state: nil`. A Plugin
without a runtime receives `runtime: nil`.

Hooks run in Plugin declaration order after each successful Turn commit and
before returned Directives. They also run when state is unchanged or there
are no Directives. Return only `:ok` or `{:error, reason}`. There is no return
path to replace state or add Directives.

The Server runs each hook in a linked task. Its limit is the finite
`directive_timeout`, or 5,000 milliseconds when that option is `:infinity`.
Inspections remain available, but the next Turn waits for settlement. A
reentrant Turn call from a hook returns `{:error, :reentrant_commit}`.
Turn cancellation ends at commit: during a hook, `cancel/2` returns
`{:error, :directing}` and `cancel_turn/3` returns `{:error, :stale_turn}`.
Stopping the Server stops the owned hook task.

Failure or timeout skips remaining hooks and Directives and uses the existing
error policy. The Outcome has stage `:after_commit`; skipped Directives are
not counted as failed Directives. `Server.call/3` has already returned the
committed Agent. Neither a hook failure nor owner loss can undo a saved
commit or completed external work. Jido does not retry these hooks.
If the error policy continues, a failed projection can remain stale until a
later successful hook or runtime replacement.

Startup, restore, runtime replacement, direct `Jido.Agent.cmd/3`, and definition
upgrades do not invoke this hook. Rebuild the current runtime view from
`Jido.Plugin.Init`. Declaring the hook makes it a required step before
Directive dispatch. It is bounded and is not a durable event stream.
Use semantic Telemetry for observation alone. Use an owned Directive for an
explicit effect request.

See [Commit Projection](../examples/09_plugins/09_08_commit_projection/README.md).

### Runtime lifecycle

The Agent Server owns tasks, timeouts, runtime handles, start order, restart,
readiness, and settlement. Runtime handles never enter Agent state or a
checkpoint.

Each runtime receives `%Jido.Plugin.Init{plugin_state: state,
state_version: version}`. The state is only the value owned by that Plugin.
The pair is one immutable committed view for that runtime generation. A
replacement receives a newly built pair. `after_commit/3` can keep the live
view current after later Turns. `Jido.Plugin.state/2` remains available with
the runtime's `Init` when it must read the current owned value. The
`plugin_state` field is selected from the complete Agent state map. It is not a
second stored map.

Jido puts a temporary owner wrapper beside the Agent Server. The wrapper hosts
each root generation as temporary under its private Supervisor. If the root
stops, the wrapper asks the Agent Server for a new root specification. This
keeps the declared permanent intent while it prevents an automatic restart
with an old state-version pair.

## Persistence and Topology callbacks

Define `dump/3` and `load/3` for one paired Plugin
state value. It cannot receive the adapter, record key, expected revision,
complete Agent, or commit result. Dump output must be portable. Load output
must also match the owned state schema.

Define `contribute/2`. It can return current canonical
Bus resources, ownership relationships, and Bus subscriptions. Bus is the
first core resource type. The callback cannot start
a process, persist data, or control live activation. Jido calls the callback while
it builds an instance Plan. It processes Agent declarations, then group
declarations, in source order and keeps Plugin declaration order. Included
Topologies receive the same expansion in their own scope. Common Topology
validation checks the complete graph before Controller activation. The source
definition stays unchanged.

Live placement policy uses a different boundary. A control Agent can receive
Topology lifecycle Signals, select an exact node, and return a Plugin-owned
Directive. The Agent Server callbacks can apply that Directive through
`Jido.Topology.Controller.place_agent/4` after commit. Static contribution does
not gain live authority.

See [Plugin Runtimes](plugin-runtimes.livemd) and
[Plugin-Owned State](plugin-state.md).
