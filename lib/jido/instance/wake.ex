defmodule Jido.Instance.Wake do
  @moduledoc false

  use GenServer

  alias Jido.Agent.Ref
  alias Jido.Instance.Names
  alias Jido.Persistence.WakeStore

  @retry_ms 250

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def register(instance, %Ref{} = ref, turn_id, waits) do
    entries =
      for wait <- waits,
          option <- wait.options,
          is_integer(option.deadline),
          do: %{agent_ref: ref, turn_id: turn_id, wait_id: wait.id, deadline: option.deadline}

    if entries == [] do
      :ok
    else
      GenServer.call(Names.wake(instance), {:register, entries})
    end
  catch
    :exit, _reason -> {:error, :wake_capability_unavailable}
  end

  def complete(nil, _ref, _turn_id), do: :ok

  def complete(instance, %Ref{} = ref, turn_id) do
    GenServer.cast(Names.wake(instance), {:complete, ref, turn_id})
  end

  @impl true
  def init(opts) do
    state = %{instance: Keyword.fetch!(opts, :instance), timers: %{}}
    {:ok, state, {:continue, :recover}}
  end

  @impl true
  def handle_continue(:recover, state) do
    case WakeStore.list(state.instance) do
      {:ok, entries} -> {:noreply, schedule_all(state, entries)}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_call({:register, entries}, _from, state) do
    case WakeStore.put(state.instance, entries) do
      :ok -> {:reply, :ok, schedule_all(state, entries)}
      {:error, _reason} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:complete, ref, turn_id}, state) do
    _ = WakeStore.delete_turn(state.instance, ref, turn_id)

    timers =
      Enum.reduce(state.timers, state.timers, fn {key, timer}, timers ->
        case key do
          {^ref, ^turn_id, _wait_id, _deadline} ->
            Process.cancel_timer(timer)
            Map.delete(timers, key)

          _ ->
            timers
        end
      end)

    {:noreply, %{state | timers: timers}}
  end

  @impl true
  def handle_info({:wake, entry}, state) do
    key = entry_key(entry)
    state = %{state | timers: Map.delete(state.timers, key)}

    if entry.deadline > System.system_time(:millisecond) do
      {:noreply, schedule(entry, state)}
    else
      case deliver(state.instance, entry) do
        :ok ->
          _ = WakeStore.delete(state.instance, entry)
          {:noreply, state}

        {:error, _reason} ->
          timer = Process.send_after(self(), {:wake, entry}, @retry_ms)
          {:noreply, put_in(state.timers[key], timer)}
      end
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

    case Jido.call(instance, entry.agent_ref, signal) do
      {:ok, %Jido.AgentServer.TurnResult{}} -> :ok
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
    do: {entry.agent_ref, entry.turn_id, entry.wait_id, entry.deadline}
end
