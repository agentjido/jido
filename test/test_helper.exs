ExUnit.start()
Code.require_file("system/support/report.exs", __DIR__)
ExUnit.configure(formatters: [ExUnit.CLIFormatter, JidoTest.System.Report])

# Focused schema and snapshot probes: mix test --only basic_contract
# Tests that start external BEAM nodes: mix test.peer
# Benchmark contract tests: mix test.bench
# All examples, including application scenarios: mix test.examples
# Agent and Topology authoring corpus: mix test.authoring
# Runtime fault and recovery scenarios: mix test.system
# External storage services: mix test.services (not included in mix test.all)
ExUnit.configure(exclude: [:skip, :flaky, :peer, :example, :bench, :authoring, :system, :service])
