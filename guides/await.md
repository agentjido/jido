# Await & Coordination

**After:** You can coordinate async agents without `Process.sleep` in tests.

```elixir
# Before: guessing with sleep
AgentServer.cast(pid, signal)
Process.sleep(500)  # Hope this is enough...
{:ok, state} = AgentServer.state(pid)

# After: event-driven waiting
AgentServer.cast(pid, signal)
{:ok, %{status: :completed, result: answer}} = Jido.await(pid, 10_000)
```

## The Pattern

Agents signal completion by setting a terminal status in their state:

```elixir
def run(_params, _context) do
  {:ok, %{status: :completed, last_answer: result}}
end
```

The await functions use event-driven waiting—no polling. The caller blocks until the agent reaches `:completed` or `:failed`, then receives the result immediately.

## Waiting for Completion

### await/2

Wait for a single agent to complete:

```elixir
{:ok, pid} = Jido.start_agent(jido, WorkerAgent)
AgentServer.cast(pid, Signal.new!("process", %{data: "input"}, source: "/api"))

case Jido.await(pid, 10_000) do
  {:ok, %{status: :completed, result: answer}} ->
    IO.puts("Got result: #{inspect(answer)}")

  {:ok, %{status: :failed, result: error}} ->
    IO.puts("Agent failed: #{inspect(error)}")

  {:error, :timeout} ->
    IO.puts("Agent didn't complete in time")
end
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `:status_path` | `[:status]` | Path to status field in agent state |
| `:result_path` | `[:last_answer]` | Path to result field |
| `:error_path` | `[:error]` | Path to error field |

Custom paths for strategies with nested state:

```elixir
Jido.await(pid, 10_000,
  status_path: [:__strategy__, :status],
  result_path: [:__strategy__, :result]
)
```

**Return shapes:**

```elixir
{:ok, %{status: :completed, result: any()}}  # Success
{:ok, %{status: :failed, result: any()}}     # Agent-level failure
{:error, :timeout}                            # Deadline exceeded
{:error, :not_found}                          # Process not found
```

### await_child/4

Wait for a specific child by tag. First looks up the child in the parent's `children` map, then waits for completion:

```elixir
{:ok, coordinator} = Jido.start_agent(jido, CoordinatorAgent)

# Coordinator spawns a child via SpawnAgent directive
AgentServer.cast(coordinator, Signal.new!("spawn_worker", %{tag: :worker_1}, source: "/test"))

# Wait for that child to complete
{:ok, result} = Jido.await_child(coordinator, :worker_1, 30_000)
```

The function polls for the child to appear (50ms intervals), then uses event-driven waiting for completion. Total timeout covers both phases.

### await_all/2

Wait for multiple agents to complete. Returns when all finish or on first infrastructure error:

```elixir
{:ok, pid1} = Jido.start_agent(jido, WorkerAgent, id: "worker-1")
{:ok, pid2} = Jido.start_agent(jido, WorkerAgent, id: "worker-2")
{:ok, pid3} = Jido.start_agent(jido, WorkerAgent, id: "worker-3")

# Trigger work on all
for pid <- [pid1, pid2, pid3] do
  AgentServer.cast(pid, Signal.new!("process", %{}, source: "/batch"))
end

case Jido.await_all([pid1, pid2, pid3], 30_000) do
  {:ok, results} ->
    # results is %{pid1 => %{status: :completed, result: ...}, ...}
    Enum.each(results, fn {pid, %{result: r}} ->
      IO.puts("#{inspect(pid)} => #{inspect(r)}")
    end)

  {:error, :timeout} ->
    IO.puts("Not all agents completed in time")

  {:error, {failed_pid, reason}} ->
    IO.puts("Agent #{inspect(failed_pid)} errored: #{inspect(reason)}")
end
```

**Return shapes:**

```elixir
{:ok, %{server => %{status: atom(), result: any()}}}  # All completed
{:error, :timeout}                                     # Deadline exceeded
{:error, {server, reason}}                             # Infrastructure error
```

Note: A `:failed` status from an agent is still success from the coordinator's perspective—it completed. Infrastructure errors (process death, network issues) return the error tuple.

### await_any/2

Wait for the first agent to complete. Racing pattern for redundancy or speculation:

```elixir
{:ok, fast} = Jido.start_agent(jido, FastWorker)
{:ok, slow} = Jido.start_agent(jido, SlowWorker)

for pid <- [fast, slow] do
  AgentServer.cast(pid, Signal.new!("compute", %{}, source: "/race"))
end

case Jido.await_any([fast, slow], 10_000) do
  {:ok, {winner_pid, %{result: answer}}} ->
    IO.puts("Winner: #{inspect(winner_pid)}, answer: #{inspect(answer)}")

  {:error, :timeout} ->
    IO.puts("No agent completed in time")
end
```

Remaining agents continue running—cancel them explicitly if needed.

## Cancellation

Request graceful cancellation of an agent:

```elixir
:ok = Jido.cancel(pid)
:ok = Jido.cancel(pid, reason: :user_requested)
```

Cancellation is advisory. The agent receives a `jido.agent.cancel` signal and decides how to respond. Typical pattern:

```elixir
def signal_routes(_ctx) do
  [{"jido.agent.cancel", HandleCancelAction}]
end

defmodule HandleCancelAction do
  use Jido.Action, name: "handle_cancel", schema: []

  def run(%{reason: reason}, _context) do
    {:ok, %{status: :failed, error: {:cancelled, reason}}}
  end
