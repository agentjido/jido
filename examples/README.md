# Jido example catalog

Supported examples use the register in
[`test/examples/catalog.yml`](../test/examples/catalog.yml). The register is
the source of truth for example IDs, categories, source files, README files,
and paired tests.

An example ID uses slash-separated lower snake case:

```text
category/topic/example_name
```

The first segment must be one of these categories:

| Category | Source root | Test root |
| --- | --- | --- |
| `flow` | `examples/flow` | `test/examples/flow` |
| `agent` | `examples/agent` | `test/examples/agent` |
| `runtime` | `examples/runtime` | `test/examples/runtime` |
| `topology` | `examples/topology` | `test/examples/topology` |
| `plugin` | `examples/plugin` | `test/examples/plugin` |
| `persistence` | `examples/persistence` | `test/examples/persistence` |
| `durable` | `examples/durable` | `test/examples/durable` |
| `ai` | `examples/ai` | `test/examples/ai` |

Each supported example has one catalog entry, one README, one primary source,
and one paired test. Register auxiliary source files in the same entry. The
catalog rejects files that are not registered.

Run all offline examples with:

```sh
mix test.examples
```

Provider and external-service examples are not part of this offline catalog.
They must have an explicit exclusion or use the opt-in live or service suite.
