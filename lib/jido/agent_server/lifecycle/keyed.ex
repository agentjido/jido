defmodule Jido.AgentServer.Lifecycle.Keyed do
  @moduledoc """
  Lifecycle implementation for keyed/pooled agents.

  Handles:
  - Attachment tracking (attach/detach/monitor owner processes)
  - Idle timer management (start/cancel/reset)
  - Hibernate on shutdown (calls Jido.Persist)

  ## State

  Adds a `lifecycle` sub-map to server state with:
  - `attachments` - MapSet of attached pids
  - `attachment_monitors` - Map of ref => pid
  - `idle_timer` - timer reference or nil
  - `idle_timeout` - timeout value in milliseconds
  - `pool` - pool name (for logging)
  - `pool_key` - pool key
  - `storage` - storage config

  ## Events

  - `{:attach, pid}` - attach a process
  - `{:detach, pid}` - detach a process
  - `:touch` - reset idle timer
  - `{:down, ref, pid}` - handle monitor DOWN
  - `:idle_timeout` - handle idle timeout
  """

  @behaviour Jido.AgentServer.Lifecycle

  require Logger

  alias Jido.AgentServer.State.Lifecycle, as: LifecycleState
  alias Jido.Persist

  @impl true
  def init(_lifecycle, state) do
    # The lifecycle struct is already populated by State.from_options
    # Just start the idle timer if appropriate
    maybe_start_idle_timer(state)
  end

  @impl true
  def handle_event({:attach, pid}, state) do
    lifecycle = state.lifecycle

    if MapSet.member?(lifecycle.attachments, pid) do
      {:cont, state}
    else
      ref = Process.monitor(pid)

      new_lifecycle = %{
        lifecycle
        | attachments: MapSet.put(lifecycle.attachments, pid),
          attachment_monitors: Map.put(lifecycle.attachment_monitors, ref, pid)
      }

      state = %{state | lifecycle: new_lifecycle}
      state = cancel_idle_timer(state)

      Logger.debug(
        "Lifecycle attached pid #{inspect(pid)} to #{lifecycle.pool}/#{inspect(lifecycle.pool_key)}"
      )

      {:cont, state}
    end
  end

  def handle_event({:detach, pid}, state) do
    lifecycle = state.lifecycle

    if MapSet.member?(lifecycle.attachments, pid) do
      {ref, monitors} = pop_monitor_by_pid(lifecycle.attachment_monitors, pid)

      if ref do
        Process.demonitor(ref, [:flush])
      end

      new_lifecycle = %{
        lifecycle
        | attachments: MapSet.delete(lifecycle.attachments, pid),
          attachment_monitors: monitors
      }

      state = %{state | lifecycle: new_lifecycle}

      Logger.debug(
        "Lifecycle detached pid #{inspect(pid)} from #{lifecycle.pool}/#{inspect(lifecycle.pool_key)}"
      )

      if MapSet.size(new_lifecycle.attachments) == 0 do
        {:cont, maybe_start_idle_timer(state)}
      else
        {:cont, state}
      end
    else
      {:cont, state}
    end
  end

  def handle_event(:touch, state) do
    state = cancel_idle_timer(state)
    {:cont, maybe_start_idle_timer(state)}
  end

  def handle_event({:down, ref, pid}, state) do
    lifecycle = state.lifecycle

    case Map.get(lifecycle.attachment_monitors, ref) do
      ^pid ->
        new_lifecycle = %{
          lifecycle
          | attachments: MapSet.delete(lifecycle.attachments, pid),
            attachment_monitors: Map.delete(lifecycle.attachment_monitors, ref)
        }

        state = %{state | lifecycle: new_lifecycle}

        Logger.debug(
          "Lifecycle owner #{inspect(pid)} down for #{lifecycle.pool}/#{inspect(lifecycle.pool_key)}"
        )

        if MapSet.size(new_lifecycle.attachments) == 0 do
          {:cont, maybe_start_idle_timer(state)}
        else
          {:cont, state}
        end

      _ ->
        {:cont, state}
    end
  end

  def handle_event(:idle_timeout, state) do
    lifecycle = state.lifecycle

    Logger.debug("Lifecycle idle timeout for #{lifecycle.pool}/#{inspect(lifecycle.pool_key)}")

    {:stop, {:shutdown, :idle_timeout}, state}
  end

  def handle_event(_event, state) do
    {:cont, state}
  end

  @impl true
  def terminate(reason, state) do
    lifecycle = state.lifecycle

    cleanup_runtime_refs(lifecycle)

    if clean_shutdown?(reason) && lifecycle.storage do
      hibernate_agent(state)
    end

    :ok
  end

  defp clean_shutdown?(:normal), do: true
  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _}), do: true
  defp clean_shutdown?(_), do: false

  defp hibernate_agent(state) do
    lifecycle = state.lifecycle
    storage = lifecycle.storage
    pool_key = lifecycle.pool_key
    agent = state.agent

    case Persist.hibernate(storage, agent) do
      :ok ->
        Logger.debug("Lifecycle hibernated agent for #{lifecycle.pool}/#{inspect(pool_key)}")

      {:error, reason} ->
        Logger.error(
          "Lifecycle hibernate failed for #{lifecycle.pool}/#{inspect(pool_key)}: #{inspect(reason)}"
        )
    end

    :ok
  end

  defp maybe_start_idle_timer(state) do
    lifecycle = state.lifecycle
    timeout = lifecycle.idle_timeout

    cond do
      timeout == :infinity or timeout == nil ->
        state

      MapSet.size(lifecycle.attachments) == 0 and is_integer(timeout) and timeout > 0 ->
        # Use a timer ref so stale timeout messages can be ignored safely.
        timer_ref = :erlang.start_timer(timeout, self(), :lifecycle_idle_timeout)
        %{state | lifecycle: %{lifecycle | idle_timer: timer_ref}}

      true ->
        state
    end
  end

  defp cancel_idle_timer(state) do
    lifecycle = state.lifecycle

    if lifecycle.idle_timer do
      :erlang.cancel_timer(lifecycle.idle_timer)
      %{state | lifecycle: LifecycleState.clear_idle_timer(lifecycle)}
    else
      state
    end
  end

  defp pop_monitor_by_pid(monitors, pid) do
    case Enum.find(monitors, fn {_ref, p} -> p == pid end) do
      {ref, _pid} -> {ref, Map.delete(monitors, ref)}
      nil -> {nil, monitors}
    end
  end

  defp cleanup_runtime_refs(lifecycle) do
    Enum.each(lifecycle.attachment_monitors, fn {ref, _pid} ->
      Process.demonitor(ref, [:flush])
    end)

    if lifecycle.idle_timer do
      :erlang.cancel_timer(lifecycle.idle_timer)
    end

    :ok
  end
end
