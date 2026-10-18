# Agent authoring contract

This suite checks [the Agent authoring specification](../../../AGENT_AUTHORING_SPEC.md).
Map input and Spark DSL input must produce the same `%Jido.Agent{}`. Definitions
have nil `id` and `state`. Instances use the same struct with an identity and
complete Zoi-validated state. No nested definition is stored.

Run from the `jido` package:

```sh
mix test test/authoring/agents --include authoring --seed 0
```

The suite checks:

- Exact equality across independent Maps, Agent structs, and Spark DSL, including defaults and order.
- Action and Flow descriptors, inline Actions, transforms, and pass-through.
- First-match input selection and explicit output connections.
- Optional emission contracts and complete supplied result batches.
- Immediate members, counted delivery, copied state inputs, and contract checks.
- Shared provider registration, static data, DSL sections, and endpoint ownership.
- Scheduling, Signal Bus, and Plugin-owned state contributions.
- Shared Zoi validation, metadata, complete instances, and invalid declarations.
- Exact JSON round trips for Map and DSL definitions and complete instances.
- Trusted JSON references, invalid documents, duplicate keys, size limits, and atom safety.

Fixtures and the source compiler are in `../support/agents/composable_*.exs`.
Tests load source fixtures only when the suite runs. Fixture Actions raise if
called during authoring. Pure result checks use supplied values; construction
starts no runtime service. The research example is compiled as part of the proof.

The former corpus used router records, old topology forms, keyword definitions,
and saved JSON. That corpus is replaced by the current specification tests.
JSON tests are in `json_test.exs`. They use an explicit reference Registry for
import and export. Runtime output delivery and topology activation require a
separate contract. Unsupported runtime paths must fail explicitly.

Leaf execution regression tests are in
[`test/jido/agent/authoring_port_test.exs`](../../jido/agent/authoring_port_test.exs).

Direct command tests are in `test/jido/agent/direct_command_test.exs`. They cover
complete local Turns and returned Directives, with no durability or delivery.
