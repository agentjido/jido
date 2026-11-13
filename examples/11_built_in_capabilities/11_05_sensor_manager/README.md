# 11_05 Sensor Manager

An Agent declares one tagged input process, and Sensor Manager keeps that
process aligned with committed Plugin state.

## What you will learn

- How an Action starts, replaces, and stops a sensor with Directives.
- How a sensor translates local input into normal Agent Signals.
- How a failed sensor starts again while its tag remains desired.
- How Agent shutdown owns sensor cleanup.

## Read the code

Read [the Agent and sensor](sensor_manager.ex), then read the behavior test.

## Run it

`mix test.examples examples/11_built_in_capabilities/11_05_sensor_manager --warnings-as-errors`

Expected result: a reading is transformed by the current sensor configuration,
a killed sensor starts again, a changed configuration replaces it, and a stop
Directive removes it.

## Important behavior

The Agent stores the portable desired sensor specification under Plugin state.
The sensor process and its AgentServer PID are temporary runtime resources.
Sensor Manager reconciles the process only after the Agent commits the desired
state. A failed sensor starts again because its tag is still desired.

The application gives each sensor an observable name. The test uses that public
application contract. It does not inspect Sensor Manager runtime internals.

## Limits

This lesson uses a local process as the input source. It does not prove durable
transport acknowledgement, overload control, or recovery of input that arrived
while the sensor was down.

## Core Fit and Gaps

`Jido.Plugin.SensorManager.start/3` and `stop/1` compose cleanly with normal
Agent Actions and Signals. The public contract supports desired state,
supervision, replacement, and cleanup without a private runtime API.

Input durability remains application or adapter work. The Manager restores the
process, but it cannot restore unacknowledged data from an external source.

## Files

- [Source](sensor_manager.ex)
- [Tests](sensor_manager_test.exs)

Previous: [Heartbeat](../11_04_heartbeat/README.md) |
Next: [Bus Delivery](../11_06_bus_delivery/README.md)
