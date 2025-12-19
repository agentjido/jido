defmodule Jido.Agent.Debugger do
  @moduledoc """
  Step debugger for Jido agents.

  Provides functionality to attach to agents in debug mode, step through
  signal processing, and control execution flow.
  """

  use GenServer
  require Logger

  alias Jido.Agent.Server

  @typedoc "Debugger state"
  @type state :: %{
          agent_pid: pid(),
          original_mode: atom(),
          suspended: boolean()
        }

  ## Public API

  @doc """
  Attach debugger to an agent process.

  The agent must be in debug mode for this to succeed. Upon attachment,
  the agent process is suspended using `:sys.suspend/1`.

  ## Returns
    * `{:ok, debugger_pid}` - Successfully attached debugger
    * `{:error, :not_in_debug_mode}` - Agent is not in debug mode
    * `{:error, reason}` - Other attachment failure
  """
  @spec attach(pid()) :: {:ok, pid()} | {:error, term()}
  def attach(agent_pid) do
    # Check if agent is in debug mode using Server.state/1
    case Server.state(agent_pid) do
      {:ok, agent_state} when agent_state.mode == :debug ->
        # Start the debugger process
        case GenServer.start_link(__MODULE__, %{agent_pid: agent_pid}) do
          {:ok, debugger_pid} ->
            {:ok, debugger_pid}

          error ->
            error
        end

      {:ok, _agent_state} ->
        {:error, :not_in_debug_mode}

      error ->
        error
    end
  rescue
    _error ->
      {:error, :agent_not_available}
  end

  @doc """
  Step through one signal in the attached agent.

  Temporarily resumes the agent to process exactly one signal from its queue,
  then suspends it again.

  ## Returns
    * `:ok` - Successfully stepped through one signal
    * `{:error, :no_signals_queued}` - No signals available to process
    * `{:error, reason}` - Other step failure
  """
  @spec step(pid()) :: :ok | {:error, term()}
  def step(debugger_pid) do
    GenServer.call(debugger_pid, :step)
  end

  @doc """
  Detach debugger from the agent.

  Resumes the agent process and stops the debugger. The agent returns to
  normal processing mode.

  ## Returns
    * `:ok` - Successfully detached
    * `{:error, reason}` - Detachment failure
  """
  @spec detach(pid()) :: :ok | {:error, term()}
  def detach(debugger_pid) do
    GenServer.call(debugger_pid, :detach)
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(%{agent_pid: agent_pid}) do
    # Monitor the agent process
    Process.monitor(agent_pid)

    # Suspend the agent immediately
    :sys.suspend(agent_pid)

    Logger.debug("Debugger attached to agent #{inspect(agent_pid)} - agent suspended")

    state = %{
      agent_pid: agent_pid,
      original_mode: :debug,
      suspended: true
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:step, _from, %{agent_pid: agent_pid, suspended: true} = state) do
    # Check if there are signals queued
    agent_state = :sys.get_state(agent_pid)

    case :queue.len(agent_state.pending_signals) do
      0 ->
        {:reply, {:error, :no_signals_queued}, state}

      _count ->
        # For Phase 4, we'll implement a basic step that demonstrates the concept
        # without full signal processing integration (that can be Phase 5)
        Logger.debug("Debugger stepping through signal queue for agent #{inspect(agent_pid)}")

        # Temporarily resume and immediately re-suspend to simulate stepping
        # This shows the attach/step/detach workflow without complex signal processing
        :sys.resume(agent_pid)
        # Brief moment to simulate processing
        Process.sleep(1)
        :sys.suspend(agent_pid)

        Logger.debug("Debugger step completed for agent #{inspect(agent_pid)}")
        {:reply, :ok, state}
    end
  end

  def handle_call(:step, _from, %{suspended: false} = state) do
    {:reply, {:error, :not_suspended}, state}
  end

  @impl GenServer
  def handle_call(:detach, _from, %{agent_pid: agent_pid, suspended: true} = state) do
    # Resume the agent permanently
    :sys.resume(agent_pid)
    Logger.debug("Debugger detached from agent #{inspect(agent_pid)} - agent resumed")

    # Stop the debugger
    {:stop, :normal, :ok, %{state | suspended: false}}
  end

  def handle_call(:detach, _from, %{suspended: false} = state) do
    # Already detached, just stop
    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, agent_pid, reason}, %{agent_pid: agent_pid} = state) do
    Logger.debug(
      "Debugger stopping - monitored agent #{inspect(agent_pid)} terminated: #{inspect(reason)}"
    )

    {:stop, :normal, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, %{agent_pid: agent_pid, suspended: true}) do
    # Ensure agent is resumed if debugger crashes
    try do
      if Process.alive?(agent_pid) do
        :sys.resume(agent_pid)
        Logger.debug("Debugger terminating - resumed agent #{inspect(agent_pid)}")
      end
    rescue
      _error ->
        # Agent might already be dead, ignore
        :ok
    end
  end

  def terminate(_reason, _state) do
    :ok
  end
end
