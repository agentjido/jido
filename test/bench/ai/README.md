# Offline AI benchmarks

The ReAct benchmark family has three metric owners:

- `test/bench/ai/react_memory.exs` owns live VM memory, allocator deltas, and
  retained Agent and Session size for one request with several tool rounds.
- `test/bench/ai/react_state_growth.exs` owns retained Session and Thread growth
  across several sequential requests on one Agent.
- `test/bench/ai/react_fresh_workflow.exs` owns fresh preflight compile cost,
  workflow shape, and retained size for independent new Agents.

All three runners use a deterministic local inference client and one local
tool. They do not read a provider key or make a network call. Metric values are
reports, not pass thresholds.

Run the bounded ReAct memory profile and write its common JSON result:

```console
JIDO_MEMORY_BENCH_PROFILE=quick JIDO_MEMORY_BENCH_OUTPUT=json JIDO_MEMORY_BENCH_FILE=tmp/bench/ai/react-memory-quick.json mix bench
```

Run the smoke checks with:

```console
mix test.bench test/bench/ai
```

The tests validate completed model and tool work before they accept any metric.
They also run both manual scripts with two requests and validate their JSON
reports. Timing and memory values are recorded, not used as pass thresholds.

Run the two focused runners with:

```console
mix bench.ai.state_growth --profile quick
mix bench.ai.fresh_workflow --profile quick
```

To save JSON, use a path under the ignored report directory:

```console
mix bench.ai.state_growth --profile quick --output tmp/bench/ai/state-growth.json
mix bench.ai.fresh_workflow --profile quick --output tmp/bench/ai/fresh-workflow.json
```
