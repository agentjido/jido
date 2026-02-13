# Testing

**After:** You can test pure logic and integration without flakes.

Testing Jido agents involves two approaches: pure agent testing (no runtime) and integration testing with AgentServer. This guide covers both patterns along with test isolation, async coordination, and mocking strategies.

## JidoTest.Case for Isolation

Use `JidoTest.Case` to get an isolated Jido instance per test. Each test receives its own Registry, TaskSupervisor, and AgentSupervisor—preventing cross-test interference even when running async.

```elixir
defmodule MyAgentTest do
  use JidoTest.Case, async: true

  test "starts agent under isolated instance", %{jido: jido} do
    {:ok, pid} = Jido.start_agent(jido, MyAgent)
    assert Process.alive?(pid)
  end
end
```

### Context Keys

The test context includes:

| Key | Description |
|-----|-------------|
| `:jido` | Name of the Jido instance (atom) |
| `:jido_pid` | PID of the Jido supervisor |

### Helper Functions

`JidoTest.Case` provides convenience functions:

```elixir
test "helper functions", %{jido: jido} = context do
  # Start agent using helper
  {:ok, pid} = start_test_agent(context, MyAgent, id: "test-1")

  # Get infrastructure names
  registry = test_registry(context)
  task_sup = test_task_supervisor(context)
  agent_sup = test_agent_supervisor(context)
end
```

## Testing Pure Agents

Agents are immutable structs. Test state transformations without any runtime:

```elixir
defmodule CounterAgentTest do
  use ExUnit.Case, async: true

  alias MyApp.CounterAgent
  alias MyApp.Actions.{Increment, Decrement}

  describe "cmd/2 state transformations" do
    test "increment updates counter" do
      agent = CounterAgent.new()
      assert agent.state.counter == 0

      {agent, directives} = CounterAgent.cmd(agent, {Increment, %{by: 5}})

      assert agent.state.counter == 5
      assert directives == []
    end

    test "decrement reduces counter" do
      agent = CounterAgent.new(state: %{counter: 10})

      {agent, _directives} = CounterAgent.cmd(agent, Decrement)

      assert agent.state.counter == 9
    end

    test "multiple actions in sequence" do
      agent = CounterAgent.new()

      {agent, _} = CounterAgent.cmd(agent, [
        {Increment, %{by: 10}},
        {Decrement, %{}},
        {Increment, %{by: 5}}
      ])

      assert agent.state.counter == 14
    end
  end

  describe "directives" do
    test "action can emit signal directive" do
      agent = CounterAgent.new()

      {agent, directives} = CounterAgent.cmd(agent, NotifyAction)

      assert [%Jido.Agent.Directive.Emit{signal: signal}] = directives
      assert signal.type == "counter.updated"
    end
  end
end
```

### Testing Validation

```elixir
test "validate/2 enforces schema" do
  agent = MyAgent.new(state: %{status: :running, extra: "data"})

  # Non-strict preserves extra fields
  {:ok, validated} = MyAgent.validate(agent)
  assert validated.state.extra == "data"

  # Strict mode removes extra fields
  {:ok, strict} = MyAgent.validate(agent, strict: true)
  refute Map.has_key?(strict.state, :extra)
end
```

### Testing set/2

```elixir
test "set/2 deep merges state" do
  agent = MyAgent.new(state: %{config: %{a: 1, b: 2}})

  {:ok, updated} = MyAgent.set(agent, %{config: %{b: 3, c: 4}})

  assert updated.state.config == %{a: 1, b: 3, c: 4}
end
```

## Testing with AgentServer

For integration tests involving signals, directives, and real process behavior:

