# 00 Quick Start

These lessons start with the Agent route and its root reasoning Flow. The first
two lessons run offline. The last lesson is an opt-in live-provider example.

1. [Simple Agent](00_01_simple_ai_agent/README.md) — inspect ReAct and expand a parallel tool round.
2. [Schema-driven overrides](00_02_schema_driven_overrides/README.md) — define and replace typed reasoning defaults.
3. [Live ReAct](00_03_live_react/README.md) — run the canonical ReAct graph with a configured provider.

Run this chapter:

```sh
mix test.examples examples/00_quick_start --warnings-as-errors
```

Run the live lesson only when you intend to make a paid provider call:

```sh
mix run examples/00_quick_start/00_03_live_react/live_react.exs
```
