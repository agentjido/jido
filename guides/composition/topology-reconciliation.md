# Topology Reconciliation

This guide explains how AgentServer turns topology data into running processes, which changes restart a member, and what happens when reconciliation fails. Read it when you need to predict the process effects of a change or a crash.

`Jido.Agent.Topology` holds only data and never starts a process. AgentServer reads that data and applies it under OTP supervisors.

## How it works

Reconciliation runs in three steps.

1. **Bind.** Jido resolves every member's definition, count, and initial state from the current Agent state. Each slot becomes a plan entry.
2. **Compare.** Jido compares the new plan with the previous plan and with the live processes.
3. **Apply.** Jido stops each live slot whose plan entry changed or disappeared. It then starts each slot that has no live match and waits for it to be ready. Last, it starts and stops local Buses to match the declared Bus Plugin.

A slot's plan entry holds its member name, slot number, resolved definition, bound initial state, and saved identity. A slot keeps its process only when that whole entry is unchanged. Its current state is not part of the comparison.

## When it runs

| Moment | Trigger |
| --- | --- |
| Startup | An Agent with members or a Bus reconciles before it reports ready. |
| After commit | A Turn changed members or connections, a Bus declaration, or a state field that alters the bound members. |
| Plugin change | A Turn changed Plugin declarations. |

A state change that does not alter any bound value does not trigger it. A change to connections alone runs reconciliation without touching a process.

## Order inside a Turn

For a Turn that needs reconciliation, AgentServer works in this order:

1. Validate the candidate, including binding. A failure here rejects the Turn with no commit.
2. Commit the state and definition.
3. Reply to the caller.
4. Reconcile.
5. Release waiting callers of `Jido.AgentServer.await_ready/2`.
6. Run the Turn's remaining Directives, such as `emit`.

The reply comes before reconciliation, so `Jido.AgentServer.status/1` can report `ready?: false` right after a successful call. Output from a member that reaches the owner during this time waits until reconciliation ends. Because Directives run after reconciliation, an `emit` in the same Turn reaches new members over new connections.

The next example shows which processes survive each kind of change. Changing a bound count keeps the existing slots. Changing bound initial state replaces every slot of that member, and the committed work in those slots is gone.

```elixir
defmodule ReconcileGuide.Lane do
  use Jido.Agent, name: "reconcile_lane"

  state do
    schema Jido.Joi.object(%{
             site: Jido.Joi.string() |> Jido.Joi.default("none"),
             packed: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/reconcile/lane"

    route "lane.pack", as: :pack do
      action %{items: items},
        schema: Jido.Joi.object(%{items: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | packed: context.agent_state.packed + items}}
      end
    end
  end

  def initialize(%{site: "closed"}, _context),
    do: {:error, Jido.Error.validation_error("site is closed")}

  def initialize(state, _context), do: {:ok, state}
end

defmodule ReconcileGuide.Floor do
  use Jido.Agent, name: "reconcile_floor"

  state do
    schema Jido.Joi.object(%{
             lanes: Jido.Joi.integer() |> Jido.Joi.default(2),
             site: Jido.Joi.string() |> Jido.Joi.default("north"),
             note: Jido.Joi.string() |> Jido.Joi.default("")
           })
  end

  routes do
    signal_source "/reconcile/floor"

    route "floor.set", as: :set do
      action input,
        schema:
          Jido.Joi.object(%{
            lanes: Jido.Joi.integer() |> Jido.Joi.optional(),
            site: Jido.Joi.string() |> Jido.Joi.optional(),
            note: Jido.Joi.string() |> Jido.Joi.optional()
          }),
        context: context do
        {:ok, Map.merge(context.agent_state, input)}
      end
    end
  end

  topology do
    agent :lanes, ReconcileGuide.Lane do
      count state(:lanes)
      initial_state %{site: state(:site)}
    end
  end
end

{:ok, _instance} = Jido.start(name: ReconcileGuide.Jido)
{:ok, floor} = Jido.start_agent(ReconcileGuide.Jido, ReconcileGuide.Floor, id: "floor-1")
:ok = Jido.AgentServer.await_ready(floor)

set = fn server, changes ->
  {:ok, signal} = ReconcileGuide.Floor.set_signal(changes)
  {:ok, _committed, []} = Jido.AgentServer.call(server, signal)
  :ok = Jido.AgentServer.await_ready(server)
  Jido.AgentServer.members(server, :lanes)
end

[lane_one, lane_two] = Jido.AgentServer.members(floor, :lanes)
{:ok, pack} = ReconcileGuide.Lane.pack_signal(%{items: 4})
{:ok, _committed, []} = Jido.AgentServer.call(lane_one, pack)

# An unrelated state field leaves every slot alone.
[^lane_one, ^lane_two] = set.(floor, %{note: "busy"})

# A bound count adds a slot and keeps the others.
[^lane_one, ^lane_two, lane_three] = set.(floor, %{lanes: 3})
4 = Jido.AgentServer.agent(lane_one).state.packed

# Bound initial state replaces every slot.
replaced = set.(floor, %{site: "south"})
[] = Enum.filter(replaced, &(&1 in [lane_one, lane_two, lane_three]))
[%{site: "south", packed: 0}, %{site: "south", packed: 0}, %{site: "south", packed: 0}] =
  Enum.map(replaced, &Jido.AgentServer.agent(&1).state)
```

