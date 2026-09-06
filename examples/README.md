> Current acceptance runs, 2026-09-05: [ten feature probes](../docs/examples/feature-acceptance-results.md)
> and [three live-upgrade examples](../docs/examples/live-upgrade-results.md) have 34 passing
> checks and 11 failing checks across nine proposed core features. All 45 checks
> are enabled. These reports supersede older research counts for these targets.

# Jido V3 examples

The main catalog has 62 fixtures in eight groups. All use the implemented
Agent and AgentServer contract. The group guides below link to their source
and tests.

| Group | Fixtures | Source and tests |
| --- | ---: | --- |
| 01_basic | 5 | [Source](01_basic/README.md), [tests](../test/examples/01_basic/README.md) |
| 02_workflow | 9 | [Source](02_workflow/README.md), [tests](../test/examples/02_workflow/README.md) |
| 03_llm | 10 | [Source](03_llm/README.md), [tests](../test/examples/03_llm/README.md) |
| 04_runtime | 13 | [Source](04_runtime/README.md), [tests](../test/examples/04_runtime/README.md) |
| 05_multi_agent | 6 | [Source](05_multi_agent/README.md), [tests](../test/examples/05_multi_agent/README.md) |
| 06_factory | 4 | [Source](06_factory/README.md), [tests](../test/examples/06_factory/README.md) |
| 07_topology | 5 | [Source](07_topology/README.md), [tests](../test/examples/07_topology/README.md) |
| 08_applications | 10 | [Source](08_applications/README.md), [tests](../test/examples/08_applications/README.md) |

The application examples use IDs `08_01` through `08_10` in source and test folders.
[Research examples](99_research/README.md) record proposed core features.
Their tests all live under `test/examples` and use the `:example` tag.

The repository compiles `examples/` in `:dev` and `:test` only. Production builds
compile `lib/` only. The Hex package contains neither examples nor tests.
Run demos with `mix run examples/.../demo.exs` or use `iex -S mix` from this
repository. JSON fixtures stay beside their example source.

```sh
mix test                                     # Core tests; examples are excluded
mix examples --seed 0                        # All example tests
mix test test/examples/01_basic --include example --seed 0
mix test --include example --include flaky --seed 0  # Complete acceptance suite
```

Core regression tests can reuse example modules. Keep each assertion in one
suite. The runtime, observation, remote, and persistence guides link to core
tests where the behavior is already covered. Do not copy those tests into the
example suite. The exact DIST-03 exclusion is the only approved skip in the
complete suite; cluster-exclusive ownership remains unsupported.

LLM and Factory tests use deterministic adapters and local HTTP/SSE servers.
Live provider demos require separate credentials and budget. The recursive
analysis stress runner and 1,000-worker Topology test are independent scale
checks. They do not prove multi-host capacity.

[Historical research](../docs/examples/README.md) retains earlier plans and
results. Use the [testing guide](../guides/testing.md) for current test commands
and the [migration guide](../guides/migration.md) for V2 changes.
