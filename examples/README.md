# Jido V3 examples

The stable catalog has 68 examples in 9 groups. Original
example numbers stay unchanged. Stable examples teach the current local runtime
contract; research entries state unsupported behavior.

| Group | Examples | Source and tests |
| --- | ---: | --- |
| 01_basic | 8 | [Source](01_basic/README.md), [tests](../test/examples/01_basic/README.md) |
| 02_workflow | 9 | [Source](02_workflow/README.md), [tests](../test/examples/02_workflow/README.md) |
| 03_llm | 6 | [Source](03_llm/README.md), [tests](../test/examples/03_llm/README.md) |
| 04_runtime | 16 | [Source](04_runtime/README.md), [tests](../test/examples/04_runtime/README.md) |
| 05_multi_agent | 3 | [Source](05_multi_agent/README.md), [tests](../test/examples/05_multi_agent/README.md) |
| 07_topology | 6 | [Source](07_topology/README.md), [tests](../test/examples/07_topology/README.md) |
| 08_applications | 5 | [Source](08_applications/README.md), [tests](../test/examples/08_applications/README.md) |
| 09_plugins | 7 | [Source](09_plugins/README.md), [tests](../test/examples/09_plugins/README.md) |
| 10_persistence | 8 | [Source](10_persistence/README.md), [tests](../test/examples/10_persistence/README.md) |

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
See [testing](../guides/testing.md) for test categories and optional services.
