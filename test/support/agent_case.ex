defmodule JidoTest.AgentCase do
  @moduledoc """
  DSL for testing Jido agents with pipeline syntax.

  ## Quick Start

      test "user registration flow" do
        spawn_agent(MyAgent)
        |> send_signal("user.registered", %{id: 123})
        |> send_signal("profile.completed", %{name: "John"})
        |> send_signal("email.verified")
      end

  ## Available Functions

  - `spawn_agent/2` - Spawn an agent with automatic cleanup
  - `send_signal/3` - Send a signal and return context for chaining

  """

  alias Jido.Agent.Server
  alias Jido.Signal

  @type agent_context :: %{agent: struct(), server_pid: pid()}
  @type agent_or_context :: agent_context() | struct()

  @doc """
  Spawn an agent for testing with automatic cleanup.

  Returns a context that can be chained with `send_signal/3`.
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
  Send a signal to an agent and return context for chaining.
  """
  @spec send_signal(agent_or_context(), String.t(), map()) :: agent_context()
  def send_signal(context, signal_type, data \\ %{})

  def send_signal(%{agent: agent, server_pid: server_pid} = context, signal_type, data)
      when is_binary(signal_type) and is_map(data) do
    validate_process!(server_pid)

    {:ok, signal} = Signal.new(%{type: signal_type, data: data, source: "test", target: agent.id})
    {:ok, _} = Server.cast(server_pid, signal)

    context
  end

  def send_signal(agent, signal_type, data) when is_struct(agent) do
    # Handle direct agent struct - look up server by agent ID
    case Jido.resolve_pid(agent.id) do
      {:ok, server_pid} ->
        send_signal(%{agent: agent, server_pid: server_pid}, signal_type, data)

      {:error, _reason} ->
        raise "Agent server not found for ID: #{agent.id}"
    end
  end

  defp validate_agent_module!(module) do
    unless is_atom(module) and function_exported?(module, :new, 1) do
      raise ArgumentError, "Expected agent module with new/1 function, got: #{inspect(module)}"
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
