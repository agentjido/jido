Code.require_file("../support/event_probe.ex", __DIR__)
Code.require_file("activation_measurements.ex", __DIR__)

defmodule Jido.Examples.Observability.ActivationMeasurementsTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias Jido.AgentServer.Status
  alias Jido.Examples.Observability.ActivationMeasurements
  alias Jido.Examples.Runtime.EventProbe

  test "a bounded report separates logical Agents from resident processes" do
    suffix = System.unique_integer([:positive])
    instance = :"activation_measurements_#{suffix}"
    namespace = "examples/observability/activation-measurements/#{suffix}"
    persistence = {Jido.Persistence.ETS, table: :"activation_measurements_store_#{suffix}"}

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: persistence, activation: [idle_residency_timeout: 250]},
      id: instance
    )

    probe = EventProbe.attach_all()

    try do
      refs = ActivationMeasurements.create(instance, namespace, 12)
      resident_before = Jido.resident_agent_count(instance)
      memory_before = :erlang.memory(:total)
      samples = ActivationMeasurements.activate(instance, refs)
      resident_peak = Jido.resident_agent_count(instance)
      assert {:ok, passivation_us} = ActivationMeasurements.await_passivation(instance, 3_000)
      resident_after = Jido.resident_agent_count(instance)
      memory_after = :erlang.memory(:total)

      persistence_operations =
        EventProbe.events(probe)
        |> Enum.count(fn event ->
          event.event in [
            [:jido, :persistence, :operation, :stop],
            [:jido, :persistence, :operation, :exception]
          ]
        end)

      report =
        ActivationMeasurements.report(
          samples,
          %{
            after_passivation: resident_after,
            before_activation: resident_before,
            peak: resident_peak,
            passivation_us: passivation_us
          },
          persistence_operations,
          %{after: memory_after, before: memory_before}
        )

      assert report.inputs.logical_agents == 12
      assert report.residents.before_activation == 0
      assert report.residents.peak == 12
      assert report.residents.after_passivation == 0
      assert report.residents.passivation_us > 0
      assert report.latency_us.p50 >= 0
      assert report.latency_us.p95 >= report.latency_us.p50
      assert report.latency_us.maximum >= report.latency_us.p95
      assert report.persistence_operations > 0
      assert Enum.all?(samples, &(&1.status == :committed))

      first = hd(refs)
      first_activation = hd(samples).activation_id
      {:ok, signal} = ActivationMeasurements.Agent.ping_signal(%{})
      assert {:ok, result} = Jido.call(instance, first, signal)
      refute result.agent_activation_id == first_activation
      assert %Status{agent_revision: 2} = Jido.status(instance, first)
    after
      EventProbe.detach(probe)
    end
  end
end
