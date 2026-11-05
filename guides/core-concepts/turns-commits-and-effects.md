# Turns and Effects

The commit divides a Turn on a live Agent into two parts. This guide explains what is true on each side, what happens when an effect fails, and how to decide where your work belongs.

## The commit boundary

Before commit, a Turn produces a candidate: a complete next Agent and an ordered batch of Directives. The candidate is a value that no one else can see. Any failure discards it, and the Agent keeps its state and revision.

At commit, the server replaces its Agent with the candidate and adds 1 to `state_version`. With persistence, the write happens first, so a commit always exists in the store before anyone can read it.

After commit, the server answers the caller and then runs the effects. No effect can undo the commit.

| | Before commit | After commit |
| --- | --- | --- |
| Agent state | Unchanged | The candidate |
| A failure | Fails the Turn, with no change | Leaves the commit in place |
| `Jido.AgentServer.cancel/2` | Stops the Turn | `{:error, :not_running}` |
| Time limit | `:turn_timeout` | `:commit_timeout`, then `:directive_timeout` |
| Crash | The Turn is lost, or resumes if durable | The remaining effects are lost |

While the server writes the candidate to its store, `cancel/2` returns `{:error, :commit_in_progress}`. For a Turn that ends in a Handoff, `cancel/2` during effects stops the successor and leaves the commit in place.

A Turn that returns unchanged state still commits. The revision still rises, and the Directives and hooks still run.

## Watch the boundary

This Agent ships an order and then notifies a warehouse through a custom Directive. The Plugin that owns the Directive pauses until the example releases it, so you can look at the server between the commit and the effect. See [Custom Directives](../plugins/plugin-custom-directives.livemd) for how a Plugin owns a Directive.

```elixir
defmodule TurnEffectsGuide.Notify do
  use Jido.Agent.Directive

  defstruct [:mode, :observer]
end

defmodule TurnEffectsGuide.Warehouse do
  use Jido.Plugin

  alias TurnEffectsGuide.Notify

  @impl true
  def directives(_opts), do: [Notify]

  @impl true
  def dispatch(_runtime, %Notify{mode: :pause, observer: observer}, _context, _opts) do
    send(observer, {:notifying, self()})

    receive do
      :release -> :ok
    end
  end

  def dispatch(_runtime, %Notify{mode: :deliver, observer: observer}, _context, _opts) do
    send(observer, :delivered)
    :ok
  end

  def dispatch(_runtime, %Notify{mode: :fail}, _context, _opts), do: {:error, :warehouse_offline}
end

defmodule TurnEffectsGuide.Ship do
  use Jido.Action,
    name: "turn_effects_guide_ship",
    schema: Jido.Joi.object(%{order_id: Jido.Joi.string(), modes: Jido.Joi.list(Jido.Joi.atom())})

  @impl Jido.Action
  def run(%{order_id: order_id, modes: modes}, %{agent_state: state, observer: observer}) do
    {:ok, %{state | shipped: [order_id | state.shipped]},
     Enum.map(modes, &%TurnEffectsGuide.Notify{mode: &1, observer: observer})}
  end
end

defmodule TurnEffectsGuide.Shipping do
  use Jido.Agent, name: "shipping", plugins: [TurnEffectsGuide.Warehouse]

  state do
    schema Jido.Joi.object(%{shipped: Jido.Joi.list(Jido.Joi.string()) |> Jido.Joi.default([])})
  end

  routes do
    signal_source "/warehouse/shipping"
    route "order.ship", TurnEffectsGuide.Ship, as: :ship

    route "order.count", as: :count do
      action _input, schema: Jido.Joi.object(%{}), context: context do
        {:ok, context.agent_state}
      end
    end
  end
end

{:ok, _instance} = Jido.start(name: TurnEffectsGuide.Jido)
{:ok, server} = Jido.start_agent(TurnEffectsGuide.Jido, TurnEffectsGuide.Shipping, id: "dock-1")
:ok = Jido.AgentServer.await_ready(server)

ship = fn order_id, modes ->
  signal = TurnEffectsGuide.Shipping.ship_signal!(%{order_id: order_id, modes: modes})
  Jido.AgentServer.call(server, signal, context: %{observer: self()})
end

{:ok, %{state: %{shipped: ["o-1"]}}, [_pause, _deliver]} = ship.("o-1", [:pause, :deliver])

effect =
  receive do
    {:notifying, pid} -> pid
  after
    1_000 -> raise "the effect did not start"
  end
```

The call has returned and the first effect is still paused. The commit is already visible, the batch is in progress, and cancelling is too late:

```elixir
%{
  phase: :running,
  state_version: 1,
  active: %{stage: :effects, committed_version: 1},
  effects: %{total: 2, completed: 0},
  last_outcome: %{status: :succeeded, committed?: true}
} = Jido.AgentServer.status(server)

{:error, :not_running} = Jido.AgentServer.cancel(server)
```

