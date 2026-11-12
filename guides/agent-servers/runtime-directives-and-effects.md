# Runtime Effects

An AgentServer runs a Turn's Directives after it commits the Agent. This guide explains that order, lists what each built-in Directive does at runtime, and shows how to observe and handle effect failures.

[State and Directives](../agents/agent-results-and-directives.md) covers how an Action returns Directives. The examples here use an order Agent whose routes return the batch that each section needs.

```elixir
defmodule EffectsGuide.Notice do
  use Jido.Agent.Directive

  defstruct [:order_id, :label, :observer]
end

defmodule EffectsGuide.Notices do
  use Jido.Plugin

  @impl true
  def state_spec(_opts), do: {:notices, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def directives(_opts), do: [EffectsGuide.Notice]

  @impl true
  def reduce(reduction, _opts) do
    count = Enum.count(reduction.directives, &match?(%EffectsGuide.Notice{}, &1))
    {:ok, reduction.plugin_state + count}
  end
end

defmodule EffectsGuide.Batch do
  use Jido.Action, name: "effects_guide_batch"

  @impl Jido.Action
  def run(_input, %{agent_state: state, batch: batch}) do
    {:ok, %{state | placed: state.placed + 1}, batch}
  end
end

defmodule EffectsGuide.Orders do
  use Jido.Agent, name: "effect_orders", plugins: [EffectsGuide.Notices]

  state do
    schema Jido.Joi.object(%{placed: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/orders"
    route "order.place", EffectsGuide.Batch, as: :place
  end
end

{:ok, _instance} = Jido.start(name: EffectsGuide.Jido)

place = fn server, batch ->
  Jido.AgentServer.call(server, EffectsGuide.Orders.place_signal!(%{}), context: %{batch: batch})
end

outbound = fn label -> Jido.Signal.new!("order.placed", %{label: label}, source: "/orders") end

start_orders = fn id, opts ->
  {:ok, server} = Jido.start_agent(EffectsGuide.Jido, EffectsGuide.Orders, [id: id] ++ opts)
  :ok = Jido.AgentServer.await_ready(server)
  server
end

# Any Turn queues behind the running effects, so a later call waits for them.
settle = fn server ->
  Jido.AgentServer.call(server, EffectsGuide.Orders.place_signal!(%{}), context: %{batch: []})
  Jido.AgentServer.status(server).last_effect_outcome
end
```

## The commit comes first

A Turn with Directives follows this order:

1. **Validate.** The server checks the whole batch against the candidate Agent. Any problem fails the Turn, and nothing runs.
2. **Save.** With persistence on, the server saves the candidate.
3. **Commit.** The candidate becomes the Agent, and `state_version` rises by one.
4. **Reply.** `Jido.AgentServer.call/3` returns to the caller here.
5. **Run hooks.** Plugin `after_commit/3` callbacks run.
6. **Run effects.** Directives run one at a time, in order.
7. **Finish.** The server records the effect outcome and takes the next queued Turn.

`call/3` returns before step 7 finishes, so its return value says nothing about effects. Queued Turns wait for the effects to finish, which makes a later `call/3` a barrier for those effects. It is not a barrier for Turns those effects enqueue: an Emit that casts back to the Agent can run after that call.

Each effect runs in its own task under the server, so reads stay available. The Turn can no longer be cancelled: `Jido.AgentServer.cancel/2` returns `{:error, :not_running}`. `Jido.AgentServer.quiesce/2` waits for the batch, with or without `active: :cancel`.

```elixir
orders = start_orders.("orders-1", [])

{:ok, %{state: %{placed: 1}}, [%Jido.Agent.Directive.Emit{}, %Jido.Agent.Directive.Emit{}]} =
  place.(orders, [
    Jido.Agent.Directive.emit(outbound.("first"), {:pid, target: self()}),
    Jido.Agent.Directive.emit(outbound.("second"), {:pid, target: self()})
  ])

for expected <- ["first", "second"] do
  receive do
    {:signal, %Jido.Signal{data: %{label: ^expected}}} -> :ok
  after
    1_000 -> raise "the effect did not run"
  end
end

%{status: :succeeded, completed: 2, total: 2, committed_version: 1, stage: :directive} =
  Jido.AgentServer.status(orders).last_effect_outcome
```

The Signal your process receives from a `:pid` dispatch arrives as `{:signal, signal}`. It carries the trace of the Turn, and its causation points at the Signal that started the Turn.

## Built-in Directives

These runtime Directives run after commit:

