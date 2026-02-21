# Multi-Agent Orchestration

**After:** You can spawn child agents, wait for results, and aggregate them — the Jido approach to parallel and hierarchical workflows.

```elixir
# Before: Manual process management
{:ok, pid1} = GenServer.start_link(Worker, %{task: "fetch"})
{:ok, pid2} = GenServer.start_link(Worker, %{task: "parse"})
# ... track PIDs, handle failures, aggregate results

# After: Declarative orchestration
def cmd({:fan_out, urls}, agent, _ctx) do
  directives = Enum.map(urls, fn url ->
    Directive.spawn_agent(FetcherAgent, :"fetcher_#{:erlang.phash2(url)}", 
      meta: %{url: url})
  end)
  
  {:ok, agent, directives}
end
```

## The Pattern

Multi-agent orchestration follows a simple flow:

1. **Parent spawns children** via `SpawnAgent` directive
2. **Parent receives notification** via `jido.agent.child.started` signal
3. **Parent sends work** to children via `emit_to_pid/2`
4. **Children process and reply** via `emit_to_parent/3`
5. **Parent aggregates results** and continues

```
    Parent (Coordinator)
        |
        |-- SpawnAgent(:worker_1) ------> Worker 1
        |                                    |
        |<-- jido.agent.child.started -------|
        |                                    |
        |-- work.request ------------------->|
        |                            [process work]
        |<-- work.result --------------------|
        |                                    |
   [aggregate]
```

## Tutorial: Building a Parallel URL Fetcher

We'll build a coordinator that spawns worker agents to fetch multiple URLs in parallel, then aggregates the results.

### Step 1: Define the Worker Agent

Workers fetch a single URL and report back to their parent:

```elixir
defmodule FetchUrlAction do
  use Jido.Action,
    name: "fetch_url",
    schema: [
      url: [type: :string, required: true],
      request_id: [type: :string, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{url: url, request_id: request_id}, context) do
    # Simulate HTTP fetch (replace with real HTTP client)
    result = 
      case :httpc.request(:get, {String.to_charlist(url), []}, [], []) do
        {:ok, {{_, 200, _}, _headers, body}} -> 
          {:ok, to_string(body)}
        {:ok, {{_, status, _}, _, _}} -> 
          {:error, "HTTP #{status}"}
        {:error, reason} -> 
          {:error, inspect(reason)}
      end

    # Build response signal
    result_signal = Signal.new!(
      "fetch.result",
      %{request_id: request_id, url: url, result: result},
      source: "/worker"
    )

    # Send to parent using emit_to_parent helper
    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok, %{status: :completed, last_fetch: url}, List.wrap(emit_directive)}
  end
end

defmodule FetcherAgent do
  use Jido.Agent,
    name: "fetcher",
    schema: [
      status: [type: :atom, default: :idle],
      last_fetch: [type: :string, default: nil]
    ],
    signal_routes: [{"fetch.request", FetchUrlAction}]
end
```

### Step 2: Define the Coordinator Agent

The coordinator spawns workers and aggregates results:

```elixir
defmodule SpawnFetchersAction do
  use Jido.Action,
    name: "spawn_fetchers",
    schema: [
      urls: [type: {:list, :string}, required: true]
    ]

  alias Jido.Agent.Directive

  def run(%{urls: urls}, _context) do
    # Create pending requests map and spawn directives
    pending = 
      urls
      |> Enum.with_index()
      |> Enum.map(fn {url, i} -> 
        request_id = "req-#{i}"
        {request_id, %{url: url, status: :pending}}
      end)
      |> Map.new()

    spawn_directives = 
      urls
      |> Enum.with_index()
      |> Enum.map(fn {url, i} ->
        Directive.spawn_agent(FetcherAgent, :"worker_#{i}",
          meta: %{url: url, request_id: "req-#{i}"})
      end)

    {:ok, %{pending: pending, completed: []}, spawn_directives}
  end
end

defmodule HandleChildStartedAction do
  use Jido.Action,
    name: "child_started",
    schema: [
      pid: [type: :any, required: true],
      tag: [type: :any, required: true],
      meta: [type: :map, default: %{}]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  def run(%{pid: pid, meta: meta}, _context) do
    # Send work to the newly spawned child
    work_signal = Signal.new!(
      "fetch.request",
      %{url: meta.url, request_id: meta.request_id},
      source: "/coordinator"
    )

    emit_directive = Directive.emit_to_pid(work_signal, pid)

    {:ok, %{}, [emit_directive]}
  end
end

defmodule HandleFetchResultAction do
  use Jido.Action,
    name: "handle_result",
    schema: [
      request_id: [type: :string, required: true],
      url: [type: :string, required: true],
      result: [type: :any, required: true]
    ]

  alias Jido.Agent.StateOp

  def run(%{request_id: request_id, url: url, result: result}, context) do
    pending = Map.get(context.state, :pending, %{})
    completed = Map.get(context.state, :completed, [])

    # Move from pending to completed
    {_, remaining_pending} = Map.pop(pending, request_id)
    
    entry = %{
      request_id: request_id,
      url: url,
      result: result,
      completed_at: DateTime.utc_now()
    }

    # Determine if all work is done
    status = if map_size(remaining_pending) == 0, do: :completed, else: :working

    # Use SetPath to replace pending (deep merge doesn't remove keys)
    set_pending_op = StateOp.set_path([:pending], remaining_pending)

    {:ok, %{completed: [entry | completed], status: status}, [set_pending_op]}
  end
end

defmodule CoordinatorAgent do
  use Jido.Agent,
    name: "coordinator",
    schema: [
      pending: [type: :map, default: %{}],
      completed: [type: {:list, :map}, default: []],
      status: [type: :atom, default: :idle]
    ],
    signal_routes: [
      {"fetch_urls", SpawnFetchersAction},
      {"jido.agent.child.started", HandleChildStartedAction},
      {"fetch.result", HandleFetchResultAction}
    ]
end
```