end
```

After cancelling, use `await/2` to confirm the agent reached a terminal state:

```elixir
:ok = Jido.cancel(pid)
{:ok, %{status: :failed}} = Jido.await(pid, 5_000)
```

## Timeout Handling

All await functions accept a timeout in milliseconds as the second argument:

| Function | Default Timeout |
|----------|-----------------|
| `await/2` | 10,000ms |
| `await_child/4` | 30,000ms |
| `await_all/2` | 10,000ms |
| `await_any/2` | 10,000ms |

Timeout errors are distinguished from agent failures:

```elixir
case Jido.await(pid, 5_000) do
  {:ok, %{status: :failed, result: error}} ->
    # Agent completed but failed (business logic)
    handle_business_error(error)

  {:error, :timeout} ->
    # Agent didn't complete in time (infrastructure)
    handle_timeout()
end
```

For long-running operations, set appropriate timeouts:

```elixir
# Short for quick lookups
Jido.await(cache_agent, 1_000)

# Long for complex processing
Jido.await(ml_agent, 120_000)

# Very long for batch operations
Jido.await_all(workers, 300_000)
```

## Fan-Out Example

Complete example: spawn 5 workers, await all, aggregate results.

```elixir
defmodule FanOut.ComputeAction do
  use Jido.Action,
    name: "compute",
    schema: [
      input: [type: :integer, required: true]
    ]

  def run(%{input: n}, _context) do
    result = n * n
    {:ok, %{status: :completed, last_answer: result}}
  end
end

defmodule FanOut.WorkerAgent do
  use Jido.Agent,
    name: "worker",
    schema: [
      status: [type: :atom, default: :idle],
      last_answer: [type: :any, default: nil]
    ]

  @signal_routes [{"compute", FanOut.ComputeAction}]
  def signal_routes(_ctx), do: @signal_routes
end

defmodule FanOut.Coordinator do
  alias Jido.AgentServer
  alias Jido.Signal

  def run(jido, inputs) do
    # 1. Spawn workers
    workers =
      Enum.map(inputs, fn input ->
        {:ok, pid} = Jido.start_agent(jido, FanOut.WorkerAgent)
        {pid, input}
      end)

    # 2. Trigger computation on all workers
    for {pid, input} <- workers do
      signal = Signal.new!("compute", %{input: input}, source: "/coordinator")
      AgentServer.cast(pid, signal)
    end

    # 3. Await all completions
    pids = Enum.map(workers, fn {pid, _} -> pid end)

    case Jido.await_all(pids, 30_000) do
      {:ok, results} ->
        # 4. Aggregate results
        total =
          results
          |> Map.values()
          |> Enum.map(& &1.result)
          |> Enum.sum()

        {:ok, total}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Usage
{:ok, total} = FanOut.Coordinator.run(jido, [1, 2, 3, 4, 5])
# total = 1 + 4 + 9 + 16 + 25 = 55
```

## Testing Patterns

Replace `Process.sleep` with await functions for reliable tests:

```elixir
defmodule MyAgentTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal}

  test "processes work without sleep", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, WorkerAgent)

    signal = Signal.new!("process", %{}, source: "/test")
    AgentServer.cast(pid, signal)

    # Deterministic: waits for actual completion
    {:ok, %{status: :completed, result: answer}} = Jido.await(pid, 5_000)
    assert answer == "expected"
  end

  test "parallel workers complete", %{jido: jido} do
    pids =
      for i <- 1..5 do
        {:ok, pid} = Jido.start_agent(jido, WorkerAgent, id: "worker-#{i}")
        signal = Signal.new!("process", %{id: i}, source: "/test")
        AgentServer.cast(pid, signal)
        pid
      end

    {:ok, results} = Jido.await_all(pids, 10_000)

    assert map_size(results) == 5
    assert Enum.all?(results, fn {_, %{status: s}} -> s == :completed end)
  end

  test "first responder wins race", %{jido: jido} do
    {:ok, fast} = Jido.start_agent(jido, FastAgent)
    {:ok, slow} = Jido.start_agent(jido, SlowAgent)

    AgentServer.cast(fast, Signal.new!("go", %{}, source: "/test"))
    AgentServer.cast(slow, Signal.new!("go", %{}, source: "/test"))

    {:ok, {winner, _result}} = Jido.await_any([fast, slow], 5_000)
    assert winner == fast
  end

  test "child agent coordination", %{jido: jido} do
    {:ok, parent} = Jido.start_agent(jido, ParentAgent)

    # Parent spawns child via directive
    signal = Signal.new!("spawn", %{tag: :worker}, source: "/test")
    {:ok, _} = AgentServer.call(parent, signal)

    # Wait for child to complete its work
    {:ok, child_result} = Jido.await_child(parent, :worker, 5_000)
    assert child_result.status == :completed
  end
end
```

### Key Testing Benefits

| Pattern | Benefit |
|---------|---------|
| `await/2` | No guessing sleep duration |
| `await_all/2` | Test parallel execution reliably |
| `await_any/2` | Test race conditions deterministically |
| `await_child/4` | Test parent-child hierarchies |

## Utility Functions

Additional helpers for inspecting agent state:

```elixir
# Check if agent is alive
Jido.alive?(pid)  # => true | false

# Get all children of a parent
{:ok, %{worker_1: pid1, worker_2: pid2}} = Jido.get_children(parent)

# Get specific child by tag
{:ok, child_pid} = Jido.get_child(parent, :worker_1)
{:error, :child_not_found} = Jido.get_child(parent, :nonexistent)
```

## Summary

| Function | Use Case |
|----------|----------|
| `await/2` | Wait for single agent completion |
| `await_child/4` | Wait for spawned child by tag |
| `await_all/2` | Wait for all agents (fan-out pattern) |
| `await_any/2` | Wait for first completion (race pattern) |
| `cancel/2` | Request graceful cancellation |
| `alive?/1` | Check if agent is responding |
| `get_children/1` | List all child PIDs |
| `get_child/2` | Get specific child PID by tag |
