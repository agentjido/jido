ExUnit.start()

# Focused schema and snapshot probes: mix test --only basic_contract
# Tests that start external BEAM nodes: mix test.peer
# Benchmark contract tests: mix test.bench
# All examples, including application scenarios: mix test.examples
# Agent and Topology authoring corpus: mix test.authoring
ExUnit.configure(exclude: [:skip, :flaky, :peer, :example, :bench, :authoring])
