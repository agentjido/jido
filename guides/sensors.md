# Input resources

V3 uses explicit input Plugins. `Jido.Plugin.Heartbeat` provides periodic input;
`Jido.Plugin.Bus` owns Bus subscriptions; `Jido.Plugin.SensorManager` owns
configured resource processes. These resources send Signals into the Agent path.
They do not write committed Agent state directly.

The V2 `Jido.Sensor` behavior, Sensor structs, translation callbacks, and built-in
Sensor modules are removed. SensorManager is not a source-compatible replacement
for an old Sensor. Port its resource startup, readiness, Signal delivery, and
cleanup into the V3 Plugin contract.

See [resource lifecycle tests](../test/jido/plugin/sensor_manager_test.exs) and
[Bus tests](../test/jido/plugin/bus_test.exs).
