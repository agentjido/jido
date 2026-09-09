ExUnit.start()

# Focused schema and snapshot probes: mix test --only basic_contract
# Tests that start external BEAM nodes: mix peer
# Benchmark contract tests: mix benchmarks
# All examples, including application scenarios: mix examples
ExUnit.configure(exclude: [:skip, :flaky, :peer, :example, :benchmark])