### Step 3: Wire It Up

Start the coordinator and trigger the fan-out:

```elixir
alias Jido.{Signal, AgentServer}

# Start Jido instance
{:ok, _} = Jido.start_link(name: MyApp.Jido)

# Start coordinator
{:ok, coordinator} = Jido.start_agent(MyApp.Jido, CoordinatorAgent, id: "coordinator-1")

# Trigger parallel fetch
urls = [
  "https://example.com",
  "https://httpbin.org/get",
  "https://jsonplaceholder.typicode.com/todos/1"
]

signal = Signal.new!("fetch_urls", %{urls: urls}, source: "/api")
{:ok, _} = AgentServer.call(coordinator, signal)
```

### Step 4: Handle Completion

Use `await/2` to wait for all results:

```elixir
# Wait for coordinator to finish aggregating
case Jido.await(coordinator, 30_000) do
  {:ok, %{status: :completed, completed: results}} ->
    IO.puts("Fetched #{length(results)} URLs")
    Enum.each(results, fn %{url: url, result: result} ->
      case result do
        {:ok, body} -> IO.puts("✓ #{url}: #{String.length(body)} bytes")
        {:error, err} -> IO.puts("✗ #{url}: #{err}")
      end
    end)

  {:error, :timeout} ->
    IO.puts("Fetch operation timed out")
end
```

## Error Handling

### Child Failures

When a child crashes, the parent receives `jido.agent.child.exit`:

```elixir
defmodule HandleChildExitAction do
  use Jido.Action,
    name: "handle_child_exit",
    schema: [
      tag: [type: :atom, required: true],
      reason: [type: :any, required: true]
    ]

  def run(%{tag: tag, reason: reason}, context) do
    pending = Map.get(context.state, :pending, %{})
    
    # Find and fail the request for this worker
    failed_request = 
      Enum.find(pending, fn {_id, info} -> 
        info[:worker_tag] == tag 
      end)

    case failed_request do
      {request_id, _info} ->
        {_, remaining} = Map.pop(pending, request_id)
        failures = Map.get(context.state, :failures, [])
        
        {:ok, %{
          pending: remaining,
          failures: [{request_id, reason} | failures]
        }}

      nil ->
        {:ok, %{}}
    end
  end
end

# Add to coordinator routes
def signal_routes(_ctx) do
  [
    # ... other routes
    {"jido.agent.child.exit", HandleChildExitAction}
  ]
end
```

### Timeout Handling

Use `await_all/2` with appropriate timeouts:

```elixir
# Get all child PIDs
{:ok, children} = Jido.get_children(coordinator)
pids = Map.values(children) |> Enum.map(& &1.pid)

case Jido.await_all(pids, 60_000) do
  {:ok, results} ->
    # All children completed
    successful = Enum.count(results, fn {_, %{status: s}} -> s == :completed end)
    IO.puts("#{successful}/#{map_size(results)} workers succeeded")

  {:error, :timeout} ->
    # Some children didn't complete in time
    # Cancel remaining work
    for pid <- pids, Jido.alive?(pid) do
      Jido.cancel(pid, reason: :timeout)
    end
end
```

### Stopping Children Gracefully

Use `StopChild` directive to clean up:

```elixir
defmodule CleanupWorkersAction do
  use Jido.Action,
    name: "cleanup",
    schema: [tags: [type: {:list, :atom}, required: true]]

  alias Jido.Agent.Directive

  def run(%{tags: tags}, _context) do
    stop_directives = Enum.map(tags, fn tag ->
      Directive.stop_child(tag, reason: :cleanup)
    end)

    {:ok, %{status: :cleaned_up}, stop_directives}
  end
end
```

## Complete Example

Here's a complete, runnable module combining everything:

