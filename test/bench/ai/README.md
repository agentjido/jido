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

Run the smoke checks with:

```console
mix test.bench test/bench/ai
```

The tests validate completed model and tool work before they accept any metric.
They also run both manual scripts with two requests and validate their JSON
reports. Timing and memory values are recorded, not used as pass thresholds.

Run the two focused runners with:

```console
mix bench.ai.state_growth --requests 5
mix bench.ai.fresh_workflow --requests 5
```

To save JSON, use a path under the ignored report directory:

```console
mix bench.ai.state_growth --requests 5 --output tmp/bench/ai/state-growth.json
mix bench.ai.fresh_workflow --requests 5 --output tmp/bench/ai/fresh-workflow.json
```
