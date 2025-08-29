defmodule JidoTest.Support do
  @moduledoc """
  Common test utilities and helpers for reducing duplication across Jido test files.

  This module provides functions for:
  - Starting unique test registries
  - Generating unique agent IDs
  - Starting basic agents with proper cleanup
  - Common setup patterns used across tests
  """

  import ExUnit.Assertions
  alias Jido.Agent.Server
  alias Jido.Signal
  alias JidoTest.TestAgents.BasicAgent

  @doc """
  Starts a unique registry for tests.

  Returns `{:ok, registry_name}` where `registry_name` is a unique atom
  that can be used for test isolation.

  ## Examples

      {:ok, registry} = JidoTest.Support.start_registry!()
      {:ok, pid} = Server.start_link(agent: BasicAgent, registry: registry)
  """
  @spec start_registry!() :: {:ok, atom()}
  def start_registry! do
    registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _pid} = Registry.start_link(keys: :unique, name: registry_name)
    {:ok, registry_name}
  end

  @doc """
  Generates a unique ID with optional prefix.

  ## Examples

      id = JidoTest.Support.unique_id("agent")
      # => "agent-123456789"

      id = JidoTest.Support.unique_id()
      # => "test-123456789"
  """
  @spec unique_id(String.t()) :: String.t()
  def unique_id(prefix \\ "test") do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  @doc """
  Starts a basic agent with default options and automatic cleanup.

  Returns `{:ok, %{pid: pid, agent: agent, registry: registry}}` for easy chaining.

  ## Options

  - `:agent_module` - Agent module to use (default: BasicAgent)
  - `:id` - Agent ID (default: generated unique ID)
  - `:registry` - Registry to use (default: creates new one)
  - `:mode` - Server mode (default: :step for predictable testing)
  - `:initial_state` - Initial agent state
  - `:actions` - Additional actions to register
  - `:cleanup` - Whether to setup automatic cleanup (default: true)

  ## Examples

      {:ok, context} = JidoTest.Support.start_basic_agent!()
      {:ok, state} = Server.state(context.pid)

      {:ok, context} = JidoTest.Support.start_basic_agent!(
        id: "my-agent",
        initial_state: %{battery_level: 50},
        cleanup: false
      )
  """
  @spec start_basic_agent!(keyword()) :: {:ok, map()}
  def start_basic_agent!(opts \\ []) do
    agent_module = Keyword.get(opts, :agent_module, BasicAgent)
    agent_id = Keyword.get(opts, :id, unique_id("test-agent"))
    registry = Keyword.get(opts, :registry, nil)
    mode = Keyword.get(opts, :mode, :step)
    initial_state = Keyword.get(opts, :initial_state, %{})
    actions = Keyword.get(opts, :actions, [])
    cleanup = Keyword.get(opts, :cleanup, true)

    # Create registry if not provided
    registry =
      if registry do
        registry
      else
        {:ok, reg} = start_registry!()
        reg
      end

    # Create agent with initial state
    agent = agent_module.new(agent_id, initial_state)

    # Start server
    server_opts = [
      agent: agent,
      id: agent_id,
      registry: registry,
      mode: mode
    ]

    server_opts =
      if actions != [], do: Keyword.put(server_opts, :actions, actions), else: server_opts

    {:ok, pid} = Server.start_link(server_opts)

    context = %{
      pid: pid,
      agent: agent,
      registry: registry,
      id: agent_id
    }

    # Setup cleanup if requested
    if cleanup do
      ExUnit.Callbacks.on_exit(fn -> cleanup_agent(context) end)
    end

    {:ok, context}
  end

  @doc """
  Creates a test signal with default values.

  ## Examples

      {:ok, signal} = JidoTest.Support.create_test_signal("user.registered")
      {:ok, signal} = JidoTest.Support.create_test_signal("test_signal", %{user_id: 123})
      {:ok, signal} = JidoTest.Support.create_test_signal("test", %{}, source: "custom")
  """
  @spec create_test_signal(String.t(), map(), keyword()) :: {:ok, Signal.t()}
  def create_test_signal(type, data \\ %{}, opts \\ []) do
    source = Keyword.get(opts, :source, "test-source")
    subject = Keyword.get(opts, :subject, "test-subject")
    dispatch = Keyword.get(opts, :dispatch, {:logger, []})

    Signal.new(%{
      type: type,
      data: data,
      source: source,
      subject: subject,
      jido_dispatch: dispatch
    })
  end

  @doc """
  Sends a signal to an agent and waits for processing to complete.

  This is useful for predictable testing where you need to ensure
  the signal has been processed before making assertions.

  ## Examples

      {:ok, context} = JidoTest.Support.start_basic_agent!()
      :ok = JidoTest.Support.send_signal_sync(context, "test_signal", %{value: 42})
  """
  @spec send_signal_sync(map(), String.t(), map(), keyword()) :: :ok
  def send_signal_sync(%{pid: pid} = _context, signal_type, data \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)

    {:ok, signal} = create_test_signal(signal_type, data)
    {:ok, _correlation_id} = Server.cast(pid, signal)

    # Wait a bit for processing in step mode
    if timeout > 0, do: Process.sleep(10)
    :ok
  end

  @doc """
  Waits for an agent to reach a specific status.

  ## Examples

      JidoTest.Support.wait_for_status(context, :idle)
      JidoTest.Support.wait_for_status(context, :running, timeout: 2000)
  """
  @spec wait_for_status(map(), atom(), keyword()) :: :ok
  def wait_for_status(%{pid: pid} = _context, expected_status, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        {:ok, state} = Server.state(pid)
        assert state.status == expected_status
      end,
      timeout: timeout,
      check_interval: check_interval
    )
  end

  @doc """
  Sets up a test registry in the test context.

  This can be used in setup blocks to provide a registry for all tests.

  ## Examples

      setup do
        JidoTest.Support.setup_test_registry()
      end

      test "my test", %{registry: registry} do
        # use registry...
      end
  """
  @spec setup_test_registry() :: %{registry: atom()}
  def setup_test_registry do
    {:ok, registry} = start_registry!()
    %{registry: registry}
  end

  @doc """
  Sets up a basic agent context for tests.

  Combines registry setup and agent creation into a single helper.

  ## Examples

      setup do
        JidoTest.Support.setup_basic_agent()
      end

      test "my test", %{agent_context: context} do
        # use context.pid, context.registry, etc.
      end
  """
  @spec setup_basic_agent(keyword()) :: %{agent_context: map(), registry: atom()}
  def setup_basic_agent(opts \\ []) do
    {:ok, context} = start_basic_agent!(opts)
    %{agent_context: context, registry: context.registry}
  end

  @doc """
  Creates a test route for signal routing.

  ## Examples

      route = JidoTest.Support.create_test_route("test_signal", BasicAction)
      routes = [
        JidoTest.Support.create_test_route("user.*", UserAction),
        JidoTest.Support.create_test_route("system.status", StatusAction)
      ]
  """
  def create_test_route(path, action_module, params \\ %{}) do
    %Jido.Signal.Router.Route{
      path: path,
      target: %Jido.Instruction{
        action: action_module,
        params: params
      }
    }
  end

  @doc """
  Asserts that an agent's state contains the expected values.

  Only checks the specified keys, allowing for partial state assertions.

  ## Examples

      JidoTest.Support.assert_agent_state(context, %{location: :office})
      JidoTest.Support.assert_agent_state(context, battery_level: 75, location: :home)
  """
  def assert_agent_state(context, expected_state) when is_list(expected_state) do
    assert_agent_state(context, Enum.into(expected_state, %{}))
  end

  def assert_agent_state(%{pid: pid}, expected_state) when is_map(expected_state) do
    {:ok, state} = Server.state(pid)
    actual_state = state.agent.state

    Enum.each(expected_state, fn {key, expected_value} ->
      actual_value = Map.get(actual_state, key)

      assert actual_value == expected_value,
             "Expected agent state #{inspect(key)} to be #{inspect(expected_value)}, got #{inspect(actual_value)}"
    end)

    :ok
  end

  @doc """
  Asserts that an agent's signal queue is empty.

  ## Examples

      JidoTest.Support.assert_queue_empty(context)
  """
  def assert_queue_empty(%{pid: pid}) do
    {:ok, state} = Server.state(pid)
    assert :queue.is_empty(state.pending_signals), "Expected queue to be empty"
    :ok
  end

  @doc """
  Asserts that an agent's signal queue has the expected size.

  ## Examples

      JidoTest.Support.assert_queue_size(context, 2)
  """
  def assert_queue_size(%{pid: pid}, expected_size) do
    {:ok, state} = Server.state(pid)
    actual_size = :queue.len(state.pending_signals)

    assert actual_size == expected_size,
           "Expected queue size to be #{expected_size}, got #{actual_size}"

    :ok
  end

  @doc """
  Retrieves the current agent state from a context.

  ## Examples

      state = JidoTest.Support.get_agent_state(context)
      assert state.battery_level == 100
  """
  def get_agent_state(%{pid: pid}) do
    {:ok, state} = Server.state(pid)
    state.agent.state
  end

  @doc """
  Stops and cleans up an agent context.

  This is automatically called if cleanup is enabled (default: true)
  when using `start_basic_agent!/1`.
  """
  def cleanup_agent(%{pid: pid}) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end
  end

  @doc """
  Creates multiple test agents with unique IDs.

  ## Examples

      contexts = JidoTest.Support.create_test_agents(3)
      # => [%{pid: pid1, ...}, %{pid: pid2, ...}, %{pid: pid3, ...}]

      contexts = JidoTest.Support.create_test_agents(2, prefix: "worker")
      # => Agents with IDs "worker-1", "worker-2"
  """
  @spec create_test_agents(pos_integer(), keyword()) :: [map()]
  def create_test_agents(count, opts \\ []) when count > 0 do
    prefix = Keyword.get(opts, :prefix, "agent")
    base_opts = Keyword.drop(opts, [:prefix])

    1..count
    |> Enum.map(fn n ->
      agent_opts = Keyword.put(base_opts, :id, "#{prefix}-#{n}")
      {:ok, context} = start_basic_agent!(agent_opts)
      context
    end)
  end

  @doc """
  Waits for all agents in a list to reach the specified status.

  ## Examples

      contexts = JidoTest.Support.create_test_agents(3)
      JidoTest.Support.wait_for_all_agents(contexts, :idle)
  """
  def wait_for_all_agents(contexts, status, opts \\ []) do
    Enum.each(contexts, fn context ->
      wait_for_status(context, status, opts)
    end)
  end

  @doc """
  Stops multiple test agents.

  ## Examples

      contexts = JidoTest.Support.create_test_agents(3)
      JidoTest.Support.stop_test_agents(contexts)
  """
  def stop_test_agents(contexts) when is_list(contexts) do
    Enum.each(contexts, &cleanup_agent/1)
  end
end
