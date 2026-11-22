# 11 Built-in Capabilities

These lessons show capabilities that ship with Jido. Each capability uses the
same Agent, Plugin, Signal, and AgentServer contracts as an application Plugin.

1. [Audit](11_01_audit/README.md) stores bounded audit records with Agent state.
2. Schedule a Signal (11_02–11_04).
   - [Schedule from a Turn](11_02_scheduled_signals/README.md) creates one-shot or recurring work through Directives.
   - [Replace a timer by key](11_03_keyed_timers/README.md) discards an old timer when a new one takes its key.
   - [Declare a recurring Timer](11_04_heartbeat/README.md) starts a periodic Signal when the Agent starts.
3. [Sensor Manager](11_05_sensor_manager/README.md) keeps tagged input processes
   aligned with committed Plugin state.
4. [Bus Delivery](11_06_bus_delivery/README.md) uses an ordered local Bus
   subscription.
5. [Standalone Approval Chart](11_07_statechart_approval/README.md) starts
   an initialized Agent from a chart.
6. [Add a Chart to an Agent](11_08_statechart_plugin/README.md) runs a guarded
   transition alongside a separate Agent route.
7. [Behavior Tree](11_09_behavior_tree/README.md) resumes a running tree and
   dispatches an Action effect.
8. [Cancel a Statechart deadline](11_10_statechart_deadline/README.md) removes a pending send when checkout confirms stock.

```sh
mix test.examples examples/11_built_in_capabilities --warnings-as-errors
```

Expected result: all bundled capability examples pass with local services.
