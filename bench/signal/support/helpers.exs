defmodule Jido.Bench.Signal.Helpers do
  @moduledoc false
  alias Jido.Signal

  def plain(name, retained, run, check, dimensions \\ %{}) do
    %{
      name: name,
      retained: retained,
      dimensions: dimensions,
      setup: fn _ -> nil end,
      run: run,
      check: fn result, _ -> check.(result) end
    }
  end

  def stateful(name, retained, setup, run, check, dimensions) do
    %{
      name: name,
      retained: retained,
      dimensions: dimensions,
      setup: fn _ ->
        {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

        try do
          setup.(%{supervisor: supervisor, owner: self(), tag: make_ref()})
        catch
          kind, reason ->
            stop(supervisor)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end
      end,
      run: run,
      check: check,
      cleanup: fn state -> stop(state.supervisor) end
    }
  end

  def child(state, specification) do
    specification = Supervisor.child_spec(specification, restart: :temporary)
    {:ok, pid} = DynamicSupervisor.start_child(state.supervisor, specification)
    pid
  end

  def worker(state, fun) do
    child(state, %{id: make_ref(), start: {Task, :start_link, [fun]}})
  end

  def bus(state, capacity, opts \\ []) do
    name = "signal-bench-extra-#{System.unique_integer([:positive, :monotonic])}"
    child(state, {Jido.Signal.Bus, [name: name, max_log_size: capacity] ++ opts})
  end

  def stop(pid) do
    ref = Process.monitor(pid)
    if Process.alive?(pid), do: Supervisor.stop(pid, :normal, 5_000)
    down(pid, ref)
  end

  def terminate(state, pid) do
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(state.supervisor, pid)
    down(pid, ref)
  end

  defp down(pid, ref) do
    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5_000 -> raise "benchmark process did not stop"
    end
  end

  def wait(tag, kind, index) do
    receive do
      {^tag, ^kind, ^index, value} -> value
    after
      30_000 -> raise "benchmark message missing: #{kind}/#{index}"
    end
  end

  def hold do
    receive do: (:stop -> :ok)
  end

  def events(count) do
    for index <- 1..count do
      Signal.new!(
        id: "extra-event#{index}",
        type: "bench.item#{index}.created",
        source: "/benchmark",
        data: %{"index" => index, "value" => 42}
      )
    end
  end

  def records(records, events, first_cursor \\ 1) do
    expect!(Enum.map(records, & &1.signal), events)

    expect!(
      Enum.map(records, & &1.cursor),
      Enum.to_list(first_cursor..(first_cursor + length(events) - 1))
    )
  end

  def empty_mailbox! do
    receive do
      {:signal, _} -> raise "unexpected Signal delivery"
      {:signal, _, _} -> raise "unexpected durable delivery"
    after
      0 -> :ok
    end
  end

  def expect!(actual, expected) do
    if actual != expected, do: raise("benchmark returned an incorrect result")
    :ok
  end
end
