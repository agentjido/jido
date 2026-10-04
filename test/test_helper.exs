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
