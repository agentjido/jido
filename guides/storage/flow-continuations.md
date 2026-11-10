# Continuation Storage

This guide shows what a durable Flow Turn writes to storage, in what order, and when those records go away. Read it to size a store for durable Flows, or to write an adapter that can back them.

For how to write and resume a waiting Flow, see [Flow Waits](../flow-runtime/flow-waits.md) and [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd). This guide covers the storage underneath.

## Two kinds of record

A persistent Agent's Flow Turn uses the same adapter for two kinds of record:

| Record | Holds | Lifetime |
| --- | --- | --- |
| The Agent record | The Agent, plus a Turn receipt: the stable Turn ID, accepted Signals, safe context, Flow fingerprint, absolute expiry, and status | Replaced on each revision |
| Execution records | Flow progress: ordered event batches, produced values, and bookkeeping | Deleted after the Turn ends |

An ordinary Action Turn writes only the Agent record. No persistence means no durable Flow: a Flow with a [wait](../flow-runtime/flow-waits.md) fails with `:unsupported_host`, and a plain Flow is not restored after an interruption.

The Turn receipt has the portable shape of `Jido.Exec.Continuation`. Execution records have no public API. Jido reads and writes them through the Store contract, and you interact with them through `Jido.AgentServer`.

## See the records

This adapter wraps ETS and remembers which keys exist, so the example can show each record family at each stage. The key prefixes appear here only to make that visible. Treat keys as private.

```elixir
defmodule ContinuationGuide.ObservedStore do
  @behaviour Jido.Persistence.Store

  alias Jido.Persistence.ETS

  def start_link, do: Agent.start_link(fn -> MapSet.new() end, name: __MODULE__)

  @impl true
  def get(key, opts), do: ETS.get(key, opts)

  @impl true
  def compare_and_swap(key, expected, value, opts) do
    with :ok <- ETS.compare_and_swap(key, expected, value, opts) do
      Agent.update(__MODULE__, &MapSet.put(&1, key))
    end
  end

  @impl true
  def delete(key, opts) do
    Agent.update(__MODULE__, &MapSet.delete(&1, key))
    ETS.delete(key, opts)
  end

  def families do
    Agent.get(__MODULE__, &MapSet.to_list/1)
    |> Enum.frequencies_by(fn
      "jido:agent:" <> _rest -> :agent
      "jido:execution:" <> _rest -> :execution
    end)
  end
end

defmodule ContinuationGuide.ApprovalFlow do
  use Jido.Flow,
    name: "continuation_guide_approval",
    schema: Jido.Joi.object(%{refund_id: Jido.Joi.string()})

  flow do
    step "prepare", refund_id <- input(:refund_id) do
      {:ok, %{refund_id: refund_id}}
    end

    await "approval", event: "refund.approved", match: %{refund_id: result("prepare", :refund_id)}

    step "finish", approval <- result("approval") do
      {:ok, %{approved_by: approval.reviewer}}
    end

    output result("finish")
  end
end

defmodule ContinuationGuide.Refund do
  use Jido.Agent, name: "continuation_guide_refund"

  state do
    schema Jido.Joi.object(%{approved_by: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    route "refund.requested", ContinuationGuide.ApprovalFlow
  end
end

defmodule ContinuationGuide.Poll do
  def until(fun, attempts \\ 200) do
    case fun.() do
      falsy when falsy in [nil, false] and attempts > 0 ->
        Process.sleep(10)
        until(fun, attempts - 1)

      value ->
        value
    end
  end

  def wait_for_open_wait(server) do
    until(fn ->
      case Jido.AgentServer.status(server) do
        %{active: %{stage: :waiting}, waits: [wait]} -> wait
        _other -> nil
      end
    end)
  end
end

{:ok, _pid} = ContinuationGuide.ObservedStore.start_link()

store = {ContinuationGuide.ObservedStore, table: :continuation_guide}

{:ok, _instance} =
  Jido.start_link(name: ContinuationGuide.Jido, namespace: "refunds", persistence: store)

{:ok, refund} =
  Jido.start_agent(ContinuationGuide.Jido, ContinuationGuide.Refund,
    id: "refund-1001",
    persistence: :inherit,
    turn_timeout: :infinity
  )

:ok = Jido.AgentServer.await_ready(refund)

%{agent: 1} = ContinuationGuide.ObservedStore.families()
```

Revision zero is the only record so far. Now start the Flow and let it reach its wait:

```elixir
request = Jido.Signal.new!("refund.requested", %{refund_id: "rf-1"}, source: "/refunds")
_pending = Jido.AgentServer.submit(refund, request)

wait = ContinuationGuide.Poll.wait_for_open_wait(refund)

%{agent: 1, execution: execution_keys} = ContinuationGuide.ObservedStore.families()
true = execution_keys > 0

{:ok, %{state: %{approved_by: ""}}, 1} =
  Jido.Persistence.load_agent_with_revision(
    ContinuationGuide.Jido,
    ContinuationGuide.Refund,
    "refund-1001"
  )
```

