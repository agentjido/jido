# Node.js and the BEAM

This guide explains how the BEAM, the virtual machine that runs Elixir, differs from Node.js. It starts from the event loop you know and ends with where each Jido piece runs.

## The two models

Both platforms keep many tasks in progress at once. They divide the work differently.

| Topic | Node.js | BEAM |
| --- | --- | --- |
| Unit of concurrency | An async function or callback on the event loop | A process, which the VM schedules itself |
| Parallel JavaScript or Elixir code | `worker_threads` or `cluster`, each with its own heap | Schedulers, by default one per online core, run processes in parallel |
| Switching | Cooperative. A callback runs until it returns or reaches `await` | Preemptive. The scheduler switches after a process uses a budget of work |
| Waiting | `await` returns control to the event loop | A blocking call suspends that one process |
| Memory | Objects are shared by reference inside one thread | Each process has its own heap. Messages are copied, apart from large binaries |
| Garbage collection | Per V8 heap | Per process |
| Uncaught failure | Ends the Node.js process by default | Ends one BEAM process and notifies the processes linked to it or monitoring it |

A BEAM process is not an operating system process. One operating system process runs the whole VM, and the VM runs your BEAM processes inside it. Starting one is an ordinary operation, so Elixir programs start them per request, per task, or per stateful thing.

## Waiting needs no `await`

In TypeScript, a function that waits on I/O returns a `Promise`, and its callers usually become async too.

```typescript
async function loadInvoice(id: string): Promise<Invoice> {
  const response = await fetch(`https://billing.example.com/invoices/${id}`);
  return response.json();
}

const invoice = await loadInvoice("inv-1001");
```

Elixir has no `async` keyword. A function that waits looks like any other function. The calling process is suspended until the result arrives, and every other process keeps running. `Process.sleep/1` stands in for a network call here.

```elixir
defmodule BeamGuide.Invoices do
  def load(id) do
    Process.sleep(100)
    %{id: id, total_cents: 5_000}
  end
end

%{id: "inv-1001", total_cents: 5_000} = BeamGuide.Invoices.load("inv-1001")
```

Concurrency is therefore explicit. A sequence of calls runs in sequence. To run work at the same time, start processes. `Task` is the standard module for that.

```typescript
const invoices = await Promise.all(
  ["inv-1", "inv-2", "inv-3"].map((id) => loadInvoice(id)),
);
```

```elixir
{elapsed_microseconds, invoices} =
  :timer.tc(fn ->
    ["inv-1", "inv-2", "inv-3"]
    |> Enum.map(fn id -> Task.async(fn -> BeamGuide.Invoices.load(id) end) end)
    |> Task.await_many()
  end)

["inv-1", "inv-2", "inv-3"] = Enum.map(invoices, & &1.id)
true = elapsed_microseconds < 300_000
```

The three calls overlap, so the total is less than three times 100 ms. Results keep input order, as they do with `Promise.all`. Errors and Async covers failure and timeouts.

## Busy work does not hold the others back

A long synchronous loop holds the Node.js event loop. Timers and other requests wait until it returns, so CPU-heavy JavaScript usually moves to a worker thread.

```typescript
const end = Date.now() + 200;
while (Date.now() < end) {
  // Nothing else on this event loop runs during this loop.
}
```

The BEAM preempts a busy process. This example gives every scheduler a process that never finishes, then starts one more. The new process still gets a turn.

```elixir
busy =
  for _scheduler <- 1..System.schedulers_online() do
    spawn(fn -> Stream.repeatedly(fn -> :erlang.phash2(:rand.uniform()) end) |> Stream.run() end)
  end

:answered = Task.await(Task.async(fn -> :answered end), 1_000)

Enum.each(busy, &Process.exit(&1, :kill))
```

Native code is the exception. A native function (a NIF) is not preempted the same way, so long-running native work has to be written with that in mind.

## Processes share no memory

Worker threads talk with `postMessage`. BEAM processes talk with `send/2` and read their mailbox with `receive`. Each process handles one message at a time.

```typescript
// worker.ts
parentPort!.on("message", (order) => {
  parentPort!.postMessage({ orderId: order.id, status: "packed" });
});
```

```elixir
packer =
  spawn(fn ->
    receive do
      {:pack, order_id, reply_to} -> send(reply_to, {:packed, order_id})
    end
  end)

send(packer, {:pack, "o-1", self()})

:got_it =
  receive do
    {:packed, "o-1"} -> :got_it
  after
    1_000 -> :no_reply
  end
```

All Elixir data is immutable, and a receiver gets its own copy of a message. No other process can change a value you hold.

## A process owns state

In Node.js, a class instance can hold state, and a synchronous method is safe because nothing else runs during it. A method with an `await` can interleave with another call at that point.

```typescript
class Ledger {
  private balanceCents = 100;

  async withdraw(cents: number): Promise<void> {
    const current = this.balanceCents;
    await audit.record("withdraw", cents); // Another withdraw can run here.
    if (current < cents) throw new Error("insufficient funds");
    this.balanceCents = current - cents;
  }
}
```

On the BEAM, state lives in a process that handles one message at a time. `GenServer` is the standard form. A blocking call inside `handle_call/3` holds up that server's next message, and no other process can read or write its state.

```elixir
defmodule BeamGuide.Ledger do
  use GenServer

  def start_link(balance_cents), do: GenServer.start_link(__MODULE__, balance_cents, name: __MODULE__)
  def withdraw(cents), do: GenServer.call(__MODULE__, {:withdraw, cents})

  @impl true
  def init(balance_cents), do: {:ok, balance_cents}

  @impl true
  def handle_call({:withdraw, cents}, _from, balance) when cents <= balance do
    {:reply, {:ok, balance - cents}, balance - cents}
  end

  def handle_call({:withdraw, _cents}, _from, balance) do
    {:reply, {:error, :insufficient_funds}, balance}
  end
