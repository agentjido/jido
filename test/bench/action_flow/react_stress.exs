Code.require_file("support.exs", __DIR__)

defmodule Jido.Bench.ActionFlow.ReActStress do
  @moduledoc false

  alias Jido.Bench.ActionFlow.Support

  @profiles %{
    "quick" => %{rounds: 1, tools: 1, max_concurrency: 1, samples: 1, warmup: 0},
    "standard" => %{rounds: 3, tools: 4, max_concurrency: 4, samples: 1, warmup: 0},
    "stress" => %{rounds: 4, tools: 4, max_concurrency: 4, samples: 1, warmup: 0}
  }

  def main(argv) do
    options = Support.options!(argv, "react_stress")
    settings = Support.profile!(options.profile, @profiles)
    result = isolated_case!(settings)
    check_result!(result, settings)

    case_row = %{
      id: "iterative/direct/serial",
      validated_before_measurement: true,
      outcome: result["outcome"],
      elapsed_ms: result["elapsed_ms"],
      model_calls: result["model_calls"],
      tool_rounds: result["tool_rounds"],
      tool_calls: result["tool_calls"],
      peak_process_delta_bytes: result["peak_process_delta_bytes"],
      peak_total_delta_bytes: result["peak_total_delta_bytes"],
      child_vm_exit_status: 0
    }

    Support.report!("jido.action_flow.react_stress", options, settings, [case_row], %{
      benchmark_owner: "test/bench/ai/react_memory.exs",
      isolation: "fresh BEAM VM"
    })
  end

  defp isolated_case!(settings) do
    mix = System.find_executable("mix") || raise "mix executable was not found"

    arguments = [
      "run",
      "--no-compile",
      "--no-deps-check",
      "test/bench/ai/react_memory.exs",
      "--case",
      "iterative",
      "direct",
      "serial",
      Integer.to_string(settings.rounds),
      Integer.to_string(settings.tools),
      Integer.to_string(settings.max_concurrency),
      "0",
      "5",
      "1"
    ]

    {output, status} =
      System.cmd(mix, arguments,
        env: [
          {"MIX_ENV", Atom.to_string(Mix.env())},
          {"ERL_FLAGS", "+S 2:2 +SDcpu 1 +SDio 1"}
        ],
        stderr_to_stdout: true
      )

    if status != 0, do: raise("ReAct benchmark child failed:\n#{output}")

    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, "JIDO_REACT_MEMORY_CASE=", parts: 2) do
        ["", encoded] -> JSON.decode!(encoded)
        _other -> nil
      end
    end)
    |> case do
      nil -> raise "ReAct benchmark child did not return a result"
      result -> result
    end
  end

  defp check_result!(result, settings) do
    expected = %{
      "outcome" => "completed",
      "model_calls" => settings.rounds + 1,
      "tool_rounds" => settings.rounds,
      "tool_calls" => settings.rounds * settings.tools
    }

    unless Map.take(result, Map.keys(expected)) == expected do
      raise "ReAct benchmark returned incorrect result data: #{inspect(result)}"
    end

    :ok
  end
end

Jido.Bench.ActionFlow.ReActStress.main(System.argv())
