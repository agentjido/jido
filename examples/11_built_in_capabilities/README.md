# 11 Built-in Capabilities

These lessons show capabilities that ship with Jido. Each capability uses the
same Agent, Plugin, Signal, and AgentServer contracts as an application Plugin.

1. [Audit](11_01_audit/README.md) stores bounded audit records with Agent state.

Scheduler, Heartbeat, SensorManager, and Bus lessons will move here from the
old runtime sections.

```sh
mix test.examples examples/11_built_in_capabilities --warnings-as-errors
```
