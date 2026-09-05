# Write an input Plugin

Port an old Sensor into an explicit V3 input Plugin. Define who owns its process,
how readiness is reported, which Signals it emits, and how it stops. Keep its
process handles in runtime state. Store only portable business intent in Agent
state when recovery is required.

See [input resources](sensors.md), [Plugins](plugins.md), and the
[resource lifecycle tests](../test/jido/plugin/sensor_manager_test.exs).
