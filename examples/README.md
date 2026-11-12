# Jido example catalog

All example chapters are direct children of this folder. A chapter contains
its numbered lessons and local support files. There are no domain folders
between `examples/` and a chapter.

| Chapter | Area | Lessons |
| --- | --- | ---: |
| [`00_quick_start`](00_quick_start/README.md) | Graph-first AI, including one opt-in live lesson | 3 |
| [`01_agent_basics`](01_agent_basics/README.md) | Agent basics | 8 |
| [`02_flow_authoring`](02_flow_authoring/README.md) | Flow definitions, DSL, and JSON | 8 |
| [`03_flow_execution`](03_flow_execution/README.md) | Flow execution | 14 |
| [`04_agent_workflows`](04_agent_workflows/README.md) | Agent workflows | 9 |
| [`05_flow_durability`](05_flow_durability/README.md) | Durable Flow runs | 4 |
| [`06_flow_patterns`](06_flow_patterns/README.md) | Flow patterns | 3 |
| [`07_flow_distribution`](07_flow_distribution/README.md) | Distributed Flow work | 0 |
| [`08_runtime`](08_runtime/README.md) | Agent runtime | 15 |
| [`09_multi_agent`](09_multi_agent/README.md) | Multi-Agent runtime | 3 |
| [`10_topologies`](10_topologies/README.md) | Agent topologies | 6 |
| [`11_plugins`](11_plugins/README.md) | Plugin mechanics | 8 |
| [`12_plugin_applications`](12_plugin_applications/README.md) | Plugin applications | 5 |
| [`13_persistence`](13_persistence/README.md) | Persistence | 8 |
| [`14_durable_agents`](14_durable_agents/README.md) | Durable Agents | 7 |
| [`15_ai_basics`](15_ai_basics/README.md) | AI basics | 9 |
| [`16_ai_conversations`](16_ai_conversations/README.md) | AI conversations and sessions | 5 |

The offline catalog has 114 lessons. The graph-first chapter also has one
opt-in live-provider lesson. Each chapter README lists its lessons in order.

The machine-readable register is
[`catalog.yml`](catalog.yml). It is the source
of truth for example IDs, categories, source files, README files, and paired
tests.

Each supported offline example has one catalog entry, one README, one primary
source file, and one paired ExUnit test in the same lesson folder:

```text
examples/03_flow_execution/03_03_choice/
├── README.md
├── choice.ex
└── choice_test.exs
```

The test loads its sibling source with `Code.require_file/2`. Example source
stays outside the package compiler paths, so a normal `mix test` does not
compile the complete catalog. Auxiliary source files are in the same catalog
entry. The catalog rejects unregistered files, separated tests, missing test
links, nested domain folders, invalid chapter or lesson numbers, and entries
that are not sorted by ID. Each entry also names the component whose canonical
behavior the lesson supplements.

Run all offline examples with:

```sh
mix test.examples
```

Run one chapter or lesson with an explicit path:

```sh
mix test.examples examples/03_flow_execution
mix test.examples examples/03_flow_execution/03_03_choice/choice_test.exs
```

`mix test.integration` runs the complete offline integration suite, including
these examples. Both commands use the standard Mix test task and ExUnit.

Provider and external-service examples are not part of the offline catalog.
They must have an explicit exclusion or use the opt-in live or service suite.
