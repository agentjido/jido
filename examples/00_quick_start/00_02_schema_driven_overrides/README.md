# 00_02 Schema-driven overrides

Use a custom reasoning Flow when the application needs fields that are not in
ReAct. The Flow schema owns defaults and validation. The Agent supplies
`"Welcome"` and `"!"`, and one request can replace either value.

The [tests](../../../test/examples/00_quick_start/00_02_schema_driven_overrides/schema_driven_overrides_test.exs)
check derived route defaults, request overrides, and unknown input rejection.

```sh
mix test.examples test/examples/00_quick_start/00_02_schema_driven_overrides --warnings-as-errors
```

Previous: [Simple Agent](../00_01_simple_ai_agent/README.md) | Next: [Live ReAct](../00_03_live_react/README.md)
