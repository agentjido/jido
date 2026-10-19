defmodule JidoTest.InstanceSupervisionTest do
  use ExUnit.Case, async: false

  import JidoTest.Eventually

  test "replacement waits for the old Flow runner before starting its children" do
    name = :"runner_shutdown_#{System.unique_integer([:positive])}"
    {:ok, original} = Jido.start_link(name: name)
    Process.unlink(original)
    runner = Process.whereis(Jido.exec_runner_name(name))
    original_ref = Process.monitor(original)
    true = :erlang.suspend_process(runner)

    try do
      Process.exit(original, :kill)
      assert_receive {:DOWN, ^original_ref, :process, ^original, :killed}, 5_000

      starter =
        Task.async(fn ->
          Process.flag(:trap_exit, true)
          result = Jido.start_link(name: name)
          if match?({:ok, _}, result), do: Process.unlink(elem(result, 1))
          result
        end)

      # Observe the startup wait itself. No startup retry or timing delay can
      # turn a failed child start into a passing replacement.
      eventually(fn ->
        case Process.info(starter.pid, :monitors) do
          {:monitors, monitors} -> {:process, runner} in monitors
          nil -> flunk("replacement exited before the old runner released its name")
        end
      end)

      true = :erlang.resume_process(runner)
      assert {:ok, replacement} = Task.await(starter, 10_000)

      try do
        assert Process.whereis(name) == replacement
        assert Process.whereis(Jido.exec_runner_name(name)) != runner
        assert Process.alive?(replacement)
      after
        Supervisor.stop(replacement)
      end
    after
      if Process.alive?(runner), do: :erlang.resume_process(runner)
      if pid = Process.whereis(name), do: Supervisor.stop(pid)
    end
  end
end
