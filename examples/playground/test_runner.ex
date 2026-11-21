defmodule Jido.Examples.ExplorerTestRunner do
  @moduledoc false

  @root Path.expand("../..", __DIR__)
  @timeout_ms 120_000
  @output_limit 48_000

  def run(path) do
    case System.find_executable("mix") do
      nil ->
        {:error, "Mix is unavailable."}

      mix ->
        port =
          Port.open({:spawn_executable, mix}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: ["test.examples", path, "--warnings-as-errors"],
            cd: @root,
            env: [{~c"MIX_ENV", ~c"test"}, {~c"JIDO_PLAYGROUND", false}, {~c"NO_COLOR", ~c"1"}]
          ])

        collect(port, "", System.monotonic_time(:millisecond) + @timeout_ms)
    end
  end

  defp collect(port, output, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, chunk}} ->
        output = output <> chunk
        start = max(byte_size(output) - @output_limit, 0)
        collect(port, binary_part(output, start, byte_size(output) - start), deadline)

      {^port, {:exit_status, status}} ->
        {:ok, %{status: status, output: String.replace_invalid(output)}}
    after
      remaining ->
        Port.close(port)
        {:error, "The test run exceeded two minutes."}
    end
  end
end
