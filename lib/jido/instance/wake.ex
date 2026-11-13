defmodule Jido.Instance.Wake do
  @moduledoc false

  use GenServer
  require Logger

  alias Jido.Agent.Address
  alias Jido.Instance.Names
  alias Jido.Persistence.WakeStore

  @retry_ms 250
  @max_recovery_retry_ms 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def await_ready(instance, timeout \\ 5_000) do
    GenServer.call(Names.wake(instance), :await_ready, timeout)
  catch
    :exit, {:timeout, _call} -> {:error, :wake_recovery_timeout}
    :exit, _reason -> {:error, :wake_capability_unavailable}
  end

  def register(instance, %Address{} = address, turn_id, waits) do
    entries =
      for wait <- waits,
          option <- wait.options,
          is_integer(option.deadline),
          do: %{agent_address: address, turn_id: turn_id, wait_id: wait.id, deadline: option.deadline}

    if entries == [] do
      :ok
    else
      GenServer.call(Names.wake(instance), {:register, entries})
    end
  catch
    :exit, _reason -> {:error, :wake_capability_unavailable}
  end

  def complete(nil, _address, _turn_id), do: :ok

  def complete(instance, %Address{} = address, turn_id) do
    GenServer.cast(Names.wake(instance), {:complete, address, turn_id})
  end

  @impl true
  def init(opts) do
    state = %{
      instance: Keyword.fetch!(opts, :instance),
      timers: %{},
      ready?: false,
      recovery_attempt: 0,
      ready_waiters: []
    }

    {:ok, state, {:continue, :recover}}
  end

  @impl true
  def handle_continue(:recover, state) do
    recover(state)
  end

  @impl true
  def handle_call(:await_ready, _from, %{ready?: true} = state), do: {:reply, :ok, state}

  def handle_call(:await_ready, from, state),
    do: {:noreply, update_in(state.ready_waiters, &[from | &1])}

  def handle_call({:register, entries}, _from, state) do
    case WakeStore.put(state.instance, entries) do
      :ok -> {:reply, :ok, schedule_all(state, entries)}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:complete, address, turn_id}, state) do
    complete_turn(state, address, turn_id)
  end

  @impl true
  def handle_info({:complete_turn, address, turn_id}, state) do
    complete_turn(state, address, turn_id)
  end

  def handle_info({:cleanup_wake, entry}, state) do
    key = entry_key(entry)
    state = %{state | timers: Map.delete(state.timers, key)}

    case WakeStore.delete(state.instance, entry) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        log_cleanup_failure(state.instance, entry, reason)
        timer = Process.send_after(self(), {:cleanup_wake, entry}, @retry_ms)
        {:noreply, put_in(state.timers[key], timer)}
    end
  end

  @impl true
  def handle_info(:recover, state), do: recover(state)

  def handle_info({:wake, entry}, state) do
    key = entry_key(entry)
    state = %{state | timers: Map.delete(state.timers, key)}

    if entry.deadline > System.system_time(:millisecond) do
      {:noreply, schedule(entry, state)}
    else
      case deliver(state.instance, entry) do
        result when result in [:ok, :stale] ->
          cleanup_wake(state, entry)

        {:error, _reason} ->
          timer = Process.send_after(self(), {:wake, entry}, @retry_ms)
          {:noreply, put_in(state.timers[key], timer)}
      end
    end
  end

  defp complete_turn(state, address, turn_id) do
    case WakeStore.delete_turn(state.instance, address, turn_id) do
      :ok ->
        {:noreply, cancel_turn_timers(state, address, turn_id)}

      {:error, reason} ->
        Logger.warning("Jido wake cleanup failed; retrying",
          instance: state.instance,
          turn_id: turn_id,
          reason: inspect(reason)
        )

        Process.send_after(self(), {:complete_turn, address, turn_id}, @retry_ms)
        {:noreply, state}
    end
  end

  defp cancel_turn_timers(state, address, turn_id) do
    timers =
      Enum.reduce(state.timers, state.timers, fn {key, timer}, timers ->
        case key do
          {^address, ^turn_id, _wait_id, _deadline} ->
            Process.cancel_timer(timer)
            Map.delete(timers, key)

          _ ->
            timers
        end
      end)

    %{state | timers: timers}
  end

  defp cleanup_wake(state, entry) do
    case WakeStore.delete(state.instance, entry) do
      :ok ->
        {:noreply, state}

      {:error, reason} ->
        log_cleanup_failure(state.instance, entry, reason)
        key = entry_key(entry)
        timer = Process.send_after(self(), {:cleanup_wake, entry}, @retry_ms)
        {:noreply, put_in(state.timers[key], timer)}
    end
  end

  defp log_cleanup_failure(instance, entry, reason) do
    Logger.warning("Jido wake cleanup failed; retrying",
      instance: instance,
      turn_id: entry.turn_id,
      wait_id: entry.wait_id,
      reason: inspect(reason)
    )
  end

  defp recover(state) do
    case WakeStore.list(state.instance) do
      {:ok, entries} ->
        Enum.each(state.ready_waiters, &GenServer.reply(&1, :ok))

        state =
          state
          |> Map.put(:ready?, true)
          |> Map.put(:recovery_attempt, 0)
          |> Map.put(:ready_waiters, [])
          |> schedule_all(entries)

        {:noreply, state}

      {:error, reason} ->
        attempt = state.recovery_attempt + 1
        retry_ms = min(@retry_ms * Integer.pow(2, min(attempt - 1, 5)), @max_recovery_retry_ms)

        Logger.warning("Jido wake recovery failed; retrying",
          instance: state.instance,
          attempt: attempt,
          retry_ms: retry_ms,
          reason: inspect(reason)
        )

        Process.send_after(self(), :recover, retry_ms)
        {:noreply, %{state | recovery_attempt: attempt}}
    end
  end

  defp schedule_all(state, entries), do: Enum.reduce(entries, state, &schedule/2)

  defp schedule(entry, state) do
    key = entry_key(entry)

    if Map.has_key?(state.timers, key) do
      state
    else
      delay = max(0, entry.deadline - System.system_time(:millisecond))
      timer = Process.send_after(self(), {:wake, entry}, min(delay, 4_294_967_295))
      put_in(state.timers[key], timer)
    end
  end

  defp deliver(instance, entry) do
    signal =
      Jido.Signal.new!(
        "jido.durable.wake",
        %{turn_id: entry.turn_id, wait_id: entry.wait_id, deadline: entry.deadline},
        id: wake_id(entry),
        source: "/jido/instance/wake"
      )

    case Jido.call(instance, entry.agent_address, signal) do
      {:ok, %Jido.AgentServer.TurnResult{}} -> :ok
      {:error, reason} when reason in [:stale_wait, :wait_not_matched, :deleted, :not_found] -> :stale
      {:error, _reason} = error -> error
    end
  end

  defp wake_id(entry) do
    entry
    |> entry_key()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp entry_key(entry),
    do: {entry.agent_address, entry.turn_id, entry.wait_id, entry.deadline}
end
