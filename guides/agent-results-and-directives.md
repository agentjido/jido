# State and Directives

An Agent handler returns two things: the complete next state, and a list of
Directives describing work to run after that state commits. This guide covers
the result contract, the Directives Jido provides, custom Directives, and how
each rule fails. Read it after [Routes and Handlers](build-agent-routes.livemd).

A handler that changes state and requests one outbound Signal looks like this:

```elixir
defmodule MyApp.Counter.Reset do
  use Jido.Action, name: "reset", schema: Zoi.object(%{})

  @impl true
  def run(_params, %{agent_state: state}) do
    {:ok, %{state | count: 0},
     [Jido.Agent.Directive.emit("counter.cleared", %{previous: state.count})]}
  end
end
```

`cmd/3` returns that state as a candidate and the `Emit` as data. A live Agent
Server commits the state, replies to the caller, then sends the Signal.

## Result Shapes

| Return | Effect |
| --- | --- |
| `{:ok, state}` | `state` becomes the candidate. No Directives. |
| `{:ok, state, directives}` | Same, plus a proper list of Directives. |
| `{:error, reason}` | The Turn fails. Committed state is unchanged. No Directives run. |

Flows on Agent routes follow the same contract. The Flow's `output` must be
the complete next state. Directives from every successful step join one
batch. A failed Flow returns no batch.

## Return Complete State

`state` is the whole next state as a plain map, never a patch. Start from
`context.agent_state` and change only the fields you mean to change:

```elixir
def run(%{amount: amount}, %{agent_state: state}) do
  {:ok, %{state | count: state.count + amount}}
end
```

`%{state | ...}` copies every other field, including Plugin-owned ones. Jido
validates the candidate against the full state schema, so a partial map fails
with `"State does not match its schema"`. On an Agent with Plugins, a partial
map usually fails first with `"Agent executable changed Plugin-owned state"`,
because a missing Plugin field counts as a changed one.

## Plugin-Owned Fields

A Plugin can own one state field. Your handler can read it. Any change to it
fails the Turn with `"Agent executable changed Plugin-owned state"`. The
Plugin updates its own field later, in `reduce/2`, with the candidate state
and the full Directive batch. See [Stateful Plugins](write-a-stateful-plugin.livemd).

## Emit A Signal

`emit` requests one outbound Signal after commit. It's imported in Agent
modules, including inline `action` blocks. In an Action module, call
`Jido.Agent.Directive.emit/2`.

| Form | Builds |
| --- | --- |
| `emit("count.changed", %{count: 3})` | A Signal with this type and data. Source: the Agent's `signal_source`. |
| `emit(signal)` | An `Emit` for a Signal you built. The envelope is kept as is. |
| `emit(signal, dispatch)` | The same, with an explicit dispatch configuration. |

The type/data form needs an exact type, a plain map of static data, and a
`signal_source` on the Agent. Without them the Turn fails with
`"Agent executable returned an invalid Directive"`.

Use a full Signal when you need to set `subject`, `source`, or extensions:

```elixir
signal = Jido.Signal.new!("count.full", %{count: 3}, source: "/billing", subject: "acct-7")

{:ok, state, [Jido.Agent.Directive.emit(signal, {:pid, target: reporter_pid})]}
```

Without an explicit dispatch, the Server sends the Signal to matching
topology connections, then the owning topology, then `default_dispatch:`,
and finally back to the Agent itself. [Life of a Signal](signal-to-effects.md)
covers this order and the loop it can cause.

## Reply To The Current Request

`Reply` is separate from `Emit`. It sends one correlated response to the
caller that submitted the current request. Build the response Signal with the
SignalAction that owns its input and output contracts, then wrap it:

```elixir
with {:ok, response} <- MyApp.PriceQuote.reply(request, result) do
  {:ok, state, [Jido.Agent.Directive.reply(response)]}
end
```

The response must use the current request ID as its causation ID. One Turn can
return at most one `Reply`. The Agent Server sends it only after the state
commits. Pure `cmd/3` returns the Directive as data and sends nothing.

## Runtime Directives

`Jido.AgentServer.Directive` builds the other built-in runtime requests:

