# Plugins And Sensors

Current-truth contract for capability composition through plugins and ingress through sensors.

## Intent

This subject covers the extension model that lets Jido add capabilities without coupling core agent logic to transport, subscriptions, or capability-specific state.

```spec-meta
id: jido.plugins_and_sensors
kind: subsystem
status: active
summary: Jido composes capabilities through plugins and ingests external events through sensors.
surface:
  - guides/plugins.md
  - guides/sensors.md
  - guides/your-first-plugin.md
  - guides/your-first-sensor.md
  - lib/jido/agent/default_plugins.ex
  - lib/jido/plugin.ex
  - lib/jido/plugin
  - lib/jido/sensor.ex
  - lib/jido/sensor
  - lib/jido/sensors
  - test/examples/plugins
  - test/examples/observability/sensor_demo_test.exs
  - test/jido/agent_plugin_integration_test.exs
  - test/jido/plugin
  - test/jido/sensor
```

## Requirements

```spec-requirements
- id: jido.plugins_and_sensors.plugin_mounting
  statement: Jido shall let plugins mount isolated state, actions, routes, and configuration onto agents.
  priority: must
  stability: stable

- id: jido.plugins_and_sensors.plugin_lifecycle
  statement: Jido shall support plugin lifecycle hooks for initialization, restore, checkpoint, and runtime middleware behavior.
  priority: must
  stability: stable

- id: jido.plugins_and_sensors.sensor_ingress
  statement: Jido shall let sensors translate external events into routed Jido signals.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: guide_file
  target: guides/plugins.md
  covers:
    - jido.plugins_and_sensors.plugin_mounting
    - jido.plugins_and_sensors.plugin_lifecycle

- kind: guide_file
  target: guides/sensors.md
  covers:
    - jido.plugins_and_sensors.sensor_ingress

- kind: command
  target: mix test test/jido/plugin test/jido/sensor/runtime_test.exs test/jido/sensor/sensor_translation_test.exs test/jido/agent_plugin_integration_test.exs test/examples/plugins test/examples/observability/sensor_demo_test.exs
  execute: true
  covers:
    - jido.plugins_and_sensors.plugin_mounting
    - jido.plugins_and_sensors.plugin_lifecycle
    - jido.plugins_and_sensors.sensor_ingress
```
