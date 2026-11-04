# Performance catalog

Load and benchmark code, smoke tests, fixtures, support modules, and documents
live under `test/perf`. Tags select load or benchmark proof without separate
ownership trees. Required CI runs `mix test.load` and `mix test.bench`. Longer
profiles are explicit and opt-in. No performance check uses a fixed wall-clock
pass limit.

The machine-readable catalog is `test/perf/catalog.yml`. It records the
component, owner, workload, expected limiter, profile settings, metrics, and
units for every family. Every JSON result uses the common schema in
`test/perf/support/result.exs`. A result records the full Git revision, dirty
state, Elixir and OTP versions, seed, workload, profile, and measurement units.

## Quick commands

| Family | Quick command |
| --- | --- |
| AgentServer bounded load | `mix test.load test/perf/jido_agent_server` |
| Exec bounded load | `mix test.load test/perf/jido_exec` |
| Signal | `MIX_ENV=test mix run test/perf/jido_signal/run.exs --profile smoke --output tmp/bench/signal/smoke` |
| Flow normalization and compile | `MIX_ENV=test mix run test/perf/jido_flow/flow_compile.exs --profile quick` |
| Action and Flow execution | `MIX_ENV=test mix run test/perf/jido_exec/flow_run.exs --profile quick` |
| Action and Flow DSL compile | `MIX_ENV=test mix run test/perf/jido_flow/dsl_compile.exs --profile quick` |
| ReAct isolated stress | `MIX_ENV=test mix run test/perf/jido_ai/react_stress.exs --profile quick` |
| ReAct retained state | `MIX_ENV=test mix bench.ai.state_growth --profile quick` |
| ReAct fresh workflow | `MIX_ENV=test mix bench.ai.fresh_workflow --profile quick` |
| ReAct memory | `JIDO_MEMORY_BENCH_PROFILE=quick JIDO_MEMORY_BENCH_OUTPUT=json JIDO_MEMORY_BENCH_FILE=tmp/bench/ai/react-memory-quick.json mix bench` |

The Action and Flow commands use `quick`, `standard`, and `stress`. The two
focused AI commands use the same profile names. The Signal runner uses `smoke`,
`short`, `candidates`, and `scale`. The ReAct memory runner uses `quick`,
`base`, and `expanded`. See `catalog.yml` for the exact input, concurrency,
warm-up, sample count, metrics, and units for each profile.

Use reports only for comparisons made with the same family, profile, code, and
compatible environment. Timing and memory values are evidence, not portable
pass limits.
