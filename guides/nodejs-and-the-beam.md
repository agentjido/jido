# Node.js and the BEAM

This guide compares the Node.js runtime with the BEAM, the virtual machine
that runs Elixir and Jido. It covers concurrency, memory, crashes, timers, and
clustering, and shows how each difference changes the code you write for an
Agent.

> #### Learn Elixir first {: .tip}
>
> This guide assumes you can read basic Elixir. The official guides cover it:
> [Introduction](https://hexdocs.pm/elixir/introduction.html),
> [Pattern matching](https://hexdocs.pm/elixir/pattern-matching.html),
> [Processes](https://hexdocs.pm/elixir/processes.html), and
> [Keyword lists and maps](https://hexdocs.pm/elixir/keywords-and-maps.html).

| | Node.js | BEAM |
| --- | --- | --- |
| Unit of concurrency | Callbacks and Promises on one event loop | Processes, each with its own heap and mailbox |
| Scheduling | Cooperative: code runs until it returns or awaits | Preemptive: each process gets a budget of reductions |
| Heap | One per isolate, shared by all requests | One per process |
| Sharing state | Closures and shared objects | Messages (data is copied) |
| Crash scope | The whole process | One process |
| Restart | An external restart manager | Supervisors in the same VM |
| Many machines | `cluster` plus an external broker | Distributed Erlang |

## One Loop vs Many

A Node.js process runs your JavaScript on one thread. Every request shares
one heap, so two concurrent requests for the same user can interleave at any
`await`. You serialize them yourself. This per-user counter keeps a promise
chain per key as a lock and writes through to Redis:

```typescript
interface Store {
  set(key: string, value: string): Promise<void>;
}
declare const redis: Store;

const counts = new Map<string, number>();
const locks = new Map<string, Promise<void>>();

async function withLock<T>(key: string, fn: () => Promise<T>): Promise<T> {
  const previous = locks.get(key) ?? Promise.resolve();
  let release!: () => void;
  const current = new Promise<void>((resolve) => (release = resolve));
  const tail = previous.then(() => current);
  locks.set(key, tail);

  await previous;
  try {
    return await fn();
  } finally {
    release();
    if (locks.get(key) === tail) locks.delete(key);
  }
}

export function increment(userId: string, amount: number): Promise<number> {
  return withLock(userId, async () => {
    const next = (counts.get(userId) ?? 0) + amount;
    await redis.set(`count:${userId}`, String(next));
    counts.set(userId, next);
    return next;
  });
}
```

On the BEAM, each user gets an Agent: one process that owns that user's
state. The Agent Server runs one Turn at a time, so the lock goes away. With
`persistence: :inherit`, it saves each commit before it replies:

```elixir
defmodule MyApp.Increment do
  use Jido.Action,
    name: "increment",
    schema: Zoi.object(%{amount: Zoi.integer()}),
    output_schema: Zoi.map()

  @impl true
  def run(%{amount: amount}, %{agent_state: state}) do
    {:ok, %{state | count: state.count + amount}}
  end
end

defmodule MyApp.Counter do
  use Jido.Agent, name: "counter"

  state do
    schema(Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)}))
  end

  routes do
    signal_source("/my_app/counters")
    route "counter.increment", MyApp.Increment, as: :increment, defaults: %{amount: 1} do
      state from: output()
    end
  end
end

defmodule MyApp.Jido do
  use Jido,
    otp_app: :my_app,
    namespace: "my-app/agents",
    persistence: {Jido.Persistence.ETS, table: :my_app_agents}
end

defmodule MyApp.Counters do
  def increment(user_id, amount) do
    signal = MyApp.Counter.increment_signal!(%{amount: amount})
    {:ok, agent, []} = Jido.AgentServer.call(counter(user_id), signal)
    agent.state.count
  end

  defp counter(user_id), do: MyApp.Jido.whereis_agent(user_id) || start(user_id)

  defp start(user_id) do
    result =
      case Jido.Persistence.load_agent(MyApp.Jido, MyApp.Counter, user_id) do
        {:ok, _record} -> MyApp.Jido.thaw(MyApp.Counter, user_id)
        {:error, :not_found} -> MyApp.Jido.start_agent(MyApp.Counter, id: user_id, persistence: :inherit)
      end

    pid =
      case result do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    :ok = Jido.AgentServer.await_ready(pid)
    pid
  end
end
```

Add `MyApp.Jido` to your supervision tree. With it running, 100 concurrent
`MyApp.Counters.increment("user-42", 1)` calls give exactly 100.

Where the analogy breaks:

- Jido doesn't lock. A process handles one message at a time, and the Agent
  Server runs one Turn at a time. Different Agents run in parallel with no
  ordering between them. A change that spans two users is two Turns, with no
  transaction around them.
- A `Map` entry costs a few bytes. A live Agent is several processes. Stop
  idle ones with `idle_timeout:` (see [Memory and GC](#memory-and-gc)).
- Persistence is off unless you pass `persistence: :inherit`. The ETS adapter
  keeps records only while the BEAM runs. For storage that survives a
  restart, configure a durable adapter. See
  [Durability Model](durability-model.md).
- `start_agent/2` needs an `id:`. It writes revision 0 in the default
  `:create` mode, so an ID that already has a record fails at `await_ready/2`.
  Use `thaw/3` for those, as above.

## Concurrency Units

A Promise is a placeholder for a result. The work behind it still runs on the
event loop thread, or in the C++ thread pool for some I/O. A BEAM process is
a unit of execution with its own stack, heap, and mailbox. The VM runs one
scheduler thread per CPU core and spreads processes across them.

| Node.js | BEAM |
| --- | --- |
| `new Promise(...)` / `await` | `Task.async/1` / `Task.await/2` |
| A `worker_threads` Worker for CPU-bound work | Another process |
| A `while` loop blocks every request | A loop uses up its reductions, then the scheduler runs another process |
| Each Worker is a separate V8 isolate with its own event loop | A process starts at 2,624 bytes; the default limit is 1,048,576 (`+P` raises it) |

The scheduler preempts a process after a budget of reductions (function
calls, roughly). A CPU-bound loop can't stall the rest of the node. A native
function (NIF) that runs too long is the exception.

Jido uses this. The Agent Server runs your Action in a separate worker
process. In a test on a 10-scheduler machine, 20 Agents ran Actions that
each spun the CPU for 2 seconds. During that time, a call to a 21st Agent
returned in 4–8 ms (1.3 ms with no load). Reads of a busy Agent, such as
`Jido.AgentServer.agent/2`, return at once. The busy Agent's next Turn waits
for the current one to finish.

## Memory and GC

V8 gives each isolate one heap. A major collection walks every live object
from every request, and parts of it pause the event loop. Large heaps mean
longer pauses.

Each BEAM process has its own heap and its own generational collector. The
VM collects one process at a time, while other processes keep running. When
a process exits, the VM frees its whole heap without a collection. Binaries
over 64 bytes are the exception: they live in a shared, reference-counted
area.

Measured on OTP 29, 64-bit:

| What | Memory |
| --- | --- |
| An idle `spawn` | 2,624 bytes (233-word initial heap) |
| The idle counter Agent above, with its activation | About 18.7 KB |

The Agent figure covers the Server, its activation supervisor, and registry
entries, with `count: 0`. Your state adds to it. Measure your own Agent as
shown in [Deployment and Sizing](deployment-and-performance.md).

In Jido, "hibernate" doesn't mean `:erlang.hibernate/3`. A Jido hibernate
saves the Agent and stops its activation, so it uses no memory until
`thaw/3` starts it again. It requires persistence:

```elixir
MyApp.Jido.start_agent(MyApp.Counter,
  id: "user-42",
  persistence: :inherit,
  idle_timeout: :timer.minutes(15),
  idle_policy: :hibernate
)
```

Without persistence, use `idle_policy: :stop`, the default. The state is lost
when the Agent stops.

## Messages, Not Closures

In Node.js, any code with a reference to an object can change it. An
EventEmitter listener runs in the same heap as the code that emitted the
event, and can change shared state while it runs.

A BEAM process can't reach into another process's heap. It sends a message,
and the VM copies the data into the receiver's mailbox. The receiver handles
it when it chooses. An Agent's state is in the Server process, so the only
way to change it is to send a Signal that runs a Turn:

```elixir
pid = MyApp.Jido.whereis_agent("user-42")
copy = Jido.AgentServer.agent(pid)
_changed = put_in(copy.state.count, 1_000)

Jido.AgentServer.agent(pid).state.count
# => 100
```

`agent/2` returns a copy. Changing the copy changes nothing in the Server.

Where the analogy breaks: copying has a cost. `call/3` replies with the
complete committed Agent, so a large state is copied to the caller on every
call. Keep Agent state to what the Agent needs to decide its next Turn.

## When Things Crash

In Node.js, an exception that escapes every handler reaches
`process.on('uncaughtException')`. The Node.js docs say the process is not
safe to resume after that, so you exit and an external restart manager
starts a new process. Every user's in-memory state goes with it:

```typescript
import { createServer } from "node:http";

const counts = new Map<string, number>();

createServer((req, res) => {
  counts.set("user-42", (counts.get("user-42") ?? 0) + 1);
  setTimeout(() => {
    throw new Error("card service returned null");
  }, 0);
  res.end("ok");
}).listen(3000);

process.on("uncaughtException", (error) => {
  console.error(error);
  process.exit(1);
});
```

On the BEAM, a crash stops one process. Its supervisor starts a new one.
Jido handles two levels. An exception in an Action fails only that Turn:

```elixir
defmodule MyApp.Fail do
  use Jido.Action, name: "fail", schema: Zoi.object(%{}), output_schema: Zoi.map()

  @impl true
  def run(_params, _context), do: raise("card service returned nil")
end

# In MyApp.Counter's routes:
#   route "counter.fail", MyApp.Fail, as: :fail do
#     state :unchanged
#   end

pid = MyApp.Jido.whereis_agent("user-42")
{:error, error} = Jido.AgentServer.call(pid, MyApp.Counter.fail_signal!())

{error.__struct__, Jido.AgentServer.agent(pid).state.count}
# => {Jido.Action.Error.ExecutionFailureError, 100}
```

The Server stays up and keeps the last committed state.

A crash of the Server process itself restarts it under its activation
supervisor. The new Server starts from the last committed Agent and revision:

```elixir
Process.exit(pid, :kill)
Process.sleep(100)

new_pid = MyApp.Jido.whereis_agent("user-42")
{new_pid != pid, Jido.AgentServer.agent(new_pid).state.count}
# => {true, 100}
```

No other Agent notices. This is "let it crash": you write the normal path,
and supervision returns a failed process to a known state.

Where the analogy breaks:

- The restart doesn't replay the Turn that was running. A caller waiting in
  `call/3` exits with `:killed`. Completed external I/O isn't undone.
- The activation supervisor allows 3 Server restarts in 5 seconds. A fourth
  crash stops the activation for good, and `whereis_agent/1` returns `nil`.
- The activation keeps its checkpoint in memory. If the activation itself
  crashes, an Agent without persistence restarts at its initial state and
  revision 0. With `persistence: :inherit`, it reloads the saved record.
- A restart is local to the VM. Restarting the BEAM loses everything not in
  durable storage, as with `process.exit(1)`.

See [Supervision and Lifecycle](agent-activation-control.md) for the
activation tree.

## Timers and Scheduling

`setTimeout` puts a callback on the event loop. The callback closes over
whatever it needs, and nothing ties it to the state it changes:

```typescript
const sent = new Map<string, string[]>();

function remind(userId: string, text: string, delayMs: number): void {
  setTimeout(() => {
    sent.set(userId, [text, ...(sent.get(userId) ?? [])]);
  }, delayMs);
}
```

A BEAM timer, such as `Process.send_after/3`, delivers a message to a
process. In Jido, an Action returns a Scheduler Directive, and the timer
delivers a Signal that runs a normal Turn:

```elixir
defmodule MyApp.Reminders do
  use Jido.Agent, name: "reminders"

  state do
    schema(Zoi.object(%{sent: Zoi.list(Zoi.string()) |> Zoi.default([])}))
  end

  plugins do
    plugin(Jido.Plugin.Scheduler)
  end

  routes do
    signal_source("/my_app/reminders")

    route "reminder.request", as: :request do
      action %{text: text, delay_ms: delay},
        schema: Zoi.object(%{text: Zoi.string(), delay_ms: Zoi.integer()}),
        output_schema: Zoi.map(), context: context do
        due = Jido.Signal.new!("reminder.due", %{text: text}, source: "/my_app/reminders")
        {:ok, context.agent_state, [Jido.Plugin.Scheduler.schedule(delay, due)]}
      end
      state from: output()
    end

    route "reminder.due" do
      action %{text: text}, schema: Zoi.object(%{text: Zoi.string()}), output_schema: Zoi.map(), context: context do
        {:ok, %{context.agent_state | sent: [text | context.agent_state.sent]}}
      end
      state from: output()
    end
  end
end
```

`MyApp.Reminders.request_signal!(%{text: "Stand up", delay_ms: 200})` sends
`"reminder.due"` to the Agent 200 ms after the commit. That Turn waits behind
any other Turn, so the timer never races with other changes to the state.

Where the analogy breaks: a one-shot `schedule/2` lives only in the
Scheduler's runtime. A Server crash, a stop, or a BEAM restart discards it.
Recurring `cron/4` definitions are in Agent state and restore with it, but
slots missed while the Agent was down aren't replayed. See
[Heartbeats and Schedules](heartbeats-and-schedules.livemd).

## Many Machines

The `cluster` module forks Node.js workers that share a port. They share no
memory, so they coordinate through an external broker such as Redis.

BEAM nodes connect with distributed Erlang. A PID can name a process on
another node, and `send/2`, links, and monitors work across nodes.

A Jido instance is local to one node. Its registry is node-local, and Jido
doesn't enforce one owner per Agent ID across a cluster or route Signals to
the node that runs an Agent. You choose the owning node for each Agent. See
[Deployment and Sizing](deployment-and-performance.md).

## What It Means for Jido

- **One Agent per entity.** A user, an order, or a conversation gets its own
  Agent, addressed by ID. Different Agents run in parallel.
- **Serial Turns without locks.** Each Agent runs one Turn at a time. You
  don't write the promise-chain lock.
- **State in the process.** The committed state lives in the Server, not in
  a cache you read on each request. Reads return it without a round trip to
  storage.
- **Durability is opt-in.** Pass `persistence: :inherit` and configure an
  adapter to save each commit before the reply. Without it, state lasts only
  as long as the activation.
- **Crashes stay local.** A failed Action fails one Turn. A crashed Server
  restarts with its last committed state, and other Agents keep running.

## Next

- [TypeScript Concept Map](typescript-concept-map.md) – TypeScript patterns
  and their Jido equivalents.
- [OTP Concepts](otp-concepts-for-jido.md) – processes, supervisors, and the
  Agent Server in OTP terms.
