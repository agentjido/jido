# Life of a Signal

This guide follows one Signal through a live Agent, from the caller to the last Directive. Read it to learn which stage owns each check, where a failure can stop the Signal, and what is already true when your call returns.

## The trace

This order Agent records each stage it can see. A small Plugin records the Plugin callbacks, and the Action records itself.

```elixir
defmodule SignalLife.Trace do
  def start, do: Agent.start(fn -> [] end, name: __MODULE__)
  def add(step), do: Agent.update(__MODULE__, &[step | &1])
  def steps, do: Agent.get(__MODULE__, &Enum.reverse/1)
end

defmodule SignalLife.Tracer do
  use Jido.Plugin

  alias SignalLife.Trace

  @impl true
  def state_spec(_opts), do: {:turns, Jido.Joi.integer() |> Jido.Joi.default(0)}

  @impl true
  def prepare(_preparation, _opts) do
    Trace.add(:prepare)
    {:ok, %{}}
  end

  @impl true
  def admit(_runtime, _admission, _opts) do
    Trace.add(:admit)
    {:ok, %{}}
  end

  @impl true
  def reduce(reduction, _opts) do
    Trace.add(:reduce)
    {:ok, reduction.plugin_state + 1}
  end

  @impl true
  def after_commit(_runtime, _commit, _opts) do
    Trace.add(:after_commit)
    :ok
  end

  @impl true
  def prepare_outbound(_runtime, signal, _context, _opts) do
    Trace.add({:outbound, signal.type})
    {:ok, signal}
  end
end

defmodule SignalLife.PlaceOrder do
  use Jido.Action,
    name: "signal_life_place_order",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string()}),
    output_schema:
      Jido.Joi.object(%{
        next_state: Jido.Joi.map(),
        confirmation: Jido.Joi.object(%{order_id: Jido.Joi.string()})
      })

  @impl Jido.Action
  def run(%{order_id: order_id}, %{agent_state: state, audit_log: audit_log}) do
    SignalLife.Trace.add(:action)
    audited = Jido.Signal.new!("order.audited", %{order_id: order_id}, source: "/orders/desk")

    {:ok,
     %{
       next_state: %{state | placed: [order_id | state.placed]},
       confirmation: %{order_id: order_id}
     }, [Jido.Agent.Directive.emit(audited, {:pid, target: audit_log})]}
  end
end

defmodule SignalLife.OrderDesk do
  use Jido.Agent, name: "order_desk", plugins: [SignalLife.Tracer]

  state do
    schema Jido.Joi.object(%{placed: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/orders/desk"

    route "order.place", SignalLife.PlaceOrder, as: :place do
      state from: output(:next_state)
      reply "order.confirmed", from: output(:confirmation)
    end
  end
end

{:ok, _trace} = SignalLife.Trace.start()
{:ok, _instance} = Jido.start(name: SignalLife.Jido)
{:ok, desk} = Jido.start_agent(SignalLife.Jido, SignalLife.OrderDesk, id: "desk-1")
:ok = Jido.AgentServer.await_ready(desk)

signal = SignalLife.OrderDesk.place_signal!(%{order_id: "o-1"})

{:ok, committed, [%Jido.Agent.Directive.Emit{}, %Jido.Agent.Directive.Reply{}]} =
  Jido.AgentServer.call(desk, signal, context: %{audit_log: self()})

%{placed: ["o-1"], turns: 1} = committed.state

# Effects run after the call returns, so wait for them.
Enum.find(1..200, fn _attempt ->
  Process.sleep(5)
  Jido.AgentServer.status(desk).phase == :idle
end)

[
  :prepare,
  :admit,
  :action,
  :reduce,
  :after_commit,
  {:outbound, "order.audited"},
  {:outbound, "order.confirmed"}
] = SignalLife.Trace.steps()
```

The rest of this guide walks through that list and the stages the Agent cannot see.

## The stages

The stages written as atoms are internal phases of the server. `Jido.AgentServer.status/2` reports the current one as `active.stage` during a Turn, while its `phase` field stays `:running`.

