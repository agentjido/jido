# 11 Built-in Capabilities

These lessons show capabilities that ship with Jido. Each capability uses the
same Agent, Plugin, Signal, and AgentServer contracts as an application Plugin.

1. [Audit](11_01_audit/README.md) stores bounded audit records with Agent state.
2. [Scheduled Signals](11_02_scheduled_signals/README.md) creates one-shot
   work through Timer Directives.
3. [Keyed Timers](11_03_keyed_timers/README.md) replaces an existing timer by
   key.
4. [Periodic Timer Signals](11_04_heartbeat/README.md) delivers static periodic
   input without a second timer engine.
5. [Sensor Manager](11_05_sensor_manager/README.md) keeps tagged input processes
   aligned with committed Plugin state.
6. [Bus Delivery](11_06_bus_delivery/README.md) uses an ordered local Bus
   subscription.
7. [Standalone Approval Chart](11_07_statechart_approval/README.md) starts
   an initialized Agent from a chart.
8. [Add a Chart to an Agent](11_08_statechart_plugin/README.md) runs a guarded
   transition alongside a separate Agent route.

```sh
mix test.examples examples/11_built_in_capabilities --warnings-as-errors
```

Expected result: all bundled capability examples pass with local services.