```elixir
defmodule ParallelFetcher do
  @moduledoc """
  A parallel URL fetcher demonstrating multi-agent orchestration.
  
  Usage:
      {:ok, results} = ParallelFetcher.fetch(["https://example.com", ...])
  """

  alias Jido.{Signal, AgentServer}
  alias Jido.Agent.{Directive, StateOp}

  # ============================================================================
  # Worker Agent
  # ============================================================================

  defmodule FetchAction do
    use Jido.Action,
      name: "fetch",
      schema: [
        url: [type: :string, required: true],
        request_id: [type: :string, required: true]
      ]

    def run(%{url: url, request_id: request_id}, context) do
      result = do_fetch(url)

      signal = Signal.new!(
        "fetch.result",
        %{request_id: request_id, url: url, result: result},
        source: "/worker"
      )

      emit = Directive.emit_to_parent(%{state: context.state}, signal)

      {:ok, %{status: :completed}, List.wrap(emit)}
    end

    defp do_fetch(url) do
      # Simple HTTP GET using httpc (comes with OTP)
      Application.ensure_all_started(:inets)
      Application.ensure_all_started(:ssl)

      case :httpc.request(:get, {String.to_charlist(url), []}, 
             [{:timeout, 10_000}], [{:body_format, :binary}]) do
        {:ok, {{_, status, _}, _headers, body}} when status in 200..299 ->
          {:ok, %{status: status, size: byte_size(body)}}
        {:ok, {{_, status, _}, _, _}} ->
          {:error, {:http_error, status}}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defmodule Worker do
    use Jido.Agent,
      name: "fetcher_worker",
      schema: [status: [type: :atom, default: :idle]],
      signal_routes: [{"fetch", FetchAction}]
  end

  # ============================================================================
  # Coordinator Agent
  # ============================================================================

  defmodule StartAction do
    use Jido.Action,
      name: "start",
      schema: [urls: [type: {:list, :string}, required: true]]

    def run(%{urls: urls}, _context) do
      pending =
        urls
        |> Enum.with_index()
        |> Map.new(fn {url, i} -> {"req-#{i}", %{url: url}} end)

      spawns =
        urls
        |> Enum.with_index()
        |> Enum.map(fn {url, i} ->
          Directive.spawn_agent(Worker, :"w#{i}", 
            meta: %{url: url, request_id: "req-#{i}"})
        end)

      {:ok, %{pending: pending, results: [], status: :working}, spawns}
    end
  end

  defmodule ChildStartedAction do
    use Jido.Action,
      name: "child_started",
      schema: [pid: [type: :any], meta: [type: :map, default: %{}]]

    def run(%{pid: pid, meta: meta}, _context) do
      signal = Signal.new!("fetch", %{
        url: meta.url,
        request_id: meta.request_id
      }, source: "/coordinator")

      {:ok, %{}, [Directive.emit_to_pid(signal, pid)]}
    end
  end

  defmodule ResultAction do
    use Jido.Action,
      name: "result",
      schema: [
        request_id: [type: :string, required: true],
        url: [type: :string, required: true],
        result: [type: :any, required: true]
      ]

    def run(%{request_id: id, url: url, result: result}, context) do
      pending = Map.delete(context.state.pending, id)
      results = [%{url: url, result: result} | context.state.results]
      status = if map_size(pending) == 0, do: :completed, else: :working

      {:ok, %{results: results, status: status}, [StateOp.set_path([:pending], pending)]}
    end
  end

  defmodule Coordinator do
    use Jido.Agent,
      name: "fetcher_coordinator",
      schema: [
        pending: [type: :map, default: %{}],
        results: [type: {:list, :map}, default: []],
        status: [type: :atom, default: :idle]
      ],
      signal_routes: [
        {"start", StartAction},
        {"jido.agent.child.started", ChildStartedAction},
        {"fetch.result", ResultAction}
      ]
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Fetch multiple URLs in parallel.

  ## Example

      {:ok, results} = ParallelFetcher.fetch([
        "https://example.com",
        "https://httpbin.org/get"
      ])

      Enum.each(results, fn %{url: url, result: result} ->
        IO.inspect({url, result})
      end)
  """
  def fetch(urls, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    jido_name = Keyword.get(opts, :jido, ParallelFetcher.Jido)

    # Ensure Jido is running
    case Jido.start_link(name: jido_name) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Start coordinator
    {:ok, coordinator} = Jido.start_agent(jido_name, Coordinator, 
      id: "coord-#{:erlang.unique_integer([:positive])}")

    # Trigger fetch
    signal = Signal.new!("start", %{urls: urls}, source: "/api")
    {:ok, _} = AgentServer.call(coordinator, signal)

    # Wait for completion
    case Jido.await(coordinator, timeout) do
      {:ok, %{status: :completed, results: results}} ->
        {:ok, Enum.reverse(results)}

      {:ok, %{status: :working, results: partial}} ->
        {:partial, Enum.reverse(partial)}

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end
end

# Usage:
# {:ok, results} = ParallelFetcher.fetch(["https://example.com", "https://httpbin.org/get"])
```

## Next Steps

- [Await & Coordination](await.md) — Event-driven waiting patterns
- [Directives](directives.md) — All available directive types
- [Testing](testing.md) — Testing multi-agent systems
