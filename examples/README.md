# Jido example catalog

Supported examples use the register in
[`test/examples/catalog.yml`](../test/examples/catalog.yml). The register is
the source of truth for example IDs, categories, source files, README files,
and paired tests.

Supported examples keep the numbered chapter and lesson structure from the
source Jido packages:

```text
examples/category/NN_chapter/NN_NN_lesson
test/examples/category/NN_chapter/NN_NN_lesson
category/NN_NN_lesson
```

The last line is the catalog ID. The category prefix prevents collisions
between equal lesson numbers in different domains. The lesson chapter prefix
must equal its parent chapter number. Numeric gaps are intentional and must
not be renumbered.

The category must be one of these values:

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
catalog rejects files that are not registered, paths that do not use the
numbered structure, mismatched chapter prefixes, and entries that are not
sorted by ID.

Run all offline examples with:

```sh
mix test.examples
```

Provider and external-service examples are not part of this offline catalog.
They must have an explicit exclusion or use the opt-in live or service suite.