| Stage | What happens | On failure |
| --- | --- | --- |
| Before the server | The caller checks the Signal and options. | `{:error, reason}`. Nothing was sent. |
| Admission | The server accepts, queues, or rejects the request. | `{:error, reason}`. No Turn exists. |
| `:preparing` | Plugins prepare and admit. One route is selected. | The Turn fails. |
| `:starting`, `:running` | The Flow runs under a Worker. | The Turn fails. |
| `:settling` | The output becomes a candidate Agent and a Directive batch. | The Turn fails. |
| `:cleaning` | The Worker stops. | The server stops if cleanup cannot be confirmed. |
| `:reconfiguring` | Runtime Plugins that this Turn changes are paused. | The Turn fails. |
| `:saving` | A server with persistence writes the candidate. | The activation stops. |
| Commit | The server publishes the candidate and the new revision. | The activation stops. |
| `:effects` | The caller gets its answer. Hooks and Directives run. | The commit stands. |

### Before the server

`Jido.AgentServer.call/3` normalizes the Signal and checks its options in the caller. It then sends one Turn request with `:gen_statem.call/3` and waits. `Jido.AgentServer.submit/3` sends the same request without waiting, and `Jido.AgentServer.cast/3` sends it with no reply address.

Both `call/3` and `submit/3` also start a small process that holds the reply Signal until the caller can receive it. A `cast/3` has no such process, which is why an ordinary cast that produces a reply fails at the settling stage. A durable Turn is the exception, because it can outlive its caller and drops the reply instead.

### Admission

The server checks readiness, whether admission is open, reentrancy, and the admission deadline. An idle server starts the Turn. A busy server queues the request, up to `:max_postponed_signals`. Queued requests run in arrival order. [Admission and Deadlines](../agent-servers/agent-server-admission.md) lists each rejection.

The Turn then gets a UUIDv7 `turn_id`, a trace context, and a deadline from `:turn_timeout`. The clock runs until commit.

### Prepare

The server does this work in a separate task, so it can still answer reads:

1. `prepare/2` runs for each Plugin, in declaration order.
2. `admit/3` runs for each Plugin, in declaration order. This callback runs only on the live path, and it can reject the Turn.
3. Route selection picks the first route whose path matches the Signal type. A Plugin that defines `select_route/2` can choose among the matches. No match returns a validation error with the code `:unmatched_input`.
4. Route defaults merge with the Signal data. The Signal data wins on an equal key.
5. Jido builds a `Jido.Agent.Turn`. An Action route becomes a one-step Flow here, so every Turn runs a Flow.

