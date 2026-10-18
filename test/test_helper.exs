ExUnit.start()
Code.require_file("system/support/report.exs", __DIR__)
ExUnit.configure(formatters: [ExUnit.CLIFormatter, JidoTest.System.Report])

# Focused schema and snapshot probes: mix test --only basic_contract
# Tests that start external BEAM nodes: mix test.peer
# Benchmark contract tests: mix test.bench
# All examples, including application scenarios: mix test.examples
# Agent and Topology authoring corpus: mix test.authoring
# Runtime fault and recovery scenarios: mix test.system
# Local persistence adapter contracts: mix test.persistence
# External storage services: mix test.services (not included in mix test.all)
ExUnit.configure(
  exclude: [
    :skip,
    :flaky,
    :peer,
    :example,
    :bench,
    :authoring,
    :system,
    :service,
    :property,
    :fuzz
  ]
)

# Write source evidence before property files compile. The formatter records the
# final suite evidence. Keep normal-suite reports independent.
selected_generated_suite? =
  Enum.any?(ExUnit.configuration()[:include], fn
    {tag, _value} -> tag in [:property, :fuzz]
    tag -> tag in [:property, :fuzz]
  end)

if selected_generated_suite? do
  Code.require_file("property/support/report.exs", __DIR__)
  JidoTest.Property.Report.prepare!()

  # The System formatter records only normal system and service tests.
  ExUnit.configure(
    formatters: [ExUnit.CLIFormatter, JidoTest.System.Report, JidoTest.Property.Report]
  )
end

# Keep both Jido reports and add passing-test evidence for the API contract.
ExUnit.configure(
  formatters: Enum.uniq(ExUnit.configuration()[:formatters] ++ [Covenant.Formatter])
)

# A full discovery compiles excluded example tests too. Load their sources
# before those tests. Focused core commands do not need the example sources.
requested_paths =
  System.argv()
  |> Enum.drop(1)
  |> Enum.map(&(&1 |> String.split(":", parts: 2) |> hd()))
  |> Enum.filter(&File.exists?/1)
  |> Enum.map(&Path.expand/1)

loads_examples? =
  requested_paths == [] or Path.expand("test") in requested_paths or
    Enum.any?(requested_paths, &String.starts_with?(&1, Path.expand("test/examples")))

if loads_examples? or
     Enum.any?(ExUnit.configuration()[:include], fn
       {tag, _} -> tag == :example
       tag -> tag == :example
     end) do
  {:ok, _, _} =
    Kernel.ParallelCompiler.compile(
      Path.wildcard("examples/**/*.ex") ++
        Path.wildcard(Path.join(__DIR__, "examples/support/*.ex")),
      return_diagnostics: true
    )
end
