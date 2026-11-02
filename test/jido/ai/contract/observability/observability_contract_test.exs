defmodule Jido.AI.Contract.ObservabilityTest do
  use Covenant.Case, component: "jido_ai.observability", async: true

  alias Jido.AI.Telemetry

  @tag obligation: [
         "jido_ai.observability.I1",
         "jido_ai.observability.I2",
         "jido_ai.observability.I5"
       ]
  test "the public event and metric catalog uses semantic AI identities" do
    assert [:jido, :ai, :agent, :start] in Telemetry.events()
    assert [:jido, :ai, :reasoning, :stop] in Telemetry.events()
    assert [:jido, :ai, :tool, :stop] in Telemetry.events()
    assert [:req_llm, :request, :stop] in Telemetry.events()

    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    assert [:jido, :ai, :agent, :stop, :duration] in names
    assert [:jido, :ai, :tool, :stop, :count] in names
    assert [:jido, :ai, :model, :request, :count] in names

    tool_metric = Enum.find(metrics, &(&1.name == [:jido, :ai, :tool, :stop, :count]))
    assert tool_metric.tags == [:status, :tool_name]

    refute Enum.any?(metrics, fn metric ->
             Enum.any?(metric.tags, &(&1 in [:prompt, :output, :arguments, :result, :state, :error]))
           end)
  end

  @tag obligation: ["jido_ai.observability.I3", "jido_ai.observability.I4"]
  test "optional OpenTelemetry hooks are safe no-op boundaries" do
    assert is_boolean(Telemetry.open_telemetry?())
    assert :ok = Telemetry.attach_open_telemetry()
    assert :ok = Telemetry.with_agent_span(%{}, fn -> :ok end)
  end
end
