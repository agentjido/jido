defmodule Jido.Test.Perf.ScriptRunner do
  @moduledoc false

  def run!(script, output) do
    {log, status} =
      System.cmd(
        System.find_executable("mix"),
        [
          "run",
          "--no-compile",
          "--no-deps-check",
          script,
          "--profile",
          "quick",
          "--output",
          output
        ],
        env: [
          {"MIX_ENV", "test"},
          {"ERL_FLAGS", "+S 4:4 +SDcpu 2 +SDio 1"}
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("#{script} failed:\n#{log}")
    output |> File.read!() |> JSON.decode!()
  end
end
