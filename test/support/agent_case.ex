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

  ## Available Functions

  - `spawn_agent/2` - Spawn an agent with automatic cleanup
  - `send_signal_async/3` - Send a signal asynchronously (may cause race conditions)
  - `send_signal_sync/3` - Send a signal and wait for idle state (prevents race conditions)
  - `assert_agent_state/2` - Assert agent state matches expected values
  - `wait_for_agent_status/3` - Wait for agent to reach specific status
  - `get_agent_state/1` - Get current agent state
  - `assert_queue_empty/1` - Assert agent's signal queue is empty
  - `assert_queue_size/2` - Assert agent's signal queue has expected size

  """

  alias Jido.Agent.Server
  alias Jido.Signal
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

    {:ok, server_pid} =
      Server.start_link(
        [
          agent: agent,
          id: agent.id,
          mode: :step,
          registry: Jido.Registry
        ] ++ opts
      )

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

    {:ok, signal} = Signal.new(%{type: signal_type, data: data, source: "test", target: agent.id})
    {:ok, _} = Server.cast(server_pid, signal)

    # Wait for agent to return to idle state
    timeout = Keyword.get(opts, :timeout, 1000)
    check_interval = Keyword.get(opts, :check_interval, 10)

    JidoTest.Helpers.Assertions.wait_for(
      fn ->
        {:ok, state_signal} =
          Signal.new(%{type: "jido.agent.cmd.state", data: %{}, source: "test", target: agent.id})

        {:ok, state} = GenServer.call(server_pid, {:signal, state_signal}, timeout)
        assert state.status == :idle
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

  defp stop_test_agent(%{server_pid: server_pid}) do
    if Process.alive?(server_pid), do: GenServer.stop(server_pid, :normal, 1000)
  end
end
