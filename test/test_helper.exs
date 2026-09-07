ExUnit.start()

# Focused schema and snapshot probes: mix test --only basic_contract
# Benchmark contract tests: mix benchmarks
# All examples, including application scenarios: mix examples
ExUnit.configure(exclude: [:skip, :flaky, :example, :benchmark])
