# Admission and Deadlines

An AgentServer runs one Turn at a time and holds later requests in a bounded queue. This guide explains when a request is accepted or rejected, and which setting bounds each wait.

The examples use a shipping Agent whose `:ship` Turn stays open until the test sends it a message.

```elixir
defmodule AdmissionGuide.Ship do
  use Jido.Action,
    name: "admission_guide_ship",
    schema: Jido.Joi.object(%{parcel: Jido.Joi.string()})

  @impl Jido.Action
  def run(%{parcel: parcel}, %{agent_state: state} = context) do
    if context[:notify], do: send(context.notify, {:shipping, self()})
    if context[:notify], do: receive(do: (:finish -> :ok))
    {:ok, %{state | shipped: state.shipped ++ [parcel]}}
  end
end

defmodule AdmissionGuide.Reenter do
  use Jido.Action, name: "admission_guide_reenter", schema: Jido.Joi.object(%{})

  @impl Jido.Action
  def run(_input, %{agent_state: state, server: server, notify: notify}) do
    signal = Jido.Signal.new!("parcel.ship", %{parcel: "inner"}, source: "/shipping")
    send(notify, {:inner_result, Jido.AgentServer.call(server, signal)})
    {:ok, state}
  end
end

defmodule AdmissionGuide.Dock do
  use Jido.Agent, name: "shipping_dock"

  state do
    schema Jido.Joi.object(%{shipped: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/shipping"
    route "parcel.ship", AdmissionGuide.Ship, as: :ship
    route "parcel.reenter", AdmissionGuide.Reenter, as: :reenter
  end
end

{:ok, _instance} = Jido.start(name: AdmissionGuide.Jido)

ship = fn parcel -> AdmissionGuide.Dock.ship_signal!(%{parcel: parcel}) end

# Starts a Turn that stays open and returns its handle and Action process.
open_turn = fn server ->
  pending = Jido.AgentServer.submit(server, ship.("open"), context: %{notify: self()})

  receive do
    {:shipping, action} -> {pending, action}
  after
    1_000 -> raise "the Turn did not start"
  end
end
```

## How a request enters

Each `call`, `submit`, and `cast` becomes one Turn request. The server checks it on arrival:

1. If the server is still starting, it rejects the request with `:not_ready`.
2. If admission is closed, it rejects the request with `:quiesced`.
3. If the caller is part of the running Turn, it rejects the request with `:reentrant_turn`.
4. If the request's admission deadline has passed, it rejects the request with `:admission_timeout`.
5. If the server is idle, the Turn starts.
6. If the queue is full, it rejects the request with `{:overloaded, details}`.
7. Otherwise the request waits in the queue.

Queued requests run in arrival order. The server checks a queued request again each time it changes phase, including when the running Turn ends. `Jido.AgentServer.upgrade/3` uses the same queue, and reports closed admission as `{:not_admitting, mode}`.

## Bound the queue

`:max_postponed_signals` limits how many requests can wait. The default is 1,000. Use a non-negative integer or `:infinity`. With `0`, a request that arrives during a Turn is rejected.

```elixir
{:ok, small_dock} =
  Jido.start_agent(AdmissionGuide.Jido, AdmissionGuide.Dock, id: "small", max_postponed_signals: 1)

{open, action} = open_turn.(small_dock)
queued = Jido.AgentServer.submit(small_dock, ship.("queued"))

%{postponed: 1, limit: 1} = Jido.AgentServer.status(small_dock).admission

{:error, {:overloaded, %{limit: 1, postponed: 1}}} =
  Jido.AgentServer.call(small_dock, ship.("excess"))
```

`Jido.AgentServer.cast/3` still returns `:ok` for an excess request. The server logs and drops it, so cast only work that you can lose.

```elixir
:ok = Jido.AgentServer.cast(small_dock, ship.("dropped"))
send(action, :finish)

{:ok, _agent, []} = Jido.AgentServer.await(open)
{:ok, %{state: %{shipped: ["open", "queued"]}}, []} = Jido.AgentServer.await(queued)
```

This limit counts queued Turn requests. It does not bound the process mailbox. Read `admission.message_queue_len` from `Jido.AgentServer.status/2` to watch that.

## Set an admission deadline

`:admission_timeout` sets a deadline for a request to start its Turn. The server checks it on arrival and at each phase change, so a caller can wait past the deadline during one long Turn. `call` and `submit` accept it, with a default of 5,000 ms. Use `:infinity` to wait without a deadline. A cast has no admission deadline.

```elixir
{:ok, dock} = Jido.start_agent(AdmissionGuide.Jido, AdmissionGuide.Dock, id: "main")
{open, action} = open_turn.(dock)

{:error, :admission_timeout} = Jido.AgentServer.call(dock, ship.("too-late"), admission_timeout: 0)
```

An expired request leaves no queued work. The deadline is checked on arrival and at each later phase change, so it does not fire by itself while one long Turn runs. In this example, the rejection arrives only after the open Turn ends, well past the deadline:

```elixir
waiting =
  Task.async(fn -> Jido.AgentServer.call(dock, ship.("queued"), admission_timeout: 20) end)

Process.sleep(100)
nil = Task.yield(waiting, 0)

send(action, :finish)
{:ok, _agent, []} = Jido.AgentServer.await(open)
{:error, :admission_timeout} = Task.await(waiting)
```

Use the caller timeout as well when the caller must not wait longer than a fixed time.

