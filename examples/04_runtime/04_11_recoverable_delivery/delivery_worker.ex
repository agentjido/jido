defmodule Jido.Examples.RecoverableDelivery.Worker do
  @moduledoc """
  A supervised worker for the example's explicit delivery protocol.

  It reads committed Plugin state at startup and at each poll. Dispatch only
  wakes it; losing that wake-up does not lose the saved work. It attempts one
  record at a time and rotates IDs so a failed record does not starve others.
  This example uses a fixed retry interval and a bounded attempt timeout.
  """
  use GenServer

  alias Jido.Examples.RecoverableDelivery, as: Agent
  alias Jido.Examples.RecoverableDelivery.{Deliver, Sink}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init) do
    send(self(), :poll)
    {:ok, %{init: init, task: nil, timer: nil, last_id: ""}}
  end

  @impl true
  def handle_cast(:wake, state), do: {:noreply, schedule(state, 0)}

  @impl true
  def handle_info(:poll, %{task: nil} = state) do
    state = %{state | timer: nil}

    case Jido.Plugin.state(state.init) do
      {:ok, %{pending: pending}} when map_size(pending) > 0 ->
        entries = Enum.sort(pending)
        {id, value} = Enum.find(entries, fn {id, _value} -> id > state.last_id end) || hd(entries)
        init = state.init

        task = Task.async(fn -> deliver_and_confirm(init, id, value) end)

        timeout = Process.send_after(self(), {:attempt_timeout, task.ref}, 5_000)
        {:noreply, %{state | task: task, timer: timeout, last_id: id}}

      _empty_or_unavailable ->
        {:noreply, schedule(state, 100)}
    end
  end

  def handle_info({ref, _result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(state.timer)
    {:noreply, schedule(%{state | task: nil, timer: nil}, 100)}
  end

  def handle_info({:attempt_timeout, ref}, %{task: %Task{ref: ref}} = state) do
    Task.shutdown(state.task, :brutal_kill)
    {:noreply, schedule(%{state | task: nil, timer: nil}, 100)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp deliver_and_confirm(init, id, value) do
    with :ok <- Sink.deliver(init.jido, %Deliver{effect_id: id, value: value}) do
      Agent.confirm_delivery(init.agent_server, id, value)
    end
  catch
    :exit, reason -> {:error, {:delivery_unavailable, reason}}
  end

  defp schedule(%{timer: nil, task: nil} = state, delay),
    do: %{state | timer: Process.send_after(self(), :poll, delay)}

  defp schedule(state, _delay), do: state
end