```elixir
defmodule AgentIntegrationTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal}

  describe "signal processing" do
    test "synchronous call returns updated agent", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CounterAgent, jido: jido)

      signal = Signal.new!("increment", %{by: 5}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.counter == 5
    end

    test "async cast processes in background", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CounterAgent, jido: jido)

      signal = Signal.new!("increment", %{}, source: "/test")
      assert :ok = AgentServer.cast(pid, signal)

      # Wait briefly for async processing
      Process.sleep(10)

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 1
    end

    test "multiple signals in sequence", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(agent: CounterAgent, jido: jido)

      for _ <- 1..5 do
        signal = Signal.new!("increment", %{}, source: "/test")
        {:ok, _} = AgentServer.call(pid, signal)
      end

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 5
    end
  end

  describe "initial state" do
    test "starts with custom initial state", %{jido: jido} do
      {:ok, pid} = AgentServer.start_link(
        agent: CounterAgent,
        initial_state: %{counter: 100},
        jido: jido
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.agent.state.counter == 100
    end

    test "starts with pre-built agent", %{jido: jido} do
      agent = CounterAgent.new(id: "prebuilt-123")
      agent = %{agent | state: Map.put(agent.state, :counter, 50)}

      {:ok, pid} = AgentServer.start_link(
        agent: agent,
        agent_module: CounterAgent,
        jido: jido
      )

      {:ok, state} = AgentServer.state(pid)
      assert state.id == "prebuilt-123"
      assert state.agent.state.counter == 50
    end
  end
end
```

### Testing Registry Lookup

```elixir
test "agent registers with ID", %{jido: jido} do
  {:ok, pid} = AgentServer.start_link(
    agent: MyAgent,
    id: "my-agent-1",
    jido: jido
  )

  registry = Jido.registry_name(jido)
  assert AgentServer.whereis(registry, "my-agent-1") == pid
end
```

## Await Patterns in Tests

Use `Jido.await/2` and related functions for coordination:

### Waiting for Completion

```elixir
test "await waits for agent completion", %{jido: jido} do
  {:ok, pid} = Jido.start_agent(jido, WorkerAgent)

  # Trigger async work
  signal = Signal.new!("start_work", %{}, source: "/test")
  AgentServer.cast(pid, signal)

  # Wait for completion (agent sets status: :completed)
  {:ok, result} = Jido.await(pid, 10_000)

  assert result.status == :completed
  assert result.result == "done"
end
```

### Waiting for Child Agents

```elixir
test "await_child waits for spawned child", %{jido: jido} do
  {:ok, parent} = Jido.start_agent(jido, CoordinatorAgent)

  # Parent spawns a child via SpawnAgent directive
  signal = Signal.new!("spawn_worker", %{tag: :worker_1}, source: "/test")
  {:ok, _} = AgentServer.call(parent, signal)

  # Wait for child to complete
  {:ok, result} = Jido.await_child(parent, :worker_1, 30_000)

  assert result.status == :completed
end
```

### Waiting for Multiple Agents

```elixir
test "await_all waits for all agents", %{jido: jido} do
  pids = for i <- 1..3 do
    {:ok, pid} = Jido.start_agent(jido, WorkerAgent, id: "worker-#{i}")
    AgentServer.cast(pid, Signal.new!("start", %{}, source: "/test"))
    pid
  end

  {:ok, results} = Jido.await_all(pids, 30_000)

  assert map_size(results) == 3
  Enum.each(results, fn {_pid, result} ->
    assert result.status == :completed
  end)
end

test "await_any returns first to complete", %{jido: jido} do
  pids = for i <- 1..3 do
    {:ok, pid} = Jido.start_agent(jido, WorkerAgent, id: "racer-#{i}")
    AgentServer.cast(pid, Signal.new!("start", %{delay: i * 100}, source: "/test"))
    pid
  end

  {:ok, {winner, result}} = Jido.await_any(pids, 10_000)

  assert winner in pids
  assert result.status == :completed
end
```

### Timeout Handling

```elixir
test "await returns timeout error", %{jido: jido} do
  {:ok, pid} = Jido.start_agent(jido, SlowAgent)
  AgentServer.cast(pid, Signal.new!("slow_work", %{}, source: "/test"))

  assert {:error, :timeout} = Jido.await(pid, 100)
end
```

## Mocking with Mimic

