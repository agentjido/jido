defmodule JidoTest.Property.Signal.Runtime do
  @moduledoc false
  import ExUnit.Assertions
  alias Jido.Signal.Bus

  def with_bus(fun), do: with_bus([], fun)

  def with_bus(opts, fun) do
    token = make_ref()
    name = "property_#{System.unique_integer([:positive])}"
    {:ok, bus} = Bus.start_link(Keyword.merge([name: name], opts))

    try do
      fun.(%{bus: bus, token: token, name: name})
    after
      stop(bus)
      drain(token)
    end
  end

  def stop(pid) do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5_000)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
  end

  def assert_workers_stopped(workers) do
    for pid <- workers, do: refute(Process.alive?(pid))
  end

  def next(token) do
    receive do
      {^token, _, _} = message -> message
      {^token, _, _, _} = message -> message
      {^token, _, _, _, _} = message -> message
    after
      5_000 -> flunk("missing owned runtime event")
    end
  end

  def drain(token) do
    receive do
      {^token, _} ->
        drain(token)

      {^token, _, _} ->
        drain(token)

      {^token, _, _, _} ->
        drain(token)

      {^token, _, _, _, _} ->
        drain(token)

      {:signal, %Jido.Signal{data: %{"_probe" => ^token}}} ->
        drain(token)

      %Jido.Signal{data: %{"_probe" => ^token}} ->
        drain(token)

      {:signal, _id, %Jido.Signal.Bus.RecordedSignal{signal: %Jido.Signal{data: %{"_probe" => ^token}}}} ->
        drain(token)
    after
      0 -> :ok
    end
  end
end