Acceptance wrote revision one, with unchanged Agent state and a running receipt. The first step's progress is in execution records. No process holds the Flow now. The Agent can hibernate, and a new activation finds the same wait in storage:

```elixir
:ok = Jido.hibernate(ContinuationGuide.Jido, refund)

{:ok, thawed} =
  Jido.thaw(ContinuationGuide.Jido, ContinuationGuide.Refund, "refund-1001",
    turn_timeout: :infinity
  )

:ok = Jido.AgentServer.await_ready(thawed)

^wait = ContinuationGuide.Poll.wait_for_open_wait(thawed)
```

Deliver the input. `:ok` from `Jido.AgentServer.deliver_wait/4` confirms that the input was saved, not that the Flow finished. Completion commits the state with a terminal receipt in one write, and then the execution records are collected:

```elixir
approval =
  Jido.Signal.new!("refund.approved", %{refund_id: "rf-1", reviewer: "ana"}, source: "/refunds")

:ok = Jido.AgentServer.deliver_wait(thawed, wait.id, approval)
:ok = Jido.AgentServer.quiesce(thawed)

%{approved_by: "ana"} = Jido.AgentServer.agent(thawed).state
%{status: :completed} = Jido.AgentServer.status(thawed).durable_turn

ContinuationGuide.Poll.until(fn -> ContinuationGuide.ObservedStore.families() == %{agent: 1} end)

%{agent: 1} = ContinuationGuide.ObservedStore.families()
```

## Write order

Each write is confirmed before the next action depends on it:

1. **Acceptance.** Jido validates Flow input and saves the running receipt in a new Agent revision. No Action starts before this save.
2. **Progress.** Jido confirms the current execution records before it starts the next node.
3. **Wait input.** Jido saves accepted input before it acknowledges delivery, and saves the wait's resolution before downstream work starts.
4. **Completion.** A successful Flow saves the candidate Agent and terminal receipt in one Agent revision. A failed or cancelled Flow saves its terminal receipt with unchanged state.
5. **Collection.** After the terminal revision is durable, a background task deletes the execution records.

Collection is best effort. A failed delete does not change the Turn result, but it leaves those records behind.

## What execution records contain

Each record belongs to one execution, identified by namespace, partition, Agent ID, and Turn ID.

| Record | Purpose |
| --- | --- |
| A batch count | How many event batches are confirmed |
| Event batches | One key per ordered batch of workflow events |
| Facts | One key per produced value, stored in full or as a delta against an earlier value, when that is smaller |
| A fact head and index | The latest value for delta encoding, and the list used for collection |

The batch write is the commit point. If a writer stops between writing a batch and updating its count, the next read finds the batch and repairs the count. Deltas form chains of at most 32 steps, and each value carries a SHA-256 digest that recovery verifies.

## What recovery checks

A new activation rebuilds from the stored Turn receipt and execution records:

- The saved Flow fingerprint must match the loaded definition.
- Missing or corrupt required records fail recovery. Jido does not start a new Flow as a fallback.
- The saved absolute expiry stays in force. Restore grants no new timeout.
- A lost caller reply is not rebuilt. Read status and Agent state after a restore.

Recovery can repeat work that was running but not yet confirmed. It does not repeat work before the last confirmed checkpoint. An Action with external effects needs its own idempotency. See [Recovery Limits](../durability/recovery-and-effect-limits.md).

A rejected, conflicting, or uncertain save stops durable execution of the Turn, so no later step runs on progress that storage did not confirm.

## What this asks of your adapter

Execution records use the ordinary Store contract, so an adapter needs nothing extra. These points affect your choice of adapter:

- **Write rate.** Each step writes several keys, and each write is a conditional write with its own read. `Jido.Persistence.S3` is meant for low-frequency records, so measure before you use it for frequent Flow Turns.
- **Value size.** One batch or fact is one value, so adapter limits apply per step. `Jido.Persistence.Bedrock` allows 128 KiB and `Jido.Persistence.S3` allows 5,000,000 bytes. Pass references to large payloads through a Flow, not the payloads.
- **`delete/2`.** `delete/2` is optional for an adapter, but without it execution records stay after every Flow Turn.
- **Expiry.** A store that expires keys, such as [Redis with `:ttl`](redis-and-s3-persistence.md), can remove a record that a waiting Flow still needs.
- **Trust.** Execution records hold workflow events with atoms and code references, so Jido decodes them without the `:safe` option of `:erlang.binary_to_term/2`. The digests detect corruption and do not authenticate a writer. Allow only your application to write to this storage.
- **Wait inputs.** One execution keeps at most 1,024 accepted wait inputs.

## Related

- [Flow Waits](../flow-runtime/flow-waits.md): declare and deliver waits.
- [Durable Turns and Flows](../durability/durable-turns-and-flows.livemd): runtime behavior of these Turns.
- [Storage Model](persistence-storage-model.md): the Agent record and write results.
