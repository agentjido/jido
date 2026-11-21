defmodule Jido.Statechart.Sends do
  @moduledoc false
  use GenServer

  def start_link(_init), do: GenServer.start_link(__MODULE__, %{})

  def schedule(server, id, delay, deliver) do
    GenServer.call(server, {:schedule, id, delay, deliver})
  end

  def cancel(server, id), do: GenServer.call(server, {:cancel, id})

  def start_task(server, work), do: GenServer.call(server, {:start_task, work})

  @impl true
  def init(timers), do: {:ok, timers}

  @impl true
  def handle_call({:schedule, id, delay, deliver}, _from, timers) do
    token = make_ref()
    timer = Process.send_after(self(), {:deliver, token, deliver}, delay)
    {:reply, :ok, Map.put(timers, token, {id, timer})}
  end

  def handle_call({:cancel, id}, _from, timers) do
    remaining =
      Map.reject(timers, fn
        {_token, {pending, timer}} when id == :all or id == pending ->
          Process.cancel_timer(timer)
          true

        _entry ->
          false
      end)

    {:reply, :ok, remaining}
  end

  def handle_call({:start_task, work}, _from, timers),
    do: {:reply, Task.start_link(work), timers}

  @impl true
  def handle_info({:deliver, token, deliver}, timers) do
    {timer, timers} = Map.pop(timers, token)
    if timer, do: deliver.()
    {:noreply, timers}
  end
end