Use [Mimic](https://hex.pm/packages/mimic) for mocking external dependencies:

### Setup

```elixir
# test/test_helper.exs
Mimic.copy(MyApp.ExternalService)
Mimic.copy(MyApp.HttpClient)

ExUnit.start()
```

### Basic Mocking

```elixir
defmodule ExternalServiceTest do
  use JidoTest.Case, async: true
  use Mimic

  test "mocks external service call", %{jido: jido} do
    expect(MyApp.ExternalService, :call, fn args ->
      assert args == %{query: "test"}
      {:ok, "mocked response"}
    end)

    {:ok, pid} = Jido.start_agent(jido, MyAgent)
    signal = Signal.new!("fetch_data", %{query: "test"}, source: "/test")
    {:ok, agent} = AgentServer.call(pid, signal)

    assert agent.state.result == "mocked response"
  end
end
```

### Stubbing

```elixir
test "stubs return consistent value", %{jido: jido} do
  stub(MyApp.HttpClient, :get, fn _url ->
    {:ok, %{status: 200, body: "stubbed"}}
  end)

  {:ok, pid} = Jido.start_agent(jido, FetcherAgent)

  # Multiple calls all return stubbed value
  for _ <- 1..3 do
    signal = Signal.new!("fetch", %{}, source: "/test")
    {:ok, agent} = AgentServer.call(pid, signal)
    assert agent.state.last_response == "stubbed"
  end
end
```

### Verifying Call Count

```elixir
test "verifies service was called", %{jido: jido} do
  expect(MyApp.ExternalService, :call, 2, fn _args ->
    {:ok, "result"}
  end)

  {:ok, pid} = Jido.start_agent(jido, MyAgent)

  signal = Signal.new!("process", %{}, source: "/test")
  {:ok, _} = AgentServer.call(pid, signal)
  {:ok, _} = AgentServer.call(pid, signal)

  # Mimic automatically verifies expect count at test end
end
```

### Rejecting Calls

```elixir
test "service should not be called", %{jido: jido} do
  reject(&MyApp.ExternalService.call/1)

  {:ok, pid} = Jido.start_agent(jido, CachedAgent)

  # Agent uses cache, should not call external service
  signal = Signal.new!("get_cached", %{}, source: "/test")
  {:ok, _} = AgentServer.call(pid, signal)
end
```

## Testing Parent-Child Hierarchies

```elixir
defmodule HierarchyTest do
  use JidoTest.Case, async: true

  alias Jido.{AgentServer, Signal}
  alias Jido.AgentServer.ParentRef

  test "child receives parent reference", %{jido: jido} do
    {:ok, parent_pid} = AgentServer.start_link(
      agent: ParentAgent,
      id: "parent-1",
      jido: jido
    )

    parent_ref = ParentRef.new!(%{
      pid: parent_pid,
      id: "parent-1",
      tag: :worker
    })

    {:ok, child_pid} = AgentServer.start_link(
      agent: ChildAgent,
      id: "child-1",
      parent: parent_ref,
      jido: jido
    )

    {:ok, child_state} = AgentServer.state(child_pid)

    assert child_state.parent.pid == parent_pid
    assert child_state.parent.id == "parent-1"
  end

  test "parent receives child exit notification", %{jido: jido} do
    {:ok, parent_pid} = AgentServer.start(
      agent: ParentAgent,
      id: "parent-1",
      jido: jido
    )

    # Parent spawns child via directive
    signal = Signal.new!(
      "spawn_agent",
      %{module: ChildAgent, tag: :worker_1},
      source: "/test"
    )
    {:ok, _} = AgentServer.call(parent_pid, signal)

    # Wait for child to appear
    Process.sleep(50)
    {:ok, state} = AgentServer.state(parent_pid)
    child_info = state.children[:worker_1]

    # Terminate child
    child_ref = Process.monitor(child_info.pid)
    DynamicSupervisor.terminate_child(
      Jido.agent_supervisor_name(jido),
      child_info.pid
    )
    assert_receive {:DOWN, ^child_ref, :process, _, :shutdown}, 500

    # Parent should process child exit
    Process.sleep(50)
    {:ok, final_state} = AgentServer.state(parent_pid)
    refute Map.has_key?(final_state.children, :worker_1)
    assert length(final_state.agent.state.child_events) == 1
  end
end
```

## Testing Directive Execution

```elixir
test "Schedule directive fires after delay", %{jido: jido} do
  {:ok, pid} = AgentServer.start_link(agent: SchedulerAgent, jido: jido)

  signal = Signal.new!("schedule_ping", %{}, source: "/test")
  {:ok, _} = AgentServer.call(pid, signal)

  # Wait for scheduled message
  Process.sleep(100)

  {:ok, state} = AgentServer.state(pid)
  assert state.agent.state.received_ping == true
end

test "Stop directive terminates agent", %{jido: jido} do
  {:ok, pid} = AgentServer.start_link(agent: MyAgent, jido: jido)
  ref = Process.monitor(pid)

  signal = Signal.new!("shutdown", %{}, source: "/test")
  {:ok, _} = AgentServer.call(pid, signal)

  assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000
end
```

## Common Patterns

### Capturing Logs

```elixir
import ExUnit.CaptureLog

test "logs on termination", %{jido: jido} do
  {:ok, pid} = AgentServer.start_link(
    agent: MyAgent,
    id: "log-test",
    jido: jido
  )

  log = capture_log(fn ->
    GenServer.stop(pid, :normal)
    Process.sleep(10)
  end)

  assert log =~ "log-test"
  assert log =~ "terminating"
end
```

### Testing Error Handling

```elixir
test "returns error directive for invalid action", %{jido: _jido} do
  agent = MyAgent.new()

  {_agent, directives} = MyAgent.cmd(agent, {InvalidAction, %{}})

  assert [%Jido.Agent.Directive.Error{context: :instruction}] = directives
end
```

### Trapping Exits

```elixir
test "child stops when parent dies", %{jido: jido} do
  Process.flag(:trap_exit, true)

  {:ok, parent_pid} = AgentServer.start(agent: ParentAgent, jido: jido)
  parent_ref = ParentRef.new!(%{pid: parent_pid, id: "parent", tag: :worker})

  {:ok, child_pid} = AgentServer.start(
    agent: ChildAgent,
    parent: parent_ref,
    on_parent_death: :stop,
    jido: jido
  )

  child_ref = Process.monitor(child_pid)

  DynamicSupervisor.terminate_child(
    Jido.agent_supervisor_name(jido),
    parent_pid
  )

  assert_receive {:DOWN, ^child_ref, :process, ^child_pid, _}, 1000
end
```

## Debugging Failing Tests

Use instance-level debug to capture events when diagnosing test failures:

```elixir
test "diagnose agent behavior", %{jido: jido} do
  Jido.Debug.enable(jido, :on)

  {:ok, pid} = Jido.start_agent(jido, MyAgent)
  signal = Signal.new!("process", %{}, source: "/test")
  AgentServer.cast(pid, signal)
  Process.sleep(50)

  {:ok, events} = Jido.AgentServer.recent_events(pid)
  IO.inspect(events, label: "debug events")
end
```

Debug overrides use `:persistent_term` and will leak between tests if not reset. Always reset in `setup` or `on_exit` when using `Jido.Debug.enable/3`:

```elixir
setup %{jido: jido} = context do
  Jido.Debug.reset(jido)
  on_exit(fn -> Jido.Debug.reset(jido) end)
  context
end
```

## Summary

| Scenario | Approach |
|----------|----------|
| State transformations | Pure `cmd/2` testing, no runtime |
| Signal processing | `JidoTest.Case` + `AgentServer.call/cast` |
| Async coordination | `Jido.await/2`, `Jido.await_child/4` |
| External dependencies | Mimic `expect/stub/reject` |
| Test isolation | `JidoTest.Case` per-test instances |

## Further Reading

- `JidoTest.Case` — Test case module documentation
- `Jido.Await` — Coordination API details
- `Jido.AgentServer` — Server API reference
