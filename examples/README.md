# Jido V3 examples

The stable catalog has 75 executable examples in 10 groups. Original
example numbers stay unchanged. Stable examples teach the current local runtime
contract; research entries state unsupported behavior.

The [durable Flow proposals](11_durable/README.md#proposed-lessons) reserve
11_08–11_19 as README-only spikes. They are not part of the executable count.

| Group | Examples | Source and tests |
| --- | ---: | --- |
| 01_basic | 8 | [Source](01_basic/README.md), [tests](../test/examples/01_basic/README.md) |
| 02_workflow | 9 | [Source](02_workflow/README.md), [tests](../test/examples/02_workflow/README.md) |
| 03_llm | 6 | [Source](03_llm/README.md), [tests](../test/examples/03_llm/README.md) |
| 04_runtime | 15 | [Source](04_runtime/README.md), [tests](../test/examples/04_runtime/README.md) |
| 05_multi_agent | 3 | [Source](05_multi_agent/README.md), [tests](../test/examples/05_multi_agent/README.md) |
| 07_topology | 6 | [Source](07_topology/README.md), [tests](../test/examples/07_topology/README.md) |
| 08_applications | 5 | [Source](08_applications/README.md), [tests](../test/examples/08_applications/README.md) |
| 09_plugins | 8 | [Source](09_plugins/README.md), [tests](../test/examples/09_plugins/README.md) |
| 10_persistence | 8 | [Source](10_persistence/README.md), [tests](../test/examples/10_persistence/README.md) |
| 11_durable | 7 | [Source](11_durable/README.md), [tests](../test/examples/11_durable/README.md) |

## Choose a path

- **Start here:** [Minimal Agent](01_basic/01_01_minimal_agent/README.md), [typed input](01_basic/01_02_typed_command_agent/README.md), [route selection](01_basic/01_06_route_selection/README.md), [owned state](01_basic/01_03_plugin_state_agent/README.md), then [request modes](04_runtime/04_15_request_modes/README.md).
- **Author from data:** [saved JSON and Scheduler](01_basic/01_07_data_defined_agent/README.md), [authoring Plugin](01_basic/01_09_authoring_plugin/README.md), [Plugin DSL structure](09_plugins/09_10_plugin_dsl/README.md), then [JSON topology](07_topology/07_01_independent/README.md).
- **Recover work:** [persistent Agent](10_persistence/10_01_persistent_agent/README.md), [hibernate and thaw](10_persistence/10_02_hibernate_and_thaw/README.md), [saved Flow progress](11_durable/11_02_saved_progress/README.md), then [durable approval waits](11_durable/11_06_durable_wait/README.md).

Use [dynamic child lifecycle](05_multi_agent/05_01_child_lifecycle/README.md)
when a Turn decides to create a child. Use [declared topology](07_topology/README.md)
when composition belongs to the Agent definition. The optional
[LLM path](03_llm/README.md) uses example-owned model ports. It does not prove
compatibility with the current `jido_ai` API.

The [coverage register](COVERAGE.md) maps capabilities to evidence.
The [research catalog](99_research/README.md) states unsupported contracts.

Factory and Elastic Group moved to
[application demonstrations](../../examples/jido_lab/experiments/jido_core/README.md).
Those retained applications need separate API updates and are not loaded here.
LLM examples use deterministic adapters and test Agent integration; model
behavior belongs to `jido_ai`.

```sh
mix test
mix test test/examples/01_basic/01_01_minimal_agent --include example --seed 0
mix test.examples
```

The example test loader compiles all `.ex` example sources before running a
selected test. One source failure can therefore block another example.
Use the tests as executable evidence; a passing suite does not replace the
coverage register or each lesson’s stated limits.

The Hex package excludes examples and tests. Production compiles `lib/` only.
See [testing](../guides/test-jido-systems.livemd) for test categories and optional services.
