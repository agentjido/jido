# 00_02 Schema-driven overrides

Use a custom reasoning Flow when the application needs fields that are not in
ReAct. The Flow schema owns defaults and validation. The Agent supplies
`"Welcome"` and `"!"`, and one request can replace either value.

The [tests](../../../../test/examples/ai/00_graph_first/00_02_schema_driven_overrides/schema_driven_overrides_test.exs)
check derived route defaults, request overrides, and unknown input rejection.

```sh
mix test.examples test/examples/ai/00_graph_first/00_02_schema_driven_overrides --warnings-as-errors
```

Previous: [Simple Agent](../00_01_simple_agent/README.md) | Next: [AI basics](../../01_basics/README.md)
