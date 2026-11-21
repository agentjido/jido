Code.require_file("../support/runner.exs", __DIR__)

defmodule Jido.Test.Perf.Flow.DSLCompile do
  @moduledoc false

  alias Jido.Test.Perf.Runner

  @profiles %{
    "quick" => %{modules: 2, samples: 2, warmup: 1},
    "standard" => %{modules: 10, samples: 10, warmup: 1},
    "stress" => %{modules: 25, samples: 25, warmup: 1}
  }

  def main(argv) do
    options = Runner.options!(argv, "dsl_compile")
    settings = Runner.profile!(options.profile, @profiles)
    preflight!()

    {cases, compiled_modules} =
      Enum.map_reduce(1..settings.modules, [], fn index, modules ->
        {row, compiled} = compile_case!(index)
        {row, compiled ++ modules}
      end)

    Runner.report!("jido.flow.dsl_compile", options, settings, cases, %{
      cleanup: purge_modules!(compiled_modules)
    })
  end

  defp preflight! do
    {_row, modules} = compile_case!(0)
    purge_modules!(modules)
  end

  defp purge_modules!(modules) do
    for module <- modules do
      :code.delete(module)
      :code.purge(module)
    end

    remaining =
      Enum.count(modules, fn module ->
        :code.is_loaded(module) != false or :erlang.check_old_code(module)
      end)

    if remaining != 0, do: raise("generated DSL modules remain loaded after cleanup")
    %{purged_modules: length(modules), remaining_modules: remaining}
  end

  defp compile_case!(index) do
    suffix = "#{index}_#{System.unique_integer([:positive])}"
    action = Module.concat([Jido, Test, Perf, Flow, Generated, "Action#{suffix}"])
    flow = Module.concat([Jido, Test, Perf, Flow, Generated, "Flow#{suffix}"])
    source = source(action, flow, suffix)
    started = System.monotonic_time()
    compiled = Code.compile_string(source, "jido_flow_dsl_#{suffix}.ex")
    elapsed = System.monotonic_time() - started

    unless Jido.Exec.run(flow, %{value: 11}) == {:ok, %{value: 11}} do
      raise "compiled DSL Flow returned an incorrect result"
    end

    modules = Enum.map(compiled, &elem(&1, 0))

    row = %{
      id: "dsl/#{index}",
      validated_before_measurement: true,
      elapsed_us: System.convert_time_unit(elapsed, :native, :microsecond),
      compiled_modules: length(modules),
      source_sha256: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
    }

    {row, modules}
  end

  defp source(action, flow, suffix) do
    """
    defmodule #{inspect(action)} do
      use Jido.Action, name: "dsl_benchmark_action_#{suffix}"
      @impl true
      def run(params, _context), do: {:ok, %{value: params.value}}
    end

    defmodule #{inspect(flow)} do
      use Jido.Flow, name: "dsl_benchmark_flow_#{suffix}"
      flow do
        step "echo", action: #{inspect(action)}, params: %{value: input(:value)}
        output result("echo")
      end
    end
    """
  end
end

Jido.Test.Perf.Flow.DSLCompile.main(System.argv())
