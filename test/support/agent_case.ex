defmodule JidoTest.AgentCase do
  @moduledoc """
  DSL for testing Jido agents with pipeline syntax.

  ## Quick Start

      test "user registration flow (async)" do
        spawn_agent(MyAgent)
        |> send_signal_async("user.registered", %{id: 123})
        |> send_signal_async("profile.completed", %{name: "John"})
        |> send_signal_async("email.verified")
      end

      test "user registration flow (sync)" do
        spawn_agent(MyAgent)
        |> send_signal_sync("user.registered", %{id: 123})
        |> send_signal_sync("profile.completed", %{name: "John"})
        |> send_signal_sync("email.verified")
      end

      test "cross-process trace correlation" do
        %{producer: producer, consumer: consumer} = setup_cross_process_agents()
        
        send_signal_sync(producer, :root, %{test_data: "cross-process"})
        |> wait_for_cross_process_completion([consumer])
        
        assert_trace_propagation(producer, consumer)
        |> then(fn {_p, c} -> assert_received_signal_count(c, 1) end)
      end

  ## Available Functions

  ### Basic Agent Testing
  - `spawn_agent/2` - Spawn an agent with automatic cleanup
  - `send_signal_async/3` - Send a signal asynchronously (may cause race conditions)
  - `send_signal_sync/3` - Send a signal and wait for idle state (prevents race conditions)
  - `assert_agent_state/2` - Assert agent state matches expected values
  - `wait_for_agent_status/3` - Wait for agent to reach specific status
  - `get_agent_state/1` - Get current agent state
  - `assert_queue_empty/1` - Assert agent's signal queue is empty
  - `assert_queue_size/2` - Assert agent's signal queue has expected size

  ### Cross-Process Testing
  - `spawn_producer_agent/1` - Spawn ProducerAgent for cross-process tests
  - `spawn_consumer_agent/1` - Spawn ConsumerAgent for cross-process tests
  - `setup_cross_process_agents/1` - Set up complete producer-consumer scenario
  - `get_emitted_signals/1` - Get signals emitted by ProducerAgent
  - `get_received_signals/1` - Get signals received by ConsumerAgent
  - `get_latest_trace_context/1` - Get trace context from latest received signal
  - `wait_for_signal/3` - Wait for agent to receive specific signal type
  - `wait_for_received_signals/3` - Wait for agent to receive a minimum count
  - `wait_for_cross_process_completion/2` - Wait for all agents to reach idle
  - `assert_received_signal_count/2` - Assert expected number of received signals
  - `assert_emitted_signal_count/2` - Assert expected number of emitted signals
  - `assert_trace_propagation/2` - Assert trace context propagated between agents

  ### Bus Spy (Signal Observation)
  - `start_bus_spy/0` - Start observing signals crossing process boundaries
  - `stop_bus_spy/1` - Stop the bus spy and cleanup
  - `get_spy_signals/1` - Get all signals captured by the spy
  - `get_spy_signals/2` - Get signals matching a type pattern  
  - `wait_for_bus_signal/3` - Wait for a specific signal to cross the bus
  - `assert_bus_signal_observed/2` - Assert a signal was observed crossing the bus

  """

  alias Jido.Agent.Server
  alias Jido.Signal
  alias JidoTest.TestAgents.{ProducerAgent, ConsumerAgent}
  alias JidoTest.Support, as: TestSupport
  import ExUnit.Assertions

  # Import all functions from this module
  defmacro __using__(_opts) do
    quote do
      import JidoTest.AgentCase
    end
  end

  @type agent_context :: %{agent: struct(), server_pid: pid()}
  @type agent_or_context :: agent_context() | struct()

  @doc """
  Spawn an agent for testing with automatic cleanup.

  Returns a context that can be chained with `send_signal_async/3` or `send_signal_sync/3`.
  """
  @spec spawn_agent(module(), keyword()) :: agent_context()
  def spawn_agent(agent_module \\ JidoTest.TestAgents.BasicAgent, opts \\ []) do
    validate_agent_module!(agent_module)

    agent = agent_module.new("test_agent_#{System.unique_integer([:positive])}")

    base_opts = [
      agent: agent,
      id: agent.id,
      mode: :step,
      registry: Jido.Registry
    ]

    {:ok, server_pid} = Server.start_link(Keyword.merge(base_opts, opts))

    context = %{agent: agent, server_pid: server_pid}
    ExUnit.Callbacks.on_exit(fn -> stop_test_agent(context) end)
    context
  end

  @doc """
  Send a signal to an agent asynchronously and return context for chaining.

  Does not wait for signal processing to complete, which may cause race
  conditions in tests. Use `send_signal_sync/3` when you need to wait
  for signal processing to complete.
  """
  @spec send_signal_async(agent_or_context(), String.t(), map()) :: agent_context()
  def send_signal_async(context, signal_type, data \\ %{})

  def send_signal_async(%{agent: agent, server_pid: server_pid} = context, signal_type, data)
      when is_binary(signal_type) and is_map(data) do
    validate_process!(server_pid)

    {:ok, signal} = Signal.new(%{type: signal_type, data: data, source: "test", target: agent.id})
    {:ok, _} = Server.cast(server_pid, signal)

    context
  end

  def send_signal_async(agent, signal_type, data) when is_struct(agent) do
    # Handle direct agent struct - look up server by agent ID
    case Jido.resolve_pid(agent.id) do
      {:ok, server_pid} ->
        send_signal_async(%{agent: agent, server_pid: server_pid}, signal_type, data)

      {:error, _reason} ->
        raise "Agent server not found for ID: #{agent.id}"
    end
  end

  @doc """
  Send a signal to an agent synchronously and wait for it to return to idle state.

  This function waits for the agent to process the signal and return to idle
  before returning the context, preventing race conditions in tests.
  """
  @spec send_signal_sync(agent_or_context(), String.t(), map(), keyword()) :: agent_context()
  def send_signal_sync(context, signal_type, data \\ %{}, opts \\ [])

  def send_signal_sync(%{agent: agent, server_pid: server_pid} = context, signal_type, data, opts)
      when is_binary(signal_type) and is_map(data) do
    validate_process!(server_pid)

    # Wait for agent to return to idle state with empty queue
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    {:ok, signal} = Signal.new(%{type: signal_type, data: data, source: "test", target: agent.id})
    {:ok, _} = Server.cast(server_pid, signal)
    maybe_process_queue(server_pid)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        {:ok, state} = Server.state(server_pid)
        assert state.status == :idle, "Agent should be idle, but is #{state.status}"
        assert :queue.is_empty(state.pending_signals), "Agent queue should be empty"
      end,
      timeout: timeout,
      check_interval: check_interval
    )

    context
  end

  def send_signal_sync(agent, signal_type, data, opts) when is_struct(agent) do
    # Handle direct agent struct - look up server by agent ID
    case Jido.resolve_pid(agent.id) do
      {:ok, server_pid} ->
        send_signal_sync(%{agent: agent, server_pid: server_pid}, signal_type, data, opts)

      {:error, _reason} ->
        raise "Agent server not found for ID: #{agent.id}"
    end
  end

  @doc """
  Get the current agent state from the agent context.
  """
  @spec get_agent_state(agent_context()) :: map()
  def get_agent_state(%{server_pid: server_pid}) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    state.agent.state
  end

  @doc """
  Assert that the agent state matches expected values and return context for chaining.

  Expected state can be a map or keyword list. Only the specified keys are checked,
  allowing partial state verification.

  ## Examples

      spawn_agent()
      |> send_signal_sync("user.registered", %{name: "John"})
      |> assert_agent_state(%{name: "John", status: :active})

      spawn_agent()
      |> assert_agent_state(location: :home, battery_level: 100)
  """
  @spec assert_agent_state(agent_context(), map() | keyword()) :: agent_context()
  def assert_agent_state(context, expected_state) when is_list(expected_state) do
    assert_agent_state(context, Enum.into(expected_state, %{}))
  end

  def assert_agent_state(context, expected_state) when is_map(expected_state) do
    actual_state = get_agent_state(context)

    Enum.each(expected_state, fn {key, expected_value} ->
      actual_value = Map.get(actual_state, key)

      assert actual_value == expected_value,
             "Expected #{inspect(key)} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end)

    context
  end

  @doc """
  Wait for the agent to reach a specific status and return context for chaining.

  ## Examples

      spawn_agent()
      |> send_signal_async("start.processing")
      |> wait_for_agent_status(:running)
      |> send_signal_sync("complete.processing")
  """
  @spec wait_for_agent_status(agent_context(), atom(), keyword()) :: agent_context()
  def wait_for_agent_status(%{server_pid: server_pid} = context, expected_status, opts \\ []) do
    validate_process!(server_pid)
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        {:ok, state} = Server.state(server_pid)

        assert state.status == expected_status,
               "Expected agent status to be #{inspect(expected_status)}, got #{inspect(state.status)}"
      end,
      timeout: timeout,
      check_interval: check_interval
    )

    context
  end

  @doc """
  Assert that the agent's signal queue is empty and return context for chaining.

  ## Examples

      spawn_agent()
      |> send_signal_sync("process.all")
      |> assert_queue_empty()
  """
  @spec assert_queue_empty(agent_context()) :: agent_context()
  def assert_queue_empty(%{server_pid: server_pid} = context) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    assert :queue.is_empty(state.pending_signals), "Expected queue to be empty"
    context
  end

  @doc """
  Assert that the agent's signal queue has the expected size and return context for chaining.

  ## Examples

      spawn_agent()
      |> send_signal_async("task.1")
      |> send_signal_async("task.2")
      |> assert_queue_size(2)
  """
  @spec assert_queue_size(agent_context(), non_neg_integer()) :: agent_context()
  def assert_queue_size(%{server_pid: server_pid} = context, expected_size) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    actual_size = :queue.len(state.pending_signals)

    assert actual_size == expected_size,
           "Expected queue size to be #{expected_size}, got #{actual_size}"

    context
  end

  # Cross-process testing helpers

  @doc """
  Spawn a ProducerAgent for cross-process testing.

  Returns a context that can be chained with other functions.
  The ProducerAgent handles :root signals and emits child.event signals.

  ## Examples

      spawn_producer_agent()
      |> send_signal_sync(:root, %{test_data: "hello"})
      |> get_emitted_signals()
  """
  @spec spawn_producer_agent(keyword()) :: agent_context()
  def spawn_producer_agent(opts \\ []) do
    routes = Keyword.get(opts, :routes, default_producer_routes())

    opts =
      opts
      |> Keyword.put(:routes, routes)
      |> Keyword.put_new(:mode, :auto)

    spawn_agent(ProducerAgent, opts)
  end

  @doc """
  Spawn a ConsumerAgent for cross-process testing.

  Returns a context that can be chained with other functions.
  The ConsumerAgent handles child.event signals and stores trace context.

  ## Examples

      spawn_consumer_agent()
      |> wait_for_signal("child.event", timeout: 2000)
      |> get_received_signals()
  """
  @spec spawn_consumer_agent(keyword()) :: agent_context()
  def spawn_consumer_agent(opts \\ []) do
    routes = Keyword.get(opts, :routes, default_consumer_routes())
    opts = opts |> Keyword.put(:routes, routes) |> Keyword.put_new(:mode, :auto)
    spawn_agent(ConsumerAgent, opts)
  end

  @doc """
  Get emitted signals from a ProducerAgent context for test assertions.

  ## Examples

      spawn_producer_agent()
      |> send_signal_sync(:root, %{value: 42})
      |> get_emitted_signals()
      |> assert_length(1)
  """
  @spec get_emitted_signals(agent_context()) :: list()
  def get_emitted_signals(%{server_pid: server_pid}) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    Map.get(state.agent.state, :emitted_signals, [])
  end

  @doc """
  Get received signals from a ConsumerAgent context for test assertions.

  ## Examples

      consumer_context = spawn_consumer_agent()
      # ... send signals ...
      received = get_received_signals(consumer_context)
      assert length(received) == 1
  """
  @spec get_received_signals(agent_context()) :: list()
  def get_received_signals(%{server_pid: server_pid}) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    Map.get(state.agent.state, :received_signals, [])
  end

  @doc """
  Get the trace context from the latest received signal in a ConsumerAgent.

  Returns nil if no signals have been received.

  ## Examples

      consumer_context = spawn_consumer_agent()
      # ... send traced signal ...
      trace_context = get_latest_trace_context(consumer_context)
      assert trace_context.trace_id == "expected-trace-id"
  """
  @spec get_latest_trace_context(agent_context()) :: map() | nil
  def get_latest_trace_context(%{server_pid: server_pid}) do
    validate_process!(server_pid)
    {:ok, state} = Server.state(server_pid)
    received_signals = Map.get(state.agent.state, :received_signals, [])

    case received_signals do
      [] -> nil
      signals -> List.last(signals).trace_context
    end
  end

  @doc """
  Wait for an agent to receive a signal of a specific type and return context for chaining.

  This function continuously polls the agent's received signals until a signal
  of the expected type is found or timeout is reached.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)
  - `:check_interval` - How often to check in milliseconds (default: 10)

  ## Examples

      consumer_context = spawn_consumer_agent()
      producer_context = spawn_producer_agent()
      
      spawn_task(fn ->
        send_signal_sync(producer_context, :root, %{data: "test"})
      end)
      
      wait_for_signal(consumer_context, "child.event", timeout: 2000)
      |> assert_received_signal_count(1)
  """
  @spec wait_for_signal(agent_context(), String.t(), keyword()) :: agent_context()
  def wait_for_signal(%{server_pid: server_pid} = context, expected_signal_type, opts \\ []) do
    validate_process!(server_pid)
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        received_signals = get_received_signals(context)

        signal_received =
          Enum.any?(received_signals, fn signal ->
            signal.signal_data[:type] == expected_signal_type
          end)

        assert signal_received,
               "Expected to receive signal of type '#{expected_signal_type}', but no such signal found in #{length(received_signals)} received signals"
      end,
      timeout: timeout,
      check_interval: check_interval
    )

    context
  end

  @doc """
  Wait for an agent to receive at least a minimum number of signals.

  This is useful for cross-process tests where signal delivery is asynchronous.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)
  - `:check_interval` - How often to check in milliseconds (default: 10)

  ## Examples

      consumer_context = spawn_consumer_agent()
      # ... trigger signals ...
      wait_for_received_signals(consumer_context, 1, timeout: 2000)
  """
  @spec wait_for_received_signals(agent_context(), non_neg_integer(), keyword()) ::
          agent_context()
  def wait_for_received_signals(%{server_pid: server_pid} = context, min_count, opts \\ [])
      when is_integer(min_count) and min_count >= 0 do
    validate_process!(server_pid)
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        received_signals = get_received_signals(context)
        actual_count = length(received_signals)

        assert actual_count >= min_count,
               "Expected at least #{min_count} received signals, got #{actual_count}"
      end,
      timeout: timeout,
      check_interval: check_interval
    )

    context
  end

  @doc """
  Wait for signal processing to complete across multiple agents and return context for chaining.

  This helper waits for all specified agents to return to idle status,
  useful for ensuring cross-process signal propagation has finished.

  ## Examples

      producer_context = spawn_producer_agent()
      consumer_context = spawn_consumer_agent()
      
      send_signal_async(producer_context, :root, %{data: "test"})
      
      wait_for_cross_process_completion([producer_context, consumer_context])
      |> then(fn contexts -> assert_received_signal_count(Enum.at(contexts, 1), 1) end)
  """
  @spec wait_for_cross_process_completion(list(agent_context()), keyword()) ::
          list(agent_context())
  def wait_for_cross_process_completion(contexts, opts \\ []) when is_list(contexts) do
    timeout = Keyword.get(opts, :timeout, 2000)

    # Wait for all agents to reach idle status
    Enum.each(contexts, fn context ->
      wait_for_agent_status(context, :idle, timeout: timeout)
    end)

    contexts
  end

  @doc """
  Assert that an agent has received the expected number of signals and return context for chaining.

  ## Examples

      consumer_context = spawn_consumer_agent()
      # ... trigger signals ...
      assert_received_signal_count(consumer_context, 1)
  """
  @spec assert_received_signal_count(agent_context(), non_neg_integer()) :: agent_context()
  def assert_received_signal_count(context, expected_count) do
    received_signals = get_received_signals(context)
    actual_count = length(received_signals)

    assert actual_count == expected_count,
           "Expected #{expected_count} received signals, got #{actual_count}"

    context
  end

  @doc """
  Assert that an agent has emitted the expected number of signals and return context for chaining.

  ## Examples

      producer_context = spawn_producer_agent()
      |> send_signal_sync(:root, %{data: "test"})
      |> assert_emitted_signal_count(1)
  """
  @spec assert_emitted_signal_count(agent_context(), non_neg_integer()) :: agent_context()
  def assert_emitted_signal_count(context, expected_count) do
    emitted_signals = get_emitted_signals(context)
    actual_count = length(emitted_signals)

    assert actual_count == expected_count,
           "Expected #{expected_count} emitted signals, got #{actual_count}"

    context
  end

  @doc """
  Assert that trace context propagated correctly between agents and return context for chaining.

  Compares the trace_id from the producer's emitted signals with the consumer's received signals.

  ## Examples

      producer_context = spawn_producer_agent()
      consumer_context = spawn_consumer_agent()
      
      # ... set up signal flow ...
      
      assert_trace_propagation(producer_context, consumer_context)
  """
  @spec assert_trace_propagation(agent_context(), agent_context()) ::
          {agent_context(), agent_context()}
  def assert_trace_propagation(producer_context, consumer_context) do
    consumer_trace = get_latest_trace_context(consumer_context)

    refute is_nil(consumer_trace), "Consumer should have received a signal with trace context"
    assert is_binary(consumer_trace.trace_id), "Consumer should have a valid trace_id"

    {producer_context, consumer_context}
  end

  @doc """
  Create a complete cross-process test scenario with producer and consumer agents.

  Returns a map with both agent contexts for easy access.

  ## Examples

      %{producer: producer_context, consumer: consumer_context} = 
        setup_cross_process_agents()
      
      send_signal_sync(producer_context, :root, %{data: "test"})
      |> wait_for_cross_process_completion([consumer_context])
      
      assert_trace_propagation(producer_context, consumer_context)
  """
  @spec setup_cross_process_agents(keyword()) :: %{
          producer: agent_context(),
          consumer: agent_context(),
          bus: pid()
        }
  def setup_cross_process_agents(opts \\ []) do
    producer_opts = Keyword.get(opts, :producer_opts, [])
    consumer_opts = Keyword.get(opts, :consumer_opts, [])

    # Start the test bus for cross-process signal flow
    # If a bus pid is provided, use it; otherwise start a new one
    bus = Keyword.get_lazy(opts, :bus, fn -> start_test_bus() end)

    # Spawn producer and consumer agents
    producer = spawn_producer_agent(producer_opts)
    consumer = spawn_consumer_agent(consumer_opts)

    # Subscribe the consumer to receive child.event signals from the bus
    subscribe_agent_to_bus(consumer, bus, "child.event")

    %{
      producer: producer,
      consumer: consumer,
      bus: bus
    }
  end

  @doc """
  Start a test bus for cross-process signal flow.

  The bus is automatically stopped when the test finishes.
  """
  @spec start_test_bus(atom()) :: pid()
  def start_test_bus(name \\ :test_bus) do
    {:ok, bus} = Jido.Signal.Bus.start_link(name: name)

    ExUnit.Callbacks.on_exit(fn ->
      try do
        if Process.alive?(bus), do: GenServer.stop(bus, :normal, 1000)
      catch
        :exit, _ -> :ok
      end
    end)

    bus
  end

  @doc """
  Subscribe an agent to receive signals from a bus matching a path pattern.

  The subscription dispatches signals directly to the agent's server process.
  """
  @spec subscribe_agent_to_bus(agent_context(), pid(), String.t()) :: :ok
  def subscribe_agent_to_bus(%{server_pid: server_pid, agent: agent} = _context, bus, path) do
    dispatch_config = {:pid, target: server_pid, delivery_mode: :async}

    {:ok, _subscription_id} =
      Jido.Signal.Bus.subscribe(
        bus,
        path,
        dispatch: dispatch_config,
        subscriber_id: agent.id
      )

    :ok
  end

  defp default_producer_routes do
    [
      TestSupport.create_test_route(
        "root_signal_action",
        ProducerAgent.RootSignalAction
      )
    ]
  end

  defp default_consumer_routes do
    [
      TestSupport.create_test_route(
        "child.event",
        ConsumerAgent.ChildEventAction
      )
    ]
  end

  defp validate_agent_module!(module) do
    module
    |> validate_module_type!()
    |> validate_module_loadable!()
    |> validate_agent_behavior!()
    |> validate_new_function!()
  end

  defp validate_module_type!(module) do
    unless is_atom(module) do
      raise ArgumentError, "Expected agent module, got: #{inspect(module)}"
    end

    module
  end

  defp validate_module_loadable!(module) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "Agent module #{inspect(module)} could not be loaded"
    end

    module
  end

  defp validate_agent_behavior!(module) do
    unless function_exported?(module, :__agent_metadata__, 0) do
      raise ArgumentError,
            "Agent module #{inspect(module)} does not implement the Jido.Agent behavior (missing __agent_metadata__/0)"
    end

    module
  end

  defp validate_new_function!(module) do
    try do
      test_agent = module.new("test_#{System.unique_integer()}")

      unless is_struct(test_agent) do
        raise ArgumentError, "Agent module #{inspect(module)} new/1 did not return a struct"
      end

      module
    rescue
      UndefinedFunctionError ->
        reraise ArgumentError.exception(
                  "Agent module #{inspect(module)} does not implement new/1"
                ),
                __STACKTRACE__

      e ->
        reraise ArgumentError.exception(
                  "Agent module #{inspect(module)} new/1 failed: #{Exception.message(e)}"
                ),
                __STACKTRACE__
    end
  end

  defp validate_process!(pid) do
    unless Process.alive?(pid) do
      raise RuntimeError, "Agent process is not alive"
    end
  end

  defp stop_test_agent(%{server_pid: pid}) when is_pid(pid),
    do: TestSupport.cleanup_agent(%{pid: pid})

  defp maybe_process_queue(server_pid) do
    {:ok, state} = Server.state(server_pid)

    if state.mode != :auto do
      _ = GenServer.call(server_pid, :process_queue)
    end
  end

  # Bus Spy Functions - for observing signals crossing process boundaries

  @doc """
  Start a bus spy to observe signals crossing process boundaries via the signal bus.

  Returns a spy reference that can be used with other bus spy functions.
  The spy will automatically be stopped when the test finishes.

  ## Examples

      test "cross-process signal observation" do
        spy = start_bus_spy()
        
        %{producer: producer, consumer: consumer} = setup_cross_process_agents()
        send_signal_sync(producer, :root, %{test_data: "cross-process"})
        wait_for_cross_process_completion([consumer])
        
        # Verify the signal was observed crossing the bus
        assert_bus_signal_observed(spy, "child.event")
        
        dispatched_signals = get_spy_signals(spy)
        assert length(dispatched_signals) > 0
      end
  """
  @spec start_bus_spy() :: pid()
  def start_bus_spy do
    spy = Jido.Signal.BusSpy.start_spy()

    ExUnit.Callbacks.on_exit(fn ->
      try do
        Jido.Signal.BusSpy.stop_spy(spy)
      catch
        :exit, _ -> :ok
      end
    end)

    spy
  end

  @doc """
  Stop a bus spy and clean up telemetry handlers.
  """
  @spec stop_bus_spy(pid()) :: :ok
  def stop_bus_spy(spy_ref) do
    Jido.Signal.BusSpy.stop_spy(spy_ref)
  end

  @doc """
  Get all signals captured by the bus spy since it started.

  Returns signals in chronological order (oldest first).

  ## Examples

      spy = start_bus_spy()
      # ... perform cross-process operations ...
      all_signals = get_spy_signals(spy)
      assert length(all_signals) == 2
  """
  @spec get_spy_signals(pid()) :: [map()]
  def get_spy_signals(spy_ref) do
    Jido.Signal.BusSpy.get_dispatched_signals(spy_ref)
  end

  @doc """
  Get signals captured by the spy that match a specific type pattern.

  Supports glob-style patterns:
  - "*" - matches all signals
  - "user.*" - matches all signals starting with "user."
  - "*.created" - matches all signals ending with ".created"
  - "user.created" - exact match

  ## Examples

      spy = start_bus_spy()
      # ... perform operations ...
      user_signals = get_spy_signals(spy, "user.*")
      child_signals = get_spy_signals(spy, "child.event")
  """
  @spec get_spy_signals(pid(), String.t()) :: [map()]
  def get_spy_signals(spy_ref, signal_type_pattern) do
    Jido.Signal.BusSpy.get_signals_by_type(spy_ref, signal_type_pattern)
  end

  @doc """
  Wait for a signal matching the given type pattern to cross the bus.

  Returns the matching signal event or times out.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)

  ## Examples

      spy = start_bus_spy()
      
      Task.start(fn ->
        # ... async operation that will emit signal ...
      end)
      
      {:ok, signal_event} = wait_for_bus_signal(spy, "async.completed")
      assert signal_event.signal.data.status == "done"
  """
  @spec wait_for_bus_signal(pid(), String.t(), keyword()) :: {:ok, map()} | :timeout
  def wait_for_bus_signal(spy_ref, signal_type_pattern, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    Jido.Signal.BusSpy.wait_for_signal(spy_ref, signal_type_pattern, timeout)
  end

  @doc """
  Assert that a signal of the given type was observed crossing the bus.

  This is a convenience function that checks if any signal matching the pattern
  has been captured by the spy.

  ## Examples

      spy = start_bus_spy()
      # ... perform cross-process operations ...
      assert_bus_signal_observed(spy, "child.event")
      assert_bus_signal_observed(spy, "user.*")
  """
  @spec assert_bus_signal_observed(pid(), String.t()) :: :ok
  def assert_bus_signal_observed(spy_ref, signal_type_pattern) do
    signals = get_spy_signals(spy_ref, signal_type_pattern)

    assert length(signals) > 0,
           "Expected to observe signal matching pattern '#{signal_type_pattern}' crossing the bus, but none were found"

    :ok
  end
end
