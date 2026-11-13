# Deployment and Sizing

This guide explains how Jido uses a node's resources and which settings limit it, so you can plan a deployment and size it from your own measurements. Jido publishes no capacity figures, because results depend on your Actions, state size, and store. Load Testing shows how to measure them.

## How work uses processes

Each started Agent has its own processes:

- One activation supervisor.
- One AgentServer, which holds the committed Agent in its heap and a checkpoint copy in a local ETS table.
- A Flow worker and task processes during a Turn. They end with the Turn.
- Any Plugin runtimes and owned child Agents that you add.

Each instance adds a fixed set of processes that all of its Agents share. An idle Agent runs nothing, but it still holds its memory.

This example measures the cost of idle Agents on this node. Run it with your own Agent and realistic state.

```elixir
defmodule SizingGuide.Account do
  use Jido.Agent, name: "sizing_guide_account"

  state do
    schema Jido.Joi.object(%{ledger: Jido.Joi.list(Jido.Joi.integer()) |> Jido.Joi.default([])})
  end
end

{:ok, _pid} = Jido.start_link(name: SizingGuide.Jido)

measure = fn -> {:erlang.system_info(:process_count), :erlang.memory(:total)} end

:erlang.garbage_collect()
{processes_before, memory_before} = measure.()

count = 100
ledger = Enum.to_list(1..50)

for index <- 1..count do
  {:ok, _server} =
    Jido.start_agent(SizingGuide.Jido, SizingGuide.Account,
      id: "account-#{index}",
      state: %{ledger: ledger}
    )
end

{processes_after, memory_after} = measure.()

per_agent = %{
  processes: (processes_after - processes_before) / count,
  bytes: (memory_after - memory_before) / count
}

^count = Jido.agent_count(SizingGuide.Jido)
true = per_agent.processes >= 2
```

Treat `per_agent` as an estimate for one Agent shape on one runtime version. Multiply it by your expected live Agent count and compare the result with your node's memory and `:erlang.system_info(:process_limit)`.

To hold fewer Agents in memory, use `:idle_timeout` with `idle_policy: :hibernate`, which saves a durable Agent and stops it when unused. See Hibernate and Thaw.

## What limits throughput

An Agent runs one Turn at a time. Adding load to one Agent lengthens its queue. It does not use more cores. Throughput therefore comes from two levels:

- **Across Agents:** Turns in different Agents run at the same time, up to what your schedulers and dependencies allow. Split work across more Agents when one Agent becomes a bottleneck.
- **Inside a Turn:** a Flow's steps run one at a time by default. Raise `:max_concurrency` in `:exec_opts` to run ready steps in parallel. See [Execution Policy](../actions/action-execution-policy.md).

The time of one Turn usually comes from your code and your store:

| Stage | Cost comes from |
| --- | --- |
| Admission | The queue ahead of this request. |
| Evaluation | Your Actions, including external calls and retries. |
| Commit | Schema validation, and one store write for a durable Turn. A durable Flow Turn also writes at acceptance and between steps. See Durability Model. |
| Effects | Directive delivery and Plugin hooks, after the caller has its result. |

Large Agent state costs more at each commit, because the commit copies the entire state to its checkpoint and a durable commit writes it to your store. Keep large data in your own store and hold references in the Agent.

## Limits you control

These settings bound resource use. Each one fails in a visible way, so choose values you can handle.

| Limit | Scope | Default | Bounds |
| --- | --- | --- | --- |
| `:max_postponed_signals` | Agent | 1,000 | Requests waiting for a Turn. It does not bound the process mailbox. |
| `:admission_timeout` | Request | 5,000 ms | The time a request waits before it starts. |
| `:turn_timeout` | Agent | 60,000 ms | The time from a Turn's start to its commit. |
| `:max_directives_per_turn` | Agent | 1,000 | The Directives one Turn may return. |
| `:debug_max_events` | Agent | 100 | Retained history, only with `debug: true`. |
| `:max_concurrency` in `:exec_opts` | Agent | 1 | Parallel steps inside one Turn. |
| `:max_tasks` | Instance | 1,000 | The instance Task supervisor. Jido uses it for cleaning up finished Flow data. That cleanup is best effort, so it does not limit Turn throughput. |

Jido has no limit on the number of Agents and no backpressure across Agents. Add your own admission control at your system's edge, and treat `{:error, {:overloaded, details}}` as a signal to slow down.

## Choose your BEAM settings

Jido needs no special VM flags. Check these against your measurements:

- The process limit, if your Agent count multiplied by the processes per Agent comes near it. Raise it with the `+P` VM flag.
- The atom table. Do not build Jido instance names or action names from runtime data. See [Instances and Tenants](configuration-and-tenant-isolation.md#choose-a-tenant-model).
- Container memory limits. The BEAM stops when the host refuses memory, and every live Agent stops with it. Leave headroom for traffic peaks.

## Run more than one node

Each node runs its own instance, Registry, and Agent processes. Jido has no cluster registry, placement layer, or writer lease. Lookups such as `Jido.whereis_agent/3` and `Jido.resolve_agent/2` see only the local node.

To run several nodes:

1. Give each Agent one active node. Route by a stable hash of its Ref, or use a placement layer that you choose.
2. Share a store that supports your node count. See the [Persistence Matrix](../reference/persistence-adapter-matrix.md). `Jido.Persistence.File` and `Jido.Persistence.ETS` belong to one BEAM.
3. Use the same namespace for the same logical Agents on each node.
4. Move an Agent by hibernating it on its old node and activating it on its new one.

If two nodes activate one Ref, compare-and-swap rejects the stale write, and the losing activation stops at that point. It can run Actions before then. See Revisions and Conflicts.

## Roll out new code

A rolling deploy stops old nodes and starts new ones. Plan for these points:

- **Drain the old node.** Follow Shutdown and Recovery. Allow enough time in your platform's stop setting.
- **Activate on the new node.** Jido does not do this for you. See [Production Setup](production-configuration.md#activate-durable-agents-after-boot).
- **Keep saved records readable.** Restore checks the code that a record references, and a Flow in progress needs a compatible definition. See Checkpoints and Upgrades.
- **Change running Agents in place** only through a planned upgrade. See Upgrade Live Agents.

## Next steps

- Load Testing
- [Production Setup](production-configuration.md)
- Metrics and OTel
