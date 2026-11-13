# Jido offline examples

The examples are a progressive learning path and an offline integration suite.
The folder tree is the inventory source of truth. Each numbered chapter has a
README, and each supported lesson has reader-facing source and a colocated
integration test.

The target learning order and planned coverage are in
[the table of contents](table_of_contents.md). The current SDK findings are in
[the gap and friction register](core_gaps.md).

Run all examples:

```sh
mix test.examples --warnings-as-errors
```

Run one chapter or lesson with its path:

```sh
mix test.examples examples/00_start_here --warnings-as-errors
mix test.examples examples/03_flow_execution/03_03_choice --warnings-as-errors
```

All supported examples run without network access, credentials, paid APIs, or
live providers. Deterministic local adapters preserve external application
boundaries.

The suite conversion is in progress. Older chapter names remain supported
until their lessons move to the table-of-contents structure.