## What a crash does

Each member is a complete activation under the owner's activation. Its restart policy is `:permanent`. Where the crash happens decides what survives.

| What crashed | Member processes | Member state |
| --- | --- | --- |
| A member's worker | That member restarts and the other members keep running. A member output that finds no live destination during the restart is dropped and recorded on the owner. See [Connect Agent Outputs](connect-agent-outputs.livemd). | Kept. The worker restarts from its activation's committed checkpoint. |
| The owner's worker | The owner's activation restarts as a group, and every member stops and starts again through reconciliation. | Reset to `initial_state`, unless the member restores from persistence. The owner keeps its committed state and revision. |

An activation allows 3 worker restarts in 5 seconds. A member's activation restarts from its bound `initial_state` when it passes that limit. If this repeats, the crashes can exceed the limit of the owner's supervisor and stop the owner too.

```elixir
[lane | _others] = Jido.AgentServer.members(floor, :lanes)
{:ok, _committed, []} = Jido.AgentServer.call(lane, pack)

wait_for = fn check ->
  Enum.find_value(1..200, fn _attempt ->
    check.() || (Process.sleep(10) && nil)
  end)
end

# A member's worker crashes and its committed state survives.
Process.exit(lane, :kill)

restarted =
  wait_for.(fn ->
    case Jido.AgentServer.members(floor, :lanes) do
      [pid, _, _] when pid != lane -> pid
      _other -> nil
    end
  end)

4 = Jido.AgentServer.agent(restarted).state.packed

# The owner's worker crashes. The owner keeps its state and members reset.
version = Jido.AgentServer.snapshot(floor).state_version
activation = Jido.AgentServer.activation(floor)
Process.exit(floor, :kill)

new_floor =
  wait_for.(fn ->
    case Jido.AgentServer.worker(activation) do
      pid when is_pid(pid) and pid != floor -> pid
      _other -> nil
    end
  end)

:ok = Jido.AgentServer.await_ready(new_floor)
^version = Jido.AgentServer.snapshot(new_floor).state_version
"south" = Jido.AgentServer.agent(new_floor).state.site

[0, 0, 0] =
  Jido.AgentServer.members(new_floor, :lanes)
  |> Enum.map(&Jido.AgentServer.agent(&1).state.packed)
```

## When reconciliation fails

Binding failures reject the Turn, so they never reach this stage. A member can still fail after commit, for example when its `initialize/2` returns an error or it does not become ready in time. The owner's `:readiness_timeout` option sets that limit and defaults to 5,000 milliseconds.

| Stage | Result |
| --- | --- |
| Startup | `Jido.start_agent/3` already returned `{:ok, pid}`. The server stops with the failure as its reason, and `await_ready/2` returns `{:error, reason}`. |
| After commit | The caller already has `{:ok, ...}`. The owner stops with `{:shutdown, :effect_lifecycle_failed}`, its activation shuts down, and `await_ready/2` returns an error. The change is not rolled back. |

Jido does not retry and does not return to the previous definition. Supervise or restart the owner according to what your application needs. A persistent owner keeps its stored revision, as [Recovery Limits](../durability/recovery-and-effect-limits.md) explains.

This Turn commits a site that makes `initialize/2` fail:

```elixir
monitor = Process.monitor(new_floor)
{:ok, close} = ReconcileGuide.Floor.set_signal(%{site: "closed"})
{:ok, _committed, []} = Jido.AgentServer.call(new_floor, close)

{:shutdown, :effect_lifecycle_failed} =
  receive do
    {:DOWN, ^monitor, :process, _pid, reason} -> reason
  after
    5_000 -> :timeout
  end

nil = Jido.whereis_agent(ReconcileGuide.Jido, "floor-1")
```

## Saved members

When the owner has persistence, each member inherits it. On reconciliation, a member loads its saved record if one exists, and otherwise creates one. The owner saves a slot identity with its topology, and that identity is part of the member's ID. A slot that is removed and later added again gets a new identity, so it starts fresh and does not pick up old state.

An owner's saved record holds its state and topology under one revision. Each member saves its own record separately, so there is no atomic snapshot of an Agent family. See [Durable Topology](../durability/durable-topology.md).

## Limits

- Reconciliation works on one node. There is no placement engine or remote failover.
- It compares declared plans. It does not move state between slots or replay effects.
- Runtime children are outside the plan. See [Parent and Child Agents](parent-and-child-agents.md).
