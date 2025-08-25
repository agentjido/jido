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

  """

  alias Jido.Agent.Server
  alias Jido.Signal
  import ExUnit.Assertions

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
