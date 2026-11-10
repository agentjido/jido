defmodule Jido.Test.Perf.ChildProcess do
  @moduledoc false

  @timeout 120_000
  @guard_margin 5_000
  @source __ENV__.file

  # Start the lifetime guard before Mix or the benchmark can block.
  def mix!(arguments, options \\ []) do
    timeout = Keyword.get(options, :timeout, @timeout)
    unless is_integer(timeout) and timeout > 0, do: raise(ArgumentError, "timeout must be positive")

    environment =
      Map.merge(
        %{"MIX_ENV" => "test"},
        Map.new(Keyword.get(options, :env, []))
      )
      |> Map.put("JIDO_PERF_CHILD_TIMEOUT_MS", Integer.to_string(timeout + @guard_margin))
      |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)

    bootstrap = "Jido.Test.Perf.ChildProcess.guard!(); Mix.start(); Mix.CLI.main(System.argv())"

    port =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-r", @source, "-e", bootstrap, "--" | arguments],
        env: environment
      ])

    try do
      collect(port, [], System.monotonic_time(:millisecond) + timeout)
    after
      if Port.info(port), do: Port.close(port)
    end
  end

  # These processes live only in the child VM. Port closure closes its stdin.
  def guard! do
    spawn(fn ->
      IO.binread(:stdio, :eof)
      System.halt(125)
    end)

    timeout = System.fetch_env!("JIDO_PERF_CHILD_TIMEOUT_MS") |> String.to_integer()

    spawn(fn ->
      receive do
      after
        timeout -> System.halt(124)
      end
    end)

    :ok
  end

  defp collect(port, output, deadline) do
    receive do
      {^port, {:data, data}} -> collect(port, [data | output], deadline)
      {^port, {:exit_status, 0}} -> output |> Enum.reverse() |> IO.iodata_to_binary()
      {^port, {:exit_status, status}} -> raise "benchmark child exited with status #{status}:\n#{log(output)}"
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        {:os_pid, pid} = Port.info(port, :os_pid)
        System.cmd(System.find_executable("kill"), ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)

        receive do
          {^port, {:exit_status, _status}} -> :ok
        after
          5_000 -> raise "benchmark child did not stop after SIGKILL"
        end

        raise "benchmark child timed out:\n#{log(output)}"
    end
  end

  defp log(output), do: output |> Enum.reverse() |> IO.iodata_to_binary()
end
