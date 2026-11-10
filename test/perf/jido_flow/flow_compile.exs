Code.require_file("../support/runner.exs", __DIR__)
Code.require_file("../support/flow_fixtures.exs", __DIR__)

defmodule Jido.Test.Perf.Flow.Compile do
  @moduledoc false

  alias Jido.Test.Perf.Flow.Fixtures
  alias Jido.Test.Perf.Runner

  @profiles %{
    "quick" => %{widths: [4, 16], samples: 2, warmup: 1},
    "standard" => %{widths: [16, 64], samples: 5, warmup: 2},
    "stress" => %{widths: [64, 256], samples: 10, warmup: 3}
  }

  def main(argv) do
    options = Runner.options!(argv, "flow_compile")
    settings = Runner.profile!(options.profile, @profiles)

    cases =
      Enum.flat_map(settings.widths, fn width ->
        input = Fixtures.wide_input(width)
        flow = Jido.Flow.new!(input)

        normalize =
          Runner.measure!(
            "normalize/#{width}",
            fn -> Jido.Flow.new!(input) end,
            &check_flow!(&1, width),
            settings
          )

        compile =
          Runner.measure!(
            "compile/#{width}",
            fn -> Jido.Exec.compile!(flow) end,
            &check_program!/1,
            settings
          )

        [Map.put(normalize, :width, width), Map.put(compile, :width, width)]
      end)

    Runner.report!("jido.flow.compile", options, settings, cases)
  end

  defp check_flow!(flow, width) do
    if map_size(flow.components) != width,
      do: raise("normalized Flow has an incorrect component count")

    {:ok, ^flow} = Jido.Flow.validate(flow)
    :ok
  end

  defp check_program!(program) do
    if map_size(program.components) == 0, do: raise("compiled Flow has no components")
    :ok
  end
end

Jido.Test.Perf.Flow.Compile.main(System.argv())
