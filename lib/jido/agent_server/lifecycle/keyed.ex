defmodule Jido.AgentServer.Lifecycle.Keyed do
  @moduledoc """
  Lifecycle implementation for keyed/pooled agents.

  Handles:
  - Attachment tracking (attach/detach/monitor owner processes)
  - Idle timer management (start/cancel/reset)
  - Hibernate on shutdown (calls `Jido.Persist`)

  ## State

  Adds a `lifecycle` sub-map to server state with:
  - `attachments` - MapSet of attached pids
  - `attachment_monitors` - Map of ref => pid
  - `idle_timer` - timer reference or nil
  - `idle_timeout` - timeout value in milliseconds
  - `pool` - pool name (for logging)
  - `pool_key` - pool key
  - `storage` - storage config for persistence

  ## Events

  - `{:attach, pid}` - attach a process
  - `{:detach, pid}` - detach a process
  - `:touch` - reset idle timer
  - `{:down, ref, pid}` - handle monitor DOWN
  - `:idle_timeout` - handle idle timeout
  """

  @behaviour Jido.AgentServer.Lifecycle

  require Logger

  alias Jido.Persist

  @impl true
  def init(_opts, state) do
    state = maybe_restore_agent_from_storage(state)

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
  def persist_cron_specs(state, cron_specs) when is_map(cron_specs) do
    lifecycle = state.lifecycle

    if lifecycle.storage do
      persistence_key = persistence_key(state)
      agent = attach_cron_specs(state.agent, cron_specs)

      Persist.persist_scheduler_manifest(
        lifecycle.storage,
        state.agent_module,
        persistence_key,
        agent,
        cron_specs
      )
    else
      :ok
    end
  end

  @impl true
  def terminate(reason, state) do
    lifecycle = state.lifecycle

    if clean_shutdown?(reason) && lifecycle.storage do
      hibernate_agent(state)
    end

    :ok
  end

  defp clean_shutdown?(:normal), do: true
  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _}), do: true
  defp clean_shutdown?(_), do: false

  defp maybe_restore_agent_from_storage(state) do
    lifecycle = state.lifecycle

    cond do
      state.restored_from_storage ->
        state

      is_nil(lifecycle.storage) ->
        state

      map_size(state.cron_specs) > 0 ->
        state

      true ->
        persistence_key = persistence_key(state)

        case Persist.thaw(lifecycle.storage, state.agent_module, persistence_key) do
          {:ok, restored_agent} ->
            {restored_agent, restored_cron_specs} = extract_cron_specs(restored_agent)
            %{state | agent: restored_agent, cron_specs: restored_cron_specs}

          {:error, :not_found} ->
            state

          {:error, reason} ->
            Logger.warning(
              "Lifecycle restore failed for #{lifecycle.pool}/#{inspect(lifecycle.pool_key)}: #{inspect(reason)}"
            )

            state
        end
    end
  end

  defp hibernate_agent(state) do
    lifecycle = state.lifecycle
    storage = lifecycle.storage
    pool_key = lifecycle.pool_key
    persistence_key = persistence_key(state)
    agent = Jido.Scheduler.attach_staged_cron_specs(state.agent, state.cron_specs)
    agent_module = state.agent_module

    case Persist.hibernate(storage, agent_module, persistence_key, agent) do
      :ok ->
        Logger.debug("Lifecycle hibernated agent for #{lifecycle.pool}/#{inspect(pool_key)}")

      {:error, reason} ->
        Logger.error(
          "Lifecycle hibernate failed for #{lifecycle.pool}/#{inspect(pool_key)}: #{inspect(reason)}"
        )
    end
  end

  defp persistence_key(state) do
    Jido.partition_key({state.lifecycle.pool, state.lifecycle.pool_key}, state.partition)
  end

  defp attach_cron_specs(agent, cron_specs) when is_map(cron_specs) do
    Jido.Scheduler.attach_staged_cron_specs(agent, cron_specs)
  end

  defp extract_cron_specs(%{id: agent_id} = agent) do
    {cleaned_agent, staged_cron_specs} = Jido.Scheduler.extract_staged_cron_specs(agent)
    {cron_specs, invalid_cron_specs} = Jido.Scheduler.classify_cron_specs(staged_cron_specs)

    Enum.each(invalid_cron_specs, fn {job_id, spec, reason} ->
      Logger.error(
        "Lifecycle dropped malformed persisted cron spec #{inspect(job_id)} for #{inspect(agent_id)}: #{inspect(spec)} (#{inspect(reason)})"
      )
    end)

    {cleaned_agent, cron_specs}
  end

  defp extract_cron_specs(agent), do: {agent, %{}}

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
      %{state | lifecycle: %{lifecycle | idle_timer: nil}}
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
end
