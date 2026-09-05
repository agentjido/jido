# Jido V3 examples

The current catalog has 52 fixtures in seven groups. All use the implemented
Agent and AgentServer contract. The group guides below link to their source
and tests.

| Group | Fixtures | Source and tests |
| --- | ---: | --- |
| 01_basic | 5 | [Source](01_basic/README.md), [tests](../../test/examples/01_basic/README.md) |
| 02_workflow | 9 | [Source](02_workflow/README.md), [tests](../../test/examples/02_workflow/README.md) |
| 03_llm | 10 | [Source](03_llm/README.md), [tests](../../test/examples/03_llm/README.md) |
| 04_runtime | 13 | [Source](04_runtime/README.md), [tests](../../test/examples/04_runtime/README.md) |
| 05_multi_agent | 6 | [Source](05_multi_agent/README.md), [tests](../../test/examples/05_multi_agent/README.md) |
| 06_factory | 4 | [Source](06_factory/README.md), [tests](../../test/examples/06_factory/README.md) |
| 07_topology | 5 | [Source](07_topology/README.md), [tests](../../test/examples/07_topology/README.md) |

The ten [application scenarios](../../test/integration/README.md) are additional
tests. Shared authoring and streaming tests, core Topology tests, and the mapped
observation, recovery, remote, and persistence tests are also required.

Run `mix test --include example --include integration --include flaky --seed 0`
from the repository root. The exact DIST-03 exclusion is the only approved skip.
Its cluster-exclusive ownership capability remains unsupported.

LLM and Factory tests use deterministic adapters and local HTTP/SSE servers.
Live provider demos require separate credentials and budget. The recursive
analysis stress runner and 1,000-worker Topology test are independent scale
checks. They do not prove multi-host capacity.

[Historical research](../../docs/examples/README.md) retains earlier plans and
results. Use the [testing guide](../../guides/testing.md) for current test commands
and the [migration guide](../../guides/migration.md) for V2 changes.
