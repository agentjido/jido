Code.require_file("passive_fleet_measurement.ex", __DIR__)

alias Jido.Examples.Operations.PassiveFleetMeasurement

suffix = System.unique_integer([:positive])
instance = :"operations_fleet_runner_#{suffix}"
namespace = "examples/operations/fleet-runner/#{suffix}"

{:ok, _runtime} =
  Jido.start_link(
    name: instance,
    namespace: namespace,
    persistence: {Jido.Persistence.ETS, table: :"operations_fleet_runner_store_#{suffix}"},
    activation: [idle_residency_timeout: 200]
  )

report = PassiveFleetMeasurement.run(instance, namespace, 50, 8)
IO.inspect(report, label: "Passive Agent Fleet measurement")
Jido.stop(instance)
