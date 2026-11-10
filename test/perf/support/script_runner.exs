Code.require_file("child_process.exs", __DIR__)

defmodule Jido.Test.Perf.ScriptRunner do
  @moduledoc false

  def run!(script, output) do
    Jido.Test.Perf.ChildProcess.mix!(
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
      env: [{"ERL_FLAGS", "+S 4:4 +SDcpu 2 +SDio 1"}]
    )

    output |> File.read!() |> JSON.decode!()
  end
end