The server still answers reads, but the next Turn waits in the queue until the batch ends. Effects therefore run in order, with no overlap, across Turns as well as within one.

```elixir
queued = Jido.AgentServer.submit(server, TurnEffectsGuide.Shipping.count_signal!(%{}))

Enum.find(1..200, fn _attempt ->
  Process.sleep(5)
  Jido.AgentServer.status(server).admission.postponed == 1
end)

send(effect, :release)

receive do
  :delivered -> :ok
after
  1_000 -> raise "the second effect did not run"
end

{:ok, %{state: %{shipped: ["o-1"]}}, []} = Jido.AgentServer.await(queued)
%{state_version: 2} = Jido.AgentServer.snapshot(server)
```

## When an effect fails

A failed effect stops the rest of its batch and leaves the commit in place. The caller has already received `{:ok, agent, directives}`, so that return value does not tell you the effects worked. Read `last_effect_outcome` from `Jido.AgentServer.status/2`.

```elixir
wait_for_idle = fn ->
  Enum.find(1..200, fn _attempt ->
    Process.sleep(5)
    Jido.AgentServer.status(server).phase == :idle
  end)
end

{:ok, %{state: %{shipped: ["o-2", "o-1"]}}, [_, _, _]} = ship.("o-2", [:deliver, :fail, :deliver])

wait_for_idle.()

%{
  state_version: 3,
  error_count: 0,
  last_outcome: %{status: :succeeded},
  last_effect_outcome: %{status: :failed, stage: :directive, completed: 1, total: 3, committed_version: 3}
} = Jido.AgentServer.status(server)
```

The first Directive ran, the second failed, and the third never ran. `error_count` stayed at 0 because the Turn succeeded, so `:error_policy` did not run. Jido does not retry an effect or run the rest of the batch later.

| Event after commit | Result | Rest of the batch | Server |
| --- | --- | --- | --- |
| A Directive returns an error or raises | `last_effect_outcome.status` is `:failed` | Skipped | Keeps running |
| A Plugin `after_commit/3` fails | `:failed`, with `stage: :after_commit` | Skipped, with later hooks | Keeps running |
| The time limit passes | `:timed_out` | Skipped | Keeps running |
| A `Jido.AgentServer.Directive.error_report/2` Directive runs | `:failed`, and `:error_policy` runs | Skipped | Follows the policy |
| A `Jido.Agent.Directive.server_stop/1` Directive runs | `:succeeded` | It must be last | Stops with the given reason |
| The task running the effect dies | `:indeterminate` | Skipped | Stops with `{:shutdown, :effect_lifecycle_failed}` |
| A composition change is not ready in time | `:indeterminate` | Not started | Stops with `{:shutdown, :effect_lifecycle_failed}` |
| The server crashes | No record, because the status starts empty after a restart | Lost | Restarts from the last commit |

`:directive_timeout` bounds the whole batch, and `:commit_timeout` bounds all of the `after_commit/3` hooks together. Each defaults to 5,000 ms. [Runtime Effects](../agent-servers/runtime-directives-and-effects.md) covers each built-in Directive.

## Effects are not durable

A commit does not save its Directives. If the node dies between the commit and the last effect, the state is saved and the remaining effects are gone. Each commit runs its Directives at most once, and a restarted server keeps no record of how far they got. A caller that sends the Signal again starts a new Turn, with a new commit and new effects.

When an effect must happen, make the state say so. Commit a field such as `invoice_status: "pending_send"`, and have a separate step that sends and then records the result through a new Signal. [Recovery Limits](../durability/recovery-and-effect-limits.md) has the patterns.

## Choose a side

An Action runs before commit. A Directive runs after it. The question is whether the next state depends on the result of the work.

| The work | Do it in | Why |
| --- | --- | --- |
| The next state needs its result, such as a price from an API | An Action | The result must exist before commit. |
| It must not happen unless the state commits, such as a "paid" notification | A Directive | A failed Turn produces no effects. |
| It announces a change to other Agents | An `Emit` Directive | Receivers see a Signal only for committed state. |
| It answers the request | A `reply` declaration | Jido correlates it with the request. |
| It runs after every commit, whichever route ran | A Plugin `after_commit/3` | See [Post-Commit Work](../plugins/plugin-post-commit-work.md). |
| Its result should change the state later | A Directive, then a new Signal | State only changes in a Turn. |

Work in an Action stays done if the Turn later fails. An Action that charges a card and returns an invalid state leaves the card charged and the Agent unchanged. Keep that kind of Action small, and validate early.

No code can change committed state from an effect. A Directive that learns something new must send a Signal, which starts a later Turn with its own commit.

## Related

- [Life of a Signal](signal-to-effects.md) places the commit in the full sequence.
- [State and Directives](../agents/agent-results-and-directives.md) shows each return shape and Directive.
- [Durability Model](../durability/durability-model.md) explains what a commit writes.
