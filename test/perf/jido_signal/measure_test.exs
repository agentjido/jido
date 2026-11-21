Code.require_file("support/measure.exs", __DIR__)

defmodule Jido.Signal.Perf.MeasureTest do
  use ExUnit.Case, async: false
  @moduletag :bench

  alias Jido.Test.Perf.Signal.Measure

  test "timing and activity workers stop when their owner exits" do
    for mode <- [:timing, :activity] do
      test = self()
      tag = make_ref()

      workload = %{
        setup: fn _ -> nil end,
        run: fn _ ->
          send(test, {tag, self()})
          receive do: (:release -> :ok)
        end,
        check: fn _, _ -> :ok end
      }

      owner = spawn(fn -> measure(mode, workload) end)
      on_exit(fn -> Process.exit(owner, :kill) end)
      assert_receive {^tag, worker}, 1_000
      on_exit(fn -> Process.exit(worker, :kill) end)
      ref = Process.monitor(worker)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1_000
    end
  end

  test "resource cancellation stops its caller and unlinked descendants" do
    for phase <- [:running, :finishing] do
      cancel_resources(phase)
    end
  end

  defp cancel_resources(phase) do
    test = self()
    tag = make_ref()

    workload = %{
      setup: fn _ -> nil end,
      run: fn _ ->
        caller = self()

        child =
          spawn(fn ->
            child = self()

            grandchild =
              spawn(fn ->
                send(child, {tag, self()})
                receive do: (:release -> :ok)
              end)

            receive do
              {^tag, ^grandchild} -> send(caller, {tag, child, grandchild})
            end

            receive do: (:release -> :ok)
          end)

        receive do
          {^tag, ^child, grandchild} -> send(test, {tag, caller, child, grandchild})
        end

        if phase == :running, do: receive(do: (:release -> :ok)), else: :ok
      end,
      check: fn _, _ -> :ok end
    }

    owner = spawn(fn -> Measure.resources(workload) end)
    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {^tag, caller, child, grandchild}, 1_000
    processes = [caller, child, grandchild]
    on_exit(fn -> Enum.each(processes, &Process.exit(&1, :kill)) end)
    monitors = Enum.map(processes, &{&1, Process.monitor(&1)})

    if phase == :finishing do
      caller_ref = Process.monitor(caller)
      assert_receive {:DOWN, ^caller_ref, :process, ^caller, :normal}, 1_000
    end

    Process.exit(owner, :kill)

    for {pid, ref} <- monitors do
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    end
  end

  defp measure(:timing, workload), do: Measure.timing(workload, 1, 1)
  defp measure(:activity, workload), do: Measure.activity(workload)
end
