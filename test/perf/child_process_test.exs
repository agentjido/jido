Code.require_file("support/child_process.exs", __DIR__)

defmodule Jido.Perf.ChildProcessTest do
  use ExUnit.Case, async: false

  @moduletag :bench
  @moduletag :tmp_dir

  alias Jido.Test.Perf.ChildProcess

  test "captures output and reports child failures" do
    assert ChildProcess.mix!(["run", "--no-mix-exs", "-e", "IO.puts(:child_result)"]) =~ "child_result"

    assert_raise RuntimeError, ~r/exited with status 7.*child_failure/s, fn ->
      ChildProcess.mix!(["run", "--no-mix-exs", "-e", "IO.puts(:child_failure); System.halt(7)"])
    end
  end

  test "the deadline stops a blocked child", %{tmp_dir: directory} do
    file = Path.join(directory, "timeout.pid")

    task =
      Task.async(fn ->
        assert_raise RuntimeError, ~r/benchmark child timed out/, fn ->
          ChildProcess.mix!(blocked_child(), env: [{"PERF_TEST_PID_FILE", file}], timeout: 3_000)
        end
      end)

    pid = await_pid(file)
    Task.await(task, 10_000)
    await_exit(pid)
  end

  test "a child stops when its calling process is killed", %{tmp_dir: directory} do
    file = Path.join(directory, "owner.pid")
    owner = spawn(fn -> ChildProcess.mix!(blocked_child(), env: [{"PERF_TEST_PID_FILE", file}]) end)
    on_exit(fn -> Process.exit(owner, :kill) end)
    pid = await_pid(file)
    Process.exit(owner, :kill)
    await_exit(pid)
  end

  test "parent loss also stops a nested benchmark VM", %{tmp_dir: directory} do
    outer_file = Path.join(directory, "outer.pid")
    inner_file = Path.join(directory, "inner.pid")

    code =
      "File.write!(System.fetch_env!(\"PERF_OUTER_PID_FILE\"), System.pid()); " <>
        "Jido.Test.Perf.ChildProcess.mix!(#{inspect(blocked_child())}, " <>
        "env: [{\"PERF_TEST_PID_FILE\", System.fetch_env!(\"PERF_INNER_PID_FILE\")}])"

    owner =
      spawn(fn ->
        ChildProcess.mix!(["run", "--no-mix-exs", "-e", code],
          env: [{"PERF_OUTER_PID_FILE", outer_file}, {"PERF_INNER_PID_FILE", inner_file}]
        )
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    outer = await_pid(outer_file)
    inner = await_pid(inner_file)
    Process.exit(owner, :kill)
    await_exit(outer)
    await_exit(inner)
  end

  defp blocked_child do
    [
      "run",
      "--no-mix-exs",
      "-e",
      "File.write!(System.fetch_env!(\"PERF_TEST_PID_FILE\"), System.pid()); Process.sleep(:infinity)"
    ]
  end

  defp await_pid(file, attempts \\ 200)
  defp await_pid(_file, 0), do: flunk("child did not signal startup")

  defp await_pid(file, attempts) do
    case File.read(file) do
      {:ok, pid} when pid != "" ->
        # Always stop this test's child, including when an assertion fails.
        on_exit({:child, pid}, fn -> System.cmd("kill", ["-KILL", pid], stderr_to_stdout: true) end)
        pid

      _ ->
        Process.sleep(10)
        await_pid(file, attempts - 1)
    end
  end

  defp await_exit(pid, attempts \\ 200)
  defp await_exit(_pid, 0), do: flunk("benchmark child survived its owner or deadline")

  defp await_exit(pid, attempts) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_output, status} when status != 0 ->
        on_exit({:child, pid}, fn -> :ok end)

      _ ->
        Process.sleep(10)
        await_exit(pid, attempts - 1)
    end
  end
end