| Constructor | Effect | Rejected before commit when |
| --- | --- | --- |
| `Jido.Agent.Directive.emit/2` | Dispatches one Signal to its target. With no target, see [Where the output goes](../agents/route-transforms-and-forwards.md#where-the-output-goes). | The dispatch configuration is invalid. |
| `Jido.AgentServer.Directive.signal_send/3` | Builds an `Emit` for one local process, with `:delivery_mode`, `:timeout`, and `:message_format` options. | Unknown options raise `ArgumentError` when you build it. |
| `Jido.Agent.Directive.reply/1` | Sends one reply Signal to the caller. | There is no live caller: `:requester_not_found`. |
| `Jido.Agent.Directive.agent_send/2` | Casts a Signal to a child by tag, or to all members of a topology name. | The server has no activation, or the name is invalid or reserved. |
| `Jido.Agent.Directive.parent_send/1` | Casts a Signal to the parent. | The Agent has no parent: `:parent_not_found`. |
| `Jido.AgentServer.Directive.agent_start/3` | Starts a tracked child and waits until it is ready. | The options are invalid, the name belongs to the topology, or the node is remote. |
| `Jido.AgentServer.Directive.agent_stop/2` | Stops a tracked child. | The server has no activation, or the name belongs to the topology. |
| `Jido.AgentServer.Directive.process_start/1` | Starts one untracked OTP child under the instance's Agent supervisor. | The server has no instance, or the child spec is invalid. |
| `Jido.AgentServer.Directive.error_report/2` | Reports an error to the error policy. | Not applicable. |
| `Jido.Agent.Directive.server_stop/1` | Stops the server. | It is not last in the batch: `:terminal_directive_not_last`. |

[Child Agent Adoption](child-agents-and-adoption.md) shows the child Directives in use.

A Turn fails with `{:error, :too_many_directives}` when its batch exceeds `:max_directives_per_turn`, which has a default of 1,000. A failure here is an ordinary pre-commit Turn failure: the state does not change, and no effect runs.

```elixir
{:error, :parent_not_found} =
  place.(orders, [Jido.Agent.Directive.parent_send(outbound.("no parent"))])

{:error, :terminal_directive_not_last} =
  place.(orders, [
    Jido.Agent.Directive.server_stop(),
    Jido.Agent.Directive.emit(outbound.("after stop"), {:pid, target: self()})
  ])

%{state: %{placed: 1}} = Jido.AgentServer.agent(orders)
```

`process_start/1` does not track what it starts. Your code owns stopping that process, and the process outlives the Agent.

```elixir
spec = %{
  id: :order_printer,
  start: {Agent, :start_link, [fn -> [] end, [name: EffectsGuide.Printer]]},
  restart: :temporary
}

{:ok, _agent, _batch} = place.(orders, [Jido.AgentServer.Directive.process_start(spec)])
%{status: :succeeded} = settle.(orders)

:ok = Agent.stop(EffectsGuide.Printer)
```

## When an effect fails

A failed effect does not undo the commit, because the Agent had already changed. It stops the rest of the batch, and the server records the outcome. The caller has already received `{:ok, agent, directives}`.

Here the first dispatch targets a dead process, so the second never runs.

```elixir
dead = spawn(fn -> :ok end)
monitor = Process.monitor(dead)

receive do
  {:DOWN, ^monitor, :process, ^dead, _reason} -> :ok
after
  1_000 -> raise "the target did not exit"
end

failing = start_orders.("orders-2", [])

{:ok, %{state: %{placed: 1}}, [_first, _second]} =
  place.(failing, [
    Jido.Agent.Directive.emit(outbound.("lost"), {:pid, target: dead}),
    Jido.Agent.Directive.emit(outbound.("never sent"), {:pid, target: self()})
  ])

failed_outcome = settle.(failing)

%{status: :succeeded, committed?: true} = Jido.AgentServer.status(failing).last_outcome
%{state: %{placed: 2}} = Jido.AgentServer.agent(failing)
```

`last_effect_outcome` keeps a batch's result until another batch replaces it.

```elixir
%{status: :failed, completed: 0, total: 2} = failed_outcome
```

| `status` | Meaning |
| --- | --- |
| `:succeeded` | Every effect ran. |
| `:failed` | An effect returned an error or raised, or a Plugin hook failed. `:completed` counts the effects that ran before it. |
| `:timed_out` | The batch or hook deadline passed. The server killed the running effect. |
| `:indeterminate` | The server stopped during the effects, so some may have run. |

If an effect task dies abruptly, the worker stops with `{:shutdown, :effect_lifecycle_failed}`.

Jido does not retry effects. After a restart, the server does not run an interrupted batch again. See [Recovery Limits](../durability/recovery-and-effect-limits.md). For work that must eventually happen, record it in Agent state in the same Turn and let a later Signal retry it.

## Report an error to the error policy

A failed effect does not run the error policy. `Jido.AgentServer.Directive.error_report/2` does. Return it when a Turn should commit and also count as a failure: for example, an order accepted while its notification channel is down.

The server treats it as an effect that fails: it stops the batch, adds one to `error_count`, and runs the policy with `{:reported_error, context, error}`. The summary given to the policy has `committed?: true`, and its `stage` is `:directive`.

```elixir
observer = self()

policy = fn reason, summary ->
  send(observer, {:policy, reason, summary.committed?, summary.stage})
  :continue
end

reporting = start_orders.("orders-3", error_policy: policy)
report = Jido.AgentServer.Directive.error_report(:channel_down, :notification)

{:ok, %{state: %{placed: 1}}, [^report]} = place.(reporting, [report])

receive do
  {:policy, {:reported_error, :notification, :channel_down}, true, :directive} -> :reported
after
  1_000 -> raise "the policy did not run"
end
```

With `:stop_on_error`, the same report stops the worker after the commit. See [Agent Lifecycle](agent-activation-control.md#handle-failed-turns).

## Limits

| Option | Default | Limit |
| --- | --- | --- |
| `:max_directives_per_turn` | 1,000 | The batch size. `0` allows only an empty batch. |
| `:directive_timeout` | 5,000 ms | All Directives of one Turn together. It must be finite. |
| `:commit_timeout` | 5,000 ms | All Plugin `after_commit/3` callbacks of one Turn together. It must be finite. |

`:turn_timeout` does not apply after commit.

## Set a default dispatch

An `Emit` with no target goes to connections, then a topology parent, then the `:default_dispatch` option, and otherwise back to the Agent itself. A chain of Emits back to the Agent stops after 32 hops with a failed effect and a warning that names the Signal type and `:self_emit_limit`. `:default_dispatch` takes a Signal dispatch configuration. See [Signal Dispatch Adapters](../signals/dispatch-adapters.md).

```elixir
routed = start_orders.("orders-4", default_dispatch: {:pid, target: self()})

{:ok, _agent, _batch} = place.(routed, [Jido.Agent.Directive.emit(outbound.("default"))])

receive do
  {:signal, %Jido.Signal{data: %{label: "default"}}} -> :delivered
after
  1_000 -> raise "the default dispatch did not run"
end
```

## Run custom Directives

A custom Directive needs a Plugin that owns it, or the Turn fails with "Agent Directive has no owner". The Plugin chooses how it runs:

- With a `dispatch/4` callback, the Plugin runs it after commit. See [Custom Directives](../plugins/plugin-custom-directives.livemd). This is the standard form.
- With only `reduce/2`, the Plugin changes its own state. The Directive then has no runtime work, and the effect counts as done, unless the server has a `:directive_handler`.

`:directive_handler` is a two-argument function that receives the Directive and a runtime context. It runs for Directives with no dispatching Plugin, not for built-ins. The context includes `:agent`, `:turn_id`, `:signal_id`, `:state_version`, `:server`, `:jido`, and `:partition`.

| Handler returns | Result |
| --- | --- |
| `:ok` | The batch continues. |
| `{:stop, reason}` | The worker stops. |
| `{:reply, signal}` | The server sends the Signal to the caller, and the batch continues. |
| `{:reported_error, error}` | The same as `Jido.AgentServer.Directive.error_report/2`. |
| Anything else, or a raise | The effect fails, and the batch stops. |

This handler holds the effect open, so you can see the state of a server in its effects stage.

```elixir
handler = fn %EffectsGuide.Notice{} = notice, context ->
  send(notice.observer, {:notice, notice.label, self(), context.state_version})

  receive do
    :finish -> :ok
  end
end

noticing = start_orders.("orders-5", directive_handler: handler)
notice = %EffectsGuide.Notice{order_id: "o-1", label: "paid", observer: self()}

{:ok, committed, [^notice]} = place.(noticing, [notice])
%{placed: 1, notices: 1} = committed.state

effect =
  receive do
    {:notice, "paid", pid, 1} -> pid
  after
    1_000 -> raise "the handler did not run"
  end

%{active: %{stage: :effects, committed_version: 1}, effects: %{total: 1, completed: 0}} =
  Jido.AgentServer.status(noticing)

^committed = Jido.AgentServer.agent(noticing)
{:error, :not_running} = Jido.AgentServer.cancel(noticing)

send(effect, :finish)
%{status: :succeeded, completed: 1} = settle.(noticing)
```

The `Notices` Plugin counted the Directive when the Turn committed, and the handler ran it afterward. The handler's work is outside the commit, like any other effect.

## Observe effects

The runtime emits `[:jido, :agent_server, :effects, :start]` and `[:jido, :agent_server, :effects, :stop]`, with the status and stage on the stop event. See [Telemetry and Tracing](../operations/telemetry-tracing-and-logs.md).

## Related

- [Post-Commit Work](../plugins/plugin-post-commit-work.md) explains Plugin hooks.
- [Status and Turn History](status-and-history.md) describes the outcome fields.
