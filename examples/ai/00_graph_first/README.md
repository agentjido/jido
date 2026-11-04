# Graph-first AI examples

These lessons start with the Agent route and its root reasoning Flow. They run
offline. Provider calls use deterministic fixtures only in the paired tests.

1. [Simple Agent](00_01_simple_agent/README.md) — inspect ReAct and expand a parallel tool round.
2. [Schema-driven overrides](00_02_schema_driven_overrides/README.md) — define and replace typed reasoning defaults.

Run this chapter:

```sh
mix test.examples test/examples/ai/00_graph_first --warnings-as-errors
```
