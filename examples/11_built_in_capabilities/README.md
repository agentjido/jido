# 11 Built-in Capabilities

These lessons show capabilities that ship with Jido. Each capability uses the
same Agent, Plugin, Signal, and AgentServer contracts as an application Plugin.

1. [Audit](11_01_audit/README.md) stores bounded audit records with Agent state.
2. [Scheduled Signals](11_02_scheduled_signals/README.md) creates one-shot
   work through Scheduler Directives.
3. [Keyed Timers](11_03_keyed_timers/README.md) replaces an existing timer by
   key.
4. [Heartbeat](11_04_heartbeat/README.md) delivers periodic input.
5. SensorManager is used by the
   [Inbox application](../24_application_patterns/24_02_inbox/README.md). A
   focused capability lesson remains to be added.
6. [Bus Delivery](11_06_bus_delivery/README.md) uses an ordered local Bus
   subscription.

```sh
mix test.examples examples/11_built_in_capabilities --warnings-as-errors
```

Expected result: all bundled capability examples pass with local services.
