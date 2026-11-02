defmodule Jido.AgentServer.ReplyGate do
  @moduledoc false

  def start(owner, server) when is_pid(owner) do
    server = GenServer.whereis(server)
    spawn(fn -> init(owner, server) end)
  end

  def open(gate), do: request(gate, :open)
  def abandon(gate), do: request(gate, :abandon)

  def deliver(nil, _signal), do: :ok

  def deliver(gate, signal) when is_pid(gate) do
    send(gate, {:deliver, signal})
    :ok
  end

  def done(nil), do: :ok

  def done(gate) when is_pid(gate) do
    send(gate, :done)
    :ok
  end

  defp request(gate, command) when is_pid(gate) do
    monitor = Process.monitor(gate)
    ref = make_ref()
    send(gate, {command, self(), ref})

    receive do
      {^ref, :ok} ->
        Process.demonitor(monitor, [:flush])
        :ok

      {:DOWN, ^monitor, :process, ^gate, _reason} ->
        :ok
    end
  end

  defp init(owner, server) do
    owner_monitor = Process.monitor(owner)
    server_monitor = if is_pid(server), do: Process.monitor(server), else: nil

    loop(%{
      owner: owner,
      owner_monitor: owner_monitor,
      server_monitor: server_monitor,
      open?: false,
      abandoned?: false,
      done?: false,
      signals: []
    })
  end

  defp loop(state) do
    receive do
      {:deliver, _signal} when state.abandoned? ->
        loop(state)

      {:deliver, signal} when state.open? ->
        send(state.owner, signal)
        loop(state)

      {:deliver, signal} ->
        loop(%{state | signals: [signal | state.signals]})

      {:open, caller, ref} ->
        state.signals |> Enum.reverse() |> Enum.each(&send(state.owner, &1))
        send(caller, {ref, :ok})

        if state.done?,
          do: :ok,
          else: loop(%{state | open?: true, signals: []})

      {:abandon, caller, ref} ->
        send(caller, {ref, :ok})

        if state.done?,
          do: :ok,
          else: loop(%{state | abandoned?: true, signals: []})

      :done when state.open? or state.abandoned? or state.signals == [] ->
        :ok

      :done ->
        loop(%{state | done?: true})

      {:DOWN, ref, :process, _pid, _reason} when ref == state.owner_monitor ->
        :ok

      {:DOWN, ref, :process, _pid, _reason} when ref == state.server_monitor ->
        if state.abandoned? or state.signals == [],
          do: :ok,
          else: loop(%{state | done?: true})
    end
  end
end