A finite admission deadline needs a caller on the server's node, because it uses that node's monotonic clock. A caller on another node gets `{:error, :admission_clock_unavailable}` and should pass `admission_timeout: :infinity`.

## Reject reentrant calls

An Action or effect in a Turn cannot wait on its own server, because the server would wait on the Action. The call returns `{:error, :reentrant_turn}` right away. The same applies to tasks that the Action starts, and to the control functions such as `Jido.AgentServer.cancel/2`.

```elixir
reenter = AdmissionGuide.Dock.reenter_signal!(%{})
{:ok, _agent, []} = Jido.AgentServer.call(dock, reenter, context: %{server: dock, notify: self()})

receive do
  {:inner_result, {:error, :reentrant_turn}} -> :rejected
after
  1_000 -> raise "the Action did not report"
end
```

A cast from inside a Turn does not wait, so it queues as usual.

## Bound each stage of a Turn

These settings cover different waits. Stopping a wait does not always stop the work.

| Setting | Default | Bounds | On expiry |
| --- | --- | --- | --- |
| `:admission_timeout` (per request) | 5,000 ms | The wait before a Turn starts. | `{:error, :admission_timeout}`. No work starts. |
| `:timeout` or the `call/3` timeout (per request) | 5,000 ms | The caller's wait. | The caller exits. The Turn continues. |
| `Jido.AgentServer.await/2` timeout (per request) | 5,000 ms | One wait for a submitted Turn. | `{:error, :timeout}`. Call `await/2` again. |
| `:turn_timeout` | 60,000 ms | The Turn from start to commit. | The Turn stops with `{:error, :turn_timeout}` and no commit. |
| `:timeout` in `:exec_opts` | `:infinity` | Execution of each step in the Turn. | The Turn fails with a `Jido.Error.TimeoutError` and no commit. |
| `:persistence_timeout` | 5,000 ms | A durable save in a Turn. | The outcome is uncertain, and the activation stops. |
| `:commit_timeout` | 5,000 ms | Plugin `after_commit/3` callbacks in one Turn. | The effects are recorded as timed out. The commit stands. |
| `:directive_timeout` | 5,000 ms | The Directive batch of one Turn. | The effects are recorded as timed out. The commit stands. |
| `:error_policy_timeout` | 5,000 ms | One error policy run. | The activation stops with `{:shutdown, :error_policy_timeout}`. |
| `:readiness_timeout` | 5,000 ms | Plugin startup and composition changes. | The activation stops. |

`:turn_timeout` accepts any non-negative integer in milliseconds or `:infinity`. The clock stops at commit, so slow effects do not cause a Turn timeout.

```elixir
{:ok, strict_dock} =
  Jido.start_agent(AdmissionGuide.Jido, AdmissionGuide.Dock, id: "strict", turn_timeout: 30)

{:error, :turn_timeout} =
  Jido.AgentServer.call(strict_dock, ship.("slow"), context: %{notify: self()})

%{status: :timed_out, committed?: false} = Jido.AgentServer.status(strict_dock).last_outcome
```

The server cancels the Action when the Turn times out. `:exec_opts` also accepts `:max_attempts`, `:backoff`, `:base_delay_ms`, `:max_delay_ms`, `:max_concurrency`, and `:hooks`. Jido retries only errors that `Jido.Error.retryable?/1` accepts. See [Action Execution Policy](../actions/action-execution-policy.md) for what these settings mean in execution.

## Configure the defaults

Set the options on one Agent when you start it, or on an instance for all its Agents. A start option overrides the instance default.

```elixir
{:ok, _instance} =
  Jido.start(
    name: AdmissionGuide.Tenant,
    agent_server: [turn_timeout: 30_000, max_postponed_signals: 50]
  )

{:ok, default_dock} = Jido.start_agent(AdmissionGuide.Tenant, AdmissionGuide.Dock, id: "a")

{:ok, custom_dock} =
  Jido.start_agent(AdmissionGuide.Tenant, AdmissionGuide.Dock, id: "b", max_postponed_signals: 5)

{Jido.AgentServer.status(default_dock).admission.limit, Jido.AgentServer.status(custom_dock).admission.limit}
```

`:turn_timeout` has one more source. When neither the start options nor the instance set it, Jido reads application config. This config accepts no other key.

<!-- partial -->
```elixir
config :jido, Jido.AgentServer, turn_timeout: 120_000
```

[Agent Lifecycle](agent-activation-control.md#startup-options) lists every startup option.

## Rejection reasons

| Reason | Cause | What to do |
| --- | --- | --- |
| `:not_ready` | The server is restoring or starting Plugins. | Call `Jido.AgentServer.await_ready/2` first. |
| `:quiesced` | Admission is closed, or the request was queued when it closed. | Call `Jido.AgentServer.resume/2` when the server has settled, then send the request again. |
| `{:overloaded, %{limit: limit, postponed: count}}` | The queue is full. | Back off, or raise `:max_postponed_signals`. |
| `:admission_timeout` | The deadline passed before the Turn started. | Retry, or raise the deadline. |
| `:admission_clock_unavailable` | A finite deadline came from another node. | Pass `admission_timeout: :infinity`. |
| `:reentrant_turn` | Owned work waited on its own server. | Use a Directive, or return the result from the Action. |

None of these reasons means the Turn ran. No state changed.

## Related

- [Call, Cast, and Await](send-signals-to-live-agents.livemd) shows each request mode.
- [Control Activations](inspect-and-control-activations.livemd) closes and reopens admission.
- [Cancel Turns](cancel-turns.livemd) stops an admitted Turn.
