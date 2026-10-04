# Jido V3 examples

The main catalog has 82 fixtures in ten stable groups. All use the implemented
Agent and AgentServer contract. One separate research probe records the missing
distributed-authority contract. The [coverage register](COVERAGE.md) maps
capabilities to owners and evidence. Counts below are navigation inventory, not
a coverage score.

| Group | Fixtures | Source and tests |
| --- | ---: | --- |
| 01_basic | 9 | [Source](01_basic/README.md), [tests](../test/examples/01_basic/README.md) |
| 02_workflow | 9 | [Source](02_workflow/README.md), [tests](../test/examples/02_workflow/README.md) |
| 03_llm | 6 | [Source](03_llm/README.md), [tests](../test/examples/03_llm/README.md) |
| 04_runtime | 16 | [Source](04_runtime/README.md), [tests](../test/examples/04_runtime/README.md) |
| 05_multi_agent | 6 | [Source](05_multi_agent/README.md), [tests](../test/examples/05_multi_agent/README.md) |
| 06_factory | 4 | [Source](06_factory/README.md), [tests](../test/examples/06_factory/README.md) |
| 07_topology | 10 | [Source](07_topology/README.md), [tests](../test/examples/07_topology/README.md) |
| 08_applications | 7 | [Source](08_applications/README.md), [tests](../test/examples/08_applications/README.md) |
| 09_plugins | 7 | [Source](09_plugins/README.md), [tests](../test/examples/09_plugins/README.md) |
| 10_persistence | 8 | [Source](10_persistence/README.md), [tests](../test/examples/10_persistence/README.md) |

The [research section](99_research/README.md) retains only the unsupported
cluster-exclusive ownership contract. Its test lives under `test/examples` and
uses the `:example` tag.

The repository compiles `examples/` in `:dev` and `:test` only. Production builds
compile `lib/` only. The Hex package contains neither examples nor tests.
Run demos with `mix run examples/.../demo.exs` or use `iex -S mix` from this
repository. JSON fixtures stay beside their example source.

```sh
mix test                                     # Core tests; examples are excluded
mix test.examples                        # All example tests
mix test test/examples/01_basic --include example --seed 0
mix test --include example --include flaky --seed 0  # Complete acceptance suite
```

Every numbered example folder has at least one small executable behavior test.
Deeper core regression suites can reuse the same example modules. The exact
DIST-03 exclusion is the only approved skip in the complete suite;
cluster-exclusive ownership remains unsupported.

LLM and Factory tests use deterministic adapters and local HTTP/SSE servers.
The LLM group is an ecosystem integration suite owned by `jido_ai`. Factory is
an optional combined application suite. Neither folder count is a Jido public
feature count. Live provider demos require separate credentials and budget.
The recursive analysis stress runner and 1,000-worker Topology test are
independent scale checks. They do not prove multi-host capacity.

Use the [testing guide](../guides/testing.md) for current test commands
and the [migration guide](../guides/migration.md) for V2 changes.
