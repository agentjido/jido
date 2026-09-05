defmodule JidoTest.TelemetryTest do
  use ExUnit.Case, async: false

  alias Jido.Telemetry

  test "setup/0 is idempotent" do
    assert :ok = Telemetry.setup()
    assert :ok = Telemetry.setup()
  end

  test "metrics expose only Agent Server events" do
    metrics = Telemetry.metrics()
    names = Enum.map(metrics, & &1.name)

    assert names == [
             [:jido, :agent_server, :signal, :stop, :count],
             [:jido, :agent_server, :signal, :stop, :duration],
             [:jido, :agent_server, :directive, :stop, :count]
           ]
  end

  test "start events need no logging work" do
    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :signal, :start],
               %{},
               %{agent_id: "agent-1"},
               nil
             )

    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :directive, :start],
               %{},
               %{agent_id: "agent-1"},
               nil
             )
  end

  test "stop events accept bounded Agent metadata" do
    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :signal, :stop],
               %{duration: 1, directive_count: 0},
               %{
                 agent_id: "agent-1",
                 agent_module: __MODULE__,
                 signal_type: "test.signal",
                 jido_instance: nil
               },
               nil
             )

    assert :ok =
             Telemetry.handle_event(
               [:jido, :agent_server, :directive, :stop],
               %{duration: 1, result: :ok},
               %{
                 agent_id: "agent-1",
                 directive_type: "Emit",
                 jido_instance: nil
               },
               nil
             )
  end
end