| Constructor | Request |
| --- | --- |
| `signal_send(signal, pid)` | An `Emit` with `{:pid, target: pid}` dispatch. |
| `agent_send(name, signal)` | Send a Signal to a tracked child Agent. |
| `parent_send(signal)` | Send a Signal to the parent Agent. |
| `agent_start(agent, name, opts \\ [])` | Start a tracked child Agent. |
| `agent_stop(name, reason \\ :normal)` | Stop a tracked child Agent. |
| `process_start(child_spec)` | Start a process under the Jido instance. It can outlive the Server. |
| `error_report(error, context \\ nil)` | Apply the Server error policy after commit. |
| `server_stop(reason \\ :normal)` | Stop the Server after commit. |

`server_stop` must be the last Directive in its batch. A live Server rejects
any other order with `{:error, :terminal_directive_not_last}`. `cmd/3` does
not check this rule, so test Directive order against a live Server.

## Definition Directives

Mutation Directives such as `Jido.Agent.Directive.route_add/3`,
`agent_add/3`, and `plugin_add/3` edit the Agent's own definition: routes,
child Agents, connections, and Plugins. Jido applies them to the candidate
before commit, so the new definition and the new state commit as one revision.
See [Mutations and Diffs](agent-mutations-and-diffs.livemd).

## Custom Directives

A custom Directive is a struct that uses `Jido.Agent.Directive`:

```elixir
defmodule MyApp.Notice do
  defstruct [:text]
  use Jido.Agent.Directive

  def schema, do: Zoi.struct(__MODULE__, %{text: Zoi.string() |> Zoi.min(1)}, coerce: true)
end
```

`use Jido.Agent.Directive` adds a default `validate/1`. When the module
defines `schema/0`, the default checks the struct against it. Override
`validate/1` for other rules. A struct that fails the default check makes the
Turn return `{:error, [%Zoi.Error{}]}`, a raw list of Zoi issues rather than a
Jido error struct.

Every custom Directive needs an owner: a Plugin that lists it in
`directives/1` and carries it out in `dispatch/4`.

```elixir
defmodule MyApp.Notices do
  use Jido.Plugin

  @impl true
  def directives(_opts), do: [MyApp.Notice]

  @impl true
  def dispatch(_runtime, %MyApp.Notice{text: text}, context, _opts) do
    MyApp.Inbox.post(text, revision: context.state_version)
  end
end
```

A Directive with no owner fails the Turn with `"Agent Directive has no owner"`.
`dispatch/4` runs after commit and receives the committed revision in
`context.state_version`. [Custom Directives](plugin-custom-directives.livemd)
covers runtime references and the full context.

## I/O Or Directive

Actions can call external systems directly. That call runs before commit, so
if a later step fails, the call has already happened and Jido can't undo it.
A Directive runs only after the state commits, and `cmd/3` returns it as data
your tests can assert on.

| Situation | Use |
| --- | --- |
| The next state depends on the result: a model reply, a price lookup. | I/O in the Action. Make it idempotent. |
| The work reports what happened: a notification, an event. | A Directive. |
| The work must not happen unless the state commits. | A Directive. |
| You want to test the plan without running it. | A Directive. |
| Infrastructure should retry or deliver it. | A Directive owned by a Plugin. |

## Failure Messages

Each rule fails the whole Turn. Committed state is unchanged, and no
Directives run.

| Problem | Error message |
| --- | --- |
| State isn't a map | `"Action output validation must return a map"` |
| State is a struct | `"Agent executable output must be a plain state map"` |
| State doesn't match the schema | `"State does not match its schema"` |
| A Plugin-owned field changed or is missing | `"Agent executable changed Plugin-owned state"` |
| The third element isn't a proper list | `"Action returned an invalid effects list"` |
| A list item isn't a Directive | `"Agent executable returned an invalid Directive"` |
| A custom Directive has no owner | `"Agent Directive has no owner"` |
| A Reply has the wrong causation ID | `"Agent Reply Directive must match the current request"` |
| A Turn returns more than one Reply | `"Agent turn can return only one Reply Directive"` |
| More Directives than `max_directives_per_turn:` (default 1,000) | The live Server rejects the Turn. |

For your own failures, return a structured error such as
`Jido.Action.Error.execution_error("inventory unavailable", %{code: :out_of_stock})`.
Callers can match on the `code` instead of the message.

## Next

- [Mutations and Diffs](agent-mutations-and-diffs.livemd) changes routes,
  child Agents, and Plugins from a Turn.
- [Custom Directives](plugin-custom-directives.livemd) shows how to own and
  dispatch your own Directives.