The handler context now holds `:agent_state`, `:signal`, `:plugin_inputs`, and the other keys listed in [Agent Turns and Replies](../agents/turns-state-and-replies.md#what-the-handler-sees).

### Run

Jido compiles the Flow to a `Runic.Workflow` and starts it as a Worker under the instance's Runner. The server moves to `:running` and waits for a message from the Worker. It does not block, so `Jido.AgentServer.status/2`, `Jido.AgentServer.agent/2`, and `Jido.AgentServer.cancel/2` still work.

`:exec_opts` sets the policy for this run, including retries and the timeout for each Action. See [Execution Policy](../actions/action-execution-policy.md).

A route to an authored Flow takes a longer path when the server has persistence. The server first saves the accepted Turn, which adds one revision. It then runs the Flow one saved step at a time, and it can suspend on a wait in the `:waiting` phase. [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd) covers that path. Without persistence, the same route runs as an ordinary Turn, and a wait fails it.

### Settle

When the Worker finishes, the server reads the result and turns it into a candidate. Each check below can fail the Turn:

1. The output must be a plain Map.
2. Each Directive is built. A short `emit("type", %{})` becomes a Signal that uses the Agent's `signal_source`.
3. The route's `state` selector picks the next state, and its `reply` selector builds a Reply Directive. The Reply goes last in the batch, or before a trailing `ServerStop`.
4. Jido rejects a change to a Plugin-owned field, and it validates every Directive.
5. `reduce/2` runs for each Plugin, which updates that Plugin's field.
6. Mutation Directives apply to the candidate, and the complete state is checked against the schema.
7. The server checks any change to composition, and then checks the batch against what this server can do. A `ParentSend` needs a parent. A `Reply` needs a caller. A `ServerStop` must be last. The batch must fit within `:max_directives_per_turn`.

The source Agent is untouched through all of this. The candidate is a value that no one else can see.

### Clean up

The server cancels the Worker and waits for confirmation before it continues. A timeout or cancellation that arrives here takes effect when cleanup ends. A failed Turn passes through this stage too.

### Commit

Up to this point the Turn can still fail with no trace in the Agent. The commit runs in this order:

1. Runtime Plugins that this Turn adds, changes, or removes are paused.
2. With persistence, the server calls `dump/3` for Plugin state and writes the candidate and the next revision. `:persistence_timeout` bounds the write. The Turn deadline stops here.
3. The activation's local checkpoint takes the candidate and the revision.
4. The server's own Agent value and `state_version` change. `last_outcome` records the Turn, and `error_count` returns to 0.

A failed write or checkpoint does not fail the Turn. The result is uncertain, so the activation stops. See [Revisions and Conflicts](../durability/durable-revisions-and-conflicts.md).

### The caller gets its answer

The caller's `{:ok, agent, directives}` goes out at commit, before any effect runs. A Reply Signal arrives after that return value, as an ordinary message in the caller's mailbox.

```elixir
receive do
  %Jido.Signal{type: "order.confirmed", data: %{order_id: "o-1"}} -> :confirmed
after
  1_000 -> raise "no reply"
end

receive do
  {:signal, %Jido.Signal{type: "order.audited"}} -> :audited
after
  1_000 -> raise "no audit"
end
```

### Effects

The server stays in `:effects` and runs each step in its own task, one at a time:

1. If this Turn changed composition or Plugin configuration, Jido rebuilds those Plugins and reconciles the topology. `:readiness_timeout` bounds this step.
2. `after_commit/3` runs for each Plugin, in declaration order, even if the state did not change. `:commit_timeout` bounds all of the hooks.
3. Directives run in batch order. Mutation Directives are skipped, because they already applied to the candidate. `:directive_timeout` bounds the whole batch.

Each outbound Signal first gets trace data from the source Signal, and then passes through `prepare_outbound/4` in reverse Plugin order. That is why the trace shows `{:outbound, ...}` before each Signal leaves.

An `Emit` with a dispatch configuration uses that dispatch. An `Emit` with none looks for a matching connection, then a topology parent, then `:default_dispatch`. If it finds none of those, it casts the Signal back to this server, where it starts again at admission as a new Turn. See [Transforms and Forwards](../agents/route-transforms-and-forwards.md#where-the-output-goes).

`last_effect_outcome` records the result. [Turns and Effects](turns-commits-and-effects.md) explains what happens when an effect fails.

### Back to idle

The server returns to `:idle`, and OTP delivers the queued requests again. The next one starts. The next Turn cannot begin until this Turn's effects are done, so a slow Directive delays the queue.

```elixir
%{
  state_version: 1,
  last_outcome: %{status: :succeeded, stage: :commit, committed?: true},
  last_effect_outcome: %{status: :succeeded, completed: 2, total: 2, committed_version: 1}
} = Jido.AgentServer.status(desk)
```

## Where a Signal can stop

A failed Turn skips the remaining stages and then does the following:

1. The failure passes through cleanup, with no commit and no change to `state_version`.
2. A server with a durable Turn in progress writes a terminal receipt.
3. Paused Plugins resume.
4. `last_outcome` records the status. Only a `:failed` status raises `error_count` and runs `:error_policy`. A cancelled or timed-out Turn does not.
5. The caller gets `{:error, reason}`. A cast logs a warning.

```elixir
unrouted = Jido.Signal.new!("order.unknown", %{}, source: "/orders/api")

{:error, %Jido.Error.ValidationError{code: :unmatched_input}} =
  Jido.AgentServer.call(desk, unrouted)

%{state_version: 1, error_count: 1, last_outcome: %{status: :failed, committed?: false}} =
  Jido.AgentServer.status(desk)
```

Losing the Worker, the Runner, or the instance is different. The server stops instead of failing the Turn. See [Why a worker stopped](../agent-servers/agent-activation-control.md#why-a-worker-stopped).

## A Handoff extends the path

A Flow that ends in a Handoff commits its own candidate and runs its effects, then the server starts the successor as a new Turn with the same caller. That caller gets one answer, from the end of the chain. See [Dynamic Flows](../flows/dynamic-flows.md).

## Related

- [Turns and Effects](turns-commits-and-effects.md) explains the commit boundary.
- [Status and Turn History](../agent-servers/status-and-history.md) reads each stage on a live server.
- [Observe Agent Turns](../operations/observe-agent-turns.livemd) follows a Turn with Telemetry.
