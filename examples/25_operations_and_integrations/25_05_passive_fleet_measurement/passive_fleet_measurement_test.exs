Code.require_file("passive_fleet_measurement.ex", __DIR__)

defmodule Jido.Examples.Operations.PassiveFleetMeasurementTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.Examples.Operations.PassiveFleetMeasurement

  test "a bounded report publishes inputs, environment, latency, throughput, and memory" do
    suffix = System.unique_integer([:positive])
    instance = :"operations_fleet_#{suffix}"
    namespace = "examples/operations/fleet/#{suffix}"

    start_supervised!(
      {Jido,
       name: instance,
       namespace: namespace,
       persistence: {Jido.Persistence.ETS, table: :"operations_fleet_store_#{suffix}"},
       activation: [idle_residency_timeout: 200]},
      id: instance
    )

    report = PassiveFleetMeasurement.run(instance, namespace, 8, 4)

    assert report.inputs == %{
             concurrency: 4,
             logical_agents: 8,
             store: "Jido.Persistence.ETS"
           }

    assert report.residents.before == 0
    assert report.residents.peak == 8
    assert report.residents.after == 0
    assert report.activation.latency_us.p95 >= report.activation.latency_us.p50
    assert report.activation.latency_us.maximum >= report.activation.latency_us.p95
    assert report.activation.agents_per_second > 0
    assert report.passivation.agents_per_second > 0
    assert report.results == %{committed: 8}
    assert is_binary(report.environment.architecture)
    assert report.memory_bytes.before > 0
  end
end