end

{:ok, _pid} = BeamGuide.Ledger.start_link(100)
{:ok, 40} = BeamGuide.Ledger.withdraw(60)
{:error, :insufficient_funds} = BeamGuide.Ledger.withdraw(60)
```

The price of this model is that one process is one queue. A server that spends a long time on each message makes its callers wait, so Elixir programs split independent state into independent processes.

## Crashes stay local

In Node.js, an uncaught exception ends the process by default, and everything in it stops. A tool outside the program, such as systemd or Kubernetes, starts a new one. Code guards against this with `try`/`catch` and rejection handlers.

A failed BEAM process ends alone. Another process can monitor it and receive a message saying why it ended.

```elixir
{worker, monitor} = spawn_monitor(fn -> exit(:gateway_unavailable) end)

:gateway_unavailable =
  receive do
    {:DOWN, ^monitor, :process, ^worker, reason} -> reason
  after
    1_000 -> :no_message
  end
```

A supervisor is a process that starts other processes and restarts them under a policy you choose. It does for one BEAM process what systemd does for a whole Node.js program, and supervisors nest into a tree.

```elixir
defmodule BeamGuide.ShiftClock do
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: {:ok, :started}
end

{:ok, _supervisor} = Supervisor.start_link([BeamGuide.ShiftClock], strategy: :one_for_one)

first = Process.whereis(BeamGuide.ShiftClock)
monitor = Process.monitor(first)
Process.exit(first, :kill)

receive do
  {:DOWN, ^monitor, :process, ^first, :killed} -> :ok
after
  1_000 -> raise "the server did not exit"
end

replacement =
  Enum.find_value(1..100, fn _attempt ->
    Process.sleep(10)

    case Process.whereis(BeamGuide.ShiftClock) do
      pid when is_pid(pid) and pid != first -> pid
      _not_restarted -> nil
    end
  end)

true = is_pid(replacement)
```

A restarted `GenServer` runs `init/1` again, so its in-memory state starts over unless you store it elsewhere.

## Where Jido runs on this model

Most Jido values are plain data. Processes appear at these points:

| Jido piece | BEAM form | Node.js shape it resembles |
| --- | --- | --- |
| `Jido.Action` run with `Jido.Exec.run/4` | A supervised task for the length of the run | A function run on a worker that the caller awaits |
| `Jido.Agent` definition or instance | No process. An immutable value | A plain object |
| `Jido.Agent.cmd/3` | No process of its own. Runs from the caller | A reducer call |
| `Jido.AgentServer` | One long-lived process for one Agent | A class instance with its own request queue |
| Jido instance, started with `Jido.start/1` | A supervisor with its registry and child processes | A service container, with restart built in |

This example runs one Agent per ticket queue, each in its own process, and crashes one of them. The new worker loads the last committed state.

```elixir
defmodule BeamGuide.CountTicket do
  use Jido.Action,
    name: "beam_guide_count_ticket",
    schema: Jido.Joi.object(%{})

  @impl true
  def run(_input, %{agent_state: state}), do: {:ok, %{state | handled: state.handled + 1}}
end

defmodule BeamGuide.TicketQueue do
  use Jido.Agent, name: "beam_guide_ticket_queue"

  state do
    schema Jido.Joi.object(%{handled: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/support/queue"
    route "ticket.handle", BeamGuide.CountTicket, as: :handle
  end
end

{:ok, _instance} = Jido.start(name: BeamGuide.Jido)
{:ok, billing} = Jido.start_agent(BeamGuide.Jido, BeamGuide.TicketQueue, id: "billing")
{:ok, returns} = Jido.start_agent(BeamGuide.Jido, BeamGuide.TicketQueue, id: "returns")
:ok = Jido.AgentServer.await_ready(billing)
:ok = Jido.AgentServer.await_ready(returns)

ticket = BeamGuide.TicketQueue.handle_signal!(%{})
{:ok, %{state: %{handled: 1}}, []} = Jido.AgentServer.call(billing, ticket)

monitor = Process.monitor(billing)
Process.exit(billing, :kill)

receive do
  {:DOWN, ^monitor, :process, ^billing, :killed} -> :ok
after
  1_000 -> raise "the worker did not exit"
end

restarted =
  Enum.find_value(1..100, fn _attempt ->
    Process.sleep(10)

    case Jido.whereis_agent(BeamGuide.Jido, "billing") do
      pid when is_pid(pid) and pid != billing -> pid
      _not_ready -> nil
    end
  end)

%{handled: 1} = Jido.AgentServer.snapshot(restarted).agent.state
%{handled: 0} = Jido.AgentServer.snapshot(returns).agent.state

:ok = Jido.stop(BeamGuide.Jido)
```

The `billing` worker crashed. The `returns` worker never noticed. The Turn in progress and any queued casts are lost in a crash, and an activation allows three restarts in five seconds. Agent Lifecycle lists every effect of a restart.

## Next steps

- [TypeScript Concept Map](typescript-concept-map.md) translates tools, syntax, and Jido terms.
- Errors and Async moves `try`, `catch`, and `Promise` code to Elixir.
- [Start and Address Agents](../agent-servers/start-and-address-live-agents.livemd) runs Agents in a Jido instance.
